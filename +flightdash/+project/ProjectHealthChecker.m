classdef ProjectHealthChecker
    %PROJECTHEALTHCHECKER  Inspect external file links (Phase D-1).
    %
    %   Read-only. Returns a report struct describing every external
    %   asset the project references and whether it currently exists
    %   on disk. Treats option1.dat / option2.dat as first-class roles
    %   alongside flight_data_N / video_N.

    methods (Static)
        function report = check(project)
            report = flightdash.project.ProjectHealthChecker.emptyReport();
            if isempty(project) || ~isa(project, 'flightdash.project.ProjectModel')
                return;
            end
            projectRoot = flightdash.project.ProjectHealthChecker.projectRoot(project);

            % Project file itself.
            try
                report = flightdash.project.ProjectHealthChecker.append(report, ...
                    'project_json', char(project.ProjectFilePath), false, 0, '', 0, projectRoot);
            catch
            end

            % Each session's flight / video / option paths.
            try
                for k = 1:numel(project.Sessions)
                    sess = project.Sessions(k);
                    sessionId = '';
                    try, sessionId = char(sess.SessionId); catch, end
                    % flight_data_N
                    paths = flightdash.project.ProjectHealthChecker.cellPath(sess.FlightFilePath);
                    for ch = 1:numel(paths)
                        report = flightdash.project.ProjectHealthChecker.append(report, ...
                            sprintf('flight_data_%d', ch), paths{ch}, true, k, sessionId, ch, projectRoot);
                    end
                    % video_N (optional)
                    paths = flightdash.project.ProjectHealthChecker.cellPath(sess.VideoFilePath);
                    for ch = 1:numel(paths)
                        report = flightdash.project.ProjectHealthChecker.append(report, ...
                            sprintf('video_%d', ch), paths{ch}, false, k, sessionId, ch, projectRoot);
                    end
                    % option_N (first-class)
                    paths = flightdash.project.ProjectHealthChecker.cellPath( ...
                        flightdash.project.ProjectHealthChecker.fieldCell(sess, 'OptionFilePath'));
                    for ch = 1:numel(paths)
                        report = flightdash.project.ProjectHealthChecker.append(report, ...
                            sprintf('option%d_dat', ch), paths{ch}, false, k, sessionId, ch, projectRoot);
                    end
                end
            catch
            end

            % Roll up flags.
            req = [report.Items.Required];
            exists = [report.Items.Exists];
            report.HasMissingRequiredFiles = any(req & ~exists);
            report.HasMissingOptionalFiles = any(~req & ~exists);
        end

        function tf = isHealthy(report)
            tf = false;
            try
                tf = ~report.HasMissingRequiredFiles && ~report.HasMissingOptionalFiles;
            catch
            end
        end

        function tf = isCritical(report)
            tf = false;
            try
                tf = report.HasMissingRequiredFiles;
            catch
            end
        end

        function summary = summarize(report)
            summary = 'Project Health: OK';
            if isempty(report.Items)
                summary = 'Project Health: (no external assets)';
                return;
            end
            if report.HasMissingRequiredFiles
                missing = sum([report.Items.Required] & ~[report.Items.Exists]);
                summary = sprintf('Project Health: %d critical file(s) missing', missing);
            elseif report.HasMissingOptionalFiles
                missing = sum(~[report.Items.Required] & ~[report.Items.Exists]);
                summary = sprintf('Project Health: %d optional file(s) missing', missing);
            end
        end
    end

    methods (Static, Access = private)
        function r = emptyReport()
            r = struct();
            r.Items = struct('Role', {}, 'Path', {}, 'Exists', {}, ...
                'Required', {}, 'Message', {}, 'SessionIndex', {}, ...
                'SessionId', {}, 'ChannelIndex', {}, 'ResolvedPath', {});
            r.HasMissingRequiredFiles = false;
            r.HasMissingOptionalFiles = false;
        end

        function r = append(r, role, path, required, sessionIndex, sessionId, channelIndex, projectRoot)
            if nargin < 5 || isempty(sessionIndex), sessionIndex = 0; end
            if nargin < 6 || isempty(sessionId), sessionId = ''; end
            if nargin < 7 || isempty(channelIndex), channelIndex = 0; end
            if nargin < 8, projectRoot = ''; end
            path = char(path);
            if isempty(path), return; end  % nothing to track
            resolvedPath = flightdash.project.ProjectHealthChecker.resolveProjectPath( ...
                path, projectRoot);
            exists = isfile(resolvedPath);
            msg = 'OK';
            if ~exists
                if required, msg = 'MISSING (required)';
                else,        msg = 'MISSING (optional)';
                end
            end
            r.Items(end+1).Role = char(role);
            r.Items(end).Path     = path;
            r.Items(end).Exists   = exists;
            r.Items(end).Required = logical(required);
            r.Items(end).Message  = msg;
            r.Items(end).SessionIndex = double(sessionIndex);
            r.Items(end).SessionId = char(sessionId);
            r.Items(end).ChannelIndex = double(channelIndex);
            r.Items(end).ResolvedPath = resolvedPath;
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

        function resolvedPath = resolveProjectPath(pathValue, projectRoot)
            resolvedPath = char(pathValue);
            try
                if isempty(resolvedPath) || isempty(projectRoot) ...
                        || flightdash.project.ProjectHealthChecker.isAbsolutePath(resolvedPath)
                    return;
                end
                resolvedPath = fullfile(char(projectRoot), resolvedPath);
            catch
                resolvedPath = char(pathValue);
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

        function out = cellPath(p)
            out = {};
            if iscell(p), out = p;
            elseif ischar(p) || isstring(p), out = cellstr(p);
            end
            for k = 1:numel(out), out{k} = char(out{k}); end
        end

        function v = fieldCell(s, name)
            v = {};
            try
                if isprop(s, name) && ~isempty(s.(name))
                    v = s.(name);
                end
            catch
            end
        end
    end
end
