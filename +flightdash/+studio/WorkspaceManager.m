classdef WorkspaceManager < handle
    % flightdash.studio.WorkspaceManager
    % Center area: tabgroup that hosts Dashboard / Graph / Result / Report
    % tabs. Phase 1 shows a welcome tab only; Phase 3 embeds dashboards.
    %
    % Active session tracking (Phase 0.8 prep):
    %   SelectionChangedFcn updates app.ActiveSessionId so controllers
    %   can gate WindowButton callbacks by the active tab's session id.

    properties (Access = public)
        App
        Panel        % uipanel
        TabGroup     % uitabgroup
        WelcomeTab   % uitab
        % [PHASE 3b] Map of SessionId -> embedded FlightDataDashboard
        % handle, plus the uitab that hosts it.
        DashboardEntries  % containers.Map (created in ctor)
        % Phase C Start Page widgets.
        RecentList        % uilistbox on the WelcomeTab
        StartPageFooter   % uilabel showing runtime status line
    end

    methods
        function obj = WorkspaceManager(app, parentGrid)
            obj.App = app;
            obj.DashboardEntries = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.build(parentGrid);
        end

        function delete(obj)
            % Tear down embedded dashboards before parent uitabs go away.
            try
                if ~isempty(obj.DashboardEntries)
                    keys_ = obj.DashboardEntries.keys;
                    for k = 1:numel(keys_)
                        entry = obj.DashboardEntries(keys_{k});
                        obj.releaseSessionResources(keys_{k}, entry);
                        try
                            if ~isempty(entry.Dashboard) && isvalid(entry.Dashboard)
                                delete(entry.Dashboard);
                            end
                        catch, end
                    end
                end
            catch, end
        end

        function tab = addDashboardTab(obj, sessionId, displayName, sessionModel)
            % [PHASE 3b] Create a workspace tab and embed a
            % FlightDataDashboard inside it for the given session.
            if nargin < 4
                sessionModel = [];
            end
            sessionId = char(sessionId);
            displayName = char(displayName);
            if obj.DashboardEntries.isKey(sessionId)
                % Bring existing tab to front
                entry = obj.DashboardEntries(sessionId);
                if ~isempty(entry.Tab) && isvalid(entry.Tab)
                    obj.TabGroup.SelectedTab = entry.Tab;
                    tab = entry.Tab;
                    return;
                end
            end

            tab = uitab(obj.TabGroup, 'Title', displayName);
            tab.UserData = struct('SessionId', sessionId);

            try
                % Create dashboard with this tab as parent. Constructor
                % builds its full UI inside the tab.
                dash = flightdash.FlightDataDashboard(tab, sessionId);
                obj.attachSharedServices(dash);
                if ~isempty(sessionModel) && ismethod(dash, 'applySessionSnapshot')
                    dash.applySessionSnapshot(sessionModel);
                end

                obj.DashboardEntries(sessionId) = struct( ...
                    'SessionId', sessionId, ...
                    'Tab',       tab, ...
                    'Dashboard', dash);

                obj.TabGroup.SelectedTab = tab;
                obj.onTabChanged();

                % Safety net: if SelectedTab is still pointing at the
                % WelcomeTab (rare timing race when the tab group hasn't
                % flushed selection yet), force the switch again.
                if ~isempty(obj.WelcomeTab) && isvalid(obj.WelcomeTab) ...
                        && isequal(obj.TabGroup.SelectedTab, obj.WelcomeTab)
                    obj.TabGroup.SelectedTab = tab;
                    obj.onTabChanged();
                end

                % Phase 11: propagate the active Studio theme into the
                % newly built dashboard chrome so it doesn't render with
                % default colors until the next toggle. Cheap (one
                % findall on the tab subtree).
                try
                    if ~isempty(obj.App) && isvalid(obj.App) ...
                            && isprop(obj.App, 'CurrentThemeStruct') ...
                            && isstruct(obj.App.CurrentThemeStruct) ...
                            && isfield(obj.App.CurrentThemeStruct, 'Background')
                        flightdash.ui.StudioTheme.apply(tab, obj.App.CurrentThemeStruct);
                    end
                catch ME
                    obj.logIfPossible(ME, 'Workspace:addDashboardTab:theme');
                end
            catch ME
                % Roll back the empty tab if dashboard construction fails
                try, delete(tab); catch, end
                rethrow(ME);
            end
        end

        function removeDashboardTab(obj, sessionId)
            sessionId = char(sessionId);
            if ~obj.DashboardEntries.isKey(sessionId), return; end
            % Snapshot surviving keys BEFORE any teardown so we can detect
            % accidental collateral removal (RISK-5 regression guard).
            try
                survivorKeys = setdiff(obj.DashboardEntries.keys, {sessionId});
            catch
                survivorKeys = {};
            end
            entry = obj.DashboardEntries(sessionId);
            obj.releaseSessionResources(sessionId, entry);
            try
                if ~isempty(entry.Dashboard) && isvalid(entry.Dashboard)
                    delete(entry.Dashboard);
                end
            catch, end
            try
                if ~isempty(entry.Tab) && isvalid(entry.Tab)
                    delete(entry.Tab);
                end
            catch, end
            if obj.DashboardEntries.isKey(sessionId)
                obj.DashboardEntries.remove(sessionId);
            end
            % Defensive: ensure releaseSessionResources / delete cascades
            % did not silently drop unrelated sessions. If they did, log
            % the discrepancy (cannot resurrect, but tests will see it).
            try
                missing = setdiff(survivorKeys, obj.DashboardEntries.keys);
                if ~isempty(missing) && ~isempty(obj.App) && isvalid(obj.App)
                    obj.App.logCaught( ...
                        MException('Workspace:CollateralRemoval', ...
                            'Sessions unexpectedly removed: %s', strjoin(missing, ', ')), ...
                        'Workspace:removeDashboardTab:collateral');
                end
            catch
            end
            try, obj.onTabChanged(); catch, end
        end

        function closeActiveTab(obj)
            % [PHASE 3c] Close the currently selected workspace tab AND
            % drop the matching session from the project model so
            % Project Explorer no longer lists it.
            try
                if isempty(obj.TabGroup) || ~isvalid(obj.TabGroup), return; end
                activeTab = obj.TabGroup.SelectedTab;
                if isempty(activeTab), return; end
                if ~isempty(obj.WelcomeTab) && isequal(activeTab, obj.WelcomeTab)
                    return;  % don't close the welcome placeholder
                end
                sessionId = obj.tabSessionId(activeTab);
                if ~isempty(sessionId) && ~isempty(obj.App) && isvalid(obj.App)
                    obj.App.removeSession(sessionId);  % cascades: project + tab + explorer
                else
                    try, delete(activeTab); catch, end
                    obj.onTabChanged();
                end
            catch ME
                obj.logIfPossible(ME, 'Workspace:closeActiveTab');
            end
        end

        function closeAllTabs(obj)
            % [PHASE 3c] Close every dashboard tab, dropping every
            % matching session from the project model.
            try
                if ~isempty(obj.App) && isvalid(obj.App)
                    obj.App.removeAllSessions();
                end
            catch ME
                obj.logIfPossible(ME, 'Workspace:closeAllTabs');
            end
        end

        function id = tabSessionId(~, tab)
            id = '';
            try
                if ~isempty(tab) && isvalid(tab) && isstruct(tab.UserData) ...
                        && isfield(tab.UserData, 'SessionId')
                    id = char(tab.UserData.SessionId);
                end
            catch
            end
        end

        function renameDashboardTab(obj, sessionId, newName)
            % [PHASE 5] Update the workspace tab title for the given session.
            sessionId = char(sessionId);
            if ~obj.DashboardEntries.isKey(sessionId), return; end
            entry = obj.DashboardEntries(sessionId);
            try
                if ~isempty(entry.Tab) && isvalid(entry.Tab)
                    entry.Tab.Title = char(newName);
                end
            catch
            end
        end

        function tf = selectSession(obj, sessionId)
            % [PHASE 3c] Switch the workspace to the tab bound to the
            % given session id. Returns true if a matching tab existed.
            tf = false;
            sessionId = char(sessionId);
            try
                if ~obj.DashboardEntries.isKey(sessionId), return; end
                entry = obj.DashboardEntries(sessionId);
                if ~isempty(entry.Tab) && isvalid(entry.Tab) ...
                        && ~isempty(obj.TabGroup) && isvalid(obj.TabGroup)
                    obj.TabGroup.SelectedTab = entry.Tab;
                    obj.onTabChanged();
                    tf = true;
                end
            catch
            end
        end

        function refreshActiveLayout(obj, reason)
            % [PHASE 4 review] Notify the active session's dashboard to
            % rerun its responsive layout. Called when:
            %   - Studio's UIFigure changes size
            %   - The user switches tabs
            %   - Side dock widths change
            % Without this, the embedded dashboard keeps the column
            % widths it computed when the tab was first opened.
            if nargin < 2, reason = 'workspace'; end
            try
                if isempty(obj.DashboardEntries) || obj.DashboardEntries.Count == 0
                    return;
                end
                if isempty(obj.TabGroup) || ~isvalid(obj.TabGroup), return; end
                activeTab = obj.TabGroup.SelectedTab;
                if isempty(activeTab) || ~isvalid(activeTab), return; end
                sessId = obj.tabSessionId(activeTab);
                if isempty(sessId) || ~obj.DashboardEntries.isKey(sessId), return; end
                entry = obj.DashboardEntries(sessId);
                dash = entry.Dashboard;
                if ~isempty(dash) && isvalid(dash)
                    if ismethod(dash, 'refreshLayout')
                        dash.refreshLayout(reason);
                    elseif ~isempty(dash.LayoutMgr) && isvalid(dash.LayoutMgr)
                        dash.LayoutMgr.applyLayout(dash, char(reason));
                    end
                end
            catch ME
                obj.logIfPossible(ME, 'Workspace:refreshActiveLayout');
            end
        end

        function id = activeSessionId(obj)
            % Phase 1: returns 'standalone' since no real sessions exist.
            % Phase 3: returns the SessionId stored on the active tab's UserData.
            id = 'standalone';
            try
                if ~isempty(obj.TabGroup) && isvalid(obj.TabGroup)
                    activeTab = obj.TabGroup.SelectedTab;
                    if ~isempty(activeTab) && ~isempty(activeTab.UserData) ...
                            && isfield(activeTab.UserData, 'SessionId')
                        id = activeTab.UserData.SessionId;
                    end
                end
            catch
            end
        end
    end

    methods (Access = private)
        function build(obj, parentGrid)
            obj.Panel = uipanel(parentGrid, ...
                'Title', 'Workspace', 'FontWeight', 'bold', ...
                'BackgroundColor', 'w');
            obj.Panel.Layout.Column = 2;

            grid = uigridlayout(obj.Panel, [1 1], ...
                'RowHeight', {'1x'}, 'Padding', [4 4 4 4]);

            obj.TabGroup = uitabgroup(grid);
            obj.TabGroup.SelectionChangedFcn = @(~,~) obj.onTabChanged();

            % Phase C: Start Page replaces the bare welcome placeholder.
            % Action buttons + Recent Projects list. Tab still uses the
            % 'standalone' session-id so existing auto-Session-1 and
            % WelcomeTab safety net code paths keep working.
            obj.WelcomeTab = uitab(obj.TabGroup, 'Title', 'Welcome');
            obj.WelcomeTab.UserData = struct('SessionId', 'standalone');
            obj.buildStartPage(obj.WelcomeTab);
        end

        function buildStartPage(obj, tab)
            UIScale = flightdash.util.UIScale;
            root = uigridlayout(tab, [4 1], ...
                'RowHeight', {UIScale.px(64), UIScale.px(120), '1x', UIScale.px(36)}, ...
                'ColumnWidth', {'1x'}, ...
                'RowSpacing', 12, 'Padding', [32 28 32 24]);

            % Title row.
            titleGrid = uigridlayout(root, [2 1], ...
                'RowHeight', {'fit','fit'}, 'RowSpacing', 2, 'Padding', [0 0 0 0]);
            uilabel(titleGrid, 'Text', 'Flight Review Studio', ...
                'FontSize', 22, 'FontWeight', 'bold');
            uilabel(titleGrid, 'Text', 'Multi-session flight-data review with synchronized video.', ...
                'FontSize', 12, 'FontColor', [0.4 0.4 0.4]);

            % Action button grid (5 buttons).
            actionGrid = uigridlayout(root, [1 5], ...
                'ColumnWidth', repmat({'1x'}, 1, 5), ...
                'ColumnSpacing', 10, 'Padding', [0 0 0 0]);
            uibutton(actionGrid, 'Text', 'New Review Session', 'FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.startPageAction('NewSession'));
            uibutton(actionGrid, 'Text', 'Open Project…',      'FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.startPageAction('OpenProject'));
            uibutton(actionGrid, 'Text', 'Open Sample Project','FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.startPageAction('OpenSample'));
            uibutton(actionGrid, 'Text', 'Load Flight Data…',  'FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.startPageAction('LoadData'));
            uibutton(actionGrid, 'Text', 'Quick Start Guide',  'FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.startPageAction('QuickStart'));

            % Recent Projects list.
            recentPanel = uipanel(root, 'Title', 'Recent Projects', ...
                'FontWeight', 'bold', 'BorderType', 'line');
            recentGrid = uigridlayout(recentPanel, [1 1], 'Padding', [4 4 4 4]);
            obj.RecentList = uilistbox(recentGrid, ...
                'Items', flightdash.util.UserPreferences.getRecentProjects(), ...
                'DoubleClickedFcn', @(src,~) obj.openRecentProject(src.Value));
            if isempty(obj.RecentList.Items)
                obj.RecentList.Items = {'(no recent projects yet)'};
                obj.RecentList.Enable = 'off';
            end

            % Footer (runtime status).
            footer = uilabel(root, 'Text', obj.runtimeStatusLine(), ...
                'FontSize', 10, 'FontColor', [0.45 0.45 0.45]);
            obj.StartPageFooter = footer;
        end

        function refreshStartPage(obj)
            try
                if ~isempty(obj.RecentList) && isvalid(obj.RecentList)
                    items = flightdash.util.UserPreferences.getRecentProjects();
                    if isempty(items)
                        obj.RecentList.Items = {'(no recent projects yet)'};
                        obj.RecentList.Enable = 'off';
                    else
                        obj.RecentList.Items = items;
                        obj.RecentList.Enable = 'on';
                    end
                end
                if ~isempty(obj.StartPageFooter) && isvalid(obj.StartPageFooter)
                    obj.StartPageFooter.Text = obj.runtimeStatusLine();
                end
            catch
            end
        end

        function startPageAction(obj, action)
            try
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                switch char(action)
                    case 'NewSession'
                        obj.App.addSession();
                    case 'OpenProject'
                        obj.App.dispatchCommand('File:OpenProject', 'StartPage');
                    case 'OpenSample'
                        obj.openSampleProject();
                    case 'LoadData'
                        obj.App.dispatchCommand('Toolbar:LoadData', 'StartPage');
                    case 'QuickStart'
                        obj.App.dispatchCommand('Help:QuickStart', 'StartPage');
                end
            catch ME
                warning('WorkspaceManager:StartPageAction', '%s', ME.message);
            end
        end

        function openRecentProject(obj, path)
            try
                path = char(path);
                if isempty(path) || ~isfile(path), return; end
                if ismethod(obj.App, 'openProject')
                    obj.App.openProject(path);
                end
            catch ME
                warning('WorkspaceManager:OpenRecent', '%s', ME.message);
            end
        end

        function openSampleProject(obj)
            % Review fix: WorkspaceManager.m lives at
            % <root>/+flightdash/+studio/WorkspaceManager.m so the
            % repo root is two `..` levels up — NOT three. The previous
            % three-up calculation landed one directory above <root>,
            % making the Start Page sample button always report
            % "not found" even on installs that shipped the sample.
            try
                here = fileparts(mfilename('fullpath'));
                root = fullfile(here, '..', '..');
                if ~isfolder(root)
                    obj.notifyStatus(sprintf( ...
                        'Sample project search: repo root "%s" not a folder.', root));
                    return;
                end
                samplePath = fullfile(root, 'sample_data', 'sample_project.frsproj');
                if isfile(samplePath) && ismethod(obj.App, 'openProject')
                    obj.App.openProject(samplePath);
                else
                    obj.notifyStatus(sprintf( ...
                        'Sample project not found at %s', samplePath));
                end
            catch ME
                warning('WorkspaceManager:OpenSample', '%s', ME.message);
                obj.logIfPossible(ME, 'WorkspaceManager:openSampleProject');
            end
        end

        function notifyStatus(obj, msg)
            try
                if ~isempty(obj.App) && isvalid(obj.App) ...
                        && ~isempty(obj.App.StatusBar) && isvalid(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(msg);
                end
            catch
            end
        end

        function logIfPossible(obj, ME, tag)
            try
                if ~isempty(obj.App) && isa(obj.App, 'handle') && isvalid(obj.App) ...
                        && ismethod(obj.App, 'logCaught')
                    obj.App.logCaught(ME, tag);
                end
            catch
            end
        end

        function line = runtimeStatusLine(~)
            try
                vi = flightdash.util.VersionInfo.current();
                line = sprintf('v%s   |   MATLAB R%s   |   %s', ...
                    vi.Version, vi.MatlabRelease, vi.SupportEmail);
            catch
                line = '';
            end
        end

        function onTabChanged(obj)
            % Update active session id (Phase 0.8 prep) and notify status.
            % [PHASE 4] Also publish the session id to SessionScope so
            % every per-session controller's EventBus gate can read it,
            % and ask the newly active dashboard to recompute its
            % responsive layout (the tab area may have changed size
            % while it was hidden).
            try
                newId = obj.activeSessionId();
                if ~isempty(obj.App) && isvalid(obj.App)
                    obj.App.ActiveSessionId = newId;
                    if ~isempty(obj.App.StatusBar)
                        obj.App.StatusBar.setActiveSession(newId);
                    end
                end
                if isempty(newId) || strcmp(newId, 'standalone')
                    flightdash.util.SessionScope.clear();
                else
                    flightdash.util.SessionScope.setActive(newId);
                end
                % Phase 10: notify the shared decode service so requests
                % from the newly active session get priority 0 and stale
                % background-session requests fall to priority 10.
                try
                    if ~isempty(obj.App) && isvalid(obj.App) ...
                            && isprop(obj.App, 'SharedDecodeService') ...
                            && ~isempty(obj.App.SharedDecodeService) ...
                            && isvalid(obj.App.SharedDecodeService) ...
                            && ismethod(obj.App.SharedDecodeService, 'setActiveSession')
                        obj.App.SharedDecodeService.setActiveSession(newId);
                    end
                catch ME
                    obj.logIfPossible(ME, 'Workspace:onTabChanged:sharedDecode');
                end
                obj.refreshActiveLayout('tabActivated');
                obj.refreshActiveInspector();
                obj.refreshActiveUndoUi();
            catch ME
                warning('WorkspaceManager:onTabChanged', '%s', ME.message);
            end
        end

        function refreshActiveInspector(obj)
            % [PHASE 6b] Repopulate Object Manager + clear Inspector for
            % whichever dashboard owns the active workspace tab.
            try
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                if isempty(obj.App.RightDock) || ~isvalid(obj.App.RightDock), return; end
                dash = obj.activeDashboard();
                obj.App.RightDock.refreshObjectsFor(dash);
            catch
            end
        end

        function refreshActiveUndoUi(obj)
            try
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                dash = obj.activeDashboard();
                if ~isempty(obj.App.RightDock) && isvalid(obj.App.RightDock) && ...
                        ismethod(obj.App.RightDock, 'refreshHistoryForDashboard')
                    obj.App.RightDock.refreshHistoryForDashboard(dash);
                end
                if ismethod(obj.App, 'refreshUndoStateForActiveSession')
                    obj.App.refreshUndoStateForActiveSession();
                end
            catch
            end
        end

        function dash = activeDashboard(obj)
            % [PHASE 6b] Return the FlightDataDashboard handle bound to
            % the currently selected workspace tab, or [] if Welcome.
            dash = [];
            try
                if isempty(obj.TabGroup) || ~isvalid(obj.TabGroup), return; end
                t = obj.TabGroup.SelectedTab;
                sid = obj.tabSessionId(t);
                if isempty(sid), return; end
                if obj.DashboardEntries.isKey(sid)
                    e = obj.DashboardEntries(sid);
                    if isfield(e, 'Dashboard') && ~isempty(e.Dashboard) && isvalid(e.Dashboard)
                        dash = e.Dashboard;
                    end
                end
            catch
            end
        end

        function attachSharedServices(obj, dash)
            try
                if isempty(dash) || ~isvalid(dash), return; end
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                if isprop(obj.App, 'MouseRouter') && ~isempty(obj.App.MouseRouter) && ...
                        isvalid(obj.App.MouseRouter) && ismethod(dash, 'setMouseRouter')
                    dash.setMouseRouter(obj.App.MouseRouter);
                end
                if ismethod(obj.App, 'ensureSharedServices') && ismethod(dash, 'setSharedServices')
                    [cacheService, decodeService] = obj.App.ensureSharedServices();
                    dash.setSharedServices(cacheService, decodeService);
                end
                if isprop(dash, 'UndoService') && ismethod(obj.App, 'getUndoService')
                    dash.UndoService = obj.App.getUndoService(dash.ActiveSessionId);
                end
            catch ME
                try, obj.App.logCaught(ME, 'Workspace:sharedServices'); catch, end
            end
        end

        function releaseSessionResources(obj, sessionId, entry)
            sessionId = char(sessionId);
            if nargin < 3
                entry = struct();
            end
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ...
                        ~isempty(obj.App.MouseRouter) && isvalid(obj.App.MouseRouter) && ...
                        ismethod(obj.App.MouseRouter, 'cancelSession')
                    obj.App.MouseRouter.cancelSession(sessionId);
                end
            catch
            end
            try
                if isstruct(entry) && isfield(entry, 'Dashboard') && ...
                        ~isempty(entry.Dashboard) && isvalid(entry.Dashboard) && ...
                        ismethod(entry.Dashboard, 'prepareForSessionUnload')
                    entry.Dashboard.prepareForSessionUnload();
                end
            catch ME
                try, obj.App.logCaught(ME, 'Workspace:sessionUnload'); catch, end
            end
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ...
                        ~isempty(obj.App.SharedDecodeService) && isvalid(obj.App.SharedDecodeService)
                    obj.App.SharedDecodeService.cancelSession(sessionId);
                end
            catch
            end
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ...
                        ~isempty(obj.App.SharedCacheService) && isvalid(obj.App.SharedCacheService)
                    obj.App.SharedCacheService.invalidateSession(sessionId);
                end
            catch
            end
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ismethod(obj.App, 'removeUndoService')
                    obj.App.removeUndoService(sessionId);
                end
            catch
            end
        end
    end
end
