classdef ProjectExplorerPanel < handle
    % flightdash.studio.ProjectExplorerPanel
    % Left dock: project tree (sessions, figures, results, themes, logs).
    %
    % Phase 1: placeholder tree showing the planned 12 root nodes.
    % Phase 5 wires real project model + context menus + search.
    % UI reality check: drag-reorder unsupported in MATLAB uitree;
    % planned to use right-click "Move to..." dialog instead.

    properties (Access = public)
        App
        Panel       matlab.ui.container.Panel
        Tree        matlab.ui.container.CheckBoxTree   % unused in Phase 1
        SearchField matlab.ui.control.EditField
        Roots       struct = struct()
    end

    methods
        function obj = ProjectExplorerPanel(app, parentGrid)
            obj.App = app;
            obj.build(parentGrid);
        end

        function delete(~)
        end
    end

    methods (Access = private)
        function build(obj, parentGrid)
            UIScale = flightdash.util.UIScale;

            obj.Panel = uipanel(parentGrid, ...
                'Title', 'Project Explorer', 'FontWeight', 'bold', ...
                'BackgroundColor', 'w');
            obj.Panel.Layout.Column = 1;

            grid = uigridlayout(obj.Panel, [2 1], ...
                'RowHeight', {UIScale.px(28), '1x'}, ...
                'RowSpacing', 4, 'Padding', [4 4 4 4]);

            % --- Search field ---
            obj.SearchField = uieditfield(grid, 'text', ...
                'Placeholder', 'Find in project...', ...
                'ValueChangedFcn', @(src,~) obj.onSearch(src.Value));

            % --- Tree (uitree, R2017b+) ---
            tree = uitree(grid, 'tree');
            tree.SelectionChangedFcn = @(src,evt) obj.onTreeSelection(evt);

            % Phase 1 placeholder structure (matches plan §1.2)
            obj.Roots.Project   = obj.makeNode(tree,             obj.App.ProjectName);
            obj.Roots.Sessions  = obj.makeNode(obj.Roots.Project, 'Sessions');
            obj.Roots.FlightData = obj.makeNode(obj.Roots.Project, 'Flight Data');
            obj.Roots.Videos    = obj.makeNode(obj.Roots.Project, 'Videos');
            obj.Roots.Graphs    = obj.makeNode(obj.Roots.Project, 'Graphs');
            obj.Roots.Roi       = obj.makeNode(obj.Roots.Project, 'ROI Results');
            obj.Roots.Sync      = obj.makeNode(obj.Roots.Project, 'Sync Results');
            obj.Roots.Snapshots = obj.makeNode(obj.Roots.Project, 'Snapshots');
            obj.Roots.Reports   = obj.makeNode(obj.Roots.Project, 'Reports');
            obj.Roots.Notes     = obj.makeNode(obj.Roots.Project, 'Notes');
            obj.Roots.Themes    = obj.makeNode(obj.Roots.Project, 'Analysis Themes');
            obj.Roots.Logs      = obj.makeNode(obj.Roots.Project, 'Logs');
            obj.makeNode(obj.Roots.Logs, 'Message Log');
            obj.makeNode(obj.Roots.Logs, 'Error Log');
            obj.makeNode(obj.Roots.Logs, 'Result Log');

            try, expand(obj.Roots.Project); catch, end
            obj.Tree = tree;

            % Right-click context menu (Phase 5 wires real actions)
            cm = uicontextmenu(obj.App.UIFigure);
            uimenu(cm, 'Text', 'Add Session',       'MenuSelectedFcn', @(~,~) obj.onContext('AddSession'));
            uimenu(cm, 'Text', 'Rename...',         'MenuSelectedFcn', @(~,~) obj.onContext('Rename'));
            uimenu(cm, 'Text', 'Move to...',        'MenuSelectedFcn', @(~,~) obj.onContext('Move'));
            uimenu(cm, 'Text', 'Delete',            'MenuSelectedFcn', @(~,~) obj.onContext('Delete'));
            uimenu(cm, 'Text', 'Show / Hide', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.onContext('ToggleVisibility'));
            tree.ContextMenu = cm;
        end

        function n = makeNode(~, parent, label)
            n = uitreenode(parent, 'Text', label);
        end

        function onSearch(obj, query)
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ~isempty(obj.App.StatusBar)
                    if isempty(query)
                        obj.App.StatusBar.setMessage('Search cleared');
                    else
                        obj.App.StatusBar.setMessage(sprintf('Search: "%s" (Phase 5 wiring)', query));
                    end
                end
            catch
            end
        end

        function onTreeSelection(obj, evt)
            try
                if ~isempty(evt.SelectedNodes) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Selected: %s', evt.SelectedNodes(1).Text));
                end
            catch
            end
        end

        function onContext(obj, action)
            try
                if ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Context: %s (Phase 5)', action));
                end
            catch
            end
        end
    end
end
