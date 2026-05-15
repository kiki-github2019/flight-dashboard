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
        HistoryTab         % uitab
        LogsTab            % uitab
        AppsTab            % uitab
        AnalysisTab        % uitab (Path 2 placeholder)
        HistoryPanel       % flightdash.studio.HistoryPanel

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

        function delete(obj)
            try
                if ~isempty(obj.HistoryPanel) && isvalid(obj.HistoryPanel)
                    delete(obj.HistoryPanel);
                end
            catch
            end
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
            obj.HistoryTab       = obj.buildHistoryTab();
            obj.AnalysisTab      = obj.buildAnalysisTab();
            obj.LogsTab          = obj.buildLogsTab();
            obj.AppsTab          = obj.buildAppsTab();
        end

        function tab = buildAnalysisTab(obj)
            % Path 2 placeholder: future home for Analyzer / ROI / Plot
            % Detail panels that currently spawn as separate aux figures.
            tab = uitab(obj.TabGroup, 'Title', 'Analysis');
            grid = uigridlayout(tab, [1 1], 'Padding', [12 12 12 12]);
            uilabel(grid, ...
                'Text', '(Analysis tools will dock here — Analyzer, ROI, Plot Detail)', ...
                'FontColor', [0.5 0.5 0.5], ...
                'HorizontalAlignment', 'center', 'WordWrap', 'on');
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

        function tab = buildHistoryTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'History');
            obj.HistoryPanel = flightdash.studio.HistoryPanel(tab, []);
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

        function refreshObjectManager(obj, dashboard)
            obj.refreshObjectsFor(dashboard);
        end

        function refreshForDashboard(obj, dashboard)
            obj.refreshObjectsFor(dashboard);
            obj.refreshHistoryForDashboard(dashboard);
        end

        function refreshHistoryForDashboard(obj, dashboard)
            try
                svc = [];
                if ~isempty(dashboard) && isvalid(dashboard) && isprop(dashboard, 'UndoService')
                    svc = dashboard.UndoService;
                end
                if ~isempty(obj.HistoryPanel) && isvalid(obj.HistoryPanel)
                    obj.HistoryPanel.bindUndoService(svc);
                end
            catch
            end
        end

        function selectObject(obj, h)
            obj.refreshInspector(h);
            obj.syncObjectTreeSelection(h);
        end

        function setSelectedObject(obj, h)
            obj.selectObject(h);
        end

        function showObjectProperties(obj, h)
            obj.selectObject(h);
        end

        function toggleSelectedVisible(obj)
            try
                info = obj.describeSelection(obj.SelectedHandle);
                if ~info.CanEdit
                    obj.flashStatus(info.Status);
                    return;
                end
                current = 'on';
                try, current = char(info.Handle.Visible); catch, end
                if strcmpi(current, 'on')
                    obj.setSelectedVisible('off');
                else
                    obj.setSelectedVisible('on');
                end
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:toggleVisible'); catch, end
            end
        end

        function setSelectedVisible(obj, value)
            try
                obj.setSelectedProperty('Visible', value);
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:setVisible'); catch, end
            end
        end

        function tf = setSelectedProperty(obj, propName, value)
            tf = false;
            try
                info = obj.describeSelection(obj.SelectedHandle);
                if ~info.CanEdit
                    obj.flashStatus(info.Status);
                    obj.rebuildInspector(info);
                    return;
                end

                propName = char(propName);
                if ~any(strcmp(propName, obj.safePropertyNames()))
                    obj.flashStatus(sprintf('Unsupported property: %s', propName));
                    obj.rebuildInspector(info);
                    return;
                end
                if ~isprop(info.Handle, propName)
                    obj.flashStatus(sprintf('Read-only: %s is not available', propName));
                    obj.rebuildInspector(info);
                    return;
                end

                coerced = obj.coercePropertyValue(propName, value);
                try
                    set(info.Handle, propName, coerced);
                    tf = true;
                    obj.flashStatus(sprintf('Inspector updated %s', propName));
                catch ME_set
                    obj.flashStatus(sprintf('Read-only: %s', propName));
                    try, obj.App.logCaught(ME_set, ['Inspector:set:' propName]); catch, end
                end
                obj.refreshInspector(info.Handle);
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:setSelectedProperty'); catch, end
                try
                    obj.SelectedHandle = [];
                    obj.rebuildInspector([]);
                catch
                end
            end
        end

        function info = getSelectedPropertyInfo(obj)
            info = obj.describeSelection(obj.SelectedHandle);
        end

        function refreshInspector(obj, h)
            try
                info = obj.describeSelection(h);
                if ~info.IsValid
                    obj.SelectedHandle = [];
                    obj.rebuildInspector(info);
                    return;
                end
                obj.SelectedHandle = info.Handle;
                obj.rebuildInspector(info);
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:refreshPublic'); catch, end
                try
                    obj.SelectedHandle = [];
                    obj.rebuildInspector([]);
                catch
                end
            end
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
                    info = obj.describeSelection(nd.Handle, nd);
                    if info.IsValid
                        obj.SelectedHandle = info.Handle;
                    else
                        obj.SelectedHandle = [];
                    end
                    obj.rebuildInspector(info);
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

            if ~isfield(meta, 'SafeProperties')
                meta = obj.describeSelection(meta.Handle, meta);
            end

            props = meta.SafeProperties;
            rowCount = 4 + max(1, numel(props));
            obj.InspectorBody.RowHeight = repmat({24}, 1, rowCount);
            obj.InspectorBody.ColumnWidth = {90, '1x'};
            obj.InspectorBody.ColumnSpacing = 6;
            obj.InspectorBody.RowSpacing = 4;

            obj.addRow('Label',  meta.Label, false);
            obj.addRow('Field',  meta.Field, false);
            obj.addRow('Type',   meta.Type, false);
            obj.addRow('Status', meta.Status, false);

            if meta.CanEdit
                for p = 1:numel(props)
                    obj.addSafePropertyRow(props{p}, meta.Handle);
                end
            else
                obj.addRow('Mode', meta.Mode, false);
            end
        end

        function addRow(obj, key, val, editable)
            if nargin < 4, editable = false; end
            uilabel(obj.InspectorBody, 'Text', key, 'FontWeight', 'bold');
            if editable
                obj.addEditor(key, val);
            else
                uilabel(obj.InspectorBody, 'Text', char(val), 'FontColor', [0.2 0.2 0.2]);
            end
        end

        function addSafePropertyRow(obj, propName, h)
            value = obj.safeGetProperty(h, propName);
            uilabel(obj.InspectorBody, 'Text', propName, 'FontWeight', 'bold');
            obj.addEditor(propName, value);
        end

        function addEditor(obj, propName, value)
            propName = char(propName);
            switch propName
                case 'Visible'
                    val = 'on';
                    if strcmpi(char(value), 'off'), val = 'off'; end
                    uidropdown(obj.InspectorBody, ...
                        'Items', {'on', 'off'}, ...
                        'Value', val, ...
                        'ValueChangedFcn', @(src,~) obj.setSelectedProperty('Visible', src.Value));
                case 'LineWidth'
                    num = 0.5;
                    try, num = double(value); catch, end
                    uieditfield(obj.InspectorBody, 'numeric', ...
                        'Value', num, ...
                        'Limits', [0 Inf], ...
                        'ValueChangedFcn', @(src,~) obj.setSelectedProperty('LineWidth', src.Value));
                otherwise
                    uieditfield(obj.InspectorBody, 'text', ...
                        'Value', obj.valueToText(value), ...
                        'ValueChangedFcn', @(src,~) obj.setSelectedProperty(propName, src.Value));
            end
        end

        function onQuickAction(obj, action)
            % [PHASE 6b] Show / Hide the currently inspected handle.
            try
                info = obj.describeSelection(obj.SelectedHandle);
                if ~info.CanEdit
                    obj.flashStatus(info.Status);
                    return;
                end
                switch char(action)
                    case 'show'
                        obj.setSelectedVisible('on');
                    case 'hide'
                        obj.setSelectedVisible('off');
                end
            catch ME
                try, obj.App.logCaught(ME, 'Inspector:quickAction'); catch, end
            end
        end

        function info = describeSelection(obj, h, meta)
            if nargin < 3 || ~isstruct(meta)
                meta = struct();
            end

            info = struct( ...
                'Kind',           'handle', ...
                'ChannelIdx',     obj.metaField(meta, 'ChannelIdx', 0), ...
                'Field',          obj.metaField(meta, 'Field', ''), ...
                'Label',          obj.metaField(meta, 'Label', ''), ...
                'Handle',         [], ...
                'IsValid',        false, ...
                'IsScalar',       false, ...
                'Type',           '(none)', ...
                'Mode',           'Read-Only', ...
                'Status',         'No selection', ...
                'SafeProperties', {{}}, ...
                'CanEdit',        false);

            if isempty(h)
                return;
            end

            if ~obj.isUsableHandle(h)
                info.Type = '(invalid handle)';
                info.Status = 'Invalid or deleted object';
                return;
            end

            info.Handle = h;
            info.IsValid = true;
            info.IsScalar = isscalar(h);
            try, info.Type = class(h); catch, info.Type = '(handle)'; end
            if isempty(info.Field), info.Field = info.Type; end
            if isempty(info.Label), info.Label = info.Type; end

            if ~info.IsScalar
                info.Mode = 'Unsupported';
                info.Status = 'Unsupported: bulk editing is out of MVP scope';
                return;
            end

            props = obj.safeAvailableProperties(h);
            info.SafeProperties = props;
            if isempty(props)
                info.Mode = 'Read-Only';
                info.Status = 'Read-Only: no MVP-safe editable properties';
                return;
            end

            info.Mode = 'Editable';
            info.Status = sprintf('Editable: %s', strjoin(props, ', '));
            info.CanEdit = true;
        end

        function out = metaField(~, meta, fieldName, defaultValue)
            out = defaultValue;
            try
                if isstruct(meta) && isfield(meta, fieldName) && ~isempty(meta.(fieldName))
                    out = meta.(fieldName);
                end
            catch
                out = defaultValue;
            end
        end

        function tf = isUsableHandle(~, h)
            tf = false;
            try
                tf = ~isempty(h) && all(isgraphics(h));
            catch
                tf = false;
            end
        end

        function names = safePropertyNames(~)
            names = {'Visible', 'DisplayName', 'LineWidth', 'Color'};
        end

        function props = safeAvailableProperties(obj, h)
            props = {};
            if ~obj.isUsableHandle(h) || ~isscalar(h)
                return;
            end
            candidates = obj.safePropertyNames();
            for i = 1:numel(candidates)
                name = candidates{i};
                try
                    if isprop(h, name)
                        value = h.(name); %#ok<NASGU>
                        props{end+1} = name; %#ok<AGROW>
                    end
                catch
                end
            end
        end

        function value = safeGetProperty(obj, h, propName)
            value = '';
            try
                if obj.isUsableHandle(h) && isscalar(h) && isprop(h, propName)
                    value = h.(propName);
                end
            catch
                value = '';
            end
        end

        function value = coercePropertyValue(obj, propName, raw)
            propName = char(propName);
            switch propName
                case 'Visible'
                    if islogical(raw)
                        if raw
                            value = 'on';
                        else
                            value = 'off';
                        end
                    else
                        value = lower(strtrim(char(raw)));
                        if ~any(strcmp(value, {'on', 'off'}))
                            value = 'on';
                        end
                    end
                case 'DisplayName'
                    value = char(raw);
                case 'LineWidth'
                    value = double(raw);
                    if isempty(value) || ~isscalar(value) || ~isfinite(value) || value < 0
                        value = 0.5;
                    end
                case 'Color'
                    value = obj.coerceColor(raw);
                otherwise
                    value = raw;
            end
        end

        function value = coerceColor(~, raw)
            if isnumeric(raw) && numel(raw) == 3
                value = reshape(double(raw), 1, 3);
                value = max(0, min(1, value));
                return;
            end

            text = strtrim(char(raw));
            nums = sscanf(regexprep(text, '[\[\],;]', ' '), '%f');
            if numel(nums) >= 3
                value = reshape(double(nums(1:3)), 1, 3);
                value = max(0, min(1, value));
            else
                value = text;
            end
        end

        function text = valueToText(~, value)
            try
                if isnumeric(value)
                    if isvector(value)
                        text = ['[' strtrim(sprintf('%.4g ', value(:).')) ']'];
                    else
                        text = mat2str(value);
                    end
                elseif islogical(value)
                    text = mat2str(value);
                elseif isstring(value)
                    text = char(value);
                elseif ischar(value)
                    text = value;
                else
                    text = char(string(value));
                end
            catch
                text = '';
            end
        end

        function syncObjectTreeSelection(obj, h)
            try
                if isempty(obj.ObjectTree) || ~isvalid(obj.ObjectTree) || ...
                        ~obj.isUsableHandle(h) || ~isscalar(h)
                    return;
                end
                node = obj.findTreeNodeForHandle(obj.ObjectTree.Children, h);
                if ~isempty(node) && isvalid(node)
                    obj.ObjectTree.SelectedNodes = node;
                end
            catch
            end
        end

        function match = findTreeNodeForHandle(obj, nodes, h)
            match = [];
            for i = 1:numel(nodes)
                node = nodes(i);
                try
                    nd = node.NodeData;
                    if isstruct(nd) && isfield(nd, 'Handle') && ...
                            obj.isUsableHandle(nd.Handle) && isscalar(nd.Handle) && ...
                            isequal(nd.Handle, h)
                        match = node;
                        return;
                    end
                catch
                end

                try
                    match = obj.findTreeNodeForHandle(node.Children, h);
                    if ~isempty(match), return; end
                catch
                end
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
