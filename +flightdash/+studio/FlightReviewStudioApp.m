classdef FlightReviewStudioApp < matlab.apps.AppBase
    % flightdash.studio.FlightReviewStudioApp
    % OriginPro-style integrated shell for FlightDataDashboard sessions.
    %
    % Phase 1: empty shell only — UI regions are visible but inert.
    % Phase 2 wires Project/Session models. Phase 3 embeds dashboards.
    %
    % Layout:
    %   row 1   : header (menu + toolbar)
    %   row 2   : body (left explorer | center workspace | right dock)
    %   row 3   : status bar
    %
    % Active session pattern (Phase 0.8 prep):
    %   - ActiveSessionId tracks which workspace tab is currently
    %     in focus. Controllers later will gate WindowButton callbacks
    %     by this id (see docs/test-multi-instance-drag.md).

    properties (Access = public)
        UIFigure              % uifigure
        BodyGrid              % uigridlayout
        HeaderPanel           % uipanel
        StatusBarPanel        % uipanel

        % Region managers (Phase 1: shells only)
        MenuMgr               % flightdash.studio.MenuManager
        ToolbarMgr            % flightdash.studio.ToolbarManager
        ProjectExplorer       % flightdash.studio.ProjectExplorerPanel
        Workspace             % flightdash.studio.WorkspaceManager
        RightDock             % flightdash.studio.RightDockManager
        StatusBar             % flightdash.studio.StatusBarManager

        % Studio-level state
        % Phase 2: Project model holds Sessions/Figures/Results/Themes.
        Project               % flightdash.project.ProjectModel (value class)
        ProjectFolder         char    = ''
        ActiveSessionId       char    = ''
        IsDeleting            logical = false
    end

    properties (Dependent)
        % Convenience accessor — pulled from app.Project so the title bar
        % and status bar can read it without referencing Project directly.
        ProjectName
    end

    methods
        % Dependent property accessors must live in an attribute-free
        % methods block per MATLAB classdef rules.
        function name = get.ProjectName(app)
            if isempty(app.Project)
                name = 'Untitled';
            else
                name = app.Project.ProjectName;
            end
        end
    end

    methods (Access = public)
        function app = FlightReviewStudioApp()
            try
                % Initialize an empty project before any UI accesses it.
                app.Project = flightdash.project.ProjectModel('Untitled');
                app.buildShell();
                app.refreshTitle();
            catch ME
                % If shell construction fails, ensure no orphan figure
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
                rethrow(ME);
            end
        end

        function sessionId = addSession(app, displayName)
            % Phase 2/3b entry point: Menu > Project > Add Review Session.
            % - Phase 2: appends a SessionModel to app.Project.
            % - Phase 3b: embeds a FlightDataDashboard inside a new
            %   workspace tab bound to that session.
            if nargin < 2 || isempty(displayName)
                displayName = sprintf('Session %d', app.Project.sessionCount() + 1);
            end
            sess = flightdash.project.SessionModel(displayName);
            app.Project = app.Project.addSession(sess);
            sessionId = sess.SessionId;
            app.refreshExplorer();
            app.refreshTitle();

            % [PHASE 3b] Embed dashboard in a workspace tab
            embedOk = false; embedME = [];
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.addDashboardTab(sessionId, sess.DisplayName);
                    embedOk = true;
                else
                    embedME = MException('FlightReviewStudio:NoWorkspace', ...
                        'Workspace manager is not available.');
                end
            catch ME
                embedME = ME;
            end

            if embedOk
                msg = sprintf('Added session: %s (%s)', sess.DisplayName, sessionId);
                if ~isempty(app.StatusBar), app.StatusBar.setMessage(msg); end
            else
                % Surface the failure prominently so the user can see *why*
                % the new tab did not appear. Status bar alone is too
                % discreet for a multi-step pipeline failure.
                shortMsg = sprintf('Embed failed: %s', embedME.message);
                if ~isempty(app.StatusBar), app.StatusBar.setMessage(shortMsg); end
                try
                    detail = sprintf(['The session was added to the project, but the\n' ...
                        'FlightDataDashboard could not be embedded in a workspace tab.\n\n' ...
                        'Identifier: %s\n' ...
                        'Message:    %s\n\n' ...
                        'Top stack frame:\n  %s'], ...
                        embedME.identifier, embedME.message, ...
                        flightdash.studio.FlightReviewStudioApp.formatTopStackFrame(embedME));
                    if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                        uialert(app.UIFigure, detail, 'Embed FlightDataDashboard failed');
                    end
                catch
                    % Fallback: warn to console.
                    warning('FlightReviewStudio:EmbedFailed', '%s', embedME.message);
                end
            end
        end

        function refreshExplorer(app)
            try
                if ~isempty(app.ProjectExplorer) && isvalid(app.ProjectExplorer)
                    app.ProjectExplorer.refreshFromProject(app.Project);
                end
            catch
            end
        end

        function removeSession(app, sessionId)
            % [PHASE 3c] Remove a session everywhere it lives:
            %   1) ProjectModel (so cascades drop dependent results too)
            %   2) Workspace (deletes embedded dashboard + uitab)
            %   3) Project Explorer tree
            sessionId = char(sessionId);
            try
                app.Project = app.Project.removeSession(sessionId);
            catch ME
                try, app.logCaught(ME, 'Studio:removeSession:project'); catch, end
            end
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.removeDashboardTab(sessionId);
                end
            catch ME
                try, app.logCaught(ME, 'Studio:removeSession:workspace'); catch, end
            end
            app.refreshExplorer();
            if ~isempty(app.StatusBar)
                app.StatusBar.setMessage(sprintf('Removed session: %s', sessionId));
            end
        end

        function removeAllSessions(app)
            % [PHASE 3c] Bulk remove every session.
            try
                if ~isempty(app.Project) && ~isempty(app.Project.Sessions)
                    ids = arrayfun(@(s) s.SessionId, app.Project.Sessions, ...
                        'UniformOutput', false);
                    for k = 1:numel(ids)
                        app.removeSession(ids{k});
                    end
                end
            catch ME
                try, app.logCaught(ME, 'Studio:removeAllSessions'); catch, end
            end
        end

        function logCaught(app, ME, tag)
            % Studio-level error logging facade (mirrors the dashboard's
            % flightdash.util.ErrorLog.log convention so manager classes
            % can report errors uniformly regardless of which app they
            % belong to).
            try
                flightdash.util.ErrorLog.log(ME, tag, false);
            catch
                fprintf('[Studio:%s] %s\n', tag, ME.message);
            end
        end

        function delete(app)
            if app.IsDeleting, return; end
            app.IsDeleting = true;
            try, delete(app.MenuMgr);          catch, end
            try, delete(app.ToolbarMgr);       catch, end
            try, delete(app.ProjectExplorer);  catch, end
            try, delete(app.Workspace);        catch, end
            try, delete(app.RightDock);        catch, end
            try, delete(app.StatusBar);        catch, end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch, end
        end

        function refreshTitle(app)
            % Title bar: "FlightDataReviewStudio - <ProjectName> [<Folder>]"
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                if isempty(app.ProjectFolder)
                    app.UIFigure.Name = sprintf('FlightDataReviewStudio - %s', app.ProjectName);
                else
                    folder = app.shortenPath(app.ProjectFolder, 60);
                    app.UIFigure.Name = sprintf('FlightDataReviewStudio - %s [%s]', app.ProjectName, folder);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function buildShell(app)
            UIScale = flightdash.util.UIScale;

            % --- Figure ---
            app.UIFigure = uifigure( ...
                'Name', 'FlightDataReviewStudio', ...
                'Position', app.initialFigurePosition(), ...
                'Color', [0.94 0.94 0.96], ...
                'AutoResizeChildren', 'off');
            % [PHASE 3c] Start maximized so the embedded FlightDataDashboard
            % gets enough horizontal room to avoid NARROW-profile rails.
            % MATLAB Online resizes the maximized figure to the browser
            % viewport, which is typically wider than our 1700px preferred
            % size and pushes the workspace area above the 1120px COMPACT
            % threshold even after subtracting the side docks.
            try
                if isprop(app.UIFigure, 'WindowState')
                    app.UIFigure.WindowState = 'maximized';
                end
            catch
            end
            app.UIFigure.CloseRequestFcn = @(~,~) app.onCloseRequest();

            % --- Top-level grid: header / body / status bar ---
            shellGrid = uigridlayout(app.UIFigure, [3 1], ...
                'RowHeight', {UIScale.px(70), '1x', UIScale.px(28)}, ...
                'ColumnWidth', {'1x'}, ...
                'RowSpacing', 0, 'ColumnSpacing', 0, ...
                'Padding', [0 0 0 0]);

            % --- Header (menu + toolbar) ---
            app.HeaderPanel = uipanel(shellGrid, 'BorderType', 'none', ...
                'BackgroundColor', [0.97 0.97 0.98]);
            app.HeaderPanel.Layout.Row = 1;
            headerGrid = uigridlayout(app.HeaderPanel, [2 1], ...
                'RowHeight', {UIScale.px(28), UIScale.px(36)}, ...
                'RowSpacing', 0, 'Padding', [0 0 0 0]);

            app.MenuMgr    = flightdash.studio.MenuManager(app);
            app.ToolbarMgr = flightdash.studio.ToolbarManager(app, headerGrid);

            % --- Body (3-column: explorer | workspace | dock) ---
            % [PHASE 3c] Slim down the side panels so the workspace
            % column has enough width to keep the embedded
            % FlightDataDashboard out of NARROW profile (rail mode).
            app.BodyGrid = uigridlayout(shellGrid, [1 3], ...
                'ColumnWidth', {UIScale.px(200), '1x', UIScale.px(260)}, ...
                'RowHeight', {'1x'}, ...
                'ColumnSpacing', 4, 'Padding', [4 4 4 4], ...
                'BackgroundColor', [0.94 0.94 0.96]);
            app.BodyGrid.Layout.Row = 2;

            app.ProjectExplorer = flightdash.studio.ProjectExplorerPanel(app, app.BodyGrid);
            app.Workspace       = flightdash.studio.WorkspaceManager(app, app.BodyGrid);
            app.RightDock       = flightdash.studio.RightDockManager(app, app.BodyGrid);

            % --- Status bar ---
            app.StatusBarPanel = uipanel(shellGrid, 'BorderType', 'none', ...
                'BackgroundColor', [0.92 0.92 0.94]);
            app.StatusBarPanel.Layout.Row = 3;
            app.StatusBar = flightdash.studio.StatusBarManager(app, app.StatusBarPanel);
        end

        function onCloseRequest(app)
            % Defensive close (Phase 0 pattern): always delete figure.
            figHandle = app.UIFigure;
            try
                delete(app);
            catch
            end
            try
                if ~isempty(figHandle) && isvalid(figHandle)
                    delete(figHandle);
                end
            catch
            end
        end

        function pos = initialFigurePosition(~)
            % Studio embeds the FlightDataDashboard inside its workspace
            % column. The dashboard's responsive layout drops every
            % channel panel to "rail mode" (text-only summary) when the
            % available width is below the COMPACT threshold (~1120px).
            % The previous 1280px cap with a 240+320 explorer+dock
            % chrome left only ~700px for the workspace, putting the
            % embedded dashboard into NARROW profile and triggering rail
            % mode on Att/Map/Info/Video. Open the figure as wide as the
            % monitor allows so the embedded layout has room.
            try
                monitors = get(groot, 'MonitorPositions');
                if ~isempty(monitors) && size(monitors, 2) >= 4
                    mon = monitors(1, 1:4);
                else
                    mon = [1 1 1600 900];
                end
            catch
                mon = [1 1 1600 900];
            end
            preferredW = 1700;
            preferredH = 1000;
            w = min(preferredW, floor(mon(3) * 0.95));
            h = min(preferredH, floor(mon(4) * 0.92));
            w = max(1280, w);
            h = max(720,  h);
            x = mon(1) + max(10, floor((mon(3) - w) / 2));
            y = mon(2) + max(10, floor((mon(4) - h) / 2));
            pos = [x, y, w, h];
        end

        function out = shortenPath(~, p, maxLen)
            if numel(p) <= maxLen
                out = p;
            else
                head = floor(maxLen / 3);
                tail = maxLen - head - 3;
                out = [p(1:head), '...', p(end-tail+1:end)];
            end
        end
    end

    methods (Static)
        function s = formatTopStackFrame(ME)
            s = '(no stack info)';
            try
                if isempty(ME.stack), return; end
                f = ME.stack(1);
                s = sprintf('%s (line %d)', f.name, f.line);
            catch
            end
        end
    end
end
