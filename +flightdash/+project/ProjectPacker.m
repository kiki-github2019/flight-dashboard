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

                projName = char(project.ProjectName);
                if isempty(projName), projName = 'PackedProject'; end
                packedRoot = fullfile(destFolder, projName);

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
                result.OK = true;
            catch ME
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
                [~, b, e] = fileparts(src);
                dst = fullfile(packedRoot, subdir, [b e]);
                try
                    copyfile(src, dst);
                    % Store as relative path (forward slashes for cross-platform).
                    rel = fullfile(subdir, [b e]);
                    rel = strrep(rel, '\', '/');
                    outPaths{k} = rel;
                catch ME
                    result.Warnings{end+1} = sprintf( ...
                        'Copy failed: %s (%s)', src, ME.message);
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
