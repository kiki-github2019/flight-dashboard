classdef DragController < handle
    % flightdash.controller.DragController
    % - SplitterDragStarted 이벤트 구독
    
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = DragController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('PanelSplitterDragStarted', @(~,d) obj.onPanelSplitterStart(d));
            obj.Listeners{end+1} = EB('SplitterDragStarted', @(~,d) obj.onSplitterStart(d));
        end
        
        function onPanelSplitterStart(obj, d)
            if ~obj.App.isActiveSession(), return; end
            obj.App.startPanelSplitterDrag(d.ChannelIdx, d.Payload);
        end
        function onSplitterStart(obj, d)
            if ~obj.App.isActiveSession(), return; end
            obj.App.startHISplitterDrag(d.ChannelIdx);
        end
        
        % 호환 wrapper
        function startSplitter(obj, fIdx), obj.App.startHISplitterDrag(fIdx); end
        
        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
