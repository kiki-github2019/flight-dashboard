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

        function publish(eventName, data, targetSessionId)
            % In Studio mode, older view callbacks may omit SessionId.
            % Fill it from SessionScope so controller guards can reliably
            % reject events from inactive embedded tabs.
            if nargin < 2
                data = [];
            end
            if nargin < 3
                targetSessionId = '';
            end
            data = flightdash.util.EventBus.normalizePayload(data);
            data = flightdash.util.EventBus.attachSession(data, targetSessionId);

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

        function listener = subscribe(eventName, callback, sessionId)
            eventName = char(eventName);
            if nargin < 3
                sessionId = '';
            end
            if ~flightdash.util.EventBus.isKnownEvent(eventName)
                error('flightdash:EventBus:UnknownEvent', ...
                    'Unknown EventBus event: %s', eventName);
            end
            inst = flightdash.util.EventBus.instance();
            sessionId = char(sessionId);
            if isempty(sessionId)
                listener = addlistener(inst, eventName, callback);
            else
                listener = addlistener(inst, eventName, ...
                    @(src, data) flightdash.util.EventBus.safeSessionCallback( ...
                    sessionId, eventName, callback, src, data));
            end
        end

        function tf = acceptsSession(listenerSessionId, eventSessionId)
            listenerSessionId = char(listenerSessionId);
            eventSessionId = char(eventSessionId);
            tf = isempty(listenerSessionId) || isempty(eventSessionId) || ...
                strcmp(listenerSessionId, eventSessionId);
        end
    end

    methods (Static, Access = private)
        function data = normalizePayload(data)
            if isempty(data)
                data = flightdash.util.AppEventData();
            elseif isa(data, 'event.EventData')
                return;
            elseif isstruct(data) && isfield(data, 'SessionId')
                data = flightdash.util.AppEventData(0, data, data.SessionId);
            else
                data = flightdash.util.AppEventData(0, data);
            end
        end

        function data = attachSession(data, targetSessionId)
            try
                if ~isa(data, 'flightdash.util.AppEventData')
                    return;
                end
                targetSessionId = char(targetSessionId);
                if ~isempty(targetSessionId)
                    data.SessionId = targetSessionId;
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

        function safeSessionCallback(listenerSessionId, eventName, callback, src, data)
            try
                eventSessionId = flightdash.util.EventBus.payloadSessionId(data);
                if ~flightdash.util.EventBus.acceptsSession(listenerSessionId, eventSessionId)
                    return;
                end
                callback(src, data);
            catch ME
                flightdash.util.ErrorLog.log(ME, ['EventBus:' char(eventName) ':SessionCallback'], false);
            end
        end

        function sessionId = payloadSessionId(data)
            sessionId = '';
            try
                if isa(data, 'flightdash.util.AppEventData') || ...
                        (isobject(data) && isprop(data, 'SessionId'))
                    sessionId = char(data.SessionId);
                elseif isstruct(data) && isfield(data, 'SessionId')
                    sessionId = char(data.SessionId);
                end
            catch
                sessionId = '';
            end
        end

        function tf = isKnownEvent(eventName)
            mc = ?flightdash.util.EventBus;
            tf = any(strcmp(eventName, {mc.EventList.Name}));
        end
    end
end
