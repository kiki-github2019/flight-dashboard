classdef VideoSyncController < handle
    % flightdash.controller.VideoSyncController
    % - 동기/Hz/Cache 이벤트 구독
    
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = VideoSyncController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('VideoSyncRequested',  @(~,d) obj.onApplySync(d));
            obj.Listeners{end+1} = EB('HzAdjustRequested',   @(~,d) obj.onHzAdjust(d));
            obj.Listeners{end+1} = EB('HzInputChanged',      @(~,d) obj.onHzChanged(d));
            obj.Listeners{end+1} = EB('CacheBudgetChanged',  @(~,d) obj.onCacheBudget(d));
        end
        
        function onApplySync(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.applyVideoSync(d.ChannelIdx);
        end
        function onHzAdjust(obj, d)
            if ~obj.App.isActiveSession(), return; end
            p = d.Payload;
            obj.App.adjustHzValue(d.ChannelIdx, p.target, p.delta);
        end
        function onHzChanged(obj, d)
            if ~obj.App.isActiveSession(), return; end
            p = d.Payload;
            obj.App.onHzInputChanged(d.ChannelIdx, p.target, p.value);
        end
        function onCacheBudget(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.setCacheBudget(d.Payload);
        end
        
        % 호환 wrapper
        function applySync(obj, fIdx),                   obj.App.applyVideoSync(fIdx); end
        function adjustHz(obj, fIdx, target, delta),     obj.App.adjustHzValue(fIdx, target, delta); end
        function onHzChangedCb(obj, fIdx, target, value), obj.App.onHzInputChanged(fIdx, target, value); end
        function setCacheBudget(obj, budgetMB),          obj.App.setCacheBudget(budgetMB); end
        
        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
