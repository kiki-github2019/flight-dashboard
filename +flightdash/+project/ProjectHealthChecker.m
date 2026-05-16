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

            % Project file itself.
            try
                report = flightdash.project.ProjectHealthChecker.append(report, ...
                    'project_json', char(project.ProjectFilePath), false);
            catch
            end

            % Each session's flight / video / option paths.
            try
                for k = 1:numel(project.Sessions)
                    sess = project.Sessions(k);
                    % flight_data_N
                    paths = flightdash.project.ProjectHealthChecker.cellPath(sess.FlightFilePath);
                    for ch = 1:numel(paths)
                        report = flightdash.project.ProjectHealthChecker.append(report, ...
                            sprintf('flight_data_%d', ch), paths{ch}, true);
                    end
                    % video_N (optional)
                    paths = flightdash.project.ProjectHealthChecker.cellPath(sess.VideoFilePath);
                    for ch = 1:numel(paths)
                        report = flightdash.project.ProjectHealthChecker.append(report, ...
                            sprintf('video_%d', ch), paths{ch}, false);
                    end
                    % option_N (first-class)
                    paths = flightdash.project.ProjectHealthChecker.cellPath( ...
                        flightdash.project.ProjectHealthChecker.fieldCell(sess, 'OptionFilePath'));
                    for ch = 1:numel(paths)
                        report = flightdash.project.ProjectHealthChecker.append(report, ...
                            sprintf('option%d_dat', ch), paths{ch}, false);
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
                'Required', {}, 'Message', {});
            r.HasMissingRequiredFiles = false;
            r.HasMissingOptionalFiles = false;
        end

        function r = append(r, role, path, required)
            path = char(path);
            if isempty(path), return; end  % nothing to track
            exists = isfile(path);
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
