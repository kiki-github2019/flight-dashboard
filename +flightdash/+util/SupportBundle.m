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

                % 1. Project manifest snapshot.
                try
                    if ~isempty(app) && isvalid(app) && ~isempty(app.Project)
                        s = flightdash.project.ProjectSerializer.projectToStruct(app.Project);
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
                    here = fileparts(mfilename('fullpath'));
                    root = fullfile(here, '..', '..');
                    cfgDir = fullfile(stage, 'config');
                    mkdir(cfgDir);
                    added = false;
                    for n = 1:2
                        candidate = fullfile(root, 'sample_data', sprintf('option%d.dat', n));
                        if isfile(candidate)
                            copyfile(candidate, fullfile(cfgDir, sprintf('option%d.dat', n)));
                            added = true;
                        end
                    end
                    % Also try paths stored in the active project sessions.
                    if ~isempty(app) && isvalid(app) && ~isempty(app.Project)
                        for k = 1:numel(app.Project.Sessions)
                            sess = app.Project.Sessions(k);
                            if isprop(sess, 'OptionFilePath') && iscell(sess.OptionFilePath)
                                for ch = 1:numel(sess.OptionFilePath)
                                    p = char(sess.OptionFilePath{ch});
                                    if ~isempty(p) && isfile(p)
                                        [~, b, e] = fileparts(p);
                                        copyfile(p, fullfile(cfgDir, [b e]));
                                        added = true;
                                    end
                                end
                            end
                        end
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

                % Clean stage.
                try, rmdir(stage, 's'); catch, end
            catch ME
                try, warning('SupportBundle:export', '%s', ME.message); catch, end
            end
        end
    end
end
