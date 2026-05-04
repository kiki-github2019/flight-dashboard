classdef EventBus < handle
    % flightdash.util.EventBus
    % - View↔Controller 결합도를 낮추는 중앙 메시지 브로커 (싱글톤)
    %
    % 사용:
    %   flightdash.util.EventBus.publish('TableRowSelected', flightdash.util.AppEventData(fIdx, evt));
    %   listener = flightdash.util.EventBus.subscribe('TableRowSelected', @(src,d) handle(d));
    %
    % 이벤트 이름 규칙: PascalCase, "동작Target" 또는 "TargetVerbed"
    
    events
        % 파일/로드
        FlightFileRequested      % FileController.loadFlight
        AviFileRequested         % FileController.loadAvi
        CoastFileRequested       % handleCoastFile
        ConfigExportRequested    % export current dashboard session config
        ConfigImportRequested    % import dashboard session config
        DebugModeToggled         % toggleDebugMode
        SyncToggled              % toggleSync (양 채널 동기 on/off)
        
        % 패널 토글 / Splitter
        LayoutFitRequested       % fit window to current monitor
        ChannelViewChanged       % both / flight1 / flight2 row visibility
        PanelToggled             % togglePanel
        PanelSplitterDragStarted % start non-video panel splitter drag
        SplitterDragStarted      % startHISplitterDrag
        
        % Playback
        SpinnerChanged           % handleSpinnerChange
        TableRowSelected         % handleTableSelection
        InfoFormatRequested      % set current info value display format
        InfoOrderMoveRequested   % move selected current info row up/down
        FlightPlayRequested      % start flight-data playback from current marker
        FlightStopRequested      % stop flight-data playback
        FlightPlayIntervalChanged % set flight-data playback interval
        PlotSelected             % plotSelectedVariable
        PlotTabAddRequested      % addPlotTab
        PlotTabClearRequested    % clearCurrentTab
        TabChanged               % updateTabTimeLines
        PlotVisibilityChanged    % togglePlotVisibility
        PlotManagerSelected      % selectManagedPlot
        PlotDetailChanged        % updatePlotDetails
        PlotAxisChanged          % set selected plot X/Y axis limits and auto modes
        DetailsToggleRequested   % toggle pooled details/plots popup figure
        PlotManagerToggled       % show/hide plot manager
        PlotDetailsToggled       % show/hide plot details
        PannerToggled            % show/hide compact range bar
        PannerClicked            % set plot window from overview click
        PannerRangeChanged       % set plot window from From/To inputs
        PannerResetRequested     % reset plot window to full time span
        RoiAddRequested          % add current ROI
        RoiSelectionChanged      % select ROI table row
        RoiDeleteSelectedRequested % delete selected ROI row
        RoiClearRequested        % clear ROI/annotation rows
        AnalysisComputeRequested % compute simple ROI statistics
        SliderChanging           % onVdubSliderChanging
        SliderChanged            % onVdubSliderChanged
        NavActionRequested       % onVdubNav
        
        % Video Sync / Hz / Cache
        VideoSyncRequested       % applyVideoSync
        HzAdjustRequested        % adjustHzValue
        HzInputChanged           % onHzInputChanged
        CacheBudgetChanged       % setCacheBudget
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
            % 이벤트 발행 - data는 flightdash.util.AppEventData 권장
            if nargin < 2 || isempty(data)
                data = flightdash.util.AppEventData();
            end
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
            % 이벤트 구독 - 호출자가 listener 핸들 보관 (GC 방지)
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
        function tf = isKnownEvent(eventName)
            mc = ?flightdash.util.EventBus;
            tf = any(strcmp(eventName, {mc.EventList.Name}));
        end
    end
end
