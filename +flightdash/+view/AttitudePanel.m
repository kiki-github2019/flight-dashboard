classdef AttitudePanel
    % flightdash.view.AttitudePanel
    % - Col 1: 비행 자세 (Pitch / Roll / Heading 게이지)
    % - 외부 콜백 없음 (시각화만)
    %
    % [REFACTOR] app 의존 완전 제거 - createGaugePanel 헬퍼를 view 내부로 이동
    %
    % 사용:
    %   ui = flightdash.view.AttitudePanel.build(dataGrid);
    %   → ui.panelAttitude / pitchAxes / rollAxes / hdgAxes / pitchLabel / rollLabel / hdgLabel

    methods (Static)
        function ui = build(dataGrid)
            ui = struct();
            ui.panelAttitude = uipanel(dataGrid, 'Title', '비행 자세', ...
                'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', 'w');
            ui.panelAttitude.Layout.Column = 1;

            gGrid = uigridlayout(ui.panelAttitude, [3 1]);
            gGrid.RowHeight = {'1x', '1x', '1x'};
            gGrid.Padding = [2 2 2 2];
            gGrid.RowSpacing = 2;

            [ui.pitchAxes, ui.pitchLabel] = flightdash.view.AttitudePanel.createGauge(gGrid, 'Pitch');
            [ui.rollAxes,  ui.rollLabel]  = flightdash.view.AttitudePanel.createGauge(gGrid, 'Roll');
            [ui.hdgAxes,   ui.hdgLabel]   = flightdash.view.AttitudePanel.createGauge(gGrid, 'Heading');

            % [FIX] hgtransform 핸들 사전 placeholder - initPlots에서 실제 객체로 교체
            % - buildUIGroups가 createLayout 단계에서 이 필드를 참조하므로 미초기화 시 에러
            ui.hgPitch = gobjects(0);
            ui.hgRoll  = gobjects(0);
            ui.hgHdg   = gobjects(0);
        end

        function [ax, lbl] = createGauge(parentPnl, titleStr)
            % 게이지 패널 생성 헬퍼 (제목 라벨 + uiaxes 1:1 비율) + High-DPI 행 보정
            grid = uigridlayout(parentPnl, [2 1]);
            grid.RowHeight = {flightdash.util.UIScale.px(20), '1x'};
            grid.Padding = [0 0 0 0];
            grid.RowSpacing = 0;

            lbl = uilabel(grid, 'Text', [titleStr ' +0.000'], 'FontWeight', 'bold', ...
                'FontSize', 12, 'HorizontalAlignment', 'center');
            axPnl = uipanel(grid, 'BorderType', 'none', 'BackgroundColor', 'w');

            axGrid = uigridlayout(axPnl, [1 1], 'Padding', [0 0 0 0]);
            ax = uiaxes(axGrid);
            set(ax, 'XTick', [], 'YTick', [], 'XColor', 'none', 'YColor', 'none', 'Color', 'none');
            ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(ax);

            hold(ax, 'on');
            ax.DataAspectRatio = [1 1 1];
            ax.PlotBoxAspectRatio = [1 1 1];
            axis(ax, [-1.35 1.35 -1.35 1.35]);
            axis(ax, 'off');
        end
    end
end
