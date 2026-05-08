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
            % [PHASE 3c] Close the currently selected workspace tab.
            % The Welcome tab is preserved (it's the placeholder when
            % no sessions are open).
            try
                if isempty(obj.TabGroup) || ~isvalid(obj.TabGroup), return; end
                activeTab = obj.TabGroup.SelectedTab;
                if isempty(activeTab), return; end
                if ~isempty(obj.WelcomeTab) && isequal(activeTab, obj.WelcomeTab)
                    return;  % don't close the welcome placeholder
                end
                sessionId = obj.tabSessionId(activeTab);
                if ~isempty(sessionId)
                    obj.removeDashboardTab(sessionId);
                else
                    try, delete(activeTab); catch, end
                    obj.onTabChanged();
                end
            catch
            end
        end

        function closeAllTabs(obj)
            % [PHASE 3c] Close every dashboard tab. Welcome stays.
            try
                if isempty(obj.DashboardEntries), return; end
                ids = obj.DashboardEntries.keys;
                for k = 1:numel(ids)
                    obj.removeDashboardTab(ids{k});
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
            try
                newId = obj.activeSessionId();
                if ~isempty(obj.App) && isvalid(obj.App)
                    obj.App.ActiveSessionId = newId;
                    if ~isempty(obj.App.StatusBar)
                        obj.App.StatusBar.setActiveSession(newId);
                    end
                end
            catch
            end
        end
    end
end
