classdef VideoSyncController < flightdash.controller.ControllerBase
    % flightdash.controller.VideoSyncController
    % - 동기/Hz/Cache 이벤트 구독
    %
    % [Phase 4 stabilization] Inherits from ControllerBase so EventBus
    % subscriptions go through `trackListener` + are deleted by the
    % shared `cleanup` path.

    methods
        function obj = VideoSyncController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.ControllerBase.normalizeAdapterInput( ...
                    adapterOrApp, 'VideoSyncController'));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            obj.subscribeEvent('VideoSyncRequested', @(~,d) obj.onApplySync(d));
            obj.subscribeEvent('HzAdjustRequested',  @(~,d) obj.onHzAdjust(d));
            obj.subscribeEvent('HzInputChanged',     @(~,d) obj.onHzChanged(d));
            obj.subscribeEvent('CacheBudgetChanged', @(~,d) obj.onCacheBudget(d));
        end

        function onApplySync(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.applyVideoSync(d.ChannelIdx);
        end
        function onHzAdjust(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            p = d.Payload;
            app.adjustHzValue(d.ChannelIdx, p.target, p.delta);
        end
        function onHzChanged(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            p = d.Payload;
            app.onHzInputChanged(d.ChannelIdx, p.target, p.value);
        end
        function onCacheBudget(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.setCacheBudget(d.Payload);
        end

        % 호환 wrapper
        function applySync(obj, fIdx),                    a = obj.app(); if ~isempty(a), a.applyVideoSync(fIdx); end, end
        function adjustHz(obj, fIdx, target, delta),      a = obj.app(); if ~isempty(a), a.adjustHzValue(fIdx, target, delta); end, end
        function onHzChangedCb(obj, fIdx, target, value), a = obj.app(); if ~isempty(a), a.onHzInputChanged(fIdx, target, value); end, end
        function setCacheBudget(obj, budgetMB),           a = obj.app(); if ~isempty(a), a.setCacheBudget(budgetMB); end, end
    end

end
