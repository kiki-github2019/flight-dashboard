classdef SessionScope
    %SESSIONSCOPE Phase 4 — global "active session id" registry.
    %
    %   Studio's WorkspaceManager publishes the currently selected
    %   workspace tab's session id via setActive(). Each EventBus
    %   listener owned by a per-session controller can then consult
    %   isOwner(app) to decide whether to react to a broadcast event.
    %
    %   Fallback semantics:
    %   - If no active id is registered (standalone, or before Studio
    %     finishes initial layout), getActive() returns ''.
    %   - isOwner(app) returns true when there is no registered active
    %     session OR the app's ActiveSessionId is empty/'standalone',
    %     so legacy single-dashboard code keeps working unchanged.
    %
    %   Storage: setappdata on the root graphics object (groot). This
    %   lets every dashboard instance read the same value regardless
    %   of class caching.

    methods (Static)
        function setActive(sessionId)
            if nargin < 1, sessionId = ''; end
            if isempty(sessionId)
                if isappdata(0, 'FlightDashStudioActiveSession')
                    rmappdata(0, 'FlightDashStudioActiveSession');
                end
                return;
            end
            setappdata(0, 'FlightDashStudioActiveSession', char(sessionId));
        end

        function id = getActive()
            id = '';
            try
                if isappdata(0, 'FlightDashStudioActiveSession')
                    id = char(getappdata(0, 'FlightDashStudioActiveSession'));
                end
            catch
            end
        end

        function clear()
            try
                if isappdata(0, 'FlightDashStudioActiveSession')
                    rmappdata(0, 'FlightDashStudioActiveSession');
                end
            catch
            end
        end

        function tf = isOwner(app)
            % Returns true when `app` is the dashboard that should
            % respond to the current EventBus broadcast.
            %
            % Rules (any one true => isOwner = true):
            %   1) No active session registered globally -> broadcast
            %      mode (legacy / standalone).
            %   2) The app's ActiveSessionId is missing, empty, or
            %      'standalone' -> the app is not a Studio embed.
            %   3) The app's ActiveSessionId matches the global active
            %      session.
            tf = true;
            try
                active = flightdash.util.SessionScope.getActive();
                if isempty(active)
                    return;  % rule 1
                end
                appId = '';
                if ~isempty(app) && isvalid(app) && isprop(app, 'ActiveSessionId')
                    appId = char(app.ActiveSessionId);
                end
                if isempty(appId) || strcmp(appId, 'standalone')
                    return;  % rule 2
                end
                tf = strcmp(appId, active);
            catch
                tf = true;
            end
        end
    end
end
