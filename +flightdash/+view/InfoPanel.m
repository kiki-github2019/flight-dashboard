classdef InfoPanel
    % flightdash.view.InfoPanel
    % - Col 3: 현재 비행 정보 (uitable)
    % - context menu (plot 추가) + cell selection 콜백 wiring
    
    methods (Static)
        function ui = build(dataGrid, fIdx)
            % [REFACTOR] app 의존 제거 - ancestor()로 figure 핸들 자동 탐색
            import flightdash.util.EventBus
            import flightdash.util.AppEventData
            ui = struct();
            infoPanel = uipanel(dataGrid, 'Title', '현재 비행 정보', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', 'w', 'Scrollable', 'on');
            infoPanel.Layout.Column = 3;
            
            glInfo = uigridlayout(infoPanel, [1 1], 'Padding', [0 0 0 0]);
            if fIdx == 1
                tblBgColor = [0.23 0.51 0.96];
            else
                tblBgColor = [0.31 0.27 0.90];
            end
            ui.dataTable = uitable(glInfo, 'BackgroundColor', tblBgColor, ...
                'ForegroundColor', [1 1 1], 'FontWeight', 'bold', ...
                'RowStriping', 'off', 'ColumnName', {'항목', '값'}, ...
                'RowName', [], 'ColumnWidth', {'auto', '1x'}, ...
                'FontSize', 12, 'FontName', 'Consolas');
            
            % 부모를 타고 올라가 최상위 figure 자동 탐색
            hFigure = ancestor(dataGrid, 'figure');
            cm = uicontextmenu(hFigure);
            uimenu(cm, 'Text', 'H 영역에 Plot 추가 (현재 탭)', ...
                'MenuSelectedFcn', @(~,~) EventBus.publish('PlotSelected', AppEventData(fIdx)));
            ui.dataTable.ContextMenu = cm;
            ui.dataTable.CellSelectionCallback = @(~, event) EventBus.publish('TableRowSelected', AppEventData(fIdx, event));
        end
    end
end
