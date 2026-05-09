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
        Panel       % uipanel
        Tree        % uitree (matlab.ui.container.Tree)
        SearchField % uieditfield
        Roots       struct = struct()
    end

    methods
        function obj = ProjectExplorerPanel(app, parentGrid)
            obj.App = app;
            obj.build(parentGrid);
        end

        function delete(~)
        end

        function refreshFromProject(obj, project)
            % Rebuild the tree from a flightdash.project.ProjectModel.
            % Phase 2: rebuilds Sessions/Themes children only; other root
            % nodes (Graphs/Reports/etc.) stay placeholders until Phase 3+.
            try
                if isempty(obj.Tree) || ~isvalid(obj.Tree), return; end
                if isempty(obj.Roots) || ~isfield(obj.Roots, 'Project'), return; end

                % Update root label
                if ~isempty(project) && ~isempty(project.ProjectName)
                    obj.Roots.Project.Text = project.ProjectName;
                end

                % --- Sessions ---
                obj.replaceChildren(obj.Roots.Sessions);
                if ~isempty(project) && ~isempty(project.Sessions)
                    for k = 1:numel(project.Sessions)
                        s = project.Sessions(k);
                        node = uitreenode(obj.Roots.Sessions, ...
                            'Text', sprintf('%s (%s)', s.DisplayName, s.SessionId), ...
                            'NodeData', struct('SessionId', s.SessionId, 'Kind', 'session'));
                    end
                end

                % --- Analysis Themes ---
                obj.replaceChildren(obj.Roots.Themes);
                if ~isempty(project) && ~isempty(project.AnalysisThemes)
                    for k = 1:numel(project.AnalysisThemes)
                        t = project.AnalysisThemes(k);
                        uitreenode(obj.Roots.Themes, ...
                            'Text', t.ThemeName, ...
                            'NodeData', struct('ThemeId', t.ThemeId, 'Kind', 'theme'));
                    end
                end

                % --- Review / Analysis Results ---
                obj.replaceChildren(obj.Roots.Roi);
                obj.replaceChildren(obj.Roots.Sync);
                obj.replaceChildren(obj.Roots.Snapshots);
                if ~isempty(project) && ~isempty(project.Results)
                    for k = 1:numel(project.Results)
                        r = project.Results(k);
                        parentNode = obj.resultRootFor(r);
                        uitreenode(parentNode, ...
                            'Text', obj.resultLabel(r), ...
                            'NodeData', struct('ResultId', r.ResultId, ...
                                'SessionId', r.SessionId, 'Kind', 'result'));
                    end
                end

                try, expand(obj.Roots.Project); catch, end
                try, expand(obj.Roots.Sessions); catch, end
                try, expand(obj.Roots.Roi); catch, end
            catch
            end
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

            % [PHASE 5] Right-click context menu wired to real actions.
            cm = uicontextmenu(obj.App.UIFigure);
            uimenu(cm, 'Text', 'Add Session',       'MenuSelectedFcn', @(~,~) obj.onContext('AddSession'));
            uimenu(cm, 'Text', 'Rename...',         'MenuSelectedFcn', @(~,~) obj.onContext('Rename'));
            uimenu(cm, 'Text', 'Duplicate',         'MenuSelectedFcn', @(~,~) obj.onContext('Duplicate'));
            uimenu(cm, 'Text', 'Delete',            'MenuSelectedFcn', @(~,~) obj.onContext('Delete'));
            uimenu(cm, 'Text', 'Move to...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.onContext('Move'));
            uimenu(cm, 'Text', 'Show / Hide',       'MenuSelectedFcn', @(~,~) obj.onContext('ToggleVisibility'));
            tree.ContextMenu = cm;
        end

        function n = makeNode(~, parent, label)
            n = uitreenode(parent, 'Text', label);
        end

        function replaceChildren(~, parentNode)
            % Remove existing children of a tree node so refresh can
            % re-create them from the current ProjectModel state.
            try
                if isempty(parentNode) || ~isvalid(parentNode), return; end
                kids = parentNode.Children;
                for i = numel(kids):-1:1
                    try, delete(kids(i)); catch, end
                end
            catch
            end
        end

        function parentNode = resultRootFor(obj, resultModel)
            parentNode = obj.Roots.Roi;
            try
                typ = lower(char(resultModel.ResultType));
                switch typ
                    case {'synccheck', 'sync'}
                        parentNode = obj.Roots.Sync;
                    case {'snapshot'}
                        parentNode = obj.Roots.Snapshots;
                    otherwise
                        parentNode = obj.Roots.Roi;
                end
            catch
                parentNode = obj.Roots.Roi;
            end
        end

        function label = resultLabel(~, resultModel)
            try
                tr = resultModel.TimeRange;
                vars = resultModel.Variables;
                varName = '';
                if iscell(vars) && ~isempty(vars), varName = char(vars{1}); end
                if isempty(varName), varName = char(resultModel.ResultType); end
                label = sprintf('%s ch%d %.3g-%.3g (%s)', ...
                    varName, resultModel.ChannelIdx, tr(1), tr(2), resultModel.ResultId);
            catch
                label = char(resultModel.ResultId);
            end
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
                if isempty(evt.SelectedNodes), return; end
                node = evt.SelectedNodes(1);
                if ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Selected: %s', node.Text));
                end

                % [PHASE 3c] If the selected node is a Session (NodeData
                % carries a SessionId), switch the workspace to that tab.
                nd = node.NodeData;
                if isstruct(nd) && isfield(nd, 'Kind') && strcmp(nd.Kind, 'session') ...
                        && isfield(nd, 'SessionId') ...
                        && ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace)
                    obj.App.Workspace.selectSession(nd.SessionId);
                end
            catch
            end
        end

        function onContext(obj, action)
            % [PHASE 5] Route context-menu items to actual operations
            % when the selected node represents a session.
            try
                node = obj.selectedNode();
                sessionId = obj.sessionIdFromNode(node);
                switch char(action)
                    case 'AddSession'
                        obj.App.addSession();
                        return;
                    case 'Rename'
                        if isempty(sessionId)
                            obj.notifyStatus('Select a session to rename');
                            return;
                        end
                        obj.promptAndRename(sessionId);
                        return;
                    case 'Duplicate'
                        if isempty(sessionId)
                            obj.notifyStatus('Select a session to duplicate');
                            return;
                        end
                        obj.App.duplicateSession(sessionId);
                        return;
                    case 'Delete'
                        if isempty(sessionId)
                            obj.notifyStatus('Select a session to delete');
                            return;
                        end
                        obj.confirmAndDelete(sessionId, node);
                        return;
                    case 'Move'
                        obj.notifyStatus('Move to... is not implemented yet');
                        return;
                    case 'ToggleVisibility'
                        obj.notifyStatus('Visibility toggle is not implemented yet');
                        return;
                end
                obj.notifyStatus(sprintf('Context: %s', action));
            catch ME
                obj.notifyStatus(sprintf('Context %s failed: %s', action, ME.message));
            end
        end

        function notifyStatus(obj, msg)
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(msg);
                end
            catch
            end
        end

        function node = selectedNode(obj)
            node = [];
            try
                if isempty(obj.Tree) || ~isvalid(obj.Tree), return; end
                sel = obj.Tree.SelectedNodes;
                if ~isempty(sel)
                    node = sel(1);
                end
            catch
            end
        end

        function id = sessionIdFromNode(~, node)
            id = '';
            try
                if isempty(node) || ~isvalid(node), return; end
                nd = node.NodeData;
                if isstruct(nd) && isfield(nd, 'Kind') && strcmp(nd.Kind, 'session') ...
                        && isfield(nd, 'SessionId')
                    id = char(nd.SessionId);
                end
            catch
            end
        end

        function promptAndRename(obj, sessionId)
            try
                sess = obj.App.Project.findSession(sessionId);
                if isempty(sess), return; end
                answer = inputdlg({'New session name:'}, 'Rename Session', ...
                    [1 50], {sess.DisplayName});
                if isempty(answer), return; end
                newName = strtrim(answer{1});
                if isempty(newName), return; end
                obj.App.renameSession(sessionId, newName);
            catch ME
                obj.notifyStatus(sprintf('Rename failed: %s', ME.message));
            end
        end

        function confirmAndDelete(obj, sessionId, node)
            try
                sess = obj.App.Project.findSession(sessionId);
                displayName = sessionId;
                if ~isempty(sess), displayName = sess.DisplayName; end
                fig = obj.App.UIFigure;
                if ~isempty(fig) && isvalid(fig)
                    sel = uiconfirm(fig, ...
                        sprintf('Delete session "%s"? Embedded dashboard will close.', displayName), ...
                        'Confirm Delete Session', ...
                        'Options', {'Delete', 'Cancel'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(sel, 'Delete'), return; end
                end
                obj.App.removeSession(sessionId);
            catch ME
                obj.notifyStatus(sprintf('Delete failed: %s', ME.message));
            end
        end
    end
end
