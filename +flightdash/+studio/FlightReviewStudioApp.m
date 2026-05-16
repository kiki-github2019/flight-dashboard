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
        CommandRouter         % flightdash.studio.CommandRouter
        ProjectExplorer       % flightdash.studio.ProjectExplorerPanel
        Workspace             % flightdash.studio.WorkspaceManager
        RightDock             % flightdash.studio.RightDockManager
        StatusBar             % flightdash.studio.StatusBarManager

        % [PHASE 3.5] Owns the figure-level WindowButton callbacks so
        % per-session drag controllers do not race for the single slot.
        MouseRouter           % flightdash.studio.StudioMouseRouter

        % [PHASE 10 prototype] Studio-owned shared services. These are
        % injected into embedded dashboards but do not replace the current
        % per-dashboard decode path yet.
        SharedCacheService
        SharedDecodeService
        UndoService
        UndoServices
        UndoListeners
        StatusRestoreTimer

        % Studio-level state
        % Phase 2: Project model holds Sessions/Figures/Results/Themes.
        Project               % flightdash.project.ProjectModel (value class)
        ProjectFolder         char    = ''
        ActiveSessionId       char    = ''
        IsDeleting            logical = false

        % Resize throttle (review §13-14)
        LastResizeTic
        ResizeThrottleMs      double  = 80

        % Theme (review §15-18). Default Light preserves existing chrome.
        CurrentTheme          char    = 'Light'
        CurrentThemeStruct    struct  = struct()

        % P0-2: collapsible side-dock state. Width-reclaim toggles set
        % BodyGrid.ColumnWidth to 0 alongside Panel.Visible='off' so the
        % center Workspace actually grows when a side dock is hidden.
        SavedExplorerWidthPx  double  = NaN
        SavedRightDockWidthPx double  = NaN
        IsExplorerCollapsed   logical = false
        IsRightDockCollapsed  logical = false
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
                app.ensureSharedServices();
                app.ensureUndoServices();
                app.buildShell();
                app.applyGuiMode(app.Project.GuiMode, false);
                app.refreshTitle();
                % Auto Session 1 has been moved to the user-facing
                % FlightReviewStudio() entry-point wrapper so tests and
                % diagnostics that instantiate this class directly start
                % with a deterministic 0-session baseline.
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

        function [cacheService, decodeService] = ensureSharedServices(app)
            if isempty(app.SharedCacheService) || ~isvalid(app.SharedCacheService)
                app.SharedCacheService = flightdash.services.SharedCacheService();
            end
            if isempty(app.SharedDecodeService) || ~isvalid(app.SharedDecodeService)
                app.SharedDecodeService = flightdash.services.SharedDecodeService(app.SharedCacheService);
            end
            cacheService = app.SharedCacheService;
            decodeService = app.SharedDecodeService;
        end

        function services = ensureUndoServices(app)
            if isempty(app.UndoServices) || ~isa(app.UndoServices, 'containers.Map')
                app.UndoServices = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            if isempty(app.UndoListeners) || ~isa(app.UndoListeners, 'containers.Map')
                app.UndoListeners = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            services = app.UndoServices;
        end

        function undoService = getUndoService(app, sessionId)
            sessionId = char(sessionId);
            app.ensureUndoServices();
            if app.UndoServices.isKey(sessionId)
                undoService = app.UndoServices(sessionId);
                if ~isempty(undoService) && isvalid(undoService)
                    app.UndoService = undoService;
                    return;
                end
                app.UndoServices.remove(sessionId);
            end
            undoService = flightdash.studio.UndoService(sessionId);
            undoService.StatusCallback = @(msg, duration) app.updateStatusBar(msg, duration);
            app.UndoServices(sessionId) = undoService;
            app.attachUndoStateListener(sessionId, undoService);
            app.UndoService = undoService;
            app.refreshUndoStateForActiveSession();
        end

        function removeUndoService(app, sessionId)
            try
                sessionId = char(sessionId);
                if ~isempty(app.UndoServices) && isa(app.UndoServices, 'containers.Map') && ...
                        app.UndoServices.isKey(sessionId)
                    svc = app.UndoServices(sessionId);
                    if isequal(app.UndoService, svc)
                        app.UndoService = [];
                    end
                    app.UndoServices.remove(sessionId);
                end
                if ~isempty(app.UndoListeners) && isa(app.UndoListeners, 'containers.Map') && ...
                        app.UndoListeners.isKey(sessionId)
                    listener = app.UndoListeners(sessionId);
                    try
                        if ~isempty(listener) && isvalid(listener), delete(listener); end
                    catch
                    end
                    app.UndoListeners.remove(sessionId);
                end
                app.refreshUndoStateForActiveSession();
            catch
            end
        end

        function refreshUndoStateForActiveSession(app)
            canUndo = false;
            canRedo = false;
            try
                svc = app.getActiveUndoService();
                if ~isempty(svc) && isvalid(svc)
                    canUndo = svc.canUndo();
                    canRedo = svc.canRedo();
                    app.UndoService = svc;
                end
            catch
            end
            try
                if ~isempty(app.ToolbarMgr) && isvalid(app.ToolbarMgr) && ismethod(app.ToolbarMgr, 'setUndoState')
                    app.ToolbarMgr.setUndoState(canUndo, canRedo);
                end
            catch
            end
            try
                if ~isempty(app.MenuMgr) && isvalid(app.MenuMgr) && ismethod(app.MenuMgr, 'setUndoState')
                    app.MenuMgr.setUndoState(canUndo, canRedo);
                end
            catch
            end
        end

        function svc = getActiveUndoService(app)
            svc = [];
            try
                dash = app.getActiveDashboard();
                if ~isempty(dash) && isvalid(dash) && isprop(dash, 'UndoService')
                    svc = dash.UndoService;
                    return;
                end
                sessionId = app.activeSessionIdFromWorkspace();
                if ~isempty(sessionId) && ~strcmp(char(sessionId), 'standalone') && ...
                        ~isempty(app.UndoServices) && isa(app.UndoServices, 'containers.Map') && ...
                        app.UndoServices.isKey(char(sessionId))
                    svc = app.UndoServices(char(sessionId));
                end
            catch
                svc = [];
            end
        end

        function onUndoStateChanged(app, ~, evt)
            try
                activeId = app.activeSessionIdFromWorkspace();
                if isempty(activeId) || strcmp(char(activeId), 'standalone')
                    activeId = app.ActiveSessionId;
                end
                if isempty(evt) || strcmp(char(evt.SessionId), char(activeId))
                    app.refreshUndoStateForActiveSession();
                end
            catch
                app.refreshUndoStateForActiveSession();
            end
        end

        function updateStatusBar(app, message, duration)
            if nargin < 2 || isempty(message), message = ''; end
            if nargin < 3 || isempty(duration), duration = 3; end
            try
                if ~isempty(app.StatusBar) && isvalid(app.StatusBar)
                    app.StatusBar.setMessage(char(message));
                end
            catch
            end
            if duration <= 0, return; end
            app.stopStatusRestoreTimer();
            try
                app.StatusRestoreTimer = timer('ExecutionMode', 'singleShot', ...
                    'StartDelay', duration, 'TimerFcn', @(~,~) app.restoreStatusMessage());
                start(app.StatusRestoreTimer);
            catch
            end
        end

        function restoreStatusMessage(app)
            try
                if ~isempty(app.StatusBar) && isvalid(app.StatusBar)
                    app.StatusBar.setMessage(app.getDefaultStatusText());
                end
            catch
            end
        end

        function text = getDefaultStatusText(app)
            try
                if isempty(app.ActiveSessionId) || strcmp(char(app.ActiveSessionId), 'standalone')
                    text = 'Ready';
                else
                    text = sprintf('Ready - %s', char(app.ActiveSessionId));
                end
            catch
                text = 'Ready';
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

        function dispatchCommand(app, cmdId, source)
            if nargin < 3 || isempty(source)
                source = 'Command';
            end
            try
                if isempty(app.CommandRouter) || ~isvalid(app.CommandRouter)
                    app.CommandRouter = flightdash.studio.CommandRouter(app);
                end
                app.CommandRouter.dispatch(cmdId, source);
            catch ME
                try, app.logCaught(ME, ['Studio:dispatchCommand:' char(cmdId)]); catch, end
                if ~isempty(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('%s failed: %s', char(cmdId), ME.message));
                end
            end
        end

        function onUIFigureResized(app)
            % [PHASE 4 review + GUI modernization §13-14]
            % Throttle SizeChangedFcn bursts so the active dashboard's
            % LayoutMgr.applyLayout is called at most once per
            % ResizeThrottleMs window. Burst events still see the
            % bookkeeping update of LastResizeTic but skip the heavy
            % layout pass — the next event past the window catches up.
            if app.IsDeleting, return; end
            try
                elapsedMs = toc(app.LastResizeTic) * 1000;
            catch
                app.LastResizeTic = tic;
                elapsedMs = inf;
            end
            if elapsedMs < app.ResizeThrottleMs
                return;
            end
            app.LastResizeTic = tic;
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.refreshActiveLayout('studioResize');
                end
            catch
            end
        end

        function renameSession(app, sessionId, newName)
            % [PHASE 5] Rename a session: update model, workspace tab,
            % and Project Explorer label.
            sessionId = char(sessionId);
            try
                sess = app.Project.findSession(sessionId);
                if isempty(sess), return; end
                trimmed = strtrim(char(newName));
                if isempty(trimmed)
                    if ~isempty(app.StatusBar)
                        app.StatusBar.setMessage('Rename ignored: empty name');
                    end
                    return;
                end
                sess = sess.setDisplayName(trimmed);
                app.Project = app.Project.updateSession(sessionId, sess);
            catch ME
                try, app.logCaught(ME, 'Studio:renameSession:project'); catch, end
                return;
            end
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.renameDashboardTab(sessionId, trimmed);
                end
            catch ME
                try, app.logCaught(ME, 'Studio:renameSession:tab'); catch, end
            end
            app.refreshExplorer();
            app.refreshTitle();
            if ~isempty(app.StatusBar)
                app.StatusBar.setMessage(sprintf('Renamed: %s', trimmed));
            end
        end

        function newSessionId = duplicateSession(app, sessionId)
            % [PHASE 5] Create a new session that clones the source
            % session's lightweight metadata. The embedded dashboard
            % itself starts fresh (no flight data preloaded) — users
            % typically want a clean review session with the same name
            % conventions. Phase 9 will let users opt in to deep clone
            % via the project save/load round-trip.
            newSessionId = '';
            sessionId = char(sessionId);
            try
                src = app.Project.findSession(sessionId);
                if isempty(src), return; end
                copyName = sprintf('%s (copy)', src.DisplayName);
                copy = flightdash.project.SessionModel(copyName);
                % Carry over user preferences that are session-scoped
                copy.AutoUpdateMode = src.AutoUpdateMode;
                copy.PanelVisible   = src.PanelVisible;
                copy.LayoutState    = src.LayoutState;
                app.Project = app.Project.addSession(copy);
                newSessionId = copy.SessionId;
            catch ME
                try, app.logCaught(ME, 'Studio:duplicateSession:project'); catch, end
                return;
            end
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.addDashboardTab(newSessionId, copy.DisplayName);
                end
            catch ME
                try, app.logCaught(ME, 'Studio:duplicateSession:tab'); catch, end
            end
            app.refreshExplorer();
            if ~isempty(app.StatusBar)
                app.StatusBar.setMessage(sprintf('Duplicated -> %s', copy.DisplayName));
            end
        end

        function newProject(app)
            % [PHASE 9] Replace current Project with a fresh Untitled.
            % Closes every embedded session first to free resources.
            try, app.removeAllSessions(); catch, end
            app.Project = flightdash.project.ProjectModel('Untitled');
            app.ProjectFolder = '';
            app.applyGuiMode(app.Project.GuiMode, false);
            app.refreshExplorer();
            app.refreshTitle();
            % Commit 2: parity with constructor — a brand new project
            % should land on an active Dashboard, not on Welcome only.
            try, app.addSession('Session 1'); catch autoME
                warning('FlightReviewStudio:AutoSessionFailed', '%s', autoME.message);
            end
            if ~isempty(app.StatusBar)
                app.StatusBar.setMessage('New project (Untitled)');
            end
        end

        function tf = saveProject(app, filePath)
            % [PHASE 9] Persist app.Project to a .frsproj zip.
            % If filePath is omitted and app.Project.ProjectFilePath is
            % empty, falls through to saveProjectAs (uiputfile).
            tf = false;
            if nargin < 2 || isempty(filePath)
                filePath = char(app.Project.ProjectFilePath);
            end
            if isempty(filePath)
                tf = app.saveProjectAs();
                return;
            end
            try
                app.syncProjectFromWorkspace();
                flightdash.project.ProjectSerializer.save(app.Project, filePath);
                app.Project.ProjectFilePath   = filePath;
                app.Project.ProjectFolderPath = fileparts(filePath);
                app.Project.DirtyFlag = false;
                app.ProjectFolder = fileparts(filePath);
                app.applyGuiMode(app.Project.GuiMode, false);
                app.refreshTitle();
                if ~isempty(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('Saved: %s', filePath));
                end
                tf = true;
            catch ME
                try, app.logCaught(ME, 'Studio:saveProject'); catch, end
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    uialert(app.UIFigure, sprintf('Save failed:\n%s\n\n%s', ...
                        filePath, ME.message), 'Save Project Failed');
                end
            end
        end

        function tf = saveProjectAs(app)
            % [PHASE 9] uiputfile prompt then saveProject.
            tf = false;
            try
                defaultName = char(app.Project.ProjectName);
                if isempty(defaultName), defaultName = 'Untitled'; end
                ext = flightdash.project.ProjectSerializer.FileExt;
                [f, p] = uiputfile({['*' ext], ['FlightReviewStudio Project (*' ext ')']}, ...
                    'Save Project As', [defaultName ext]);
                if isequal(f, 0), return; end
                tf = app.saveProject(fullfile(p, f));
            catch ME
                try, app.logCaught(ME, 'Studio:saveProjectAs'); catch, end
            end
        end

        function tf = openProject(app, filePath)
            % [PHASE 9] Load a .frsproj into app.Project. Closes the
            % current sessions before installing the loaded model.
            tf = false;
            if nargin < 2 || isempty(filePath)
                ext = flightdash.project.ProjectSerializer.FileExt;
                [f, p] = uigetfile({['*' ext], ['FlightReviewStudio Project (*' ext ')']}, ...
                    'Open Project');
                if isequal(f, 0), return; end
                filePath = fullfile(p, f);
            end
            try
                loaded = flightdash.project.ProjectSerializer.load(filePath);
                try, app.removeAllSessions(); catch, end
                app.Project = loaded;
                app.Project.ProjectFilePath   = filePath;
                app.Project.ProjectFolderPath = fileparts(filePath);
                app.ProjectFolder = fileparts(filePath);
                app.restoreProjectSessionTabs();
                app.applyGuiMode(app.Project.GuiMode, false);
                app.Project.DirtyFlag = false;
                app.refreshExplorer();
                app.refreshTitle();
                if ~isempty(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('Opened: %s (%d sessions)', ...
                        filePath, numel(app.Project.Sessions)));
                end
                tf = true;
            catch ME
                try, app.logCaught(ME, 'Studio:openProject'); catch, end
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    uialert(app.UIFigure, sprintf('Open failed:\n%s\n\n%s', ...
                        filePath, ME.message), 'Open Project Failed');
                end
            end
        end

        function id = activeSessionIdFromWorkspace(app)
            id = '';
            try
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    id = app.Workspace.activeSessionId();
                end
            catch
            end
        end

        function tf = loadProjectFromFile(app, filePath)
            tf = app.openProject(filePath);
        end

        function tf = openProjectFile(app, filePath)
            tf = app.openProject(filePath);
        end

        function syncProjectFromWorkspace(app)
            % Copy lightweight live dashboard state into ProjectModel before save.
            try
                if isempty(app.Project) || isempty(app.Workspace) || ~isvalid(app.Workspace)
                    return;
                end
                if ~isprop(app.Workspace, 'DashboardEntries') || isempty(app.Workspace.DashboardEntries)
                    return;
                end
                keys_ = app.Workspace.DashboardEntries.keys;
                for k = 1:numel(keys_)
                    sessionId = char(keys_{k});
                    entry = app.Workspace.DashboardEntries(sessionId);
                    if ~isfield(entry, 'Dashboard') || isempty(entry.Dashboard) || ~isvalid(entry.Dashboard)
                        continue;
                    end
                    sess = app.Project.findSession(sessionId);
                    if isempty(sess)
                        displayName = sessionId;
                        try
                            if isfield(entry, 'Tab') && ~isempty(entry.Tab) && isvalid(entry.Tab)
                                displayName = char(entry.Tab.Title);
                            end
                        catch
                        end
                        sess = flightdash.project.SessionModel(displayName);
                        sess.SessionId = sessionId;
                    end
                    if ismethod(entry.Dashboard, 'exportSessionSnapshot')
                        sess = entry.Dashboard.exportSessionSnapshot(sess);
                    end
                    if app.Project.hasSession(sessionId)
                        app.Project = app.Project.updateSession(sessionId, sess);
                    else
                        app.Project = app.Project.addSession(sess);
                    end
                end
            catch ME
                try, app.logCaught(ME, 'Studio:syncProjectFromWorkspace'); catch, end
            end
        end

        function registerReviewResult(app, resultModel)
            % Phase 7: store analysis output and refresh lightweight UI surfaces.
            try
                mustBeA(resultModel, 'flightdash.project.ReviewResultModel');
                [app.Project, theme] = flightdash.analysis.AnalysisService.ensureDefaultThemes(app.Project);
                if isempty(resultModel.AnalysisThemeId)
                    resultModel.AnalysisThemeId = theme.ThemeId;
                end
                app.Project = app.Project.addResult(resultModel);
                app.refreshExplorer();
                app.refreshTitle();
                if ~isempty(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('Analysis result saved: %s', resultModel.ResultId));
                end
            catch ME
                try, app.logCaught(ME, 'Studio:registerReviewResult'); catch, end
            end
        end

        function dash = getActiveDashboard(app)
            dash = [];
            try
                if isempty(app.Workspace) || ~isvalid(app.Workspace), return; end
                sessionId = app.Workspace.activeSessionId();
                if isempty(sessionId) || strcmp(char(sessionId), 'standalone'), return; end
                if isprop(app.Workspace, 'DashboardEntries') && ...
                        ~isempty(app.Workspace.DashboardEntries) && ...
                        isKey(app.Workspace.DashboardEntries, char(sessionId))
                    entry = app.Workspace.DashboardEntries(char(sessionId));
                    if isfield(entry, 'Dashboard') && ~isempty(entry.Dashboard) && ...
                            isvalid(entry.Dashboard)
                        dash = entry.Dashboard;
                    end
                end
            catch
                dash = [];
            end
        end

        function restoreProjectSessionTabs(app)
            try
                if isempty(app.Workspace) || ~isvalid(app.Workspace), return; end
                if isempty(app.Project) || isempty(app.Project.Sessions), return; end
                for k = 1:numel(app.Project.Sessions)
                    sess = app.Project.Sessions(k);
                    sessionId = char(sess.SessionId);
                    displayName = char(sess.DisplayName);
                    if isempty(sessionId), continue; end
                    if isprop(app.Workspace, 'DashboardEntries') && ...
                            ~isempty(app.Workspace.DashboardEntries) && ...
                            isKey(app.Workspace.DashboardEntries, sessionId)
                        continue;
                    end
                    try
                        app.Workspace.addDashboardTab(sessionId, displayName, sess);
                    catch ME
                        try, app.logCaught(ME, 'Studio:restoreSessionTab'); catch, end
                    end
                end
            catch ME
                try, app.logCaught(ME, 'Studio:restoreProjectSessionTabs'); catch, end
            end
        end

        function setGuiMode(app, modeName)
            app.applyGuiMode(modeName);
        end

        function applyGuiMode(app, modeName, markDirty)
            if nargin < 2 || isempty(modeName)
                modeName = 'Studio';
            end
            if nargin < 3 || isempty(markDirty)
                markDirty = true;
            end
            mode = app.normalizeGuiMode(modeName);

            try
                app.Project.GuiMode = mode;
                if markDirty
                    app.Project.DirtyFlag = true;
                end
            catch ME
                try, app.logCaught(ME, 'Studio:guiMode:project'); catch, end
                rethrow(ME);
            end

            try
                profile = app.guiModeProfile(mode);
                app.applyGuiModeProfile(profile);
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.refreshActiveLayout(['guiMode:' mode]);
                end
                app.syncGuiModeMenuState(mode);
                app.refreshTitle();
                if ~isempty(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('GUI mode: %s', mode));
                end
            catch ME
                try, app.logCaught(ME, 'Studio:guiMode:layout'); catch, end
            end
        end

        function mode = currentGuiMode(app)
            mode = 'Studio';
            try
                if ~isempty(app.Project) && isprop(app.Project, 'GuiMode')
                    mode = app.normalizeGuiMode(app.Project.GuiMode);
                end
            catch
                mode = 'Studio';
            end
        end

        function profile = guiModeProfile(app, modeName)
            mode = app.normalizeGuiMode(modeName);
            profile = struct( ...
                'Mode',          mode, ...
                'ToolbarVisible', true, ...
                'ExplorerVisible', true, ...
                'RightDockVisible', true, ...
                'ExplorerWidth',  220, ...
                'RightDockWidth', 300, ...
                'WindowStyle',   'normal');

            switch mode
                case 'Classic'
                    profile.ExplorerVisible = true;
                    profile.RightDockVisible = true;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 240;
                    profile.RightDockWidth = 320;
                case 'Studio'
                    profile.ExplorerVisible = true;
                    profile.RightDockVisible = true;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 220;
                    profile.RightDockWidth = 300;
                case 'Review'
                    profile.ExplorerVisible = false;
                    profile.RightDockVisible = false;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 0;
                    profile.RightDockWidth = 0;
                case 'Analysis'
                    profile.ExplorerVisible = false;
                    profile.RightDockVisible = true;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 0;
                    profile.RightDockWidth = 320;
                case 'Plot'
                    profile.ExplorerVisible = false;
                    profile.RightDockVisible = true;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 0;
                    profile.RightDockWidth = 300;
                case 'Report'
                    profile.ExplorerVisible = false;
                    profile.RightDockVisible = false;
                    profile.ToolbarVisible = false;
                    profile.ExplorerWidth = 0;
                    profile.RightDockWidth = 0;
                case 'Compact'
                    profile.ExplorerVisible = false;
                    profile.RightDockVisible = false;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 0;
                    profile.RightDockWidth = 0;
                case 'DockedFigure'
                    profile.ExplorerVisible = true;
                    profile.RightDockVisible = true;
                    profile.ToolbarVisible = true;
                    profile.ExplorerWidth = 220;
                    profile.RightDockWidth = 300;
                    profile.WindowStyle = 'docked';
            end
        end

        function mode = normalizeGuiMode(~, modeName)
            if nargin < 2 || isempty(modeName)
                modeName = 'Studio';
            end
            requested = char(modeName);
            valid = {'Classic', 'Studio', 'Review', 'Analysis', 'Plot', ...
                'Report', 'Compact', 'DockedFigure'};
            hit = find(strcmpi(requested, valid), 1);
            if isempty(hit)
                error('FlightReviewStudio:InvalidGuiMode', ...
                    'Unsupported GUI mode "%s".', requested);
            end
            mode = valid{hit};
        end

        function applyGuiModeProfile(app, profile)
            try
                app.setToolbarVisible(profile.ToolbarVisible);
                app.setManagerPanelVisible(app.ProjectExplorer, profile.ExplorerVisible);
                app.setManagerPanelVisible(app.RightDock, profile.RightDockVisible);
                app.setBodyColumnWidths(profile);
                if isfield(profile, 'WindowStyle') && ~isempty(profile.WindowStyle)
                    app.applyWindowStyle(profile.WindowStyle);
                end
            catch ME
                try, app.logCaught(ME, 'Studio:applyGuiModeProfile'); catch, end
            end
        end

        function toggleExplorer(app)
            % P0-2: collapse / restore the left Project Explorer dock and
            % its BodyGrid column so the center Workspace actually
            % reclaims the freed horizontal space. Width on first hide is
            % captured into SavedExplorerWidthPx (falls back to the
            % current GUI mode profile's ExplorerWidth on cold start).
            try
                if isempty(app.BodyGrid) || ~isvalid(app.BodyGrid), return; end
                cw = app.BodyGrid.ColumnWidth;
                if app.IsExplorerCollapsed
                    w = app.SavedExplorerWidthPx;
                    if ~(isnumeric(w) && isfinite(w) && w > 0)
                        try
                            prof = app.guiModeProfile(app.currentGuiMode());
                            w = prof.ExplorerWidth;
                        catch
                            w = 220;
                        end
                    end
                    cw{1} = w;
                    app.IsExplorerCollapsed = false;
                    if ~isempty(app.ProjectExplorer) && isvalid(app.ProjectExplorer) ...
                            && isprop(app.ProjectExplorer, 'Panel') && isgraphics(app.ProjectExplorer.Panel)
                        app.ProjectExplorer.Panel.Visible = 'on';
                    end
                else
                    if isnumeric(cw{1}) && cw{1} > 0
                        app.SavedExplorerWidthPx = double(cw{1});
                    end
                    cw{1} = 0;
                    app.IsExplorerCollapsed = true;
                    if ~isempty(app.ProjectExplorer) && isvalid(app.ProjectExplorer) ...
                            && isprop(app.ProjectExplorer, 'Panel') && isgraphics(app.ProjectExplorer.Panel)
                        app.ProjectExplorer.Panel.Visible = 'off';
                    end
                end
                app.BodyGrid.ColumnWidth = cw;
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.refreshActiveLayout('dockToggle');
                end
            catch ME
                try, app.logCaught(ME, 'Studio:toggleExplorer'); catch, end
            end
        end

        function toggleRightDock(app)
            % P0-2: symmetric collapse / restore for the right Tools &
            % Inspector dock. Width restore uses the current GUI mode's
            % RightDockWidth as the fallback when no saved width exists.
            try
                if isempty(app.BodyGrid) || ~isvalid(app.BodyGrid), return; end
                cw = app.BodyGrid.ColumnWidth;
                if app.IsRightDockCollapsed
                    w = app.SavedRightDockWidthPx;
                    if ~(isnumeric(w) && isfinite(w) && w > 0)
                        try
                            prof = app.guiModeProfile(app.currentGuiMode());
                            w = prof.RightDockWidth;
                        catch
                            w = 300;
                        end
                    end
                    cw{end} = w;
                    app.IsRightDockCollapsed = false;
                    if ~isempty(app.RightDock) && isvalid(app.RightDock) ...
                            && isprop(app.RightDock, 'Panel') && isgraphics(app.RightDock.Panel)
                        app.RightDock.Panel.Visible = 'on';
                    end
                else
                    if isnumeric(cw{end}) && cw{end} > 0
                        app.SavedRightDockWidthPx = double(cw{end});
                    end
                    cw{end} = 0;
                    app.IsRightDockCollapsed = true;
                    if ~isempty(app.RightDock) && isvalid(app.RightDock) ...
                            && isprop(app.RightDock, 'Panel') && isgraphics(app.RightDock.Panel)
                        app.RightDock.Panel.Visible = 'off';
                    end
                end
                app.BodyGrid.ColumnWidth = cw;
                if ~isempty(app.Workspace) && isvalid(app.Workspace)
                    app.Workspace.refreshActiveLayout('dockToggle');
                end
            catch ME
                try, app.logCaught(ME, 'Studio:toggleRightDock'); catch, end
            end
        end

        function toggleTheme(app)
            % Review §15-18 theme toggle. Light ↔ Dark only chrome (panels,
            % labels, axes); plot data colors and gauge needles are
            % intentionally left untouched. Public so test_T12 and the
            % Pref:Theme:Toggle command can reach it from outside the class.
            try
                if strcmp(app.CurrentTheme, 'Dark')
                    app.CurrentTheme = 'Light';
                    app.CurrentThemeStruct = flightdash.ui.StudioTheme.light();
                else
                    app.CurrentTheme = 'Dark';
                    app.CurrentThemeStruct = flightdash.ui.StudioTheme.dark();
                end
                flightdash.ui.StudioTheme.apply(app.UIFigure, app.CurrentThemeStruct);
                % Patch 4 medium-term: persist the user's choice into the
                % project model so Save round-trips Dark/Light. DirtyFlag
                % is left to ProjectModel.touch (no-op when the value
                % did not actually change), keeping Save prompts minimal.
                try
                    if ~isempty(app.Project) && isprop(app.Project, 'GuiTheme') ...
                            && ~strcmp(char(app.Project.GuiTheme), app.CurrentTheme)
                        app.Project.GuiTheme = app.CurrentTheme;
                        app.Project.DirtyFlag = true;
                    end
                catch
                end
                if ~isempty(app.StatusBar)
                    app.StatusBar.setMessage(sprintf('Theme: %s', app.CurrentTheme));
                end
            catch ME
                try, app.logCaught(ME, 'Studio:toggleTheme'); catch, end
            end
        end

        function applyWindowStyle(app, style)
            % Phase 10: optional WindowStyle='docked' for local MATLAB. On
            % MATLAB Online or any environment that rejects the setter the
            % failure is logged and the figure stays in its previous style.
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                s = lower(char(style));
                if ~ismember(s, {'normal','docked'}), s = 'normal'; end
                app.UIFigure.WindowStyle = s;
            catch ME
                try, app.logCaught(ME, 'Studio:WindowStyle'); catch
                    warning('FlightReviewStudio:WindowStyle', '%s', ME.message);
                end
            end
        end

        function setToolbarVisible(app, tf)
            try
                if isempty(app.ToolbarMgr) || ~isvalid(app.ToolbarMgr) || ...
                        ~isprop(app.ToolbarMgr, 'Panel') || ~isgraphics(app.ToolbarMgr.Panel)
                    return;
                end
                app.ToolbarMgr.Panel.Visible = app.onOff(tf);

                headerGrid = app.ToolbarMgr.Panel.Parent;
                if ~isempty(headerGrid) && isvalid(headerGrid) && isprop(headerGrid, 'RowHeight')
                    if tf
                        headerGrid.RowHeight = {flightdash.util.UIScale.px(28), flightdash.util.UIScale.px(36)};
                    else
                        headerGrid.RowHeight = {flightdash.util.UIScale.px(28), 0};
                    end
                end
            catch ME
                try, app.logCaught(ME, 'Studio:setToolbarVisible'); catch, end
            end
        end

        function setManagerPanelVisible(app, manager, tf)
            try
                if isempty(manager) || ~isvalid(manager) || ...
                        ~isprop(manager, 'Panel') || ~isgraphics(manager.Panel)
                    return;
                end
                manager.Panel.Visible = app.onOff(tf);
            catch ME
                try, app.logCaught(ME, 'Studio:setManagerPanelVisible'); catch, end
            end
        end

        function setBodyColumnWidths(app, profile)
            try
                if isempty(app.BodyGrid) || ~isvalid(app.BodyGrid), return; end
                leftW = profile.ExplorerWidth;
                rightW = profile.RightDockWidth;
                if ~profile.ExplorerVisible, leftW = 0; end
                if ~profile.RightDockVisible, rightW = 0; end
                app.BodyGrid.ColumnWidth = {leftW, '1x', rightW};
            catch ME
                try, app.logCaught(ME, 'Studio:setBodyColumnWidths'); catch, end
            end
        end

        function syncGuiModeMenuState(app, mode)
            try
                if ~isempty(app.MenuMgr) && isvalid(app.MenuMgr) && ismethod(app.MenuMgr, 'syncGuiMode')
                    app.MenuMgr.syncGuiMode(mode);
                end
            catch ME
                try, app.logCaught(ME, 'Studio:syncGuiModeMenuState'); catch, end
            end
        end

        function value = onOff(~, tf)
            if tf
                value = 'on';
            else
                value = 'off';
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

            % [PHASE 3.5] Close every embedded session FIRST so each
            % FlightDataDashboard.delete runs with the figure/router
            % still alive. Each dashboard releases its own AsyncFutures
            % + VideoReader + cache; embedded mode leaves the parpool
            % intact so the order here matters.
            try, app.removeAllSessions(); catch ME, try, app.logCaught(ME, 'Studio:teardown:sessions'); catch, end, end

            % Detach router before tearing down workspace so no late
            % motion event tries to dispatch into a freed controller.
            try
                if ~isempty(app.MouseRouter) && isvalid(app.MouseRouter)
                    app.MouseRouter.detach();
                    delete(app.MouseRouter);
                end
            catch, end
            app.MouseRouter = [];
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure) ...
                        && isappdata(app.UIFigure, 'StudioMouseRouter')
                    rmappdata(app.UIFigure, 'StudioMouseRouter');
                end
            catch, end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure) ...
                        && isappdata(app.UIFigure, 'FlightReviewStudioApp')
                    rmappdata(app.UIFigure, 'FlightReviewStudioApp');
                end
            catch, end
            app.stopStatusRestoreTimer();

            try, delete(app.MenuMgr);          catch, end
            try, delete(app.ToolbarMgr);       catch, end
            try, delete(app.CommandRouter);    catch, end
            try, delete(app.ProjectExplorer);  catch, end
            try, delete(app.Workspace);        catch, end
            try, delete(app.RightDock);        catch, end
            try, delete(app.StatusBar);        catch, end
            try
                if ~isempty(app.SharedCacheService) && isvalid(app.SharedCacheService)
                    app.SharedCacheService.clear();
                end
            catch, end
            app.SharedDecodeService = [];
            app.SharedCacheService = [];
            app.UndoService = [];
            try
                if ~isempty(app.UndoListeners) && isa(app.UndoListeners, 'containers.Map')
                    keys_ = app.UndoListeners.keys;
                    for k = 1:numel(keys_)
                        listener = app.UndoListeners(keys_{k});
                        try
                            if ~isempty(listener) && isvalid(listener), delete(listener); end
                        catch
                        end
                    end
                    remove(app.UndoListeners, keys_);
                end
            catch, end
            app.UndoListeners = [];
            try
                if ~isempty(app.UndoServices) && isa(app.UndoServices, 'containers.Map')
                    remove(app.UndoServices, app.UndoServices.keys);
                end
            catch, end
            app.UndoServices = [];

            % [PHASE 3.5] Studio owns process-global async resources
            % once embedded sessions skipped pool teardown in their
            % delete(). Run a best-effort cleanup on any current parpool
            % so the next FlightReviewStudio session starts fresh. The
            % parpool itself is intentionally left alive — MATLAB
            % reuses it across runs for fast restart.
            try
                gp = gcp('nocreate');
                if ~isempty(gp) && isvalid(gp)
                    fCleanup = parfevalOnAll(gp, @flightdash.services.cleanupAsyncDecodeCache, 0);
                    try
                        wait(fCleanup, 'finished', 3);
                    catch
                        try, cancel(fCleanup); catch, end
                    end
                end
            catch ME
                try, app.logCaught(ME, 'Studio:globalPoolCleanup'); catch, end
            end

            try
                flightdash.util.SessionScope.clear();
            catch, end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch, end
        end

        function attachUndoStateListener(app, sessionId, undoService)
            try
                sessionId = char(sessionId);
                if isempty(app.UndoListeners) || ~isa(app.UndoListeners, 'containers.Map')
                    app.UndoListeners = containers.Map('KeyType', 'char', 'ValueType', 'any');
                end
                if app.UndoListeners.isKey(sessionId)
                    listener = app.UndoListeners(sessionId);
                    try
                        if ~isempty(listener) && isvalid(listener), delete(listener); end
                    catch
                    end
                    app.UndoListeners.remove(sessionId);
                end
                if ~isempty(undoService) && isvalid(undoService)
                    app.UndoListeners(sessionId) = addlistener(undoService, 'StateChanged', ...
                        @(src, evt) app.onUndoStateChanged(src, evt));
                end
            catch ME
                try, app.logCaught(ME, 'Studio:undoListener'); catch, end
            end
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
            theme = flightdash.ui.StudioTheme.colors();

            % --- Figure ---
            app.UIFigure = uifigure( ...
                'Name', 'FlightDataReviewStudio', ...
                'Position', app.initialFigurePosition(), ...
                'Color', theme.Background, ...
                'AutoResizeChildren', 'off');
            try
                setappdata(app.UIFigure, 'FlightReviewStudioApp', app);
            catch
            end
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
            app.UIFigure.WindowKeyPressFcn = @(~,evt) app.onKeyPress(evt);
            % [PHASE 4 review] Forward figure resize to whichever
            % dashboard is currently active so its responsive layout
            % recomputes column widths/profile when the user resizes
            % the Studio window or the browser viewport changes.
            app.UIFigure.SizeChangedFcn = @(~,~) app.onUIFigureResized();

            % --- Top-level grid: header / body / status bar ---
            shellGrid = uigridlayout(app.UIFigure, [3 1], ...
                'RowHeight', {UIScale.px(70), '1x', UIScale.px(28)}, ...
                'ColumnWidth', {'1x'}, ...
                'RowSpacing', 0, 'ColumnSpacing', 0, ...
                'Padding', [0 0 0 0]);

            % --- Header (menu + toolbar) ---
            app.HeaderPanel = uipanel(shellGrid, 'BorderType', 'none', ...
                'BackgroundColor', theme.Header);
            app.HeaderPanel.Layout.Row = 1;
            headerGrid = uigridlayout(app.HeaderPanel, [2 1], ...
                'RowHeight', {UIScale.px(28), UIScale.px(36)}, ...
                'RowSpacing', 0, 'Padding', [0 0 0 0]);

            app.CommandRouter = flightdash.studio.CommandRouter(app);
            app.MenuMgr    = flightdash.studio.MenuManager(app);
            app.ToolbarMgr = flightdash.studio.ToolbarManager(app, headerGrid);

            % --- Body (3-column: explorer | workspace | dock) ---
            % [PHASE 3c] Slim down the side panels so the workspace
            % column has enough width to keep the embedded
            % FlightDataDashboard out of NARROW profile (rail mode).
            app.BodyGrid = uigridlayout(shellGrid, [1 3], ...
                'ColumnWidth', {UIScale.px(220), '1x', UIScale.px(300)}, ...
                'RowHeight', {'1x'}, ...
                'ColumnSpacing', 4, 'Padding', [4 4 4 4], ...
                'BackgroundColor', theme.Background);
            app.BodyGrid.Layout.Row = 2;

            app.ProjectExplorer = flightdash.studio.ProjectExplorerPanel(app, app.BodyGrid);
            app.Workspace       = flightdash.studio.WorkspaceManager(app, app.BodyGrid);
            app.RightDock       = flightdash.studio.RightDockManager(app, app.BodyGrid);

            % --- Status bar ---
            app.StatusBarPanel = uipanel(shellGrid, 'BorderType', 'none', ...
                'BackgroundColor', theme.Header);
            app.StatusBarPanel.Layout.Row = 3;
            app.StatusBar = flightdash.studio.StatusBarManager(app, app.StatusBarPanel);

            % [PHASE 3.5] Centralize WindowButton callbacks. Drag
            % controllers in embedded mode reach the router via
            % getappdata(parentFigure, 'StudioMouseRouter') so they do
            % not need a direct reference to FlightReviewStudioApp.
            app.MouseRouter = flightdash.studio.StudioMouseRouter(app.UIFigure, app.Workspace);
            try
                setappdata(app.UIFigure, 'StudioMouseRouter', app.MouseRouter);
            catch
            end
            app.refreshUndoStateForActiveSession();

            % Theme policy (Task 3 + Patch 4 medium-term):
            % Read the persisted theme from Project.GuiTheme; older
            % projects without the field load as 'Light' via the
            % ProjectModel default + serializer fallback. The user can
            % flip Light <-> Dark from the Theme toolbar button or
            % Pref:Theme:Toggle command; toggleTheme writes the new
            % value back so Save persists it for the next launch.
            try
                stored = 'Light';
                if ~isempty(app.Project) && isprop(app.Project, 'GuiTheme') ...
                        && ~isempty(app.Project.GuiTheme)
                    stored = char(app.Project.GuiTheme);
                end
                if strcmpi(stored, 'Dark')
                    app.CurrentTheme = 'Dark';
                    app.CurrentThemeStruct = flightdash.ui.StudioTheme.dark();
                else
                    app.CurrentTheme = 'Light';
                    app.CurrentThemeStruct = flightdash.ui.StudioTheme.light();
                end
                flightdash.ui.StudioTheme.apply(app.UIFigure, app.CurrentThemeStruct);
            catch
            end
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

        function onKeyPress(app, evt)
            try
                key = lower(char(evt.Key));
                modifiers = lower(string(evt.Modifier));
                if strcmp(key, 'z') && any(modifiers == "control")
                    app.dispatchCommand('Edit:Undo', 'Shortcut');
                elseif strcmp(key, 'y') && any(modifiers == "control")
                    app.dispatchCommand('Edit:Redo', 'Shortcut');
                end
            catch ME
                try, app.logCaught(ME, 'Studio:keyPress'); catch, end
            end
        end

        function stopStatusRestoreTimer(app)
            try
                if ~isempty(app.StatusRestoreTimer) && isvalid(app.StatusRestoreTimer)
                    stop(app.StatusRestoreTimer);
                    delete(app.StatusRestoreTimer);
                end
            catch
            end
            app.StatusRestoreTimer = [];
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
