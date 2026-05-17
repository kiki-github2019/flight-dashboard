classdef PanelToggleController < flightdash.controller.ControllerBase
    % flightdash.controller.PanelToggleController
    % - 패널 토글 + DebugMode + SyncToggle 이벤트 구독
    %
    % [Phase 4 stabilization] Inherits from ControllerBase; listener
    % tracking + cleanup centralised.

    methods
        function obj = PanelToggleController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.ControllerBase.normalizeAdapterInput( ...
                    adapterOrApp, 'PanelToggleController'));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            obj.subscribeEvent('PanelToggled',       @(~,d) obj.onPanelToggled(d));
            obj.subscribeEvent('DebugModeToggled',   @(~,d) obj.onDebugToggled(d));
            obj.subscribeEvent('SyncToggled',        @(~,~) obj.onSyncToggled());
            obj.subscribeEvent('LayoutFitRequested', @(~,~) obj.onLayoutFitRequested());
            obj.subscribeEvent('ChannelViewChanged', @(~,d) obj.onChannelViewChanged(d));
        end

        function onPanelToggled(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.togglePanel(d.ChannelIdx, d.Payload);
        end
        function onDebugToggled(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.toggleDebugMode(d.Payload);
        end
        function onSyncToggled(obj)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            app.toggleSync();
        end
        function onLayoutFitRequested(obj)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            app.toggleWindowMaximized();
        end
        function onChannelViewChanged(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.setChannelViewMode(d.Payload);
        end

        % 호환 wrapper
        function toggle(obj, fIdx, pnlName)
            a = obj.app(); if ~isempty(a), a.togglePanel(fIdx, pnlName); end
        end
    end

end
