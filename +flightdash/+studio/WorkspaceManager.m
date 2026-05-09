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
                if ~isempty(obj.DashboardEntries) && isvalid(obj.DashboardEntries)
                    keys_ = obj.DashboardEntries.keys;
                    for k = 1:numel(keys_)
                        entry = obj.DashboardEntries(keys_{k});
                        try
                            if ~isempty(entry.Dashboard) && isvalid(entry.Dashboard)
                                delete(entry.Dashboard);
                            end
                        catch, end
                    end
                end
            catch, end
        end

        function tab = addDashboardTab(obj, sessionId, displayName)
            % [PHASE 3b] Create a workspace tab and embed a
            % FlightDataDashboard inside it for the given session.
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

                obj.DashboardEntries(sessionId) = struct( ...
                    'SessionId', sessionId, ...
                    'Tab',       tab, ...
                    'Dashboard', dash);

                obj.TabGroup.SelectedTab = tab;
                obj.onTabChanged();
            catch ME
                % Roll back the empty tab if dashboard construction fails
                try, delete(tab); catch, end
                rethrow(ME);
            end
        end

        function removeDashboardTab(obj, sessionId)
            if ~obj.DashboardEntries.isKey(sessionId), return; end
            entry = obj.DashboardEntries(sessionId);
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
            obj.DashboardEntries.remove(sessionId);
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
            catch
            end
        end

        function closeAllTabs(obj)
            % [PHASE 3c] Close every dashboard tab, dropping every
            % matching session from the project model.
            try
                if ~isempty(obj.App) && isvalid(obj.App)
                    obj.App.removeAllSessions();
                end
            catch
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
            catch
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

            % Phase 1 welcome / placeholder tab
            obj.WelcomeTab = uitab(obj.TabGroup, 'Title', 'Welcome');
            obj.WelcomeTab.UserData = struct('SessionId', 'standalone');
            welcomeGrid = uigridlayout(obj.WelcomeTab, [3 1], ...
                'RowHeight', {'1x', 'fit', '1x'}, ...
                'ColumnWidth', {'1x'}, ...
                'Padding', [40 40 40 40]);
            uilabel(welcomeGrid, 'Text', 'FlightDataReviewStudio', ...
                'FontSize', 22, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(welcomeGrid, 'Text', ...
                ['Phase 1 shell. Use Project > Add Review Session to ' ...
                 'open a FlightDataDashboard tab here (Phase 3+).'], ...
                'FontSize', 12, 'WordWrap', 'on', ...
                'HorizontalAlignment', 'center', ...
                'FontColor', [0.4 0.4 0.4]);
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
                obj.refreshActiveLayout('tabActivated');
                obj.refreshActiveInspector();
            catch
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
    end
end
