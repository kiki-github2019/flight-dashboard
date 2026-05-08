classdef RightDockManager < handle
    % flightdash.studio.RightDockManager
    % Right-side dock with 4 stacked tabs:
    %   Inspector       - Property editor for the selected object
    %   Object Manager  - Tree of objects in the active workspace tab
    %   Logs            - Message / Error / Result log views
    %   Apps            - Installed analysis apps (placeholder)
    %
    % Phase 1: tab shells only. Phase 6b wires Inspector + ObjectManager
    % to selection events. Phase 6c adds Mini Toolbar quick action row
    % at the top of Inspector (per UI reality check §2.2.2).

    properties (Access = public)
        App
        Panel              % uipanel
        TabGroup           % uitabgroup
        InspectorTab       % uitab
        ObjectManagerTab   % uitab
        LogsTab            % uitab
        AppsTab            % uitab

        % Inspector content (Phase 6c: quick action row goes here)
        InspectorQuickRow  % uigridlayout
        InspectorBody      % uigridlayout

        % Object Manager
        ObjectTree         % uitree

        % Logs (3 sub-tabs)
        LogTabGroup        % uitabgroup
        MessageLogTable    % uitable
        ErrorLogTable      % uitable
        ResultLogTable     % uitable
    end

    methods
        function obj = RightDockManager(app, parentGrid)
            obj.App = app;
            obj.build(parentGrid);
        end

        function delete(~)
        end
    end

    methods (Access = private)
        function build(obj, parentGrid)
            obj.Panel = uipanel(parentGrid, ...
                'BorderType', 'line', ...
                'BackgroundColor', 'w');
            obj.Panel.Layout.Column = 3;

            grid = uigridlayout(obj.Panel, [1 1], ...
                'RowHeight', {'1x'}, 'Padding', [2 2 2 2]);

            obj.TabGroup = uitabgroup(grid);

            obj.InspectorTab     = obj.buildInspectorTab();
            obj.ObjectManagerTab = obj.buildObjectManagerTab();
            obj.LogsTab          = obj.buildLogsTab();
            obj.AppsTab          = obj.buildAppsTab();
        end

        function tab = buildInspectorTab(obj)
            UIScale = flightdash.util.UIScale;
            tab = uitab(obj.TabGroup, 'Title', 'Inspector');
            grid = uigridlayout(tab, [2 1], ...
                'RowHeight', {UIScale.px(36), '1x'}, ...
                'RowSpacing', 4, 'Padding', [4 4 4 4]);

            % Quick action row (Mini Toolbar replacement, Phase 6c expands)
            obj.InspectorQuickRow = uigridlayout(grid, [1 4], ...
                'ColumnWidth', {'1x', '1x', '1x', '1x'}, ...
                'ColumnSpacing', 3, 'Padding', [0 0 0 0]);
            uibutton(obj.InspectorQuickRow, 'Text', 'Show', 'FontSize', 10);
            uibutton(obj.InspectorQuickRow, 'Text', 'Hide', 'FontSize', 10);
            uibutton(obj.InspectorQuickRow, 'Text', 'Color', 'FontSize', 10);
            uibutton(obj.InspectorQuickRow, 'Text', 'Style', 'FontSize', 10);

            % Body: empty placeholder grid for properties (Phase 6b fills)
            obj.InspectorBody = uigridlayout(grid, [1 1], ...
                'RowHeight', {'1x'}, 'Padding', [4 4 4 4]);
            uilabel(obj.InspectorBody, ...
                'Text', '(Select an object to view its properties)', ...
                'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'center');
        end

        function tab = buildObjectManagerTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'Object Manager');
            grid = uigridlayout(tab, [1 1], ...
                'Padding', [4 4 4 4]);
            obj.ObjectTree = uitree(grid, 'tree');

            % Phase 1: placeholder structure mirroring planned hierarchy
            root = uitreenode(obj.ObjectTree, 'Text', 'Active Workspace (none)');
            f1 = uitreenode(root, 'Text', 'Flight 1');
            uitreenode(f1, 'Text', 'Map');
            uitreenode(f1, 'Text', 'Altitude Plot');
            uitreenode(f1, 'Text', 'Video Panel');
            uitreenode(f1, 'Text', 'Current Marker');
            uitreenode(f1, 'Text', 'ROI Bands');
            uitreenode(f1, 'Text', 'Event Markers');
            f2 = uitreenode(root, 'Text', 'Flight 2');
            uitreenode(f2, 'Text', 'Map');
            uitreenode(f2, 'Text', 'Altitude Plot');
            uitreenode(f2, 'Text', 'Video Panel');
            try, expand(root); catch, end
        end

        function tab = buildLogsTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'Logs');
            grid = uigridlayout(tab, [1 1], 'Padding', [2 2 2 2]);
            obj.LogTabGroup = uitabgroup(grid);

            msgTab = uitab(obj.LogTabGroup, 'Title', 'Message');
            msgGrid = uigridlayout(msgTab, [1 1], 'Padding', [2 2 2 2]);
            obj.MessageLogTable = uitable(msgGrid, 'Data', cell(0, 3), ...
                'ColumnName', {'Time', 'Tag', 'Message'}, ...
                'ColumnWidth', {110, 100, 'auto'}, ...
                'RowName', []);

            errTab = uitab(obj.LogTabGroup, 'Title', 'Error');
            errGrid = uigridlayout(errTab, [1 1], 'Padding', [2 2 2 2]);
            obj.ErrorLogTable = uitable(errGrid, 'Data', cell(0, 4), ...
                'ColumnName', {'Time', 'Session', 'Tag', 'Identifier'}, ...
                'ColumnWidth', {110, 80, 100, 'auto'}, ...
                'RowName', []);

            resTab = uitab(obj.LogTabGroup, 'Title', 'Result');
            resGrid = uigridlayout(resTab, [1 1], 'Padding', [2 2 2 2]);
            obj.ResultLogTable = uitable(resGrid, 'Data', cell(0, 4), ...
                'ColumnName', {'Time', 'Session', 'Type', 'Summary'}, ...
                'ColumnWidth', {110, 80, 90, 'auto'}, ...
                'RowName', []);
        end

        function tab = buildAppsTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'Apps');
            grid = uigridlayout(tab, [1 1], 'Padding', [12 12 12 12]);
            uilabel(grid, ...
                'Text', '(Installed analysis apps will appear here)', ...
                'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'center');
        end
    end
end
