classdef PlotController < handle
    % flightdash.controller.PlotController
    % Owns Plot/Tab EventBus routing.

    properties (Access = private)
        App
        Listeners cell = {}
    end

    methods
        function obj = PlotController(app)
            obj.App = app;
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('PlotSelected',           @(~,d) obj.onPlotSelected(d));
            obj.Listeners{end+1} = EB('PlotTabAddRequested',    @(~,d) obj.onAddTab(d));
            obj.Listeners{end+1} = EB('PlotTabClearRequested',  @(~,d) obj.onClearTab(d));
            obj.Listeners{end+1} = EB('TabChanged',             @(~,d) obj.onTabChanged(d));
            obj.Listeners{end+1} = EB('PlotVisibilityChanged',  @(~,d) obj.onPlotVisibility(d));
            obj.Listeners{end+1} = EB('PlotManagerSelected',    @(~,d) obj.onPlotManagerSelected(d));
            obj.Listeners{end+1} = EB('PlotDetailChanged',      @(~,d) obj.onPlotDetailChanged(d));
            obj.Listeners{end+1} = EB('PlotAxisChanged',        @(~,d) obj.onPlotAxisChanged(d));
            obj.Listeners{end+1} = EB('PlotManagerToggled',     @(~,d) obj.onPlotManagerToggled(d));
            obj.Listeners{end+1} = EB('PlotDetailsToggled',     @(~,d) obj.onPlotDetailsToggled(d));
        end

        function onPlotSelected(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            if obj.App.hasPlotView(d.ChannelIdx)
                obj.App.PlotView(d.ChannelIdx).addSelectedVariable();
            end
        end
        function onAddTab(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            if obj.App.hasPlotView(d.ChannelIdx)
                obj.App.PlotView(d.ChannelIdx).addTab();
            end
        end
        function onClearTab(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            if obj.App.hasPlotView(d.ChannelIdx)
                obj.App.PlotView(d.ChannelIdx).clearCurrentTab();
            end
        end
        function onTabChanged(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.updateTabTimeLines(d.ChannelIdx);
        end
        function onPlotVisibility(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onPlotVisibilityChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotManagerSelected(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onPlotManagerSelected(d.ChannelIdx, d.Payload);
        end
        function onPlotDetailChanged(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onPlotDetailChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotAxisChanged(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onPlotAxisChanged(d.ChannelIdx, d.Payload);
        end
        function onPlotManagerToggled(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.togglePlotManager(d.ChannelIdx);
        end
        function onPlotDetailsToggled(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.togglePlotDetails(d.ChannelIdx);
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
