classdef PlotController < handle
    % flightdash.controller.PlotController
    % Owns Plot/Tab EventBus routing.
    %
    % [REFACTOR R5+8] Migrated to DashboardAppAdapter. Every handler is
    % a relay to an app verb (hasPlotView / PlotView(...) actions /
    % updateTabTimeLines / onPlotVisibilityChanged / on*PlotManagerSel.
    % / on*Plot*Changed / togglePlotManager / togglePlotDetails) — they
    % escape-hatch via obj.Adapter.app(). Adapter handles the EventBus
    % subscription routing.

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
        Listeners cell = {}
    end

    methods
        function obj = PlotController(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('PlotController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            app = obj.Adapter.app();
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(app, eventName, callback);
            obj.Listeners{end+1} = EB('PlotSelected',          @(~,d) obj.onPlotSelected(d));
            obj.Listeners{end+1} = EB('PlotTabAddRequested',   @(~,d) obj.onAddTab(d));
            obj.Listeners{end+1} = EB('PlotTabClearRequested', @(~,d) obj.onClearTab(d));
            obj.Listeners{end+1} = EB('TabChanged',            @(~,d) obj.onTabChanged(d));
            obj.Listeners{end+1} = EB('PlotVisibilityChanged', @(~,d) obj.onPlotVisibility(d));
            obj.Listeners{end+1} = EB('PlotManagerSelected',   @(~,d) obj.onPlotManagerSelected(d));
            obj.Listeners{end+1} = EB('PlotDetailChanged',     @(~,d) obj.onPlotDetailChanged(d));
            obj.Listeners{end+1} = EB('PlotAxisChanged',       @(~,d) obj.onPlotAxisChanged(d));
            obj.Listeners{end+1} = EB('PlotManagerToggled',    @(~,d) obj.onPlotManagerToggled(d));
            obj.Listeners{end+1} = EB('PlotDetailsToggled',    @(~,d) obj.onPlotDetailsToggled(d));
        end

        function onPlotSelected(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            if app.hasPlotView(d.ChannelIdx)
                app.PlotView(d.ChannelIdx).addSelectedVariable();
            end
        end
        function onAddTab(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            if app.hasPlotView(d.ChannelIdx)
                app.PlotView(d.ChannelIdx).addTab();
            end
        end
        function onClearTab(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            if app.hasPlotView(d.ChannelIdx)
                app.PlotView(d.ChannelIdx).clearCurrentTab();
            end
        end
        function onTabChanged(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.updateTabTimeLines(d.ChannelIdx);
        end
        function onPlotVisibility(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onPlotVisibilityChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotManagerSelected(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onPlotManagerSelected(d.ChannelIdx, d.Payload);
        end
        function onPlotDetailChanged(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onPlotDetailChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotAxisChanged(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onPlotAxisChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotManagerToggled(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.togglePlotManager(d.ChannelIdx);
        end
        function onPlotDetailsToggled(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.togglePlotDetails(d.ChannelIdx);
        end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try
                    if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end
                catch
                end
            end
            obj.Listeners = {};
        end
    end
end
