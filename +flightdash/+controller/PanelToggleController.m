classdef PanelToggleController < handle
    % flightdash.controller.PanelToggleController
    % - 패널 토글 + DebugMode + SyncToggle 이벤트 구독
    %
    % [REFACTOR R5+5] Migrated to DashboardAppAdapter. Pure event-relay
    % controller — every callback ends in an app verb (togglePanel /
    % toggleDebugMode / toggleSync / toggleWindowMaximized /
    % setChannelViewMode) that has no adapter API yet, so the body
    % uniformly escape-hatches via obj.Adapter.app().

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
        Listeners cell = {}
    end

    methods
        function obj = PanelToggleController(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('PanelToggleController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            app = obj.Adapter.app();
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(app, eventName, callback);
            obj.Listeners{end+1} = EB('PanelToggled',       @(~,d) obj.onPanelToggled(d));
            obj.Listeners{end+1} = EB('DebugModeToggled',   @(~,d) obj.onDebugToggled(d));
            obj.Listeners{end+1} = EB('SyncToggled',        @(~,~) obj.onSyncToggled());
            obj.Listeners{end+1} = EB('LayoutFitRequested', @(~,~) obj.onLayoutFitRequested());
            obj.Listeners{end+1} = EB('ChannelViewChanged', @(~,d) obj.onChannelViewChanged(d));
        end

        function onPanelToggled(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.togglePanel(d.ChannelIdx, d.Payload);
        end
        function onDebugToggled(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.toggleDebugMode(d.Payload);
        end
        function onSyncToggled(obj)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            app.toggleSync();
        end
        function onLayoutFitRequested(obj)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            app.toggleWindowMaximized();
        end
        function onChannelViewChanged(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.setChannelViewMode(d.Payload);
        end

        % 호환 wrapper
        function toggle(obj, fIdx, pnlName)
            obj.Adapter.app().togglePanel(fIdx, pnlName);
        end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
