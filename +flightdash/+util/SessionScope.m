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
                if flightdash.util.SessionScope.hasReadableMember(app, 'ActiveSessionId')
                    appId = char(flightdash.util.SessionScope.readMember(app, 'ActiveSessionId', ''));
                    if flightdash.util.SessionScope.hasReadableMember(app, 'IsEmbedded')
                        isEmbedded = logical(flightdash.util.SessionScope.readMember(app, 'IsEmbedded', false));
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
                    tf = ~(flightdash.util.SessionScope.hasReadableMember(app, 'IsEmbedded') && ...
                        logical(flightdash.util.SessionScope.readMember(app, 'IsEmbedded', false)));
                catch
                    tf = true;
                end
            end
        end
    end

    methods (Static, Access = private)
        function tf = hasReadableMember(value, name)
            tf = false;
            try
                if isstruct(value)
                    tf = isfield(value, name);
                elseif ~isempty(value) && (~isa(value, 'handle') || isvalid(value))
                    tf = isprop(value, name);
                end
            catch
                tf = false;
            end
        end

        function out = readMember(value, name, fallback)
            out = fallback;
            try
                if flightdash.util.SessionScope.hasReadableMember(value, name)
                    out = value.(name);
                end
            catch
                out = fallback;
            end
        end
    end
end
