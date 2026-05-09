classdef PlaybackController < handle
    % flightdash.controller.PlaybackController
    % - 재생/이동 이벤트 구독: Slider/Nav/Spinner/Table/PlotTab 등
    
    properties (Access = private)
        App
        Listeners cell = {}
        FlightPlayTimers = {[], []}
        FlightPlayIntervalS = [1, 1]
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
            obj.Listeners{end+1} = EB('InfoFormatRequested',    @(~,d) obj.onInfoFormat(d));
            obj.Listeners{end+1} = EB('InfoOrderMoveRequested', @(~,d) obj.onInfoOrderMove(d));
            obj.Listeners{end+1} = EB('FlightPlayRequested',    @(~,d) obj.onFlightPlay(d));
            obj.Listeners{end+1} = EB('FlightStopRequested',    @(~,d) obj.onFlightStop(d));
            obj.Listeners{end+1} = EB('FlightPlayIntervalChanged', @(~,d) obj.onFlightPlayInterval(d));
        end
        
        function onSliderChanging(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onVdubSliderChanging(d.ChannelIdx, d.Payload);
        end
        function onSliderChanged(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onVdubSliderChanged(d.ChannelIdx, d.Payload);
        end
        function onNav(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.onVdubNav(d.ChannelIdx, d.Payload);
        end
        function onSpinner(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.handleSpinnerChange(d.ChannelIdx, d.Payload);
        end
        function onTableSelect(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.InfoCtrl.handleTableSelection(d.ChannelIdx, d.Payload);
        end
        function onInfoFormat(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.setInfoFormatMode(d.ChannelIdx, d.Payload);
        end
        function onInfoOrderMove(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.InfoCtrl.moveSelectedRow(d.ChannelIdx, d.Payload);
        end
        function onFlightPlay(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.startFlightPlayback(d.ChannelIdx);
        end
        function onFlightStop(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.stopFlightPlayback(d.ChannelIdx);
        end
        function onFlightPlayInterval(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.setFlightPlayInterval(d.ChannelIdx, d.Payload);
        end
        
        % 호환 wrapper
        function sliderChanging(obj, fIdx, value), obj.App.onVdubSliderChanging(fIdx, value); end
        function sliderChanged(obj, fIdx, src),    obj.App.onVdubSliderChanged(fIdx, src); end
        function nav(obj, fIdx, action),           obj.App.onVdubNav(fIdx, action); end
        function spinnerChange(obj, fIdx, value),  obj.App.handleSpinnerChange(fIdx, value); end
        function tableSelect(obj, fIdx, event),    obj.App.InfoCtrl.handleTableSelection(fIdx, event); end

        function startFlightPlayback(obj, fIdx)
            try
                if fIdx < 1 || fIdx > numel(obj.App.Models), return; end
                if isempty(obj.App.Models(fIdx).rawData), return; end

                obj.stopFlightPlayback(fIdx);
                periodS = obj.resolveFlightPlayPeriod(fIdx);
                obj.FlightPlayTimers{fIdx} = timer( ...
                    'Name', sprintf('FlightDashPlay%d', fIdx), ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'BusyMode', 'drop', ...
                    'Period', periodS, ...
                    'TimerFcn', @(~,~) obj.onFlightPlayTick(fIdx));
                start(obj.FlightPlayTimers{fIdx});
            catch ME
                obj.App.logCaught(ME, 'FlightPlay:start');
            end
        end

        function stopFlightPlayback(obj, fIdx)
            try
                if fIdx < 1 || fIdx > numel(obj.FlightPlayTimers), return; end
                t = obj.FlightPlayTimers{fIdx};
                if ~isempty(t)
                    try
                        if isvalid(t) && strcmpi(t.Running, 'on'), stop(t); end
                    catch
                    end
                    try
                        if isvalid(t), delete(t); end
                    catch
                    end
                end
                obj.FlightPlayTimers{fIdx} = [];
                try
                    obj.App.restorePlotMarkerInteractions(fIdx);
                catch ME_restore
                    obj.App.logCaught(ME_restore, 'FlightPlay:restoreMarkerDrag');
                end
            catch ME
                obj.App.logCaught(ME, 'FlightPlay:stop');
            end
        end

        function stopAllFlightPlayback(obj)
            for fIdx = 1:numel(obj.FlightPlayTimers)
                obj.stopFlightPlayback(fIdx);
            end
        end

        function setFlightPlayInterval(obj, fIdx, value)
            try
                if fIdx < 1 || fIdx > numel(obj.FlightPlayIntervalS), return; end
                value = double(value);
                if isempty(value) || ~isfinite(value) || value <= 0
                    value = 1;
                end
                value = max(value, obj.dataSamplePeriodS(fIdx));
                obj.FlightPlayIntervalS(fIdx) = value;
                if isfield(obj.App.UI(fIdx), 'flightPlayInterval') && isvalid(obj.App.UI(fIdx).flightPlayInterval)
                    obj.App.UI(fIdx).flightPlayInterval.Value = value;
                end

                t = obj.FlightPlayTimers{fIdx};
                if ~isempty(t) && isvalid(t) && strcmpi(t.Running, 'on')
                    obj.startFlightPlayback(fIdx);
                end
            catch ME
                obj.App.logCaught(ME, 'FlightPlay:interval');
            end
        end

        function onFlightPlayTick(obj, fIdx)
            try
                if isempty(obj.App) || ~isvalid(obj.App) || fIdx < 1 || fIdx > numel(obj.App.Models)
                    obj.stopFlightPlayback(fIdx);
                    return;
                end
                if isempty(obj.App.Models(fIdx).rawData)
                    obj.stopFlightPlayback(fIdx);
                    return;
                end

                timeCol = obj.App.Models(fIdx).mappedCols.Time;
                times = obj.App.Models(fIdx).rawData.(timeCol);
                if isempty(times)
                    obj.stopFlightPlayback(fIdx);
                    return;
                end

                currIdx = max(1, min(numel(times), obj.App.Models(fIdx).currentIndex));
                nextTime = times(currIdx) + obj.resolveFlightPlayPeriod(fIdx);
                if nextTime >= times(end)
                    obj.App.applyTimeChange(fIdx, numel(times));
                    obj.stopFlightPlayback(fIdx);
                    return;
                end

                nextIdx = obj.App.findClosestIndexByTime(times, nextTime);
                if nextIdx <= currIdx && currIdx < numel(times)
                    nextIdx = currIdx + 1;
                end
                obj.App.applyTimeChange(fIdx, nextIdx);
            catch ME
                obj.App.logCaught(ME, 'FlightPlay:tick');
                try, obj.stopFlightPlayback(fIdx); catch, end
            end
        end

        function periodS = resolveFlightPlayPeriod(obj, fIdx)
            periodS = 1;
            try
                if fIdx >= 1 && fIdx <= numel(obj.FlightPlayIntervalS)
                    periodS = obj.FlightPlayIntervalS(fIdx);
                end
                periodS = max(double(periodS), obj.dataSamplePeriodS(fIdx));
                if ~isfinite(periodS) || periodS <= 0, periodS = 1; end
            catch
                periodS = 1;
            end
        end

        function dt = dataSamplePeriodS(obj, fIdx)
            dt = 0.001;
            try
                if fIdx < 1 || fIdx > numel(obj.App.Models) || isempty(obj.App.Models(fIdx).rawData), return; end
                timeCol = obj.App.Models(fIdx).mappedCols.Time;
                times = obj.App.Models(fIdx).rawData.(timeCol);
                if numel(times) < 2, return; end
                d = diff(times(1:min(numel(times), 200)));
                d = d(isfinite(d) & d > 0);
                if ~isempty(d)
                    dt = median(d);
                elseif isfield(obj.App.VideoSyncState, 'DataFps') && obj.App.VideoSyncState(fIdx).DataFps > 0
                    dt = 1 / obj.App.VideoSyncState(fIdx).DataFps;
                end
            catch
                dt = 0.001;
            end
            if ~isfinite(dt) || dt <= 0, dt = 0.001; end
        end
        
        function delete(obj)
            obj.stopAllFlightPlayback();
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
