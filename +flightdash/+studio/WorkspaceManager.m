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
        Panel        matlab.ui.container.Panel
        TabGroup     matlab.ui.container.TabGroup
        WelcomeTab   matlab.ui.container.Tab
    end

    methods
        function obj = WorkspaceManager(app, parentGrid)
            obj.App = app;
            obj.build(parentGrid);
        end

        function delete(~)
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
