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
        function id = getSelectedNodeId(obj)
            id = '';
            try
                if isempty(obj.Tree) || ~isvalid(obj.Tree)
                    return;
                end

                sel = obj.Tree.SelectedNodes;
                if isempty(sel)
                    return;
                end

                nd = sel(1).NodeData;
                if isstruct(nd) && isfield(nd, 'SessionId')
                    id = char(nd.SessionId);
                elseif isstruct(nd) && isfield(nd, 'ResultId')
                    id = char(nd.ResultId);
                elseif isstruct(nd) && isfield(nd, 'ThemeId')
                    id = char(nd.ThemeId);
                else
                    id = char(sel(1).Text);
                end
            catch
                id = '';
            end
        end
        function tf = selectSession(obj, sessionId)
            tf = false;
            try
                if isempty(obj.Tree) || ~isvalid(obj.Tree)
                    return;
                end

                sid = char(sessionId);
                node = obj.findSessionNode(sid);

                if isempty(node) || ~isvalid(node)
                    return;
                end

                obj.Tree.SelectedNodes = node;
                drawnow limitrate;

                if ~isempty(obj.App) && isvalid(obj.App) && ...
                        ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace)
                    obj.App.Workspace.selectSession(sid);
                end

                tf = true;
            catch
                tf = false;
            end
        end

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
                        try
                            if isprop(node, 'Tooltip')
                                node.Tooltip = sprintf( ...
                                    'Session: %s\nID: %s\nClick to focus this review tab.', ...
                                    char(s.DisplayName), char(s.SessionId));
                            end
                        catch
                        end
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

                drawnow limitrate;   % ensure tree rebuild is flushed before expand/select

                try, expand(obj.Roots.Project); catch, end
                try, expand(obj.Roots.Sessions); catch, end
                try, expand(obj.Roots.Roi); catch, end

                % Commit 2: prefer App.ActiveSessionId to preserve the
                % user's current selection across refreshes; fall back to
                % the first session only when no active selection exists
                % (i.e. immediately after auto-create).
                try
                    targetId = '';
                    if ~isempty(obj.App) && isvalid(obj.App) ...
                            && isprop(obj.App, 'ActiveSessionId')
                        targetId = char(obj.App.ActiveSessionId);
                    end
                    if (isempty(targetId) || strcmp(targetId, 'standalone')) ...
                            && ~isempty(project) && ~isempty(project.Sessions)
                        targetId = char(project.Sessions(1).SessionId);
                    end
                    if ~isempty(targetId) && ~strcmp(targetId, 'standalone')
                        obj.selectSession(targetId);
                    end
                catch
                end
            catch ME
                warning('ProjectExplorerPanel:RefreshFailed', '%s', ME.message);
            end
        end
    end

    methods (Access = private)
    
        function node = findSessionNode(obj, sessionId)
            node = [];
            try
                if isempty(obj.Roots) || ~isfield(obj.Roots, 'Sessions')
                    return;
                end

                children = obj.Roots.Sessions.Children;
                sid = char(sessionId);

                for k = 1:numel(children)
                    nd = children(k).NodeData;
                    if isstruct(nd) && isfield(nd, 'SessionId') && ...
                            strcmp(char(nd.SessionId), sid)
                        node = children(k);
                        return;
                    end
                end
            catch
                node = [];
            end
        end
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
            mk = @(parent, label, tip) obj.makeNodeWithTip(parent, label, tip);
            obj.Roots.Project   = mk(tree, obj.App.ProjectName, ...
                'Current project. Right-click for project-level actions.');
            obj.Roots.Sessions  = mk(obj.Roots.Project, 'Sessions', ...
                'Review sessions. Each session opens an embedded dashboard tab.');
            obj.Roots.FlightData = mk(obj.Roots.Project, 'Flight Data', ...
                'Loaded flight log files. Drop CSV/MAT files here.');
            obj.Roots.Videos    = mk(obj.Roots.Project, 'Videos', ...
                'Synced videos paired with flight data sessions.');
            obj.Roots.Graphs    = mk(obj.Roots.Project, 'Graphs', ...
                'User-defined plot configurations and graph templates.');
            obj.Roots.Roi       = mk(obj.Roots.Project, 'ROI Results', ...
                'Region-of-interest analysis results (Auto / Manual / Frozen).');
            obj.Roots.Sync      = mk(obj.Roots.Project, 'Sync Results', ...
                'Video / flight-data synchronization quality reports.');
            obj.Roots.Snapshots = mk(obj.Roots.Project, 'Snapshots', ...
                'Saved playback snapshots and frame captures.');
            obj.Roots.Reports   = mk(obj.Roots.Project, 'Reports', ...
                'Exported review reports (PDF / HTML / images).');
            obj.Roots.Notes     = mk(obj.Roots.Project, 'Notes', ...
                'Free-form notes attached to the project or sessions.');
            obj.Roots.Themes    = mk(obj.Roots.Project, 'Analysis Themes', ...
                'Saved analysis configurations reusable across projects.');
            obj.Roots.Logs      = mk(obj.Roots.Project, 'Logs', ...
                'Diagnostic logs: messages, errors, recalc results.');
            mk(obj.Roots.Logs, 'Message Log', 'Status / info messages.');
            mk(obj.Roots.Logs, 'Error Log',   'Errors and caught exceptions.');
            mk(obj.Roots.Logs, 'Result Log',  'Recalculate / ROI result history.');

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

        function n = makeNodeWithTip(~, parent, label, tipText)
            % uitreenode Tooltip is R2022b+; fall back gracefully on
            % older releases by silently ignoring the unset property.
            n = uitreenode(parent, 'Text', label);
            try
                if ~isempty(tipText) && isprop(n, 'Tooltip')
                    n.Tooltip = char(tipText);
                end
            catch
            end
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
            % Phase 5: walk the tree depth-first, find the first node
            % whose visible label contains `query` (case-insensitive),
            % expand its ancestors, select it, and scroll it into view.
            try
                query = char(query);
                if isempty(obj.Tree) || ~isvalid(obj.Tree), return; end
                if isempty(query)
                    if ~isempty(obj.App) && isvalid(obj.App) ...
                            && ~isempty(obj.App.StatusBar)
                        obj.App.StatusBar.setMessage('Search cleared');
                    end
                    return;
                end
                hit = obj.findFirstMatching(obj.Tree, lower(query));
                if isempty(hit)
                    if ~isempty(obj.App) && isvalid(obj.App) ...
                            && ~isempty(obj.App.StatusBar)
                        obj.App.StatusBar.setMessage( ...
                            sprintf('Search: "%s" - no match', query));
                    end
                    return;
                end
                obj.expandAncestors(hit);
                try, obj.Tree.SelectedNodes = hit; catch, end
                try, scroll(obj.Tree, hit); catch, end
                if ~isempty(obj.App) && isvalid(obj.App) ...
                        && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage( ...
                        sprintf('Search: "%s" -> %s', query, char(hit.Text)));
                end
            catch ME
                warning('ProjectExplorerPanel:Search', '%s', ME.message);
            end
        end

        function node = findFirstMatching(obj, root, queryLower)
            node = [];
            try
                kids = root.Children;
            catch
                kids = [];
            end
            for k = 1:numel(kids)
                child = kids(k);
                try
                    label = lower(char(child.Text));
                    if ~isempty(label) && contains(label, queryLower)
                        node = child;
                        return;
                    end
                catch
                end
                node = obj.findFirstMatching(child, queryLower);
                if ~isempty(node), return; end
            end
        end

        function expandAncestors(~, node)
            try
                p = node.Parent;
                while ~isempty(p) && isa(p, 'matlab.ui.container.TreeNode')
                    try, expand(p); catch, end
                    p = p.Parent;
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
