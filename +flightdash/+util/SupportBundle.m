classdef SupportBundle
    %SUPPORTBUNDLE  Help > Export Support Bundle (Phase D-4).
    %
    %   Collects diagnostic info into a single zip suitable for emailing
    %   to support. Privacy: large raw flight/video data is NOT included
    %   by default. option1.dat / option2.dat ARE included because they
    %   are tiny configuration files and almost always needed to
    %   reproduce a mapping issue.

    methods (Static)
        function zipPath = exportFor(app, destFolder)
            zipPath = '';
            try
                if nargin < 2 || isempty(destFolder)
                    destFolder = uigetdir(pwd, 'Choose folder to save support bundle');
                    if isequal(destFolder, 0), return; end
                end
                stamp = datestr(now, 'yyyymmdd_HHMMSS');
                stage = fullfile(tempdir, ['flightdash_support_' stamp]);
                if isfolder(stage), rmdir(stage, 's'); end
                mkdir(stage);
                stageCleaner = onCleanup(@() flightdash.util.SupportBundle.tryRmdir(stage)); %#ok<NASGU>

                % 1. Project manifest snapshot.
                try
                    if ~isempty(app) && isvalid(app) && ~isempty(app.Project)
                        s = flightdash.project.ProjectSerializer.projectSnapshot(app.Project);
                        fid = fopen(fullfile(stage, 'project_manifest.json'), 'w');
                        if fid ~= -1
                            fprintf(fid, '%s', jsonencode(s));
                            fclose(fid);
                        end
                    end
                catch
                end

                % 2. External link health.
                try
                    if ~isempty(app) && isvalid(app) && ~isempty(app.Project)
                        report = flightdash.project.ProjectHealthChecker.check(app.Project);
                        fid = fopen(fullfile(stage, 'external_links_status.json'), 'w');
                        if fid ~= -1
                            fprintf(fid, '%s', jsonencode(report));
                            fclose(fid);
                        end
                    end
                catch
                end

                % 3. Runtime diagnostics.
                try
                    rep = flightdash.util.RuntimeDiagnostics.run();
                    fid = fopen(fullfile(stage, 'runtime_diagnostics.json'), 'w');
                    if fid ~= -1
                        fprintf(fid, '%s', jsonencode(rep));
                        fclose(fid);
                    end
                catch
                end

                % 4. System info.
                try
                    fid = fopen(fullfile(stage, 'system_info.txt'), 'w');
                    if fid ~= -1
                        fprintf(fid, 'MATLAB release: %s\n', version);
                        fprintf(fid, 'Computer:       %s\n', computer);
                        fprintf(fid, 'Java version:   %s\n', char(java.lang.System.getProperty('java.version')));
                        fprintf(fid, 'isdeployed:     %d\n', isdeployed());
                        fprintf(fid, 'PWD:            %s\n', pwd);
                        fclose(fid);
                    end
                catch
                end

                % 5. Memory log + scrub stats (if available).
                try
                    src = flightdash.util.MemoryMonitor.logPath();
                    if isfile(src)
                        copyfile(src, fullfile(stage, 'memory_log.txt'));
                    end
                catch
                end

                % 6. Option files (always include if discoverable).
                try
                    cfgDir = fullfile(stage, 'config');
                    mkdir(cfgDir);
                    added = flightdash.util.SupportBundle.copyOptionFiles( ...
                        flightdash.util.SupportBundle.projectOptionPaths(app), cfgDir);
                    if ~added
                        added = flightdash.util.SupportBundle.copyOptionFiles( ...
                            flightdash.util.SupportBundle.sampleOptionPaths(), cfgDir);
                    end
                    if ~added
                        fid = fopen(fullfile(cfgDir, 'option_files_missing.txt'), 'w');
                        if fid ~= -1
                            fprintf(fid, 'No option*.dat files were found.\n');
                            fclose(fid);
                        end
                    end
                catch
                end

                % 7. Zip everything.
                zipPath = fullfile(destFolder, sprintf('support_bundle_%s.zip', stamp));
                zip(zipPath, '*', stage);

            catch ME
                try, warning('SupportBundle:export', '%s', ME.message); catch, end
            end
        end
    end

    methods (Static, Access = private)
        function paths = projectOptionPaths(app)
            paths = {};
            try
                if isempty(app) || ~isvalid(app) || isempty(app.Project)
                    return;
                end
                root = flightdash.util.SupportBundle.projectRoot(app.Project);
                for k = 1:numel(app.Project.Sessions)
                    sess = app.Project.Sessions(k);
                    if ~isprop(sess, 'OptionFilePath') || ~iscell(sess.OptionFilePath)
                        continue;
                    end
                    for ch = 1:numel(sess.OptionFilePath)
                        p = flightdash.util.SupportBundle.resolveProjectPath( ...
                            sess.OptionFilePath{ch}, root);
                        if ~isempty(p)
                            paths{end+1} = p; %#ok<AGROW>
                        end
                    end
                end
            catch
                paths = {};
            end
        end

        function paths = sampleOptionPaths()
            paths = {};
            try
                here = fileparts(mfilename('fullpath'));
                root = fullfile(here, '..', '..');
                for n = 1:2
                    paths{end+1} = fullfile(root, 'sample_data', ...
                        sprintf('option%d.dat', n)); %#ok<AGROW>
                end
            catch
                paths = {};
            end
        end

        function added = copyOptionFiles(paths, cfgDir)
            added = false;
            usedKeys = {};
            for k = 1:numel(paths)
                src = char(paths{k});
                if isempty(src) || ~isfile(src)
                    continue;
                end
                key = flightdash.util.SupportBundle.canonicalPath(src);
                if flightdash.util.SupportBundle.pathKeySeen(key, usedKeys)
                    continue;
                end
                usedKeys{end+1} = key; %#ok<AGROW>
                [~, base, ext] = fileparts(src);
                dst = flightdash.util.SupportBundle.uniqueDestination( ...
                    cfgDir, [base ext]);
                try
                    copyfile(src, dst);
                    added = true;
                catch
                end
            end
        end

        function dst = uniqueDestination(folder, fileName)
            [base, name, ext] = fileparts(fileName);
            if isempty(base), base = folder; end
            dst = fullfile(base, [name ext]);
            serial = 2;
            while isfile(dst)
                dst = fullfile(base, sprintf('%s_%d%s', name, serial, ext));
                serial = serial + 1;
            end
        end

        function tf = pathKeySeen(pathKey, seenKeys)
            tf = false;
            try
                for k = 1:numel(seenKeys)
                    if (ispc && strcmpi(pathKey, seenKeys{k})) ...
                            || (~ispc && strcmp(pathKey, seenKeys{k}))
                        tf = true;
                        return;
                    end
                end
            catch
                tf = false;
            end
        end

        function root = projectRoot(project)
            root = '';
            try
                root = char(project.ProjectFolderPath);
                if isempty(root) && ~isempty(project.ProjectFilePath)
                    root = fileparts(char(project.ProjectFilePath));
                end
            catch
                root = '';
            end
        end

        function p = resolveProjectPath(pathValue, projectRoot)
            p = char(pathValue);
            try
                if isempty(p) || isempty(projectRoot) ...
                        || flightdash.util.SupportBundle.isAbsolutePath(p)
                    return;
                end
                p = fullfile(char(projectRoot), p);
            catch
                p = char(pathValue);
            end
        end

        function tf = isAbsolutePath(pathValue)
            tf = false;
            try
                p = char(pathValue);
                if isempty(p), return; end
                tf = logical(java.io.File(p).isAbsolute());
            catch
                try
                    p = char(pathValue);
                    tf = startsWith(p, filesep) || startsWith(p, '\\') || ...
                        ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'));
                catch
                    tf = false;
                end
            end
        end

        function p = canonicalPath(pathValue)
            p = char(pathValue);
            try
                p = char(java.io.File(p).getCanonicalPath());
            catch
            end
        end

        function tryRmdir(folder)
            try
                if isfolder(folder)
                    rmdir(folder, 's');
                end
            catch
            end
        end
    end
end
