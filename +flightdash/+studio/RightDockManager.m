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
        ShowBtn            % quick-action handle (Phase 6b)
        HideBtn            % quick-action handle (Phase 6b)

        % Object Manager
        ObjectTree         % uitree
        SelectedHandle     = []  % graphics handle currently shown in Inspector

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
            obj.ShowBtn = uibutton(obj.InspectorQuickRow, 'Text', 'Show', 'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) obj.onQuickAction('show'));
            obj.HideBtn = uibutton(obj.InspectorQuickRow, 'Text', 'Hide', 'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) obj.onQuickAction('hide'));
            uibutton(obj.InspectorQuickRow, 'Text', 'Color', 'FontSize', 10, 'Enable', 'off');
            uibutton(obj.InspectorQuickRow, 'Text', 'Style', 'FontSize', 10, 'Enable', 'off');

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
            obj.ObjectTree.SelectionChangedFcn = @(~,evt) obj.onObjectTreeSelect(evt);
            obj.populateObjectTreeForDashboard([]);
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

    methods (Access = public)

        function refreshObjectsFor(obj, dashboard)
            % [PHASE 6b] Rebuild Object Manager tree from active dashboard.
            if isempty(obj.ObjectTree) || ~isvalid(obj.ObjectTree), return; end
            obj.populateObjectTreeForDashboard(dashboard);
            obj.SelectedHandle = [];
            obj.rebuildInspector([]);
        end

    end

    methods (Access = private)

        function populateObjectTreeForDashboard(obj, dashboard)
            % Drop existing children and rebuild from dashboard.UI.
            kids = obj.ObjectTree.Children;
            for i = numel(kids):-1:1, try, delete(kids(i)); catch, end, end

            if isempty(dashboard) || ~isvalid(dashboard) || ~isprop(dashboard, 'UI') || isempty(dashboard.UI)
                uitreenode(obj.ObjectTree, 'Text', 'Active Workspace (none)');
                return;
            end

            sessId = '';
            if isprop(dashboard, 'ActiveSessionId'), sessId = char(dashboard.ActiveSessionId); end
            rootText = sprintf('Active: %s', sessId);
            if isempty(sessId), rootText = 'Active Workspace'; end
            root = uitreenode(obj.ObjectTree, 'Text', rootText);

            % Static panel handles per channel — keep the list short
            % so the tree stays scannable; ROI / Plot expansion goes to
            % a Phase 6b v2 cycle.
            specs = { ...
                'mapAxes',         'Map'; ...
                'altAxes',         'Altitude Plot'; ...
                'attitudeContent', 'Attitude Panel'; ...
                'plotShellGrid',   'Plot Area'; ...
                'pannerPanel',     'Panner'; ...
                'videoContent',    'Video Player'; ...
                'infoTable',       'Current Info Table' ...
            };

            nChannels = min(2, numel(dashboard.UI));
            for fIdx = 1:nChannels
                ch = uitreenode(root, 'Text', sprintf('Flight %d', fIdx));
                for k = 1:size(specs, 1)
                    field = specs{k, 1};
                    label = specs{k, 2};
                    h = obj.uiField(dashboard.UI(fIdx), field);
                    valid = ~isempty(h) && all(isgraphics(h));
                    leafText = label;
                    if ~valid, leafText = [label ' (n/a)']; end
                    uitreenode(ch, 'Text', leafText, ...
                        'NodeData', struct( ...
                            'Kind',       'handle', ...
                            'ChannelIdx', fIdx, ...
                            'Field',      field, ...
                            'Label',      label, ...
                            'Dashboard',  dashboard, ...
                            'Handle',     h));
                end
            end
            try, expand(root); catch, end
        end

        function h = uiField(~, uiStruct, name)
            h = [];
            try
                if isstruct(uiStruct) && isfield(uiStruct, name)
                    h = uiStruct.(name);
                end
            catch
            end
        end

        function onObjectTreeSelect(obj, evt)
            try
                if isempty(evt.SelectedNodes), return; end
                node = evt.SelectedNodes(1);
                nd = node.NodeData;
                if isstruct(nd) && isfield(nd, 'Kind') && strcmp(nd.Kind, 'handle')
                    obj.SelectedHandle = nd.Handle;
                    obj.rebuildInspector(nd);
                else
                    obj.SelectedHandle = [];
                    obj.rebuildInspector([]);
                end
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:select'); catch, end
            end
        end

        function rebuildInspector(obj, meta)
            % Clear body + render property rows for `meta`.
            if isempty(obj.InspectorBody) || ~isvalid(obj.InspectorBody), return; end
            kids = obj.InspectorBody.Children;
            for i = numel(kids):-1:1, try, delete(kids(i)); catch, end, end

            if isempty(meta)
                obj.InspectorBody.RowHeight = {'1x'};
                uilabel(obj.InspectorBody, ...
                    'Text', '(Select an object to view its properties)', ...
                    'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'center');
                return;
            end

            h = meta.Handle;
            valid = ~isempty(h) && all(isgraphics(h));
            obj.InspectorBody.RowHeight = repmat({22}, 1, 5);
            obj.InspectorBody.ColumnWidth = {90, '1x'};
            obj.InspectorBody.ColumnSpacing = 6;
            obj.InspectorBody.RowSpacing = 4;

            obj.addRow('Label',     meta.Label);
            obj.addRow('Channel',   sprintf('Flight %d', meta.ChannelIdx));
            obj.addRow('Field',     meta.Field);
            if valid
                cls = class(h);
                obj.addRow('Type',  cls);
                vis = '';
                try, vis = char(h.Visible); catch, end
                obj.addRow('Visible', vis);
            else
                obj.addRow('Type', '(invalid handle)');
                obj.addRow('Visible', '-');
            end
        end

        function addRow(obj, key, val)
            uilabel(obj.InspectorBody, 'Text', key, 'FontWeight', 'bold');
            uilabel(obj.InspectorBody, 'Text', char(val), 'FontColor', [0.2 0.2 0.2]);
        end

        function onQuickAction(obj, action)
            % [PHASE 6b] Show / Hide the currently inspected handle.
            try
                h = obj.SelectedHandle;
                if isempty(h) || ~all(isgraphics(h))
                    obj.flashStatus('Select an object first');
                    return;
                end
                switch char(action)
                    case 'show'
                        try, set(h, 'Visible', 'on'); catch, end
                    case 'hide'
                        try, set(h, 'Visible', 'off'); catch, end
                end
                % Reflect new state in Inspector
                if ~isempty(obj.ObjectTree) && isvalid(obj.ObjectTree) ...
                        && ~isempty(obj.ObjectTree.SelectedNodes)
                    nd = obj.ObjectTree.SelectedNodes(1).NodeData;
                    obj.rebuildInspector(nd);
                end
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:quickAction'); catch, end
            end
        end

        function flashStatus(obj, msg)
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(msg);
                end
            catch
            end
        end
    end
end
