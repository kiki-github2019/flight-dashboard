classdef HISplitter
    % flightdash.view.HISplitter
    % - Col 8: H↔I 경계 splitter (드래그 가능)
    
    methods (Static)
        function ui = build(dataGrid, fIdx)
            % [REFACTOR] app 의존 제거 - SplitterDragStarted 이벤트 발행
            ui = struct();
            ui.hiSplitter = uipanel(dataGrid, ...
                'BackgroundColor', [0.75 0.75 0.80], ...
                'BorderType', 'line', 'BorderColor', [0.45 0.45 0.55], ...
                'Tooltip', '드래그하여 비디오 패널 너비 조절 (H ↔ I)', ...
                'HitTest', 'on');
            ui.hiSplitter.Layout.Column = 8;
            ui.hiSplitter.ButtonDownFcn = @(~,~) flightdash.util.EventBus.publish('SplitterDragStarted', flightdash.util.AppEventData(fIdx));
        end
    end
end
