classdef MapAltPanel
    % flightdash.view.MapAltPanel
    % - Col 2: Map (위) + Altitude (아래) 수직 분할
    % - axes ButtonDownFcn / xLimListener는 app.Models 로드 후 별도 등록 (현재 코드 그대로)
    
    methods (Static)
        function ui = build(dataGrid, panelColor)
            % [REFACTOR] app 의존 제거 (사용처 없음)
            ui = struct();
            ui.panelMapAlt = uipanel(dataGrid, 'BorderType', 'none', 'BackgroundColor', panelColor);
            ui.panelMapAlt.Layout.Column = 3;

            rootGrid = uigridlayout(ui.panelMapAlt, [1 1]);
            rootGrid.Padding = [0 0 0 0];
            rootGrid.RowSpacing = 0;
            rootGrid.ColumnSpacing = 0;

            ui.mapAltContent = uipanel(rootGrid, 'BorderType', 'none', 'BackgroundColor', panelColor);
            ui.mapAltContent.Layout.Row = 1;
            ui.mapAltContent.Layout.Column = 1;
            
            pGrid = uigridlayout(ui.mapAltContent, [2 1]);
            pGrid.RowHeight = {'1.5x', '1x'};
            pGrid.Padding = [0 0 0 0];
            
            % Map
            mapPnl = uipanel(pGrid, 'Title', 'Map', 'FontSize', 12, ...
                'FontWeight', 'bold', 'BackgroundColor', 'w');
            mapGrid = uigridlayout(mapPnl, [1 1], 'Padding', [5 5 5 5]);
            ui.mapAxes = uiaxes(mapGrid);
            hold(ui.mapAxes, 'on');
            xlabel(ui.mapAxes, 'Lon', 'FontWeight', 'bold', 'FontSize', 10);
            ylabel(ui.mapAxes, 'Lat', 'FontWeight', 'bold', 'FontSize', 10);
            set(ui.mapAxes, 'XGrid', 'on', 'YGrid', 'on', ...
                'XMinorGrid', 'on', 'YMinorGrid', 'on', ...
                'XMinorTick', 'on', 'YMinorTick', 'on', 'TickDir', 'out');
            disableDefaultInteractivity(ui.mapAxes);
            ui.mapAxes.Toolbar.Visible = 'off';
            ui.mapAxes.Interactions = [panInteraction, zoomInteraction];
            
            % Altitude
            altPnl = uipanel(pGrid, 'Title', 'Altitude', 'FontSize', 12, ...
                'FontWeight', 'bold', 'BackgroundColor', 'w');
            altGrid = uigridlayout(altPnl, [1 1], 'Padding', [5 5 5 5]);
            ui.altAxes = uiaxes(altGrid);
            hold(ui.altAxes, 'on');
            xlabel(ui.altAxes, 'Time(s)', 'FontWeight', 'bold', 'FontSize', 11);
            ylabel(ui.altAxes, 'Alt', 'FontWeight', 'bold', 'FontSize', 10);
            xtickformat(ui.altAxes, '%.0f');
            set(ui.altAxes, 'XGrid', 'on', 'YGrid', 'on', ...
                'XMinorGrid', 'on', 'YMinorGrid', 'on', ...
                'XMinorTick', 'on', 'YMinorTick', 'on', 'TickDir', 'out');
            disableDefaultInteractivity(ui.altAxes);
            ui.altAxes.Toolbar.Visible = 'off';
            ui.altAxes.Interactions = [panInteraction, zoomInteraction];

            % [FIX] 데이터 로드 후 setupDataUI/initPlots에서 채워질 필드 사전 placeholder
            % - buildUIGroups가 createLayout 단계에서 참조하므로 미초기화 시 에러
            ui.hMapPath        = gobjects(0);
            ui.hgMapPlane      = gobjects(0);
            ui.hAltPath        = gobjects(0);
            ui.hAltMarker      = gobjects(0);
            ui.timeLine        = gobjects(0);
            ui.altXLimListener = [];

            ui.mapAltRail = uibutton(rootGrid, ...
                'Text', sprintf('MAP\nLat --\nLon --\nAlt --'), ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.94 0.99 0.97], ...
                'FontColor', [0.08 0.26 0.18], ...
                'Tooltip', 'Map and altitude summary', ...
                'Visible', 'off');
            ui.mapAltRail.Layout.Row = 1;
            ui.mapAltRail.Layout.Column = 1;
        end
    end
end
