classdef ProjectPacker
    %PROJECTPACKER  Phase F — folder-mode Pack Project.
    %
    %   Output layout:
    %       <destFolder>/<ProjectName>/
    %           <ProjectName>.frsproj
    %           data/   flight_*.csv (per session/channel)
    %           video/  video_*.avi  (optional)
    %           config/ option1.dat, option2.dat
    %           docs/   README_PROJECT.txt
    %
    %   Path rewrite policy:
    %     - Operates on a DEEP COPY of the project. The caller's
    %       app.Project is never mutated.
    %     - All external links in the copy are rewritten to paths
    %       relative to the packed root, so opening the packed
    %       .frsproj from any folder works as long as the assets
    %       travel together.
    %
    %   Missing assets are reported in the returned warnings list;
    %   the pack still completes so the user can fix gaps and re-pack.

    methods (Static)
        function result = pack(project, destFolder, options)
            result = struct('PackedRoot', '', 'PackedProjectPath', '', ...
                'Warnings', {{}}, 'OK', false);
            if nargin < 3 || isempty(options), options = struct(); end
            options = flightdash.project.ProjectPacker.applyDefaults(options);

            try
                if isempty(project) || ~isa(project, 'flightdash.project.ProjectModel')
                    result.Warnings{end+1} = 'No valid project to pack.';
                    return;
                end
                if isempty(destFolder) || ~isfolder(destFolder)
                    result.Warnings{end+1} = sprintf('Destination not found: %s', destFolder);
                    return;
                end

                rawProjName = char(project.ProjectName);
                [projName, adjustedName] = ...
                    flightdash.project.ProjectPacker.safeProjectName(rawProjName);
                if adjustedName
                    result.Warnings{end+1} = sprintf( ...
                        'Project name adjusted for safe packing path: %s', projName);
                end
                packedRoot = fullfile(destFolder, projName);
                if ~flightdash.project.ProjectPacker.isSafeChildPath(destFolder, packedRoot)
                    result.Warnings{end+1} = sprintf( ...
                        'Unsafe packed folder path rejected: %s', packedRoot);
                    return;
                end

                if isfolder(packedRoot)
                    if ~options.Overwrite
                        result.Warnings{end+1} = sprintf( ...
                            'Packed folder exists (Overwrite=false): %s', packedRoot);
                        return;
                    end
                    rmdir(packedRoot, 's');
                end
                mkdir(packedRoot);
                mkdir(fullfile(packedRoot, 'data'));
                mkdir(fullfile(packedRoot, 'video'));
                mkdir(fullfile(packedRoot, 'config'));
                mkdir(fullfile(packedRoot, 'docs'));

                packed = project;   % VALUE class — this is a copy.

                % Copy assets per session, rewriting paths to packed-relative.
                for k = 1:numel(packed.Sessions)
                    sess = packed.Sessions(k);
                    [sess, result] = flightdash.project.ProjectPacker.packSession( ...
                        sess, packedRoot, options, result);
                    packed.Sessions(k) = sess;
                end

                % Always include sample_data option files if available
                % AND if none were copied per-session (fallback).
                result = flightdash.project.ProjectPacker.copySampleOptionFallback( ...
                    packedRoot, result);

                % Write the relocated .frsproj into the packed root.
                packed.ProjectFilePath   = fullfile(packedRoot, [projName '.frsproj']);
                packed.ProjectFolderPath = packedRoot;
                flightdash.project.ProjectSerializer.save(packed, packed.ProjectFilePath);

                % Project README.
                try
                    fid = fopen(fullfile(packedRoot, 'docs', 'README_PROJECT.txt'), 'w');
                    if fid ~= -1
                        fprintf(fid, '%s\n', projName);
                        fprintf(fid, 'Packed by Flight Review Studio %s\n', ...
                            char(flightdash.util.VersionInfo.current().Version));
                        fprintf(fid, 'Packed at: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
                        fprintf(fid, '\nLayout:\n  data/    flight CSVs\n  video/   AVIs (optional)\n');
                        fprintf(fid, '  config/  option*.dat mapping files\n  docs/    this README\n');
                        fclose(fid);
                    end
                catch
                end

                result.PackedRoot = packedRoot;
                result.PackedProjectPath = packed.ProjectFilePath;
                result = flightdash.project.ProjectPacker.clearPackingState(result);
                result.OK = true;
            catch ME
                result = flightdash.project.ProjectPacker.clearPackingState(result);
                result.Warnings{end+1} = sprintf('Pack failed: %s', ME.message);
            end
        end
    end

    methods (Static, Access = private)
        function opts = applyDefaults(opts)
            if ~isfield(opts, 'IncludeVideo'),       opts.IncludeVideo       = true; end
            if ~isfield(opts, 'IncludeFlightData'),  opts.IncludeFlightData  = true; end
            if ~isfield(opts, 'IncludeOptionFiles'), opts.IncludeOptionFiles = true; end
            if ~isfield(opts, 'UseRelativePaths'),   opts.UseRelativePaths   = true; end
            if ~isfield(opts, 'Overwrite'),          opts.Overwrite          = false; end
        end

        function [sess, result] = packSession(sess, packedRoot, options, result)
            % FlightFilePath
            if options.IncludeFlightData && isprop(sess, 'FlightFilePath') ...
                    && iscell(sess.FlightFilePath)
                [sess.FlightFilePath, result] = ...
                    flightdash.project.ProjectPacker.copyAndRewrite( ...
                        sess.FlightFilePath, packedRoot, 'data', result);
            end
            % VideoFilePath
            if options.IncludeVideo && isprop(sess, 'VideoFilePath') ...
                    && iscell(sess.VideoFilePath)
                [sess.VideoFilePath, result] = ...
                    flightdash.project.ProjectPacker.copyAndRewrite( ...
                        sess.VideoFilePath, packedRoot, 'video', result);
            end
            % OptionFilePath (first-class)
            if options.IncludeOptionFiles && isprop(sess, 'OptionFilePath') ...
                    && iscell(sess.OptionFilePath)
                [sess.OptionFilePath, result] = ...
                    flightdash.project.ProjectPacker.copyAndRewrite( ...
                        sess.OptionFilePath, packedRoot, 'config', result);
            end
        end

        function [outPaths, result] = copyAndRewrite(inPaths, packedRoot, subdir, result)
            result = flightdash.project.ProjectPacker.ensurePackingState(result);
            outPaths = inPaths;
            for k = 1:numel(inPaths)
                src = char(inPaths{k});
                if isempty(src), continue; end
                if ~isfile(src)
                    result.Warnings{end+1} = sprintf( ...
                        'Missing asset (%s): %s', subdir, src);
                    outPaths{k} = src;
                    continue;
                end
                srcKey = [char(subdir) '|' ...
                    flightdash.project.ProjectPacker.canonicalPath(src)];
                [seen, rel] = flightdash.project.ProjectPacker.lookupPackedAsset( ...
                    result, srcKey);
                if seen
                    outPaths{k} = rel;
                    continue;
                end
                [dst, rel] = flightdash.project.ProjectPacker.uniquePackedPath( ...
                    packedRoot, subdir, src, result);
                try
                    copyfile(src, dst);
                    result = flightdash.project.ProjectPacker.rememberPackedAsset( ...
                        result, srcKey, dst, rel);
                    outPaths{k} = rel;
                catch ME
                    result.Warnings{end+1} = sprintf( ...
                        'Copy failed: %s (%s)', src, ME.message);
                end
            end
        end

        function [safe, changed] = safeProjectName(name)
            original = strtrim(char(name));
            safe = original;
            if isempty(safe)
                safe = 'PackedProject';
            end
            safe(double(safe) < 32) = '_';
            safe = regexprep(safe, '[<>:"/\\|?*]', '_');
            safe = regexprep(safe, '^[. ]+|[. ]+$', '');
            safe = regexprep(safe, '_+', '_');
            if isempty(safe) || strcmp(safe, '.') || strcmp(safe, '..')
                safe = 'PackedProject';
            end
            if numel(safe) > 80
                safe = regexprep(safe(1:80), '[. ]+$', '');
            end
            reserved = {'CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4', ...
                'COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3', ...
                'LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'};
            baseName = upper(regexprep(safe, '\..*$', ''));
            if any(strcmp(baseName, reserved))
                safe = ['PackedProject_' safe];
            end
            changed = ~strcmp(safe, original);
        end

        function tf = isSafeChildPath(parentFolder, childPath)
            tf = false;
            try
                parent = flightdash.project.ProjectPacker.canonicalPath(parentFolder);
                child = flightdash.project.ProjectPacker.canonicalPath(childPath);
                if ispc
                    parent = lower(parent);
                    child = lower(child);
                end
                if isempty(parent) || isempty(child) || strcmp(parent, child)
                    return;
                end
                if ~endsWith(parent, filesep)
                    parent = [parent filesep];
                end
                tf = startsWith(child, parent);
            catch
                tf = false;
            end
        end

        function result = ensurePackingState(result)
            if ~isfield(result, 'PackedSourceKeys')
                result.PackedSourceKeys = {};
            end
            if ~isfield(result, 'PackedRelativePaths')
                result.PackedRelativePaths = {};
            end
            if ~isfield(result, 'PackedDestKeys')
                result.PackedDestKeys = {};
            end
        end

        function result = clearPackingState(result)
            internal = {'PackedSourceKeys', 'PackedRelativePaths', 'PackedDestKeys'};
            present = internal(isfield(result, internal));
            if ~isempty(present)
                result = rmfield(result, present);
            end
        end

        function [seen, rel] = lookupPackedAsset(result, srcKey)
            seen = false;
            rel = '';
            try
                keys = result.PackedSourceKeys;
                if ispc
                    match = find(strcmpi(keys, srcKey), 1, 'first');
                else
                    match = find(strcmp(keys, srcKey), 1, 'first');
                end
                if ~isempty(match)
                    seen = true;
                    rel = result.PackedRelativePaths{match};
                end
            catch
            end
        end

        function result = rememberPackedAsset(result, srcKey, dst, rel)
            result.PackedSourceKeys{end+1} = srcKey;
            result.PackedRelativePaths{end+1} = rel;
            result.PackedDestKeys{end+1} = ...
                flightdash.project.ProjectPacker.canonicalPath(dst);
        end

        function [dst, rel] = uniquePackedPath(packedRoot, subdir, src, result)
            [~, base, ext] = fileparts(src);
            base = flightdash.project.ProjectPacker.safeAssetStem(base);
            serial = 1;
            while true
                if serial == 1
                    fileName = [base ext];
                else
                    fileName = sprintf('%s_%d%s', base, serial, ext);
                end
                dst = fullfile(packedRoot, subdir, fileName);
                rel = strrep(fullfile(subdir, fileName), '\', '/');
                if ~isfile(dst) && ~isfolder(dst) ...
                        && ~flightdash.project.ProjectPacker.destinationUsed(result, dst)
                    return;
                end
                serial = serial + 1;
            end
        end

        function tf = destinationUsed(result, dst)
            tf = false;
            try
                dstKey = flightdash.project.ProjectPacker.canonicalPath(dst);
                if ispc
                    tf = any(strcmpi(result.PackedDestKeys, dstKey));
                else
                    tf = any(strcmp(result.PackedDestKeys, dstKey));
                end
            catch
                tf = false;
            end
        end

        function stem = safeAssetStem(stem)
            stem = char(stem);
            if isempty(stem)
                stem = 'asset';
                return;
            end
            stem(double(stem) < 32) = '_';
            stem = regexprep(stem, '[<>:"/\\|?*]', '_');
            stem = regexprep(stem, '^[. ]+|[. ]+$', '');
            if isempty(stem)
                stem = 'asset';
            end
        end

        function p = canonicalPath(pathValue)
            p = char(pathValue);
            try
                p = char(java.io.File(p).getCanonicalPath());
            catch
                try
                    p = char(java.io.File(p).getAbsolutePath());
                catch
                end
            end
        end

        function result = copySampleOptionFallback(packedRoot, result)
            try
                cfg = fullfile(packedRoot, 'config');
                here = fileparts(mfilename('fullpath'));
                root = fullfile(here, '..', '..');
                for n = 1:2
                    target = fullfile(cfg, sprintf('option%d.dat', n));
                    if isfile(target), continue; end
                    src = fullfile(root, 'sample_data', sprintf('option%d.dat', n));
                    if isfile(src)
                        copyfile(src, target);
                    else
                        result.Warnings{end+1} = sprintf( ...
                            'No option%d.dat found in project or sample_data — ', n);
                    end
                end
            catch
            end
        end
    end
end
