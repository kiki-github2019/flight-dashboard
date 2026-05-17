classdef PlotController < flightdash.controller.ControllerBase
    % flightdash.controller.PlotController
    % Owns Plot/Tab EventBus routing.
    %
    % [Phase 4 stabilization] Inherits from ControllerBase; listener
    % tracking + cleanup centralised.

    methods
        function obj = PlotController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.PlotController.normalizeInput(adapterOrApp));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            appHandle = obj.app();
            if isempty(appHandle), return; end
            EB = @(eventName, callback) ...
                flightdash.util.EventBus.subscribeForApp(appHandle, eventName, callback);
            obj.trackListener(EB('PlotSelected',          @(~,d) obj.onPlotSelected(d)));
            obj.trackListener(EB('PlotTabAddRequested',   @(~,d) obj.onAddTab(d)));
            obj.trackListener(EB('PlotTabClearRequested', @(~,d) obj.onClearTab(d)));
            obj.trackListener(EB('TabChanged',            @(~,d) obj.onTabChanged(d)));
            obj.trackListener(EB('PlotVisibilityChanged', @(~,d) obj.onPlotVisibility(d)));
            obj.trackListener(EB('PlotManagerSelected',   @(~,d) obj.onPlotManagerSelected(d)));
            obj.trackListener(EB('PlotDetailChanged',     @(~,d) obj.onPlotDetailChanged(d)));
            obj.trackListener(EB('PlotAxisChanged',       @(~,d) obj.onPlotAxisChanged(d)));
            obj.trackListener(EB('PlotManagerToggled',    @(~,d) obj.onPlotManagerToggled(d)));
            obj.trackListener(EB('PlotDetailsToggled',    @(~,d) obj.onPlotDetailsToggled(d)));
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

    methods (Static, Access = private)
        function input = normalizeInput(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter') || ...
                    isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                input = adapterOrApp;
            else
                error('PlotController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
        end
    end
end
