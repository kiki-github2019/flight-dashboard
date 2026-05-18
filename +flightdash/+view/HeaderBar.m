classdef HeaderBar
    % flightdash.view.HeaderBar
    % Top header: file buttons, debug toggle, window controls, and sync controls.
    %
    % [PHASE 3c] When an `app` reference is supplied, button callbacks
    % invoke methods on THAT specific dashboard directly, bypassing the
    % singleton EventBus. This stops a click on Session A's "Flight 1"
    % button from also triggering Session B's FileController in the
    % multi-session Studio embed (the file dialog reopened twice).
    %
    % Calling HeaderBar.build(mainLayout) without `app` keeps the legacy
    % EventBus-publish behavior so any external standalone caller that
    % built the header view directly continues to work.

    methods (Static)
        function ui = build(mainLayout, app)
            if nargin < 2, app = []; end
            ui = struct();
            UIScale = flightdash.util.UIScale;

            ui.HeaderPanel = uipanel(mainLayout, ...
                'BackgroundColor', 'w', 'BorderType', 'none');
            ui.HeaderGrid = uigridlayout(ui.HeaderPanel, [1 11]);
            ui.HeaderGrid.ColumnWidth = { ...
                UIScale.px(96), UIScale.px(96), UIScale.px(80), ...
                UIScale.px(96), UIScale.px(96), UIScale.px(92), '1x', UIScale.px(42), ...
                UIScale.px(76), UIScale.px(120), UIScale.px(120)};
            ui.HeaderGrid.RowHeight = {'fit'};
            ui.HeaderGrid.Padding = [5 5 5 5];
            ui.HeaderGrid.ColumnSpacing = 5;
            ui.HeaderGrid.RowSpacing = 3;
            tokens = flightdash.ui.StudioTheme.light();

            ui.Flight1Button = uibutton(ui.HeaderGrid, 'Text', '비행 1', ...
                'BackgroundColor', [0.15 0.38 0.82], 'FontColor', 'w', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeFlightCb(app, 1));
            ui.Flight2Button = uibutton(ui.HeaderGrid, 'Text', '비행 2', ...
                'BackgroundColor', [0.31 0.27 0.90], 'FontColor', 'w', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeFlightCb(app, 2));
            ui.CoastButton = uibutton(ui.HeaderGrid, 'Text', '해안선', ...
                'BackgroundColor', [0.06 0.65 0.50], 'FontColor', 'w', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeCoastCb(app));

            ui.ExportConfigButton = uibutton(ui.HeaderGrid, 'Text', '설정 내보내기', ...
                'Tooltip', 'Export the current session configuration', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeAppCb(app, 'exportConfigInteractive', 'ConfigExportRequested'));

            ui.ImportConfigButton = uibutton(ui.HeaderGrid, 'Text', '설정 가져오기', ...
                'Tooltip', 'Import a saved session configuration', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeAppCb(app, 'importConfigInteractive', 'ConfigImportRequested'));

            ui.ChannelViewDropDown = uidropdown(ui.HeaderGrid, ...
                'Items', {'둘 다', '비행 1', '비행 2'}, ...
                'ItemsData', {'both', 'flight1', 'flight2'}, ...
                'Value', 'both', ...
                'Tooltip', 'Show both flights or focus one flight', ...
                'ValueChangedFcn', flightdash.view.HeaderBar.makeChannelViewCb(app));

            ui.HeaderSpacer = uilabel(ui.HeaderGrid, 'Text', '');

            ui.FitScreenButton = uibutton(ui.HeaderGrid, 'Text', 'Max', ...
                'Tooltip', 'Maximize / restore', ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeAppCb(app, 'toggleWindowMaximized', 'LayoutFitRequested'));

            ui.DebugBox = uicheckbox(ui.HeaderGrid, 'Text', 'Debug', 'Value', false, ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'Tooltip', 'Print debug logs to the MATLAB console', ...
                'ValueChangedFcn', flightdash.view.HeaderBar.makeDebugCb(app));

            ui.SyncInput = uieditfield(ui.HeaderGrid, 'text', 'Value', '', ...
                'Tooltip', 'ex: 23.4, 34.4', 'FontSize', 13);
            ui.SyncBtn = uibutton(ui.HeaderGrid, 'Text', '시간 동기화', ...
                'BackgroundColor', [0.58 0.0 0.83], 'FontColor', 'w', ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', flightdash.view.HeaderBar.makeAppCb(app, 'toggleSync', 'SyncToggled'));
            flightdash.ui.StudioTheme.styleButton(ui.Flight1Button, tokens, 'primary');
            flightdash.ui.StudioTheme.styleButton(ui.Flight2Button, tokens, 'accent');
            flightdash.ui.StudioTheme.styleButton(ui.CoastButton, tokens, 'success');
            flightdash.ui.StudioTheme.styleButton(ui.ExportConfigButton, tokens, 'secondary');
            flightdash.ui.StudioTheme.styleButton(ui.ImportConfigButton, tokens, 'secondary');
            flightdash.ui.StudioTheme.styleButton(ui.FitScreenButton, tokens, 'secondary');
            flightdash.ui.StudioTheme.styleButton(ui.SyncBtn, tokens, 'accent');
        end
    end

    methods (Static, Access = private)
        % Each "make*Cb" helper returns a function handle. If `app` was
        % supplied, the handle calls a method on that specific dashboard
        % so multi-session embeds do not broadcast to other sessions.
        % Otherwise it falls back to the singleton EventBus.

        function cb = makeFlightCb(app, fIdx)
            if isempty(app)
                cb = @(~,~) flightdash.util.EventBus.publish( ...
                    'FlightFileRequested', flightdash.util.AppEventData(fIdx));
            else
                cb = @(~,~) flightdash.view.HeaderBar.invokeApp(app, ...
                    @() app.handleFlightFile(fIdx));
            end
        end

        function cb = makeCoastCb(app)
            if isempty(app)
                cb = @(~,~) flightdash.util.EventBus.publish( ...
                    'CoastFileRequested', flightdash.util.AppEventData());
            else
                cb = @(~,~) flightdash.view.HeaderBar.invokeApp(app, ...
                    @() app.handleCoastFile());
            end
        end

        function cb = makeChannelViewCb(app)
            if isempty(app)
                cb = @(src,~) flightdash.util.EventBus.publish( ...
                    'ChannelViewChanged', flightdash.util.AppEventData(0, src.Value));
            else
                cb = @(src,~) flightdash.view.HeaderBar.invokeApp(app, ...
                    @() app.setChannelViewMode(src.Value));
            end
        end

        function cb = makeDebugCb(app)
            if isempty(app)
                cb = @(src,~) flightdash.util.EventBus.publish( ...
                    'DebugModeToggled', flightdash.util.AppEventData(0, src.Value));
            else
                cb = @(src,~) flightdash.view.HeaderBar.invokeApp(app, ...
                    @() flightdash.view.HeaderBar.setDebugMode(app, src.Value));
            end
        end

        function cb = makeAppCb(app, methodName, fallbackEvent)
            if isempty(app) || ~ismethod(app, methodName)
                cb = @(~,~) flightdash.util.EventBus.publish( ...
                    fallbackEvent, flightdash.util.AppEventData());
            else
                cb = @(~,~) flightdash.view.HeaderBar.invokeApp(app, ...
                    @() feval(methodName, app));
            end
        end

        function invokeApp(app, fn)
            try
                if ~isempty(app) && isvalid(app)
                    fn();
                end
            catch ME
                try, app.logCaught(ME, 'HeaderBar:cb'); catch, end
            end
        end

        function setDebugMode(app, value)
            try
                app.DebugMode = logical(value);
            catch
            end
        end
    end
end
