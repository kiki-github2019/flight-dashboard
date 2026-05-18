classdef ToolbarManager < handle
    % flightdash.studio.ToolbarManager
    % Top toolbar: project ops, data/video load, sync, playback, ROI,
    % analyze, graph, export, dock toggles.
    %
    % Phase 1: flat uibutton row (no Toolstrip/Ribbon — see UI reality
    % check). Buttons publish placeholder commands; real wiring is Phase 6.

    properties (Access = public)
        App
        Panel    % uipanel
        Buttons  struct = struct()
        CommandButtons
    end

    methods
        function obj = ToolbarManager(app, parentGrid)
            obj.App = app;
            obj.build(parentGrid);
        end

        function delete(~)
            % UI components auto-delete with parent grid.
        end

        function setUndoState(obj, canUndo, canRedo)
            try
                obj.setButtonEnabled('Undo', canUndo);
                obj.setButtonEnabled('Redo', canRedo);
            catch
            end
        end

        function setEnabledByCmd(obj, cmdId, tf)
            try
                if isempty(obj.CommandButtons) || ~isa(obj.CommandButtons, 'containers.Map')
                    return;
                end
                key = char(cmdId);
                if ~obj.CommandButtons.isKey(key)
                    return;
                end
                btn = obj.CommandButtons(key);
                if ~isempty(btn) && isvalid(btn)
                    btn.Enable = obj.onOff(tf);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function build(obj, parentGrid)
            UIScale = flightdash.util.UIScale;
            obj.CommandButtons = containers.Map('KeyType', 'char', 'ValueType', 'any');

            obj.Panel = uipanel(parentGrid, 'BorderType', 'none', ...
                'BackgroundColor', [0.97 0.97 0.98]);
            obj.Panel.Layout.Row = 2;

            % Variable-width row: groups separated by spacers.
            grid = uigridlayout(obj.Panel, [1 28], 'RowHeight', {'1x'}, ...
                'ColumnSpacing', 3, 'Padding', [6 4 6 4]);

            buttonW = UIScale.px(64);
            iconW   = UIScale.px(48);
            sepW    = UIScale.px(8);
            grid.ColumnWidth = { ...
                buttonW, buttonW, buttonW, iconW, iconW, sepW, ... % New / Open / Save / Undo / Redo | sep
                iconW, sepW, ...                        % Add Session | sep
                buttonW, buttonW, sepW, ...             % Load Data / Load Video | sep
                iconW, iconW, sepW, ...                 % Sync / Sync Quality | sep
                iconW, iconW, iconW, iconW, sepW, ...   % Play Stop Prev Next | sep
                iconW, iconW, sepW, ...                 % ROI / Marker | sep
                iconW, iconW, sepW, ...                 % Analyze / Recalc | sep
                buttonW, buttonW, buttonW};             % Expl / Dock / Theme

            obj.Buttons.New        = obj.addButton(grid, 'New',     'Toolbar:New');
            obj.Buttons.Open       = obj.addButton(grid, 'Open',    'Toolbar:Open');
            obj.Buttons.Save       = obj.addButton(grid, 'Save',    'Toolbar:Save');
            obj.Buttons.Undo       = obj.addButton(grid, 'Undo',    'Edit:Undo');
            obj.Buttons.Redo       = obj.addButton(grid, 'Redo',    'Edit:Redo');
            obj.setUndoState(false, false);
            obj.addSpacer(grid);
            obj.Buttons.AddSession = obj.addButton(grid, '+ Sess',  'Toolbar:AddSession');
            obj.addSpacer(grid);
            obj.Buttons.LoadData   = obj.addButton(grid, 'Data',    'Toolbar:LoadData');
            obj.Buttons.LoadVideo  = obj.addButton(grid, 'Video',   'Toolbar:LoadVideo');
            obj.addSpacer(grid);
            obj.Buttons.Sync       = obj.addButton(grid, 'Sync',    'Toolbar:Sync');
            obj.Buttons.SyncQual   = obj.addButton(grid, 'SyncQ',   'Toolbar:SyncQuality');
            obj.addSpacer(grid);
            obj.Buttons.Play       = obj.addButton(grid, 'Play',    'Toolbar:Play');
            obj.Buttons.Stop       = obj.addButton(grid, 'Stop',    'Toolbar:Stop');
            obj.Buttons.Prev       = obj.addButton(grid, 'Prev',    'Toolbar:Prev');
            obj.Buttons.Next       = obj.addButton(grid, 'Next',    'Toolbar:Next');
            obj.addSpacer(grid);
            obj.Buttons.Roi        = obj.addButton(grid, 'ROI',     'Toolbar:ROI');
            obj.Buttons.Marker     = obj.addButton(grid, 'Mark',    'Toolbar:Marker');
            obj.addSpacer(grid);
            obj.Buttons.Analyze    = obj.addButton(grid, 'Analyze', 'Toolbar:Analyze');
            obj.Buttons.Recalc     = obj.addButton(grid, 'Recalc',  'Toolbar:Recalc');
            obj.addSpacer(grid);
            obj.Buttons.Explorer   = obj.addButton(grid, 'Expl',    'Toolbar:ToggleExplorer');
            obj.Buttons.RightDock  = obj.addButton(grid, 'Dock',    'Toolbar:ToggleRightDock');
            obj.Buttons.Theme      = obj.addButton(grid, 'Theme',   'Pref:Theme:Toggle');
        end

        function btn = addButton(obj, grid, label, cmdId)
            btn = uibutton(grid, ...
                'Text', label, ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) obj.dispatch(cmdId));
            try, obj.CommandButtons(char(cmdId)) = btn; catch, end
        end

        function addSpacer(~, grid)
            uilabel(grid, 'Text', '', 'BackgroundColor', [0.85 0.85 0.88]);
        end

        function dispatch(obj, cmdId)
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ismethod(obj.App, 'dispatchCommand')
                    obj.App.dispatchCommand(cmdId, 'Toolbar');
                end
            catch ME
                if ~isempty(obj.App) && isvalid(obj.App) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Toolbar %s failed: %s', cmdId, ME.message));
                end
            end
        end

        function setButtonEnabled(obj, name, tf)
            try
                if isfield(obj.Buttons, name)
                    btn = obj.Buttons.(name);
                    if ~isempty(btn) && isvalid(btn)
                        btn.Enable = obj.onOff(tf);
                    end
                end
            catch
            end
        end

        function value = onOff(~, tf)
            if tf
                value = 'on';
            else
                value = 'off';
            end
        end
    end
end
