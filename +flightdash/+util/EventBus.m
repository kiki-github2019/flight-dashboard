classdef EventBus < handle
    % flightdash.util.EventBus
    % Central message broker between view components and controllers.
    %
    % Usage:
    %   data = flightdash.util.AppEventData(fIdx, payload, sessionId);
    %   flightdash.util.EventBus.publish('TableRowSelected', data);
    %   listener = flightdash.util.EventBus.subscribe('TableRowSelected', @(src,d) handle(d));
    %
    % Event names use PascalCase and are validated before notify().

    events
        % File / load
        FlightFileRequested
        AviFileRequested
        CoastFileRequested
        ConfigExportRequested
        ConfigImportRequested
        DebugModeToggled
        SyncToggled

        % Panel / splitter
        LayoutFitRequested
        ChannelViewChanged
        PanelToggled
        PanelSplitterDragStarted
        SplitterDragStarted

        % Playback / plot / ROI
        SpinnerChanged
        TableRowSelected
        InfoFormatRequested
        InfoOrderMoveRequested
        FlightPlayRequested
        FlightStopRequested
        FlightPlayIntervalChanged
        PlotSelected
        PlotTabAddRequested
        PlotTabClearRequested
        TabChanged
        PlotVisibilityChanged
        PlotManagerSelected
        PlotDetailChanged
        PlotAxisChanged
        DetailsToggleRequested
        PlotManagerToggled
        PlotDetailsToggled
        PannerToggled
        PannerClicked
        PannerRangeChanged
        PannerResetRequested
        RoiAddRequested
        RoiSelectionChanged
        RoiDeleteSelectedRequested
        RoiClearRequested
        AnalysisComputeRequested
        SliderChanging
        SliderChanged
        NavActionRequested

        % Video sync / Hz / cache
        VideoSyncRequested
        HzAdjustRequested
        HzInputChanged
        CacheBudgetChanged
    end

    methods (Access = private)
        function obj = EventBus()
        end
    end

    methods (Static)
        function inst = instance()
            persistent singleton
            if isempty(singleton) || ~isvalid(singleton)
                singleton = flightdash.util.EventBus();
            end
            inst = singleton;
        end

        function publish(eventName, data)
            % In Studio mode, older view callbacks may omit SessionId.
            % Fill it from SessionScope so controller guards can reliably
            % reject events from inactive embedded tabs.
            if nargin < 2
                data = [];
            end
            data = flightdash.util.EventBus.normalizePayload(data);
            data = flightdash.util.EventBus.attachActiveSessionIfMissing(data);

            eventName = char(eventName);
            inst = flightdash.util.EventBus.instance();
            if ~flightdash.util.EventBus.isKnownEvent(eventName)
                ME = MException('flightdash:EventBus:UnknownEvent', ...
                    'Unknown EventBus event: %s', eventName);
                flightdash.util.ErrorLog.log(ME, ['EventBus:' eventName]);
                warning('flightdash:EventBus:UnknownEvent', '%s', ME.message);
                return;
            end

            try
                notify(inst, eventName, data);
            catch ME
                flightdash.util.ErrorLog.log(ME, ['EventBus:' eventName]);
                warning('flightdash:EventBus:PublishFailed', ...
                    'EventBus callback failed for "%s": %s', eventName, ME.message);
            end
        end

        function listener = subscribe(eventName, callback)
            eventName = char(eventName);
            if ~flightdash.util.EventBus.isKnownEvent(eventName)
                error('flightdash:EventBus:UnknownEvent', ...
                    'Unknown EventBus event: %s', eventName);
            end
            inst = flightdash.util.EventBus.instance();
            listener = addlistener(inst, eventName, callback);
        end
    end

    methods (Static, Access = private)
        function data = normalizePayload(data)
            if isempty(data)
                data = flightdash.util.AppEventData();
            elseif isa(data, 'event.EventData')
                return;
            else
                data = flightdash.util.AppEventData(0, data);
            end
        end

        function data = attachActiveSessionIfMissing(data)
            try
                if ~isa(data, 'flightdash.util.AppEventData')
                    return;
                end
                if ~isempty(data.SessionId)
                    return;
                end
                activeId = flightdash.util.SessionScope.getActive();
                if ~isempty(activeId)
                    data.SessionId = char(activeId);
                end
            catch
            end
        end

        function tf = isKnownEvent(eventName)
            mc = ?flightdash.util.EventBus;
            tf = any(strcmp(eventName, {mc.EventList.Name}));
        end
    end
end
