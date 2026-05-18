classdef SessionLifecycle
    %SESSIONLIFECYCLE  Centralized embed-first session creation helpers.
    %
    %   Every session-creation path (addSession, duplicateSession,
    %   project restoreProjectSessionTabs) MUST use these helpers so
    %   that ProjectModel <-> Project Explorer <-> Workspace.
    %   DashboardEntries cannot diverge on a failed embed.
    %
    %   The contract for every helper:
    %     1. Build the embedded FlightDataDashboard in the workspace
    %        FIRST (pre-flight). If this throws, do NOT commit anything
    %        to the project model, and roll back the tab if it leaked.
    %     2. Only on embed success: append the SessionModel to the
    %        project, refresh the Project Explorer, refresh the title.
    %     3. On failure, return ok=false + the captured MException so
    %        the caller can surface a single uialert and log once.
    %
    %   Static class only. No state.

    methods (Static, Access = public)

        function [ok, sessionId, ME] = embedAndCommit(app, sess, sessionModel)
            % Embed `sess` (a SessionModel) into the workspace, then
            % commit it to app.Project. Returns ok=true + sessionId on
            % success; ok=false + ME on failure.
            ok = false;
            sessionId = '';
            ME = MException.empty;
            if nargin < 3, sessionModel = []; end
            if isempty(sess) || ~isvalid(sess)
                ME = MException('SessionLifecycle:InvalidSession', ...
                    'SessionModel is empty or invalid.');
                return;
            end
            candidateId = char(sess.SessionId);
            displayName = char(sess.DisplayName);

            % Pre-flight embed.
            try
                if isempty(app.Workspace) || ~isvalid(app.Workspace)
                    error('SessionLifecycle:NoWorkspace', ...
                        'Workspace manager is not available.');
                end
                if isempty(sessionModel)
                    app.Workspace.addDashboardTab(candidateId, displayName);
                else
                    app.Workspace.addDashboardTab(candidateId, displayName, sessionModel);
                end
            catch embedME
                ME = embedME;
                % Make absolutely sure no stale tab/entry remains for
                % candidateId before returning failure.
                flightdash.studio.SessionLifecycle.cleanupEmbedRemnants(app, candidateId);
                return;
            end

            % Commit phase — ProjectModel + Explorer + title.
            try
                app.Project = app.Project.addSession(sess);
                sessionId = candidateId;
                try, app.refreshExplorer(); catch, end
                try, app.refreshTitle();   catch, end
                ok = true;
            catch commitME
                ME = commitME;
                % Rollback the just-attached workspace tab so we never
                % leave Workspace ahead of ProjectModel.
                flightdash.studio.SessionLifecycle.cleanupEmbedRemnants(app, candidateId);
                sessionId = '';
                ok = false;
            end
        end

        function reportFailure(app, ME, scope)
            % Single place to log + alert the user when a lifecycle
            % helper returned ok=false. `scope` is a short tag for
            % status bar / log (e.g. 'addSession', 'duplicateSession',
            % 'restoreSession').
            if nargin < 3, scope = 'session'; end
            try
                if ~isempty(app.StatusBar) && isvalid(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('%s failed: %s', scope, ME.message));
                end
            catch
            end
            try
                detail = sprintf(['%s could not be completed.\n' ...
                    'No session was added to the project (state remains consistent).\n\n' ...
                    'Identifier: %s\n' ...
                    'Message:    %s\n\n' ...
                    'Top stack frame:\n  %s'], ...
                    scope, ME.identifier, ME.message, ...
                    flightdash.studio.SessionLifecycle.topStackFrame(ME));
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    uialert(app.UIFigure, detail, ...
                        sprintf('Embed FlightDataDashboard failed (%s)', scope));
                end
            catch
                try, warning('FlightReviewStudio:EmbedFailed', '%s', ME.message); catch, end
            end
            try, app.logCaught(ME, sprintf('Studio:%s:embed', scope)); catch, end
        end

        function cleanupEmbedRemnants(app, sessionId)
            % Best-effort: remove any partial tab + dashboard entry for
            % sessionId so Workspace.DashboardEntries stays empty.
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.removeDashboardTab(char(sessionId));
                end
            catch
            end
        end

        function s = topStackFrame(ME)
            s = '<no stack>';
            try
                if ~isempty(ME.stack)
                    f = ME.stack(1);
                    s = sprintf('%s (line %d)', f.name, f.line);
                end
            catch
            end
        end
    end
end
