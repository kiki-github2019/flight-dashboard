classdef HISplitter
    % flightdash.view.HISplitter
    % - Col 5: H↔I 경계 splitter (드래그 가능)
    
    methods (Static)
        function ui = build(dataGrid, fIdx)
            % [REFACTOR] app 의존 제거 - SplitterDragStarted 이벤트 발행
            import flightdash.util.EventBus
            import flightdash.util.AppEventData
            ui = struct();
            ui.hiSplitter = uipanel(dataGrid, ...
                'BackgroundColor', [0.75 0.75 0.80], ...
                'BorderType', 'line', 'BorderColor', [0.45 0.45 0.55], ...
                'Tooltip', '드래그하여 비디오 패널 너비 조절 (H ↔ I)', ...
                'HitTest', 'on');
            ui.hiSplitter.Layout.Column = 5;
            ui.hiSplitter.ButtonDownFcn = @(~,~) EventBus.publish('SplitterDragStarted', AppEventData(fIdx));
        end
    end
end
