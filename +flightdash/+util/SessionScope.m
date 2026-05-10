classdef SessionScope
    %SESSIONSCOPE Phase 4 global active session id registry.
    %
    %   Studio's WorkspaceManager publishes the currently selected
    %   workspace tab's session id via setActive(). Each EventBus
    %   listener owned by a per-session controller can then consult
    %   isOwner(app) to decide whether to react to a broadcast event.
    %
    %   Fallback semantics:
    %   - If no active id is registered (standalone, or before Studio
    %     finishes initial layout), getActive() returns ''.
    %   - isOwner(app) keeps legacy standalone fail-open behavior, but
    %     embedded Studio dashboards fail closed when the active session
    %     cannot be confirmed.
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
            % Rules:
            %   1) No active session registered globally -> broadcast
            %      mode for legacy / standalone only.
            %   2) The app's ActiveSessionId is missing, empty, or
            %      'standalone' -> the app is not a Studio embed.
            %   3) The app's ActiveSessionId matches the global active
            %      session.
            % Embedded dashboards must satisfy rule 3.
            tf = true;
            try
                active = flightdash.util.SessionScope.getActive();
                appId = '';
                isEmbedded = false;
                if isstruct(app) && isfield(app, 'ActiveSessionId')
                    appId = char(app.ActiveSessionId);
                    if isfield(app, 'IsEmbedded')
                        isEmbedded = logical(app.IsEmbedded);
                    end
                elseif ~isempty(app) && (~isa(app, 'handle') || isvalid(app)) ...
                        && isprop(app, 'ActiveSessionId')
                    appId = char(app.ActiveSessionId);
                    if isprop(app, 'IsEmbedded')
                        isEmbedded = logical(app.IsEmbedded);
                    end
                end
                if isEmbedded
                    tf = ~isempty(active) && ~isempty(appId) && ...
                        ~strcmp(appId, 'standalone') && strcmp(appId, active);
                    return;
                end
                if isempty(active)
                    return;  % rule 1
                end
                if isempty(appId) || strcmp(appId, 'standalone')
                    return;  % rule 2
                end
                tf = strcmp(appId, active);
            catch
                try
                    tf = ~(~isempty(app) && isprop(app, 'IsEmbedded') && logical(app.IsEmbedded));
                catch
                    tf = true;
                end
            end
        end
    end
end
