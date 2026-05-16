classdef UserPreferences
    %USERPREFERENCES  Persistent user-level preferences (Phase A-2).
    %
    %   Stored via MATLAB setpref/getpref so settings survive app
    %   restarts and live under the user's MATLAB preferences directory.
    %   No project / session dependency.
    %
    %   Recent project list is capped at MaxRecent. Most-recent entries
    %   sit at index 1; duplicates are deduplicated by canonical path.
    %
    %   Usage:
    %       flightdash.util.UserPreferences.addRecentProject(filePath);
    %       paths = flightdash.util.UserPreferences.getRecentProjects();
    %       flightdash.util.UserPreferences.clearRecentProjects();

    properties (Constant, Access = private)
        Group     = 'FlightReviewStudio'
        KeyRecent = 'RecentProjects'
        MaxRecent = 10
    end

    methods (Static)
        function paths = getRecentProjects()
            paths = {};
            try
                g = flightdash.util.UserPreferences.Group;
                k = flightdash.util.UserPreferences.KeyRecent;
                if ispref(g, k)
                    raw = getpref(g, k);
                    if iscell(raw)
                        paths = raw;
                    elseif ischar(raw) || isstring(raw)
                        paths = cellstr(raw);
                    end
                end
            catch
                paths = {};
            end
            % Prune entries whose file no longer exists.
            keep = false(1, numel(paths));
            for k = 1:numel(paths)
                p = char(paths{k});
                keep(k) = ~isempty(p) && isfile(p);
            end
            paths = paths(keep);
        end

        function addRecentProject(filePath)
            try
                filePath = char(filePath);
                if isempty(filePath), return; end
                try, filePath = char(java.io.File(filePath).getCanonicalPath()); catch, end
                paths = flightdash.util.UserPreferences.getRecentProjects();
                % Dedup (case-insensitive on Windows).
                if ispc, eqFn = @strcmpi; else, eqFn = @strcmp; end
                keep = ~cellfun(@(p) eqFn(char(p), filePath), paths);
                paths = paths(keep);
                paths = [{filePath}, paths];
                cap = flightdash.util.UserPreferences.MaxRecent;
                if numel(paths) > cap
                    paths = paths(1:cap);
                end
                setpref(flightdash.util.UserPreferences.Group, ...
                    flightdash.util.UserPreferences.KeyRecent, paths);
            catch
            end
        end

        function clearRecentProjects()
            try
                g = flightdash.util.UserPreferences.Group;
                k = flightdash.util.UserPreferences.KeyRecent;
                if ispref(g, k), rmpref(g, k); end
            catch
            end
        end
    end
end
