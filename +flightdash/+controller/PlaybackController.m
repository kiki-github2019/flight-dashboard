classdef PlaybackController < handle
    % flightdash.controller.PlaybackController
    % - 재생/이동 이벤트 구독: Slider/Nav/Spinner/Table/PlotTab 등
    %
    % [REFACTOR R5+10] Migrated to DashboardAppAdapter. Adapter routes
    % EventBus / logCaught; the dense playback-verb surface
    % (onVdubSliderChanging/Changed / onVdubNav / handleSpinnerChange /
    % setInfoFormatMode / applyTimeChange / findClosestIndexByTime /
    % restorePlotMarkerInteractions / InfoCtrl.handleTableSelection /
    % InfoCtrl.moveSelectedRow / app.Models / app.UI / app.VideoSyncState)
    % keeps escape-hatching via obj.Adapter.app(). This is the last of
    % the 10 controllers migrated to the adapter pattern.

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
        Listeners cell = {}
        FlightPlayTimers = {[], []}
        FlightPlayIntervalS = [1, 1]
    end

    methods
        function obj = PlaybackController(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('PlaybackController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            app = obj.Adapter.app();
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(app, eventName, callback);
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
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onVdubSliderChanging(d.ChannelIdx, d.Payload);
        end
        function onSliderChanged(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onVdubSliderChanged(d.ChannelIdx, d.Payload);
        end
        function onNav(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.onVdubNav(d.ChannelIdx, d.Payload);
        end
        function onSpinner(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.handleSpinnerChange(d.ChannelIdx, d.Payload);
        end
        function onTableSelect(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.InfoCtrl.handleTableSelection(d.ChannelIdx, d.Payload);
        end
        function onInfoFormat(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.setInfoFormatMode(d.ChannelIdx, d.Payload);
        end
        function onInfoOrderMove(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.InfoCtrl.moveSelectedRow(d.ChannelIdx, d.Payload);
        end
        function onFlightPlay(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            obj.startFlightPlayback(d.ChannelIdx);
        end
        function onFlightStop(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            obj.stopFlightPlayback(d.ChannelIdx);
        end
        function onFlightPlayInterval(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            obj.setFlightPlayInterval(d.ChannelIdx, d.Payload);
        end

        % 호환 wrapper
        function sliderChanging(obj, fIdx, value)
            obj.Adapter.app().onVdubSliderChanging(fIdx, value);
        end
        function sliderChanged(obj, fIdx, src)
            obj.Adapter.app().onVdubSliderChanged(fIdx, src);
        end
        function nav(obj, fIdx, action)
            obj.Adapter.app().onVdubNav(fIdx, action);
        end
        function spinnerChange(obj, fIdx, value)
            obj.Adapter.app().handleSpinnerChange(fIdx, value);
        end
        function tableSelect(obj, fIdx, event)
            obj.Adapter.app().InfoCtrl.handleTableSelection(fIdx, event);
        end

        function startFlightPlayback(obj, fIdx)
            try
                app = obj.Adapter.app();
                if fIdx < 1 || fIdx > numel(app.Models), return; end
                if isempty(app.Models(fIdx).rawData), return; end

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
                obj.Adapter.logCaught(ME, 'FlightPlay:start');
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
                    obj.Adapter.app().restorePlotMarkerInteractions(fIdx);
                catch ME_restore
                    obj.Adapter.logCaught(ME_restore, 'FlightPlay:restoreMarkerDrag');
                end
            catch ME
                obj.Adapter.logCaught(ME, 'FlightPlay:stop');
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
                app = obj.Adapter.app();
                if isfield(app.UI(fIdx), 'flightPlayInterval') && isvalid(app.UI(fIdx).flightPlayInterval)
                    app.UI(fIdx).flightPlayInterval.Value = value;
                end

                t = obj.FlightPlayTimers{fIdx};
                if ~isempty(t) && isvalid(t) && strcmpi(t.Running, 'on')
                    obj.startFlightPlayback(fIdx);
                end
            catch ME
                obj.Adapter.logCaught(ME, 'FlightPlay:interval');
            end
        end

        function onFlightPlayTick(obj, fIdx)
            try
                app = obj.Adapter.app();
                if isempty(app) || ~isvalid(app) || fIdx < 1 || fIdx > numel(app.Models)
                    obj.stopFlightPlayback(fIdx);
                    return;
                end
                if isempty(app.Models(fIdx).rawData)
                    obj.stopFlightPlayback(fIdx);
                    return;
                end

                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isempty(times)
                    obj.stopFlightPlayback(fIdx);
                    return;
                end

                currIdx = max(1, min(numel(times), app.Models(fIdx).currentIndex));
                nextTime = times(currIdx) + obj.resolveFlightPlayPeriod(fIdx);
                if nextTime >= times(end)
                    app.applyTimeChange(fIdx, numel(times));
                    obj.stopFlightPlayback(fIdx);
                    return;
                end

                nextIdx = app.findClosestIndexByTime(times, nextTime);
                if nextIdx <= currIdx && currIdx < numel(times)
                    nextIdx = currIdx + 1;
                end
                app.applyTimeChange(fIdx, nextIdx);
            catch ME
                obj.Adapter.logCaught(ME, 'FlightPlay:tick');
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
                app = obj.Adapter.app();
                if fIdx < 1 || fIdx > numel(app.Models) || isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if numel(times) < 2, return; end
                d = diff(times(1:min(numel(times), 200)));
                d = d(isfinite(d) & d > 0);
                if ~isempty(d)
                    dt = median(d);
                elseif isfield(app.VideoSyncState, 'DataFps') && app.VideoSyncState(fIdx).DataFps > 0
                    dt = 1 / app.VideoSyncState(fIdx).DataFps;
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
