classdef PlotPanel
    % flightdash.view.PlotPanel
    % - Col 4: H 데이터 뷰 패널 (tabGroup + 탭 추가/지우기 버튼)
    % - 셀 배열 cell(1, MAX_TABS)도 함께 초기화
    
    methods (Static)
        function ui = build(dataGrid, fIdx)
            % [REFACTOR] app 의존 제거 - AppConstants 공개 상수 참조
            %            (FlightDataDashboard.MAX_TABS는 private이라 외부 접근 위험)
            import flightdash.util.EventBus
            import flightdash.util.AppEventData
            MAX_TABS = flightdash.util.AppConstants.MAX_TABS;
            UIScale = flightdash.util.UIScale;   % High-DPI 행 높이 보정
            ui = struct();
            hPnl = uipanel(dataGrid, 'Title', 'H: 데이터 뷰 패널', ...
                'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', 'w');
            hPnl.Layout.Column = 4;

            hGrid2 = uigridlayout(hPnl, [2 1]);
            hGrid2.RowHeight = {UIScale.px(30), '1x'};
            hGrid2.Padding = [2 2 2 2];
            
            btnPnl = uipanel(hGrid2, 'BorderType', 'none', 'BackgroundColor', 'w');
            uibutton(btnPnl, 'Text', '+ 빈 탭 추가', 'Position', [5 5 90 22], ...
                'ButtonPushedFcn', @(~,~) EventBus.publish('PlotTabAddRequested', AppEventData(fIdx)));
            uibutton(btnPnl, 'Text', '현재 탭 지우기', 'Position', [100 5 100 22], ...
                'ButtonPushedFcn', @(~,~) EventBus.publish('PlotTabClearRequested', AppEventData(fIdx)));
            
            ui.tabGroup = uitabgroup(hGrid2);
            ui.tabGroup.SelectionChangedFcn = @(~,~) EventBus.publish('TabChanged', AppEventData(fIdx));
            
            ui.plotTabs = [];
            ui.plotLayouts = {};
            ui.plotAxes      = cell(1, MAX_TABS);
            ui.timeLines     = cell(1, MAX_TABS);
            ui.timeMarkers   = cell(1, MAX_TABS);
            ui.plotData      = cell(1, MAX_TABS);
            ui.xLimListeners = cell(1, MAX_TABS);
        end
    end
end
