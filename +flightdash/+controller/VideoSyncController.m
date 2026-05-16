classdef VideoSyncController < handle
    % flightdash.controller.VideoSyncController
    % - 동기/Hz/Cache 이벤트 구독
    %
    % [REFACTOR R5+7] Migrated to DashboardAppAdapter. Pure event-relay
    % controller — every callback ends in an app verb (applyVideoSync /
    % adjustHzValue / onHzInputChanged / setCacheBudget). Bodies
    % uniformly escape-hatch via obj.Adapter.app().

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
        Listeners cell = {}
    end

    methods
        function obj = VideoSyncController(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('VideoSyncController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            app = obj.Adapter.app();
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(app, eventName, callback);
            obj.Listeners{end+1} = EB('VideoSyncRequested', @(~,d) obj.onApplySync(d));
            obj.Listeners{end+1} = EB('HzAdjustRequested',  @(~,d) obj.onHzAdjust(d));
            obj.Listeners{end+1} = EB('HzInputChanged',     @(~,d) obj.onHzChanged(d));
            obj.Listeners{end+1} = EB('CacheBudgetChanged', @(~,d) obj.onCacheBudget(d));
        end

        function onApplySync(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.applyVideoSync(d.ChannelIdx);
        end
        function onHzAdjust(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            p = d.Payload;
            app.adjustHzValue(d.ChannelIdx, p.target, p.delta);
        end
        function onHzChanged(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            p = d.Payload;
            app.onHzInputChanged(d.ChannelIdx, p.target, p.value);
        end
        function onCacheBudget(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.setCacheBudget(d.Payload);
        end

        % 호환 wrapper
        function applySync(obj, fIdx)
            obj.Adapter.app().applyVideoSync(fIdx);
        end
        function adjustHz(obj, fIdx, target, delta)
            obj.Adapter.app().adjustHzValue(fIdx, target, delta);
        end
        function onHzChangedCb(obj, fIdx, target, value)
            obj.Adapter.app().onHzInputChanged(fIdx, target, value);
        end
        function setCacheBudget(obj, budgetMB)
            obj.Adapter.app().setCacheBudget(budgetMB);
        end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
