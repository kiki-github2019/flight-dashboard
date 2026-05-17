classdef PlotController < flightdash.controller.ControllerBase
    % flightdash.controller.PlotController
    % Owns Plot/Tab EventBus routing.
    %
    % [Phase 4 stabilization] Inherits from ControllerBase; listener
    % tracking + cleanup centralised.

    methods
        function obj = PlotController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.ControllerBase.normalizeAdapterInput( ...
                    adapterOrApp, 'PlotController'));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            obj.subscribeEvent('PlotSelected',          @(~,d) obj.onPlotSelected(d));
            obj.subscribeEvent('PlotTabAddRequested',   @(~,d) obj.onAddTab(d));
            obj.subscribeEvent('PlotTabClearRequested', @(~,d) obj.onClearTab(d));
            obj.subscribeEvent('TabChanged',            @(~,d) obj.onTabChanged(d));
            obj.subscribeEvent('PlotVisibilityChanged', @(~,d) obj.onPlotVisibility(d));
            obj.subscribeEvent('PlotManagerSelected',   @(~,d) obj.onPlotManagerSelected(d));
            obj.subscribeEvent('PlotDetailChanged',     @(~,d) obj.onPlotDetailChanged(d));
            obj.subscribeEvent('PlotAxisChanged',       @(~,d) obj.onPlotAxisChanged(d));
            obj.subscribeEvent('PlotManagerToggled',    @(~,d) obj.onPlotManagerToggled(d));
            obj.subscribeEvent('PlotDetailsToggled',    @(~,d) obj.onPlotDetailsToggled(d));
        end

        function onPlotSelected(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            if app.hasPlotView(d.ChannelIdx)
                app.PlotView(d.ChannelIdx).addSelectedVariable();
            end
        end
        function onAddTab(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            if app.hasPlotView(d.ChannelIdx)
                app.PlotView(d.ChannelIdx).addTab();
            end
        end
        function onClearTab(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            if app.hasPlotView(d.ChannelIdx)
                app.PlotView(d.ChannelIdx).clearCurrentTab();
            end
        end
        function onTabChanged(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.updateTabTimeLines(d.ChannelIdx);
        end
        function onPlotVisibility(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.onPlotVisibilityChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotManagerSelected(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.onPlotManagerSelected(d.ChannelIdx, d.Payload);
        end
        function onPlotDetailChanged(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.onPlotDetailChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotAxisChanged(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.onPlotAxisChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotManagerToggled(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.togglePlotManager(d.ChannelIdx);
        end
        function onPlotDetailsToggled(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.togglePlotDetails(d.ChannelIdx);
        end
    end

end
