classdef PlaybackController < handle
    % flightdash.controller.PlaybackController
    % - 재생/이동 이벤트 구독: Slider/Nav/Spinner/Table/PlotTab 등
    
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = PlaybackController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('SliderChanging',         @(~,d) obj.onSliderChanging(d));
            obj.Listeners{end+1} = EB('SliderChanged',          @(~,d) obj.onSliderChanged(d));
            obj.Listeners{end+1} = EB('NavActionRequested',     @(~,d) obj.onNav(d));
            obj.Listeners{end+1} = EB('SpinnerChanged',         @(~,d) obj.onSpinner(d));
            obj.Listeners{end+1} = EB('TableRowSelected',       @(~,d) obj.onTableSelect(d));
            obj.Listeners{end+1} = EB('PlotSelected',           @(~,d) obj.onPlotSelected(d));
            obj.Listeners{end+1} = EB('PlotTabAddRequested',    @(~,d) obj.onAddTab(d));
            obj.Listeners{end+1} = EB('PlotTabClearRequested',  @(~,d) obj.onClearTab(d));
            obj.Listeners{end+1} = EB('TabChanged',             @(~,d) obj.onTabChanged(d));
        end
        
        function onSliderChanging(obj, d), obj.App.onVdubSliderChanging(d.ChannelIdx, d.Payload); end
        function onSliderChanged(obj, d),  obj.App.onVdubSliderChanged(d.ChannelIdx, d.Payload); end
        function onNav(obj, d),            obj.App.onVdubNav(d.ChannelIdx, d.Payload); end
        function onSpinner(obj, d),        obj.App.handleSpinnerChange(d.ChannelIdx, d.Payload); end
        function onTableSelect(obj, d),    obj.App.handleTableSelection(d.ChannelIdx, d.Payload); end
        function onPlotSelected(obj, d),   obj.App.plotSelectedVariable(d.ChannelIdx); end
        function onAddTab(obj, d),         obj.App.addPlotTab(d.ChannelIdx); end
        function onClearTab(obj, d),       obj.App.clearCurrentTab(d.ChannelIdx); end
        function onTabChanged(obj, d),     obj.App.updateTabTimeLines(d.ChannelIdx); end
        
        % 호환 wrapper
        function sliderChanging(obj, fIdx, value), obj.App.onVdubSliderChanging(fIdx, value); end
        function sliderChanged(obj, fIdx, src),    obj.App.onVdubSliderChanged(fIdx, src); end
        function nav(obj, fIdx, action),           obj.App.onVdubNav(fIdx, action); end
        function spinnerChange(obj, fIdx, value),  obj.App.handleSpinnerChange(fIdx, value); end
        function tableSelect(obj, fIdx, event),    obj.App.handleTableSelection(fIdx, event); end
        function plotSelected(obj, fIdx),          obj.App.plotSelectedVariable(fIdx); end
        function addTab(obj, fIdx),                obj.App.addPlotTab(fIdx); end
        function clearTab(obj, fIdx),              obj.App.clearCurrentTab(fIdx); end
        function tabChanged(obj, fIdx),            obj.App.updateTabTimeLines(fIdx); end
        
        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
