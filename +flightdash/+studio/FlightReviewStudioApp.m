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

        function name = get.ProjectName(app)
            if isempty(app.Project)
                name = 'Untitled';
            else
                name = app.Project.ProjectName;
            end
        end

        function sessionId = addSession(app, displayName)
            % Phase 2 entry point used by Menu > Project > Add Review Session.
            % Returns the new session id so callers can route follow-up
            % actions (e.g. Phase 3 will spawn an embedded dashboard tab).
            if nargin < 2 || isempty(displayName)
                displayName = sprintf('Session %d', app.Project.sessionCount() + 1);
            end
            sess = flightdash.project.SessionModel(displayName);
            app.Project = app.Project.addSession(sess);
            sessionId = sess.SessionId;
            app.refreshExplorer();
            app.refreshTitle();
            if ~isempty(app.StatusBar)
                app.StatusBar.setMessage(sprintf('Added session: %s (%s)', ...
                    sess.DisplayName, sessionId));
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
            app.BodyGrid = uigridlayout(shellGrid, [1 3], ...
                'ColumnWidth', {UIScale.px(240), '1x', UIScale.px(320)}, ...
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
            % Conservative size that fits MATLAB Online browser viewports
            % AND most desktop monitors. Avoids "exceeds monitor range".
            try
                monitors = get(groot, 'MonitorPositions');
                if ~isempty(monitors) && size(monitors, 2) >= 4
                    mon = monitors(1, 1:4);
                else
                    mon = [1 1 1280 800];
                end
            catch
                mon = [1 1 1280 800];
            end
            % Cap at a friendly size; never larger than 90% of monitor.
            maxW = 1280;  maxH = 800;
            w = min(maxW, floor(mon(3) * 0.9));
            h = min(maxH, floor(mon(4) * 0.9));
            w = max(960, w);
            h = max(600, h);
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
end
