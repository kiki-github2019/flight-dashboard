classdef FlightDataDashboard < matlab.apps.AppBase
    % =========================================================================
    % 비행 데이터 리뷰 대시보드 - V3.22 (리팩토링: 모듈 분해 + 캐시 자료구조 개선)
    % 설명:
    %   [V3.22 변경사항]
    %   - #1 ErrorLog ring buffer (silent catch도 사후 조사 가능)
    %        + dumpErrorLog(n, filterTag) 헬퍼 메서드
    %        (cell 배열 reference shuffle 제거 → 큰 프레임 lookup 시 GC 압력 감소)
    %        cacheStoreFrame은 in-place 갱신 + lastUse 동기 관리
    %        confirmVideoReplace / invalidateFrameCache / computeStartTimeFromFlightData
    %        cleanupVideoResources / openVideoReader / applyVideoLoadedUI
    %        computeTotalFrames / loadFirstFrame
    %        MAX_SEQ_READ_STEP, MAX_PENDING_ITERS
    %   - #6 Static wrapper: workerDecodeFrame / workerCleanupCache
    %        → 향후 +flightdash 패키지 마이그레이션 옵션 확보
    %   - #7 createLayout 분해: buildHeaderBar 추출 + 비행경로 루프 섹션 가이드 추가
    %
    %   [V3.21 #1-A] Generation counter (AsyncGen): 매 startAsyncDecode 호출 시
    %   [V3.21 #3-A] 3계층 분리:
    %     Layer 1 requestFrame: 진입점 + 캐시 lookup + sync/async 전략 선택
    %     Layer 2 decodeFrameSync / startAsyncDecode: 디코딩 (전략 패턴)
    %     Layer 3 displayFrame: 표시 + 캐시 store (write-through 단일 출구)
    %   [V3.21 #2-A] persistent VideoReader in worker:
    %     asyncDecodeFramePersistent 외부 함수에서 persistent 변수로 VR 재사용
    %   [V3.20 유지] 명시적 리소스 정리, 동기화 로그 prefix 표준화.
    %   [V3.18 유지] cache lookup clamp, Pending 완전 소진, hard limit 1.0.
    %   [V3.17 유지] InGoToFrame coalescing, IsDecoding 가드.
    % =========================================================================

    % Shared constants live in flightdash.util.AppConstants.

    properties (Access = public)
        UIFigure
        UI
        UIGroup
        SyncInput
        SyncBtn

        Models
        SyncState
        VideoState
        VideoSyncState

        CoastlineData
        FixedAreaBounds

        DebugMode         = false   % [V3.14 항목 6] true 시 zoom/pan off 등 로그 출력
        State             = 'IDLE'  % [V3.17 (8)] 'IDLE' | 'DRAGGING' | 'UPDATING' | 'DECODING'
        UseAsyncDecode    = false   % [V3.19 (1)] 비동기 디코딩 활성화 (Parallel Toolbox 필요)
    end

    % [PHASE 0 / Studio prep] Manager classes (LayoutMgr, AuxWindowMgr, controllers)
    % access app state directly. Keep these public so cross-class reads/writes
    % work identically in MATLAB Online (which strictly enforces private access).
    properties (Access = public)
        IsUpdating          = [false, false] % 재귀 방지 플래그
        IsProgrammaticXLim  = [false, false] % [V3.11 A] 책장 넘기기 등 프로그래밍 XLim 변경 시 리스너 차단
        IsDraggingPanner    = false         % compact range bar handle drag state
        PannerDragFIdx      = 0             % compact range bar drag channel
        PannerDragSide      = ''            % 'left' or 'right'
        LastDisplayedFrame  = [0, 0]        % [PATCH] 동일 프레임 조기 반환용
        HISplitterFIdx      = 0             % [PATCH UX-3] H/I 경계 드래그 중인 채널
        IsDraggingSplitter  = false         % [PATCH UX-3b] splitter 드래그 상태 플래그
        VideoUserResized    = [false, false] % [FIX] 사용자가 splitter로 조작했는지 (자동 리사이즈 차단)
        % [REFACTOR Step 1] 캐시는 별도 모델 객체로 위임. 기존 8개 속성 → 1개로 단일화
        % - flightdash.model.FrameCacheModel 배열 [1x2]
        % - 기존 cacheGetFrame/cacheStoreFrame 등은 호환을 위해 thin wrapper로 잔류
        CacheModel          = []              % [REFACTOR] flightdash.model.FrameCacheModel 배열
        VideoMdl            = []              % [REFACTOR Step 2] flightdash.model.VideoModel 배열 [1x2]
        SyncMdl             = []              % [REFACTOR Step 2] flightdash.model.SyncModel 배열 [1x2]
        PlaybackState       = []              % [REFACTOR] per-channel guard/pending state model [1x2]
        VideoListeners      = {[], []}        % [REFACTOR Step 2-C] event.listener 핸들 보관 (GC 방지)
        % [REFACTOR Step 4] 콜백 진입점 컨트롤러
        FileCtrl            = []
        VideoSyncCtrl       = []
        PlaybackCtrl        = []
        PlotCtrl            = []
        RoiCtrl             = []
        PannerCtrl          = []
        PanelCtrl           = []
        DragCtrl            = []
        MarkerDragCtrl      = []
        InfoCtrl            = []
        ConfigMgr           = []
        AuxWindowMgr        = []
        PlotView            = []
        PannerView          = []
        DataLoader          = []
        LayoutMgr           = []
        CacheBudgetMB       = 30              % [V3.14 항목 3] 호환 유지: setCacheBudget 진입점이 사용
        InGoToFrame         = [false, false] % [V3.16] goToFrame 재진입 차단 플래그
        PendingFrame        = [NaN, NaN]     % [V3.17 (1)(9)] 처리 중 들어온 최신 frame 요청
        PendingMode         = {'', ''}        % [V3.17 (1)(9)] 처리 중 들어온 최신 mode
        InCascade           = false          % [V3.17 (4)(11)] cascade 재귀 가드 (인스턴스 속성)
        IsDeleting          = false          % [FIX] delete(app) 중복 호출 방어 플래그
        IsDecoding          = [false, false] % [V3.17 (7)] 디코딩 진행 중 가드
        AsyncPool           = []              % [V3.19 (1)] parallel pool 핸들
        AsyncFutures        = {[], []}        % [V3.19 (1)] 진행 중 parfeval future
        AsyncTargetFrame    = [NaN, NaN]      % [V3.19 (1)] 비동기 디코딩 중인 frame No
        AsyncGen            = [0, 0]          % [V3.21 #1-A] generation counter (race 차단)
        VideoFilePath       = {'', ''}        % [V3.19 (1)] worker가 자체 VideoReader 생성용
        DragVelocity        = [0, 0]          % [V3.19 (2)] frames/sec (부호: 방향)
        DragVelocitySamples = {[], []}        % [V3.19 (2)] 최근 샘플 (이동평균용)
        LayoutProfile       = 'wide'          % [RESPONSIVE] wide|medium|compact|narrow
        LastLayoutSize      = [NaN, NaN]      % [RESPONSIVE] last measured figure size in px
        InResponsiveLayout  = false           % [RESPONSIVE] resize/layout re-entry guard
        PreferredVideoWidth = [NaN, NaN]      % [RESPONSIVE] video aspect preferred width in px
        ManualVideoWidth    = [NaN, NaN]      % [RESPONSIVE] splitter-requested video width in px
        ManualPanelWidths   = {struct(), struct()} % splitter-requested non-video panel widths
        PanelSplitterFIdx   = 0               % non-video splitter drag channel
        PanelSplitterKind   = ''              % att-map|map-info|info-plot
        IsDraggingPanelSplitter = false       % non-video splitter drag state
        LayoutHandles       = struct()        % [RESPONSIVE] shell/header/body layout handles
        NormalFigurePosition = [NaN, NaN, NaN, NaN] % [RESPONSIVE] restore target after app-level maximize
        FlightFilePath      = {'', ''}        % session config: loaded flight data paths
        InfoFormatModes     = {struct(), struct()} % per-channel value display modes keyed by normalized header
        ChannelViewMode     = 'both'          % both|flight1|flight2
        % [PHASE 0.8] Session/Studio integration prototype
        % - standalone: 단독 실행 시 'standalone'
        % - embedded:   Studio가 부모 컨테이너에 embed 시 'S001', 'S002' 등 SessionId 부여
        % 모든 SessionId-aware 코드(throttle, drag controller, EventBus)는 이 값을 참조
        ActiveSessionId     = 'standalone'    % [PHASE 0.8] active session id (Studio 통합 prep)
        IsEmbedded          = false           % [PHASE 0.8] standalone vs embedded mode

        % [PHASE 3a] 임베드 인터페이스 자리 표시
        % - standalone: RootContainer = UIFigure (생성자가 자동 설정)
        % - embedded:   RootContainer = Studio가 넘긴 부모 컨테이너 (uitab/uipanel)
        % createLayout 등 향후 Phase 3b에서 RootContainer를 layout parent로 사용
        RootContainer       = []              % [PHASE 3a] uifigure or parent container
        % - 기존 ErrorLog/ErrorLogCapacity 속성은 더 이상 사용하지 않으나 호환을 위해 유지하지 않고 제거
    end

    methods (Access = public)
        % ---------------------------------------------------------------------
        % Construction and initialization
        % ---------------------------------------------------------------------
        function app = FlightDataDashboard(parentContainer, sessionId)
            % [PHASE 3a/3b] Constructor accepts optional embedding parameters.
            %   FlightDataDashboard()                         -> standalone (legacy)
            %   FlightDataDashboard(parentContainer, sessionId) -> embedded
            %
            % Embedded mode reuses the host figure (e.g. Studio shell) so
            % WindowButton callbacks still work, and renders the dashboard
            % UI inside parentContainer (a uitab or uipanel).
            embeddedMode = (nargin >= 1) && ~isempty(parentContainer) && isvalid(parentContainer);
            if embeddedMode
                if nargin < 2 || isempty(sessionId)
                    error('FlightDataDashboard:MissingSessionId', ...
                        'Embedded mode requires sessionId as the 2nd argument.');
                end
                app.IsEmbedded      = true;
                app.ActiveSessionId = char(sessionId);
                app.RootContainer   = parentContainer;
            else
                app.IsEmbedded      = false;
                app.ActiveSessionId = 'standalone';
                % RootContainer is set later, right after uifigure creation.
            end

            app.Models = [app.createEmptyModel(), app.createEmptyModel()];
            app.SyncState = struct('IsSynced', false, 'SyncT1', 0, 'SyncT2', 0);
            app.VideoState = struct('videoReader', {[], []}, 'videoStartTime', {0, 0}, 'vidImageHandle', {[], []});
            % [V3.12] VideoSyncState 초기화: 두 비행경로별 동기화 정보
            app.VideoSyncState = struct( ...
                'IsSynced',     {false, false}, ...     % 동기 설정 완료 여부
                'AnchorFrame',  {0, 0}, ...             % 동기 기준 프레임 번호 (정수)
                'AnchorOffset', {0, 0}, ...             % [V3.23] sub-frame 보정 [-0.5, 0.5]
                'AnchorTime',   {0, 0}, ...             % 동기 기준 비행시간(초)
                'VideoFps',     {70, 70}, ...           % 영상 Hz (기본 70)
                'DataFps',      {50, 50}, ...           % 비행데이터 Hz (기본 50)
                'TotalFrames',  {0, 0}, ...             % 영상 총 프레임 수
                'CurrentFrame', {1, 1});                % 현재 프레임 위치

            % [REFACTOR Step 1] Create one FrameCacheModel per channel.
            app.CacheModel = [flightdash.model.FrameCacheModel(app.CacheBudgetMB), ...
                              flightdash.model.FrameCacheModel(app.CacheBudgetMB)];

            % [REFACTOR Step 2] Create one VideoModel/SyncModel per channel.
            app.VideoMdl = [flightdash.model.VideoModel(), flightdash.model.VideoModel()];
            app.SyncMdl  = [flightdash.model.SyncModel(),  flightdash.model.SyncModel()];
            app.PlaybackState = flightdash.model.PlaybackStateModel();
            app.PlaybackState(2) = flightdash.model.PlaybackStateModel();

            app.CoastlineData = [];
            app.FixedAreaBounds = [];

            % Strangler-pattern managers: keep app method names as wrappers while
            % moving ownership of cohesive responsibilities out of the app shell.
            app.ConfigMgr    = flightdash.model.ConfigManager();
            app.AuxWindowMgr = flightdash.view.AuxWindowManager(app);
            app.DataLoader   = flightdash.model.FlightDataLoader();
            app.LayoutMgr    = flightdash.view.ResponsiveLayoutManager();

            if isfile('option_flight_area.dat')
                try
                    areaData = readmatrix('option_flight_area.dat');
                    if size(areaData, 2) >= 2
                        app.FixedAreaBounds = struct('minLat', min(areaData(:,1)), 'maxLat', max(areaData(:,1)), ...
                                                     'minLon', min(areaData(:,2)), 'maxLon', max(areaData(:,2)));
                    end
                catch e
                    disp(['option_flight_area.dat load failed: ', e.message]);
                end
            end

            % [PHASE 3b] Standalone owns its own uifigure; embedded mode
            % reuses the host figure (Studio's UIFigure) so WindowButton
            % callbacks attach to a single figure shared by all sessions.
            if app.IsEmbedded
                % RootContainer was set in the constructor to the parent
                % uitab/uipanel. UIFigure climbs to the ancestor figure.
                app.UIFigure = ancestor(app.RootContainer, 'figure');
                app.NormalFigurePosition = app.UIFigure.Position;
            else
                close(findobj('Type', 'figure', 'Name', 'Flight Data Review Dashboard (Dual)'));
                % [FIX] AutoResizeChildren='on' 시 SizeChangedFcn이 무시되는 경고 차단
                % - uigridlayout이 자식 리사이즈를 담당하므로 AutoResizeChildren은 불필요
                initialPos = app.LayoutMgr.initialFigurePosition(app);
                app.UIFigure = uifigure('Name', 'Flight Data Review Dashboard (Dual)', ...
                                        'Units', 'pixels', ...
                                        'Position', app.LayoutMgr.initialFigurePosition(app), ...
                                        'Color', [0.94 0.94 0.96]);
                app.NormalFigurePosition = app.UIFigure.Position;
                % In standalone, the figure IS the layout root.
                app.RootContainer = app.UIFigure;
            end
            % AutoResizeChildren is a figure property; in embedded mode
            % the Studio shell already configured it, so leave it alone.
            if ~app.IsEmbedded
                try
                    app.UIFigure.AutoResizeChildren = 'off';
                catch ME
                    app.logCaught(ME, 'UI:AutoResizeChildren');
                end
            end
            % [PHASE 3a] Figure-level callbacks only in standalone mode.
            % In embedded mode the Studio shell owns the figure, so wiring
            % CloseRequestFcn here would override Studio's close handling
            % and SizeChangedFcn would fire for the whole Studio (not
            % just this dashboard tab). Phase 3b will register a
            % per-tab resize listener via the parent container instead.
            if ~app.IsEmbedded
                app.UIFigure.CloseRequestFcn = @app.UIFigureCloseRequest;
                app.UIFigure.SizeChangedFcn = @(~,~) app.onUIFigureResized();
            end

            % [REFACTOR Step 4] 컨트롤러 인스턴스 (createLayout 전 필수)
            app.FileCtrl      = flightdash.controller.FileController(app);
            app.VideoSyncCtrl = flightdash.controller.VideoSyncController(app);
            app.PlaybackCtrl  = flightdash.controller.PlaybackController(app);
            app.PlotCtrl      = flightdash.controller.PlotController(app);
            app.RoiCtrl       = flightdash.controller.RoiController(app);
            app.PannerCtrl    = flightdash.controller.PannerController(app);
            app.PanelCtrl     = flightdash.controller.PanelToggleController(app);
            app.DragCtrl      = flightdash.controller.DragController(app);
            app.MarkerDragCtrl = flightdash.controller.MarkerDragController(app);
            app.InfoCtrl      = flightdash.controller.InfoController(app);

            app.createLayout();
            app.PlotView = flightdash.view.PlotView(app, 1);
            app.PlotView(2) = flightdash.view.PlotView(app, 2);
            app.PannerView = flightdash.view.PannerView(app);

            for i = 1:2
                if app.hasPlotView(i), app.PlotView(i).addTab(); end
                app.VideoState(i).vidImageHandle = app.UI(i).vidImageHandle;
                % [REFACTOR Step 2-B] VideoModel에도 핸들 set
                app.VideoMdl(i).ImageHandle = app.UI(i).vidImageHandle;
                % [REFACTOR Step 2-C] 이벤트 구독: VideoLoaded → cache recompute, VideoCleared → invalidate
                app.VideoListeners{i} = { ...
                    addlistener(app.VideoMdl(i), 'VideoLoaded',  @(src,~) app.onVideoLoaded(i, src)), ...
                    addlistener(app.VideoMdl(i), 'VideoCleared', @(~,~)   app.onVideoCleared(i)) };
            end
            try
                app.LayoutMgr.applyLayout(app, 'startup');
            catch ME
                app.logCaught(ME, 'Layout:startup');
            end
        end

        function delete(app)
            % [FIX] 중복 진입 방어 - CloseRequestFcn → delete → 소멸 중 재호출 차단
            if app.IsDeleting, return; end
            app.IsDeleting = true;
            try
                if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                    app.PlaybackCtrl.stopAllFlightPlayback();
                end
            catch ME, app.logCaught(ME, 'FlightPlay:delete'); end
            % [V3.20 (5)] 명시적 리소스 정리: VideoReader, AsyncPool, futures
            try
                for fIdx = 1:2
                    try
                        if ~isempty(app.AsyncFutures{fIdx}) && isvalid(app.AsyncFutures{fIdx})
                            fut = app.AsyncFutures{fIdx};
                            cancel(fut);
                            try
                                wait(fut, 'finished', 0.5);
                            catch ME_wait
                                app.logCaught(ME_wait, 'Async:cancelWait:delete');
                            end
                            app.AsyncFutures{fIdx} = [];   % post-cancel 명시 클리어
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                    % VideoReader 정리 (worker가 같은 파일 잡고 있을 가능성 차단 후)
                    try
                        if ~isempty(app.VideoState(fIdx).videoReader) && ...
                           isvalid(app.VideoState(fIdx).videoReader)
                            delete(app.VideoState(fIdx).videoReader);
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                end
                % 캐시 비우기 (메모리 즉시 해제) - CacheModel 위임
                if ~isempty(app.CacheModel)
                    for fIdx = 1:numel(app.CacheModel)
                        try
                            if isvalid(app.CacheModel(fIdx))
                                app.CacheModel(fIdx).invalidate();
                            end
                        catch ME, app.logCaught(ME, 'silent'); end
                    end
                end
                app.AsyncGen = [0, 0];   % [V3.21 #1-A] generation reset
                app.LastDisplayedFrame = [0, 0];   % [PATCH] 조기반환 키 리셋
                % [REFACTOR Step 2-C] event listener 명시 해제
                for fIdx = 1:numel(app.VideoListeners)
                    try
                        L = app.VideoListeners{fIdx};
                        for k = 1:numel(L)
                            if isvalid(L{k}), delete(L{k}); end
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                end
                app.VideoListeners = {[], []};

                % [FIX] 순환 참조 차단 + EventBus listener 명시 해제
                % - delete(ctrl) 호출 → controller.delete() → Listeners cell 정리
                % - 단순 [] 대입은 listener leak 발생 → 다음 실행 시 좀비 controller crash
                try, delete(app.FileCtrl);      catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.VideoSyncCtrl); catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PlaybackCtrl);  catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PlotCtrl);      catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.RoiCtrl);       catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PannerCtrl);    catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PanelCtrl);     catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.DragCtrl);      catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.MarkerDragCtrl); catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.InfoCtrl);      catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PlotView);      catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PannerView);    catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.AuxWindowMgr);  catch ME, app.logCaught(ME, 'silent'); end
                app.FileCtrl      = [];
                app.VideoSyncCtrl = [];
                app.PlaybackCtrl  = [];
                app.PlotCtrl      = [];
                app.RoiCtrl       = [];
                app.PannerCtrl    = [];
                app.PanelCtrl     = [];
                app.DragCtrl      = [];
                app.MarkerDragCtrl = [];
                app.InfoCtrl      = [];
                app.ConfigMgr     = [];
                app.AuxWindowMgr  = [];
                app.PlotView      = [];
                app.PannerView    = [];
                app.DataLoader    = [];
                app.LayoutMgr     = [];
            catch ME, app.logCaught(ME, 'silent'); end

            % [PHASE 4 review] Process-global resources MUST NOT be torn
            % down when this dashboard is just an embedded session being
            % closed inside a still-running Studio. Other embedded
            % dashboards share MATLAB's parpool — calling delete() on
            % it would kill their async decode workers. Only the
            % standalone path or the final dashboard in a Studio (which
            % is impossible to detect here without coordination) should
            % perform the global cleanup. Studio is responsible for
            % running parpool teardown via FlightReviewStudioApp.delete
            % once the entire shell is closing.
            if ~app.IsEmbedded
                % [PATCH / V3.22 #6 / FIX] 워커 persistent VR 명시 해제 - 2s timeout으로 hang 차단
                try
                    if ~isempty(app.AsyncPool) && isvalid(app.AsyncPool)
                        fCleanup = parfevalOnAll(app.AsyncPool, @cleanupAsyncDecodeCache, 0);
                        cleanupOk = false;
                        try
                            wait(fCleanup, 'finished', 5);
                            cleanupOk = true;
                        catch ME
                            app.logCaught(ME, 'Async:cleanupWait');
                        end
                        if ~cleanupOk
                            % [FIX] timeout 시 pending future cancel
                            try, cancel(fCleanup); catch, end
                        end
                    end
                catch ME, app.logCaught(ME, 'silent'); end

                % [FIX] pool 명시 삭제 - 다음 실행에서 깨끗한 환경 보장
                try
                    if ~isempty(app.AsyncPool) && isvalid(app.AsyncPool)
                        delete(app.AsyncPool);
                    end
                    app.AsyncPool = [];
                catch ME, app.logCaught(ME, 'silent'); end
            else
                % Embedded session unload: drop only this dashboard's
                % handle to the pool. Do NOT delete the pool itself.
                app.AsyncPool = [];
            end

            try
                app.closeAllAuxFigures();
            catch ME, app.logCaught(ME, 'silent'); end

            % [PHASE 3a] Only the standalone path owns the uifigure.
            % In embedded mode (Phase 3b+) Studio owns it: deleting the
            % figure here would tear down the Studio shell. Studio is
            % responsible for closing or removing the parent uitab/uipanel.
            if ~app.IsEmbedded
                try
                    if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                        delete(app.UIFigure);
                    end
                catch ME, app.logCaught(ME, 'silent'); end
            end
        end

        function model = createEmptyModel(~)
            model = struct('rawData', table(), 'mappedCols', struct(), 'displayMeta', struct(), ...
                           'bounds', struct('minLat',0, 'maxLat',0, 'minLon',0, 'maxLon',0, 'isValid', false), ...
                           'altBounds', struct('minAlt',0, 'maxAlt',0), ...
                           'currentIndex', 1, 'selectedRow', 1, 'isMockData', false);
        end
    end

    % =========================================================================
    % =========================================================================
    methods (Access = public)
        function applyTimeChange(app, fIdx, index)
            if app.stateIsUpdating(fIdx), return; end
            if isempty(app.Models(fIdx).rawData), return; end

            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(index);
            app.Models(fIdx).currentIndex = index;

            % [FIX] IsUpdating 플래그를 onCleanup으로 보장 - 예외/return/error 모두 안전
            app.setStateUpdating(fIdx, true);
            cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
            try
                app.updateDashboard(fIdx, index);
                if abs(app.UI(fIdx).spinner.Value - currTime) > eps
                    app.UI(fIdx).spinner.Value = currTime;
                end
            catch e
                % [FIX] warning 대신 ErrorLog로 사후 추적 가능하게
                app.logCaught(e, 'applyTimeChange');
            end
            % cleanup_ 가 IsUpdating=false 보장 후 아래 진행
            clear cleanup_;

            if app.SyncState.IsSynced && fIdx == 1 && ~isempty(app.Models(2).rawData)
                targetT2 = app.SyncState.SyncT2 + (currTime - app.SyncState.SyncT1);

                timeCol2 = app.Models(2).mappedCols.Time;
                idx2 = app.findClosestIndexByTime(app.Models(2).rawData.(timeCol2), targetT2);

                if ~isequal(app.Models(2).currentIndex, idx2)
                    app.applyTimeChange(2, idx2);
                end
            end
        end

    end

    methods (Access = public)
        % [PATCH / REFACTOR Step 0] DebugMode 게이팅 catch 로깅 헬퍼 - util.ErrorLog 위임
        % - 모든 호출처는 그대로 동작 (호환성 100%)
        % [RESTORED] commit 4631c65 리팩토링 중 누락된 메서드. 136곳에서 호출되므로 필수.
        function logCaught(app, ME, tag)
            flightdash.util.ErrorLog.log(ME, tag, app.DebugMode);
        end

        % [V3.22 #1 / REFACTOR Step 0] 사후 조사용: 누적된 에러 로그 콘솔 출력
        % 사용 예: app.dumpErrorLog()         → 전체 출력
        %         app.dumpErrorLog(20)        → 최근 20건
        %         app.dumpErrorLog(20, 'Async') → 최근 20건 중 'Async' 포함 태그만
        function dumpErrorLog(app, n, filterTag) %#ok<INUSD>
            if nargin < 2, n = []; end
            if nargin < 3, filterTag = ''; end
            flightdash.util.ErrorLog.dump(n, filterTag);
        end

        function resetIsUpdating(app, fIdx)
            try
                if isvalid(app), app.setStateUpdating(fIdx, false); end
            catch
            end
        end

        function resetInCascade(app)
            try
                if isvalid(app), app.InCascade = false; end
            catch
            end
        end

        function tf = isActiveSession(app, eventData)
            % [PHASE 4 review] Two-layer session check:
            %   1) If the EventBus payload carries a non-empty SessionId,
            %      use it as the authoritative source — only the
            %      dashboard whose ActiveSessionId matches handles it.
            %   2) Otherwise fall back to the global SessionScope (active
            %      workspace tab). This keeps standalone single-instance
            %      runs and legacy publishers working without changes.
            try
                if nargin >= 2 && ~isempty(eventData) ...
                        && isprop(eventData, 'SessionId') ...
                        && ~isempty(eventData.SessionId)
                    appId = '';
                    if isprop(app, 'ActiveSessionId'), appId = char(app.ActiveSessionId); end
                    if isempty(appId) || strcmp(appId, 'standalone')
                        tf = true;
                        return;
                    end
                    tf = strcmp(char(eventData.SessionId), appId);
                    return;
                end
            catch
            end
            tf = flightdash.util.SessionScope.isOwner(app);
        end

        function tf = throttleHit(app, slotName, fIdx, limitS)
            % [PHASE 0.7] SessionId-prefixed throttle hit
            % - 모든 throttle key에 ActiveSessionId 접두 → 다중 세션 충돌 방지
            % - 기존 호출 시그니처 호환 (slotName/fIdx/limitS 동일)
            sessionId = app.ActiveSessionId;
            if isempty(sessionId), sessionId = 'standalone'; end
            scopedSlot = [sessionId ':' slotName];
            tf = flightdash.util.Throttle.instance().hit(scopedSlot, fIdx, limitS);
        end

        function throttleReset(app, slotName, fIdx)
            % [PHASE 0.7] SessionId-prefixed throttle reset
            sessionId = app.ActiveSessionId;
            if isempty(sessionId), sessionId = 'standalone'; end
            scopedSlot = [sessionId ':' slotName];
            if nargin < 3
                flightdash.util.Throttle.instance().reset(scopedSlot);
            else
                flightdash.util.Throttle.instance().reset(scopedSlot, fIdx);
            end
        end
        function tf = hasPlaybackState(app, fIdx)
            tf = false;
            try
                tf = ~isempty(app.PlaybackState) && numel(app.PlaybackState) >= fIdx && isvalid(app.PlaybackState(fIdx));
            catch
                tf = false;
            end
        end

        function tf = stateIsUpdating(app, fIdx)
            if app.hasPlaybackState(fIdx)
                tf = app.PlaybackState(fIdx).IsUpdating;
            else
                tf = app.IsUpdating(fIdx);
            end
        end

        function setStateUpdating(app, fIdx, value)
            if app.hasPlaybackState(fIdx)
                app.PlaybackState(fIdx).setUpdating(value);
            end
            app.IsUpdating(fIdx) = logical(value);
        end

        function tf = stateIsGoToFrame(app, fIdx)
            if app.hasPlaybackState(fIdx)
                tf = app.PlaybackState(fIdx).InGoToFrame;
            else
                tf = app.InGoToFrame(fIdx);
            end
        end

        function setStateGoToFrame(app, fIdx, value)
            if app.hasPlaybackState(fIdx)
                app.PlaybackState(fIdx).setGoToFrame(value);
            end
            app.InGoToFrame(fIdx) = logical(value);
        end

        function tf = anyStateGoToFrame(app)
            tf = false;
            try
                if ~isempty(app.PlaybackState)
                    for sIdx = 1:numel(app.PlaybackState)
                        if isvalid(app.PlaybackState(sIdx)) && app.PlaybackState(sIdx).InGoToFrame
                            tf = true;
                            return;
                        end
                    end
                else
                    tf = any(app.InGoToFrame);
                end
            catch
                tf = any(app.InGoToFrame);
            end
        end

        function tf = stateIsDecoding(app, fIdx)
            if app.hasPlaybackState(fIdx)
                tf = app.PlaybackState(fIdx).IsDecoding;
            else
                tf = app.IsDecoding(fIdx);
            end
        end

        function setStateDecoding(app, fIdx, value)
            if app.hasPlaybackState(fIdx)
                app.PlaybackState(fIdx).setDecoding(value);
            end
            app.IsDecoding(fIdx) = logical(value);
        end

        function setStatePendingFrame(app, fIdx, frameNo, mode)
            if nargin < 4 || isempty(mode)
                mode = '';
            end
            if app.hasPlaybackState(fIdx)
                app.PlaybackState(fIdx).setPendingRequest(frameNo, mode);
            end
            app.PendingFrame(fIdx) = frameNo;
            app.PendingMode{fIdx} = char(mode);
        end

        function [hasPending, frameNo, mode] = peekStatePendingFrame(app, fIdx)
            if app.hasPlaybackState(fIdx)
                [hasPending, frameNo, mode] = app.PlaybackState(fIdx).peekPendingRequest();
            else
                hasPending = ~isnan(app.PendingFrame(fIdx));
                frameNo = app.PendingFrame(fIdx);
                mode = app.PendingMode{fIdx};
            end
        end

        function [hasPending, frameNo, mode] = consumeStatePendingFrame(app, fIdx)
            if app.hasPlaybackState(fIdx)
                [hasPending, frameNo, mode] = app.PlaybackState(fIdx).consumePendingRequest();
            else
                hasPending = ~isnan(app.PendingFrame(fIdx));
                frameNo = app.PendingFrame(fIdx);
                mode = app.PendingMode{fIdx};
            end
            app.PendingFrame(fIdx) = NaN;
            app.PendingMode{fIdx} = '';
        end
    end

    % =========================================================================
    % Controller/EventBus 진입점 및 메인 UI 로직
    % =========================================================================
    methods (Access = public)
        function handleFlightFile(app, fIdx)
            % [PHASE 3c] Cross-instance reentry guard.
            % In multi-session Studio embeds the EventBus broadcast still
            % reaches every dashboard's FileController if HeaderBar
            % wasn't refreshed (cached old version). Without a guard the
            % file dialog opens once per dashboard. We use setappdata on
            % the root graphics object so the flag is shared across all
            % dashboard instances regardless of class caching.
            if getappdata(0, 'FlightDashFileDialogActive')
                return;
            end
            setappdata(0, 'FlightDashFileDialogActive', true);
            cleanup_ = onCleanup(@() setappdata(0, 'FlightDashFileDialogActive', false)); %#ok<NASGU>

            [filename, pathname] = uigetfile({'*.dat;*.csv;*.txt', 'Flight data (*.dat, *.csv, *.txt)'}, ...
                sprintf('Select Flight %d Data File', fIdx));
            if isequal(filename, 0), return; end

            if app.VideoSyncState(fIdx).IsSynced
                sel = uiconfirm(app.UIFigure, ...
                    'New flight data will reset existing video sync. Continue?', ...
                    'Confirm Sync Reset', ...
                    'Options', {'Continue', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(sel, 'Cancel'), return; end
                app.resetVideoSync(fIdx);
            end

            d = uiprogressdlg(app.UIFigure, 'Title', 'Loading Data', ...
                'Message', sprintf('Parsing flight %d data...', fIdx), ...
                'Indeterminate', 'on');
            try
                fullpath = fullfile(pathname, filename);
                app.parseFlightData(fIdx, fullpath);
                app.FlightFilePath{fIdx} = fullpath;

                timeCol = app.Models(fIdx).mappedCols.Time;
                if ~issorted(app.Models(fIdx).rawData.(timeCol), 'strictascend')
                    errordlg('Time column is not strictly ascending or has duplicates.', 'Data Error');
                    close(d);
                    return;
                end

                if ~isempty(app.VideoState(fIdx).videoReader)
                    app.VideoState(fIdx).videoStartTime = app.Models(fIdx).rawData.(timeCol)(1);
                end

                % [V3.12] 비행데이터 Hz 자동 계산 후 입력란 갱신
                try
                    times = app.Models(fIdx).rawData.(timeCol);
                    if length(times) > 1
                        dt = mean(diff(times(1:min(100, end))));
                        if dt > 0
                            estFps = round(1 / dt);
                            if estFps >= 1 && estFps <= 1000
                                app.VideoSyncState(fIdx).DataFps = estFps;
                                if isfield(app.UI(fIdx), 'vidDataFpsInput') && isvalid(app.UI(fIdx).vidDataFpsInput)
                                    app.UI(fIdx).vidDataFpsInput.Value = estFps;
                                end
                            end
                        end
                    end
                catch ME_silent, app.logCaught(ME_silent, 'silent'); end
                app.setupDataUI(fIdx);

                %              FPS 재계산만 수행하여 라벨/시간 표시는 정상 갱신
                if app.VideoSyncState(fIdx).TotalFrames > 0
                    times = app.Models(fIdx).rawData.(timeCol);
                    timeSpan = times(end) - times(1);
                    if timeSpan > 0 && app.VideoSyncState(fIdx).TotalFrames > 1
                        newFps = (app.VideoSyncState(fIdx).TotalFrames - 1) / timeSpan;
                        app.VideoSyncState(fIdx).VideoFps = newFps;

                        if isfield(app.UI(fIdx), 'vidVideoFpsInput') && any(isvalid(app.UI(fIdx).vidVideoFpsInput))
                            app.UI(fIdx).vidVideoFpsInput.Value = round(newFps);
                        end

                        app.updateVdubFrameLabel(fIdx, app.VideoSyncState(fIdx).CurrentFrame);
                    end
                end

                app.UI(fIdx).fileNameLabel.Text = filename;
                close(d);
            catch e
                try
                    if ~isempty(d) && isvalid(d), close(d); end
                catch ME, app.logCaught(ME, 'silent'); end
                % [V3.20 (3)] 상세 에러 로그
                if app.DebugMode
                    fprintf('[Flight] parse failed: %s\n  %s\n  stack: %s\n', ...
                        filename, e.message, e.identifier);
                end
                errordlg(['Error: ', e.message], 'Error');
            end
        end

        function handleCoastFile(app)
            if getappdata(0, 'FlightDashFileDialogActive'), return; end
            setappdata(0, 'FlightDashFileDialogActive', true);
            cleanup_ = onCleanup(@() setappdata(0, 'FlightDashFileDialogActive', false)); %#ok<NASGU>

            [filename, pathname] = uigetfile('*.csv', 'Select Coastline File');
            if isequal(filename, 0), return; end
            try
                fullpath = fullfile(pathname, filename);
                rawData = readmatrix(fullpath);
                app.CoastlineData = rawData(~any(isnan(rawData(:, 1:2)), 2), 1:2);

                hasRealData = (~isempty(app.Models(1).rawData) && ~app.Models(1).isMockData) || ...
                              (~isempty(app.Models(2).rawData) && ~app.Models(2).isMockData);

                for i = 1:2
                    if ~hasRealData && (isempty(app.Models(i).rawData) || app.Models(i).isMockData)
                        app.Models(i).rawData = table();
                        app.calculateBounds(i);
                        app.generateMockFlightData(i);
                    else
                        app.calculateBounds(i);
                        app.initPlots(i);
                        app.updateDashboard(i, app.Models(i).currentIndex);
                    end
                end
            catch e
                errordlg(['Error: ', e.message], 'Error');
            end
        end

        function handleSpinnerChange(app, fIdx, newTime)
            if isempty(app.Models(fIdx).rawData), return; end
            if app.stateIsUpdating(fIdx), return; end

            timeCol = app.Models(fIdx).mappedCols.Time;
            idx = app.findClosestIndexByTime(app.Models(fIdx).rawData.(timeCol), newTime);

            if isequal(app.Models(fIdx).currentIndex, idx), return; end

            app.applyTimeChange(fIdx, idx);
        end

        function startFlightPlayback(app, fIdx)
            if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                app.PlaybackCtrl.startFlightPlayback(fIdx);
            end
        end

        function stopFlightPlayback(app, fIdx)
            if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                app.PlaybackCtrl.stopFlightPlayback(fIdx);
            end
        end

        function setFlightPlayInterval(app, fIdx, value)
            if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                app.PlaybackCtrl.setFlightPlayInterval(fIdx, value);
            end
        end

        function setInfoFormatMode(app, fIdx, mode)
            try
                if isempty(app.Models(fIdx).displayMeta), return; end
                row = app.Models(fIdx).selectedRow;
                if isempty(row) || row < 1 || row > numel(app.Models(fIdx).displayMeta), return; end
                key = app.infoFormatKey(app.Models(fIdx).displayMeta(row).header);
                modes = app.infoFormatStruct(fIdx);
                modes.(key) = char(mode);
                app.InfoFormatModes{fIdx} = modes;
                app.updateCurrentInfoTable(fIdx, app.Models(fIdx).currentIndex);
            catch ME
                app.logCaught(ME, 'InfoFormat:set');
            end
        end


        function UIFigureCloseRequest(app, ~, ~)
            % [PHASE 0] Defensive close: capture UIFigure handle first so we
            % can guarantee figure deletion even if subsequent steps throw.
            figHandle = [];
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    figHandle = app.UIFigure;
                    app.UIFigure.WindowButtonMotionFcn = '';
                    app.UIFigure.WindowButtonUpFcn = '';
                end
                app.IsDraggingSplitter = false;
                app.IsDraggingPanelSplitter = false;
                app.IsDraggingPanner   = false;
                if ~isempty(app.InfoCtrl) && isvalid(app.InfoCtrl)
                    app.InfoCtrl.clearState();
                end
                if ~isempty(app.MarkerDragCtrl) && isvalid(app.MarkerDragCtrl)
                    app.MarkerDragCtrl.clearDraggedMarker();
                end
            catch ME_silent
                try, app.logCaught(ME_silent, 'silent'); catch, end
            end
            try
                app.autoSaveConfigOnClose();
            catch ME_cfg
                try, app.logCaught(ME_cfg, 'Config:autoSaveOnClose'); catch, end
            end
            try
                delete(app);
            catch ME
                try, app.logCaught(ME, 'CloseRequest:delete'); catch, end
            end
            % [PHASE 0] Final guarantee: figure MUST be removed regardless of
            % what failed above. MATLAB Online keeps the window open if the
            % CloseRequestFcn returns without deleting the figure.
            try
                if ~isempty(figHandle) && isvalid(figHandle)
                    delete(figHandle);
                end
            catch
            end
        end

        function togglePanel(app, fIdx, pnlName)
            % 패널 표시/숨김 토글. 실제 폭 배분은 responsive layout manager가 담당한다.
            state = app.UI(fIdx).PanelVisible.(pnlName);
            newState = ~state;
            app.UI(fIdx).PanelVisible.(pnlName) = newState;

            if strcmp(pnlName, 'attitude')
                app.UI(fIdx).panelAttitude.Visible = newState;
                if newState
                    app.UI(fIdx).btnAtt.Text = 'Attitude OFF';
                else
                    app.UI(fIdx).btnAtt.Text = 'Attitude ON';
                end
            elseif strcmp(pnlName, 'map')
                app.UI(fIdx).panelMapAlt.Visible = newState;
                if newState
                    app.UI(fIdx).btnMap.Text = 'Map/Alt OFF';
                else
                    app.UI(fIdx).btnMap.Text = 'Map/Alt ON';
                end
            elseif strcmp(pnlName, 'video')
                if newState
                    app.resetVideoWidthPreferences(fIdx);
                end
                app.UI(fIdx).panelVideo.Visible = newState;
                if newState
                    app.UI(fIdx).btnVid.Text = 'Video OFF';
                else
                    app.UI(fIdx).btnVid.Text = 'Video ON';
                end
            end
            app.LayoutMgr.applyLayout(app, 'togglePanel');
        end

        function setChannelViewMode(app, mode)
            try
                mode = lower(char(mode));
                if ~ismember(mode, {'both', 'flight1', 'flight2'})
                    mode = 'both';
                end
                app.ChannelViewMode = mode;
                app.LayoutMgr.applyLayout(app, 'channelView');
                try
                    h = app.LayoutHandles.header;
                    if isfield(h, 'ChannelViewDropDown') && isvalid(h.ChannelViewDropDown)
                        h.ChannelViewDropDown.Value = mode;
                    end
                catch
                end
            catch ME
                app.logCaught(ME, 'Layout:channelView');
            end
        end

        % ---------------------------------------------------------------------
        % ---------------------------------------------------------------------
        function toggleSync(app)
            if app.SyncState.IsSynced
                app.SyncState.IsSynced = false;
                app.SyncBtn.Text = 'Sync Flight Time';
                app.SyncBtn.BackgroundColor = [0.58 0.0 0.83];
                app.SyncInput.Enable = 'on';
                if ~isempty(app.Models(2).rawData)
                    app.UI(2).spinner.Enable = 'on';
                end
                return;
            end

            inputStr = app.SyncInput.Value;
            tokens = regexp(inputStr, '^\s*(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)\s*$', 'tokens');
            if isempty(tokens)
                errordlg('Invalid input format. e.g. "23.4, 34.4"', 'Format Error');
                return;
            end
            if isempty(app.Models(1).rawData) || isempty(app.Models(2).rawData)
                errordlg('Both flight paths must be loaded first.', 'Data Missing');
                return;
            end

            t1 = str2double(tokens{1}{1});
            t2 = str2double(tokens{1}{2});
            app.SyncState.SyncT1 = t1;
            app.SyncState.SyncT2 = t2;
            app.SyncState.IsSynced = true;

            app.SyncBtn.Text = 'Reset Flight Time Sync';
            app.SyncBtn.BackgroundColor = [0.8 0.2 0.2];
            app.SyncInput.Enable = 'off';
            app.UI(2).spinner.Enable = 'off';

            timeCol1 = app.Models(1).mappedCols.Time;
            idx1 = app.findClosestIndexByTime(app.Models(1).rawData.(timeCol1), t1);
            app.applyTimeChange(1, idx1);

            % [V3.20 (2)] 동기화 디버그 로그 (SyncState - 두 비행데이터 시간축 매핑)
            if app.DebugMode
                fprintf('[FlightSync] enabled: T1=%.3fs ->T2=%.3fs (offset=%.3fs)\n', ...
                    t1, t2, t2 - t1);
            end
        end

        % Video load flow: confirm replacement, clear stale async/cache state,
        % create one VideoReader, update metadata/UI once, then load frame 1.
        function loadAviFile(app, fIdx)
            if getappdata(0, 'FlightDashFileDialogActive'), return; end
            setappdata(0, 'FlightDashFileDialogActive', true);
            cleanup_ = onCleanup(@() setappdata(0, 'FlightDashFileDialogActive', false)); %#ok<NASGU>

            [fname, pname] = uigetfile({'*.avi;*.mp4;*.mkv', 'Video Files (*.avi, *.mp4)'}, sprintf('Select Video %d', fIdx));
            if isequal(fname, 0), return; end
            fullPath = fullfile(pname, fname);

            vr = app.createVideoReader(fullPath, fname);
            if isempty(vr), return; end

            % Confirm before replacing an existing video/sync setup.
            if ~app.confirmVideoReplace(fIdx)
                app.deleteDetachedVideoReader(vr);
                return;
            end

            app.invalidateFrameCache(fIdx);
            startTime = app.computeStartTimeFromFlightData(fIdx);
            app.cleanupVideoResources(fIdx);

            if ~app.attachVideoReader(fIdx, vr, fullPath, fname)
                app.deleteDetachedVideoReader(vr);
                return;
            end
            app.VideoState(fIdx).videoStartTime = startTime;
            app.VideoState(fIdx).videoReader.CurrentTime = 0;
            app.throttleReset('LastVideoUpdate', fIdx);
            app.applyVideoLoadedUI(fIdx, vr);
            if app.VideoSyncState(fIdx).TotalFrames < 1
                app.cleanupVideoResources(fIdx);
                return;
            end
            app.loadFirstFrame(fIdx);
        end

        % --------- loadAviFile helpers ---------

        function ok = confirmVideoReplace(app, fIdx)
            ok = true;
            if app.VideoSyncState(fIdx).IsSynced
                sel = uiconfirm(app.UIFigure, ...
                    'Loading new video will reset existing video-flight sync. Continue?', ...
                    'Confirm Sync Reset', ...
                    'Options', {'Continue', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(sel, 'Cancel'), ok = false; return; end
                app.resetVideoSync(fIdx);
            end
        end

        % [V3.22 #3-2 / REFACTOR Step 1] 프레임 캐시 비우기 - CacheModel로 위임
        function exportConfigInteractive(app)
            app.ConfigMgr.exportConfigInteractive(app);
        end

        function importConfigInteractive(app)
            app.ConfigMgr.importConfigInteractive(app);
        end

        function autoSaveConfigOnClose(app)
            if app.IsDeleting, return; end
            app.ConfigMgr.autoSaveConfigOnClose(app);
        end

        function filePath = saveSessionConfig(app, saveMode, showErrors)
            if nargin < 2 || isempty(saveMode), saveMode = 'manual'; end
            if nargin < 3, showErrors = false; end
            filePath = app.ConfigMgr.saveSessionConfig(app, saveMode, showErrors);
        end

        function importSessionConfig(app, configPath)
            app.ConfigMgr.importSessionConfig(app, configPath);
        end

        function ok = loadFlightDataFromPath(app, fIdx, fullpath, quiet)
            if nargin < 4, quiet = false; end
            ok = false;
            try
                if ~isfile(fullpath)
                    error('flightdash:Config:MissingFlightFile', 'Flight data file does not exist: %s', fullpath);
                end
                if app.VideoSyncState(fIdx).IsSynced
                    app.resetVideoSync(fIdx);
                end

                app.parseFlightData(fIdx, fullpath);
                app.FlightFilePath{fIdx} = fullpath;

                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if ~issorted(times, 'strictascend')
                    error('flightdash:Config:TimeNotSorted', ...
                        'Time data must be strictly increasing: %s', fullpath);
                end

                app.updateDataFpsFromLoadedData(fIdx, times);
                if ~isempty(app.VideoState(fIdx).videoReader)
                    app.VideoState(fIdx).videoStartTime = times(1);
                end
                app.setupDataUI(fIdx);
                app.recomputeVideoFpsFromLoadedData(fIdx, times);

                [~, fname, ext] = fileparts(fullpath);
                app.UI(fIdx).fileNameLabel.Text = [fname ext];
                ok = true;
            catch ME
                app.logCaught(ME, 'Config:loadFlightData');
                if ~quiet
                    app.notifyUser('Flight Data Load Failed', ME.message, true);
                end
            end
        end

        function ok = loadAviFromPathForConfig(app, fIdx, fullPath)
            ok = false;
            try
                if ~isfile(fullPath)
                    error('flightdash:Config:MissingVideoFile', 'Video file does not exist: %s', fullPath);
                end
                if app.VideoSyncState(fIdx).IsSynced
                    app.resetVideoSync(fIdx);
                end
                app.invalidateFrameCache(fIdx);
                startTime = app.computeStartTimeFromFlightData(fIdx);
                app.cleanupVideoResources(fIdx);

                [~, fname, ext] = fileparts(fullPath);
                vr = app.openVideoReader(fIdx, fullPath, [fname ext]);
                if isempty(vr), return; end
                app.VideoState(fIdx).videoStartTime = startTime;
                app.VideoState(fIdx).videoReader.CurrentTime = 0;
                app.throttleReset('LastVideoUpdate', fIdx);
                app.applyVideoLoadedUI(fIdx, vr);
                if app.VideoSyncState(fIdx).TotalFrames < 1
                    app.cleanupVideoResources(fIdx);
                    return;
                end
                app.loadFirstFrame(fIdx);
                ok = true;
            catch ME
                app.logCaught(ME, 'Config:loadVideo');
            end
        end

        function cfg = collectSessionConfig(app, saveMode, filePath)
            if nargin < 2 || isempty(saveMode), saveMode = 'manual'; end
            if nargin < 3, filePath = ''; end
            cfg = app.ConfigMgr.collectSessionConfig(app, saveMode, filePath);
        end

        function sess = exportSessionSnapshot(app, baseSession)
            % Lightweight Studio save snapshot. Linked files stay external.
            if nargin >= 2 && isa(baseSession, 'flightdash.project.SessionModel')
                sess = baseSession;
            else
                sess = flightdash.project.SessionModel(app.snapshotDisplayName());
            end
            try
                if ~isempty(app.ActiveSessionId)
                    sess.SessionId = char(app.ActiveSessionId);
                end
                if isempty(sess.DisplayName)
                    sess.DisplayName = app.snapshotDisplayName();
                end
                sess.FlightFilePath = app.pathPair(app.FlightFilePath);
                sess.VideoFilePath = app.pathPair(app.VideoFilePath);
                sess.CurrentIndex = [app.safeCurrentIndex(1), app.safeCurrentIndex(2)];
                sess.CurrentFrame = [app.safeCurrentFrame(1), app.safeCurrentFrame(2)];
                sess.FlightSyncState = app.SyncState;
                sess.VideoSyncState = app.VideoSyncState;

                plotTabs = struct();
                roiRows = {cell(0, 5), cell(0, 5)};
                panelVisible = struct();
                for ch = 1:2
                    cfg = app.collectChannelConfig(ch);
                    plotTabs.(sprintf('Channel%d', ch)) = cfg.Tabs;
                    roiRows{ch} = cfg.RoiRows;
                    panelVisible.(sprintf('Channel%d', ch)) = cfg.PanelVisible;
                end
                sess.PlotTabs = plotTabs;
                sess.RoiRows = roiRows;
                sess.PanelVisible = panelVisible;
                sess.LayoutState = app.exportLayoutState();
                sess.ModifiedAt = flightdash.project.ProjectModel.nowIso();
            catch ME
                try, app.logCaught(ME, 'Studio:exportSessionSnapshot'); catch, end
            end
        end

        function applySessionSnapshot(app, sess)
            % Restore linked metadata into a fresh embedded dashboard.
            if ~isa(sess, 'flightdash.project.SessionModel'), return; end
            try
                if ~isempty(sess.SessionId)
                    app.ActiveSessionId = char(sess.SessionId);
                end
                app.FlightFilePath = app.pathPair(sess.FlightFilePath);
                app.VideoFilePath = app.pathPair(sess.VideoFilePath);
                if isstruct(sess.FlightSyncState)
                    app.SyncState = sess.FlightSyncState;
                end
                if isstruct(sess.VideoSyncState) && numel(sess.VideoSyncState) >= 1
                    for ch = 1:min(2, numel(sess.VideoSyncState))
                        app.VideoSyncState(ch) = app.mergeStructFields(app.VideoSyncState(ch), sess.VideoSyncState(ch));
                    end
                end
                for ch = 1:2
                    try, app.Models(ch).currentIndex = max(1, round(sess.CurrentIndex(ch))); catch, end
                    try, app.VideoSyncState(ch).CurrentFrame = max(0, round(sess.CurrentFrame(ch))); catch, end
                    try
                        pv = app.panelVisibleForChannel(sess.PanelVisible, ch);
                        if ~isempty(fieldnames(pv)) && isfield(app.UI(ch), 'PanelVisible')
                            app.UI(ch).PanelVisible = app.mergeStructFields(app.UI(ch).PanelVisible, pv);
                        end
                    catch
                    end
                end
                app.applyLayoutState(sess.LayoutState);
                app.refreshLayout('sessionSnapshot');
            catch ME
                try, app.logCaught(ME, 'Studio:applySessionSnapshot'); catch, end
            end
        end

        function ch = collectChannelConfig(app, fIdx)
            ch = app.emptyChannelConfig();
            ch.Channel = fIdx;
            ch.FlightDataPath = app.cellChar(app.FlightFilePath, fIdx);
            ch.VideoPath = app.cellChar(app.VideoFilePath, fIdx);
            ch.CurrentIndex = app.safeCurrentIndex(fIdx);
            ch.CurrentTime = app.safeCurrentTime(fIdx);
            ch.MappedCols = app.Models(fIdx).mappedCols;
            ch.DisplayMeta = app.Models(fIdx).displayMeta;
            ch.InfoFormatModes = app.infoFormatStruct(fIdx);
            ch.OptionFile = sprintf('option%d.dat', fIdx);
            ch.OptionText = app.optionTextForChannel(fIdx);
            ch.VideoSyncState = app.VideoSyncState(fIdx);
            ch.PanelVisible = app.safePanelVisible(fIdx);
            ch.Tabs = app.collectPlotTabsConfig(fIdx);
            ch.RoiRows = app.safeRoiRows(fIdx);
        end

        function ch = emptyChannelConfig(~)
            ch = struct('Channel', 0, 'FlightDataPath', '', 'VideoPath', '', ...
                'CurrentIndex', 1, 'CurrentTime', 0, 'MappedCols', struct(), ...
                'DisplayMeta', {struct([])}, 'InfoFormatModes', struct(), 'OptionFile', '', 'OptionText', '', ...
                'VideoSyncState', struct(), 'PanelVisible', struct(), ...
                'Tabs', {struct([])}, 'RoiRows', {cell(0, 0)});
        end

        function tabs = collectPlotTabsConfig(app, fIdx)
            tabs = struct('Title', {}, 'Selected', {}, 'Plots', {});
            try
                if fIdx > numel(app.UI) || ~isfield(app.UI(fIdx), 'plotTabs'), return; end
                selectedTab = [];
                try, selectedTab = app.UI(fIdx).tabGroup.SelectedTab; catch, end
                for tabIdx = 1:numel(app.UI(fIdx).plotTabs)
                    tabObj = app.UI(fIdx).plotTabs(tabIdx);
                    if isempty(tabObj) || ~isvalid(tabObj), continue; end
                    plots = struct('Name', {}, 'YColumn', {}, 'YLabel', {}, ...
                        'Unit', {}, 'Format', {}, 'Visible', {}, 'Legend', {}, ...
                        'XLimMode', {}, 'YLimMode', {}, 'XLim', {}, 'YLim', {});
                    if tabIdx <= numel(app.UI(fIdx).plotMeta)
                        metaList = app.UI(fIdx).plotMeta{tabIdx};
                        for pIdx = 1:numel(metaList)
                            info = metaList{pIdx};
                            xLim = app.structNumber(info, 'XLim', []);
                            yLim = app.structNumber(info, 'YLim', []);
                            try
                                if pIdx <= numel(app.UI(fIdx).plotAxes{tabIdx})
                                    ax = app.UI(fIdx).plotAxes{tabIdx}{pIdx};
                                    if ~isempty(ax) && isvalid(ax)
                                        xLim = ax.XLim;
                                        yLim = ax.YLim;
                                    end
                                end
                            catch
                            end
                            plots(end+1) = struct( ... %#ok<AGROW>
                                'Name', app.structChar(info, 'Name', ''), ...
                                'YColumn', app.structChar(info, 'YColumn', ''), ...
                                'YLabel', app.structChar(info, 'YLabel', ''), ...
                                'Unit', app.structChar(info, 'Unit', ''), ...
                                'Format', app.structChar(info, 'Format', ''), ...
                                'Visible', app.structLogical(info, 'Visible', true), ...
                                'Legend', app.structLogical(info, 'Legend', false), ...
                                'XLimMode', app.structChar(info, 'XLimMode', 'auto'), ...
                                'YLimMode', app.structChar(info, 'YLimMode', 'auto'), ...
                                'XLim', app.finiteVectorOrEmpty(xLim), ...
                                'YLim', app.finiteVectorOrEmpty(yLim));
                        end
                    end
                    tabs(end+1) = struct('Title', char(tabObj.Title), ... %#ok<AGROW>
                        'Selected', isequal(tabObj, selectedTab), 'Plots', {plots});
                end
            catch ME
                app.logCaught(ME, 'Config:collectTabs');
            end
        end

        function writeSessionConfigMarkdown(app, cfg, filePath)
            app.ConfigMgr.writeSessionConfigMarkdown(cfg, filePath);
        end

        function cfg = readSessionConfigMarkdown(app, filePath)
            cfg = app.ConfigMgr.readSessionConfigMarkdown(filePath);
        end

        function restorePlotsFromConfig(app, fIdx, ch)
            if ~isfield(ch, 'Tabs') || isempty(ch.Tabs), return; end
            try
                if app.hasPlotView(fIdx), app.PlotView(fIdx).clearAllTabs(); end
                tabs = ch.Tabs;
                for tabIdx = 1:numel(tabs)
                    if tabIdx > 1
                        if app.hasPlotView(fIdx), app.PlotView(fIdx).addTab(); end
                    end
                    if tabIdx <= numel(app.UI(fIdx).plotTabs)
                        tabObj = app.UI(fIdx).plotTabs(tabIdx);
                        if isfield(tabs(tabIdx), 'Title') && ~isempty(tabs(tabIdx).Title)
                            tabObj.Title = char(tabs(tabIdx).Title);
                        end
                        app.UI(fIdx).tabGroup.SelectedTab = tabObj;
                    end
                    if isfield(tabs(tabIdx), 'Plots')
                        app.restorePlotsForCurrentTab(fIdx, tabs(tabIdx).Plots);
                    end
                    if isfield(tabs(tabIdx), 'Selected') && ~isempty(tabs(tabIdx).Selected) && logical(tabs(tabIdx).Selected)
                        app.UI(fIdx).tabGroup.SelectedTab = app.UI(fIdx).plotTabs(tabIdx);
                    end
                end
                app.refreshPlotManager(fIdx);
                app.refreshPlotDetails(fIdx);
                app.PannerView.refresh(fIdx);
            catch ME
                app.logCaught(ME, 'Config:restorePlots');
            end
        end

        function restorePlotsForCurrentTab(app, fIdx, plots)
            if isempty(plots), return; end
            for pIdx = 1:numel(plots)
                yColumn = app.structChar(plots(pIdx), 'YColumn', '');
                if isempty(yColumn), continue; end
                row = app.findDisplayMetaRow(fIdx, yColumn);
                if isempty(row), continue; end
                app.Models(fIdx).selectedRow = row;
                if app.hasPlotView(fIdx), app.PlotView(fIdx).addSelectedVariable(); end
                tabIdx = app.currentPlotTabIndex(fIdx);
                if isempty(tabIdx), continue; end
                plotIdx = numel(app.UI(fIdx).plotMeta{tabIdx});
                app.applyRestoredPlotProperties(fIdx, tabIdx, plotIdx, plots(pIdx));
            end
        end

        function applyRestoredPlotProperties(app, fIdx, tabIdx, plotIdx, plotCfg)
            try
                if plotIdx < 1 || plotIdx > numel(app.UI(fIdx).plotMeta{tabIdx}), return; end
                info = app.UI(fIdx).plotMeta{tabIdx}{plotIdx};
                info.Name = app.structChar(plotCfg, 'Name', info.Name);
                info.YLabel = app.structChar(plotCfg, 'YLabel', info.YLabel);
                info.Unit = app.structChar(plotCfg, 'Unit', info.Unit);
                info.Format = app.structChar(plotCfg, 'Format', info.Format);
                info.Visible = app.structLogical(plotCfg, 'Visible', info.Visible);
                info.Legend = app.structLogical(plotCfg, 'Legend', info.Legend);
                info.XLimMode = app.normalizeAxisMode(app.structChar(plotCfg, 'XLimMode', app.structChar(info, 'XLimMode', 'auto')));
                info.YLimMode = app.normalizeAxisMode(app.structChar(plotCfg, 'YLimMode', app.structChar(info, 'YLimMode', 'auto')));
                info.XLim = app.sanitizeAxisLim(app.structNumber(plotCfg, 'XLim', app.structNumber(info, 'XLim', [])));
                info.YLim = app.sanitizeAxisLim(app.structNumber(plotCfg, 'YLim', app.structNumber(info, 'YLim', [])));

                ax = app.UI(fIdx).plotAxes{tabIdx}{plotIdx};
                if ~isempty(ax) && isvalid(ax)
                    title(ax, info.Name, 'Interpreter', 'none', 'FontWeight', 'bold');
                    ylabel(ax, info.YLabel, 'FontWeight', 'bold', 'FontSize', 10, 'Interpreter', 'none');
                    if info.Legend
                        app.applyMainLineLegend(ax, info);
                    else
                        legend(ax, 'off');
                    end
                    app.applyPlotAxisSettings(ax, info);
                end
                if isfield(info, 'MainLine') && ~isempty(info.MainLine) && isvalid(info.MainLine)
                    info.MainLine.DisplayName = info.Name;
                end
                vis = app.LayoutMgr.visibleState(info.Visible);
                handles = {app.UI(fIdx).plotAxes{tabIdx}{plotIdx}, ...
                    app.UI(fIdx).timeLines{tabIdx}{plotIdx}, app.UI(fIdx).timeMarkers{tabIdx}{plotIdx}};
                if isfield(app.UI(fIdx), 'plotValueLabels') && plotIdx <= numel(app.UI(fIdx).plotValueLabels{tabIdx})
                    handles{end+1} = app.UI(fIdx).plotValueLabels{tabIdx}{plotIdx};
                end
                for hIdx = 1:numel(handles)
                    try
                        if ~isempty(handles{hIdx}) && isvalid(handles{hIdx}), handles{hIdx}.Visible = vis; end
                    catch
                    end
                end
                if isfield(info, 'Panel') && ~isempty(info.Panel) && isvalid(info.Panel)
                    info.Panel.Visible = vis;
                end
                app.UI(fIdx).plotMeta{tabIdx}{plotIdx} = info;
            catch ME
                app.logCaught(ME, 'Config:plotProperties');
            end
        end

        function restoreCurrentIndexFromConfig(app, fIdx, ch)
            try
                if isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isfield(ch, 'CurrentTime') && ~isempty(ch.CurrentTime) && isfinite(ch.CurrentTime)
                    idx = app.findClosestIndexByTime(times, double(ch.CurrentTime));
                else
                    idx = round(double(app.structNumber(ch, 'CurrentIndex', 1)));
                    idx = min(max(1, idx), height(app.Models(fIdx).rawData));
                end
                app.Models(fIdx).currentIndex = idx;
                app.updateDashboard(fIdx, idx);
                try, app.UI(fIdx).spinner.Value = times(idx); catch, end
            catch ME
                app.logCaught(ME, 'Config:restoreCurrentIndex');
            end
        end

        function restoreRoisFromConfig(app, fIdx, ch)
            try
                if ~isfield(ch, 'RoiRows') || isempty(ch.RoiRows), return; end
                rows = ch.RoiRows;
                if ~iscell(rows), return; end
                if size(rows, 2) < 5, return; end
                app.UI(fIdx).roiRows = rows(:, 1:5);
                app.UI(fIdx).selectedRoiIdx = 0;
                app.RoiCtrl.refreshTable(fIdx);
                if ~isempty(app.RoiCtrl) && isvalid(app.RoiCtrl)
                    app.RoiCtrl.drawBands(fIdx);
                end
                if ~isempty(app.AuxWindowMgr) && isvalid(app.AuxWindowMgr)
                    app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
                end
            catch ME
                app.logCaught(ME, 'Config:restoreRois');
            end
        end

        function restoreVideoSyncStateFromConfig(app, fIdx, ch)
            try
                if ~isfield(ch, 'VideoSyncState') || isempty(ch.VideoSyncState), return; end
                stored = ch.VideoSyncState;
                keepTotal = app.VideoSyncState(fIdx).TotalFrames;
                storedTotal = 0;
                if isfield(stored, 'TotalFrames')
                    storedTotal = double(stored.TotalFrames);
                end
                fields = fieldnames(stored);
                for sIdx = 1:numel(fields)
                    fieldName = fields{sIdx};
                    if isfield(app.VideoSyncState, fieldName)
                        app.VideoSyncState(fIdx).(fieldName) = stored.(fieldName);
                    end
                end
                app.VideoSyncState(fIdx).TotalFrames = max(0, keepTotal);
                if app.VideoSyncState(fIdx).TotalFrames >= 1
                    app.VideoSyncState(fIdx).CurrentFrame = min(max(1, app.VideoSyncState(fIdx).CurrentFrame), ...
                        app.VideoSyncState(fIdx).TotalFrames);
                else
                    app.VideoSyncState(fIdx).CurrentFrame = 0;
                    app.VideoSyncState(fIdx).IsSynced = false;
                end
                if storedTotal > 0 && keepTotal > 0
                    tolerance = max(2, round(0.01 * max(storedTotal, keepTotal)));
                    if abs(storedTotal - keepTotal) > tolerance
                        ME = MException('flightdash:Config:VideoMetaMismatch', ...
                            'Stored TotalFrames (%g) differs from loaded video TotalFrames (%g). Video sync restore skipped.', ...
                            storedTotal, keepTotal);
                        app.logCaught(ME, 'Config:videoMetaMismatch');
                        app.VideoSyncState(fIdx).IsSynced = false;
                    end
                end
                if app.VideoSyncState(fIdx).IsSynced && ...
                        isfinite(app.VideoSyncState(fIdx).AnchorFrame) && app.VideoSyncState(fIdx).AnchorFrame >= 1 && ...
                        isfinite(app.VideoSyncState(fIdx).AnchorTime)
                    app.SyncMdl(fIdx).setAnchor(app.VideoSyncState(fIdx).AnchorFrame, ...
                        app.VideoSyncState(fIdx).AnchorTime, app.VideoSyncState(fIdx).AnchorOffset);
                    app.SyncMdl(fIdx).DataFps = app.VideoSyncState(fIdx).DataFps;
                    try
                        if isfield(app.UI(fIdx), 'vidSyncBtn') && isvalid(app.UI(fIdx).vidSyncBtn)
                            app.UI(fIdx).vidSyncBtn.Text = 'Sync Off';
                            app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.8 0.2 0.2];
                        end
                        if isfield(app.UI(fIdx), 'vidSyncStatus') && isvalid(app.UI(fIdx).vidSyncStatus)
                            app.UI(fIdx).vidSyncStatus.Text = sprintf('Sync restored (F%d <-> %.3fs)', ...
                                app.VideoSyncState(fIdx).AnchorFrame, app.VideoSyncState(fIdx).AnchorTime);
                            app.UI(fIdx).vidSyncStatus.FontColor = [0.06 0.65 0.50];
                        end
                    catch ME_ui
                        app.logCaught(ME_ui, 'Config:restoreVideoSyncUI');
                    end
                else
                    app.SyncMdl(fIdx).clear();
                    try
                        if isfield(app.UI(fIdx), 'vidSyncBtn') && isvalid(app.UI(fIdx).vidSyncBtn)
                            app.UI(fIdx).vidSyncBtn.Text = 'Sync';
                            app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.58 0.0 0.83];
                        end
                        if isfield(app.UI(fIdx), 'vidSyncStatus') && isvalid(app.UI(fIdx).vidSyncStatus)
                            app.UI(fIdx).vidSyncStatus.Text = 'Sync pending';
                            app.UI(fIdx).vidSyncStatus.FontColor = [0.5 0.5 0.5];
                        end
                    catch ME_ui
                        app.logCaught(ME_ui, 'Config:restoreVideoSyncUI');
                    end
                end
                app.updateVdubFrameLabel(fIdx, app.VideoSyncState(fIdx).CurrentFrame);
            catch ME
                app.logCaught(ME, 'Config:restoreVideoSyncState');
            end
        end

        function applyStoredMappingIfCompatible(app, fIdx, ch)
            try
                if isempty(app.Models(fIdx).rawData), return; end
                rawVars = app.Models(fIdx).rawData.Properties.VariableNames;
                if isfield(ch, 'MappedCols') && isstruct(ch.MappedCols)
                    mapped = app.Models(fIdx).mappedCols;
                    fns = fieldnames(ch.MappedCols);
                    for mapIdx = 1:numel(fns)
                        val = app.valueToChar(ch.MappedCols.(fns{mapIdx}));
                        if isempty(val) || ismember(val, rawVars)
                            mapped.(fns{mapIdx}) = val;
                        end
                    end
                    app.Models(fIdx).mappedCols = mapped;
                end
                if isfield(ch, 'DisplayMeta') && isstruct(ch.DisplayMeta) && ~isempty(ch.DisplayMeta)
                    meta = ch.DisplayMeta;
                    keep = false(1, numel(meta));
                    for metaIdx = 1:numel(meta)
                        if isfield(meta(metaIdx), 'header')
                            keep(metaIdx) = ismember(app.valueToChar(meta(metaIdx).header), rawVars);
                        end
                    end
                    if any(keep)
                        app.Models(fIdx).displayMeta = meta(keep);
                    end
                end
                if isfield(ch, 'InfoFormatModes') && isstruct(ch.InfoFormatModes)
                    app.InfoFormatModes{fIdx} = ch.InfoFormatModes;
                end
                app.setupDataUI(fIdx);
            catch ME
                app.logCaught(ME, 'Config:storedMapping');
            end
        end

        function updateDataFpsFromLoadedData(app, fIdx, times)
            try
                if length(times) > 1
                    dt = mean(diff(times(1:min(100, end))));
                    if dt > 0
                        estFps = round(1 / dt);
                        if estFps >= 1 && estFps <= 1000
                            app.VideoSyncState(fIdx).DataFps = estFps;
                            if isfield(app.UI(fIdx), 'vidDataFpsInput') && isvalid(app.UI(fIdx).vidDataFpsInput)
                                app.UI(fIdx).vidDataFpsInput.Value = estFps;
                            end
                        end
                    end
                end
            catch ME
                app.logCaught(ME, 'Config:updateDataFps');
            end
        end

        function recomputeVideoFpsFromLoadedData(app, fIdx, times)
            try
                if app.VideoSyncState(fIdx).TotalFrames <= 0, return; end
                timeSpan = times(end) - times(1);
                if timeSpan > 0 && app.VideoSyncState(fIdx).TotalFrames > 1
                    newFps = (app.VideoSyncState(fIdx).TotalFrames - 1) / timeSpan;
                    app.VideoSyncState(fIdx).VideoFps = newFps;
                    if isfield(app.UI(fIdx), 'vidVideoFpsInput') && any(isvalid(app.UI(fIdx).vidVideoFpsInput))
                        app.UI(fIdx).vidVideoFpsInput.Value = round(newFps);
                    end
                    app.updateVdubFrameLabel(fIdx, app.VideoSyncState(fIdx).CurrentFrame);
                end
            catch ME
                app.logCaught(ME, 'Config:recomputeVideoFps');
            end
        end

        function folder = sessionConfigFolder(~)
            wrapperPath = which('FlightDataDashboard');
            if isempty(wrapperPath)
                wrapperPath = mfilename('fullpath');
            end
            folder = fileparts(wrapperPath);
            if isempty(folder), folder = pwd; end
        end

        function txt = optionTextForChannel(app, fIdx)
            txt = '';
            candidates = {fullfile(app.sessionConfigFolder(), sprintf('option%d.dat', fIdx)), ...
                fullfile(app.sessionConfigFolder(), '+flightdash', sprintf('option%d.dat', fIdx)), ...
                sprintf('option%d.dat', fIdx)};
            for optIdx = 1:numel(candidates)
                if isfile(candidates{optIdx})
                    txt = fileread(candidates{optIdx});
                    return;
                end
            end
        end

        function row = findDisplayMetaRow(app, fIdx, yColumn)
            row = [];
            try
                meta = app.Models(fIdx).displayMeta;
                if isempty(meta), return; end
                headers = {meta.header};
                row = find(strcmp(headers, yColumn), 1, 'first');
            catch
                row = [];
            end
        end

        function rows = safeRoiRows(app, fIdx)
            rows = cell(0, 0);
            try
                if isfield(app.UI(fIdx), 'roiTable') && ~isempty(app.UI(fIdx).roiTable) && isvalid(app.UI(fIdx).roiTable)
                    data = app.UI(fIdx).roiTable.Data;
                    if iscell(data)
                        rows = data;
                    end
                end
            catch
            end
        end

        function modes = infoFormatStruct(app, fIdx)
            modes = struct();
            try
                if fIdx <= numel(app.InfoFormatModes) && isstruct(app.InfoFormatModes{fIdx})
                    modes = app.InfoFormatModes{fIdx};
                end
            catch
                modes = struct();
            end
        end

        function panelVisible = safePanelVisible(app, fIdx)
            panelVisible = struct();
            try
                if isfield(app.UI(fIdx), 'PanelVisible')
                    panelVisible = app.UI(fIdx).PanelVisible;
                end
            catch
            end
        end

        function profile = currentLayoutProfile(app)
            profile = app.LayoutProfile;
        end

        function mode = currentChannelViewMode(app)
            mode = app.ChannelViewMode;
        end

        function idx = safeCurrentIndex(app, fIdx)
            idx = 1;
            try
                idx = app.Models(fIdx).currentIndex;
            catch
            end
        end

        function t = safeCurrentTime(app, fIdx)
            t = 0;
            try
                if isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                idx = min(max(1, app.Models(fIdx).currentIndex), height(app.Models(fIdx).rawData));
                t = app.Models(fIdx).rawData.(timeCol)(idx);
            catch
            end
        end

        function frame = safeCurrentFrame(app, fIdx)
            frame = 0;
            try
                if fIdx <= numel(app.VideoSyncState)
                    frame = double(app.VideoSyncState(fIdx).CurrentFrame);
                end
            catch
                frame = 0;
            end
        end

        function name = snapshotDisplayName(app)
            name = char(app.ActiveSessionId);
            if isempty(name) || strcmp(name, 'standalone')
                name = 'Dashboard Session';
            end
        end

        function pair = pathPair(app, value)
            pair = {'', ''};
            try
                if iscell(value)
                    for k = 1:min(2, numel(value))
                        pair{k} = app.valueToChar(value{k});
                    end
                elseif isstring(value)
                    for k = 1:min(2, numel(value))
                        pair{k} = app.valueToChar(value(k));
                    end
                elseif ischar(value)
                    pair{1} = value;
                end
            catch
                pair = {'', ''};
            end
        end

        function state = exportLayoutState(app)
            state = struct();
            try
                state.LayoutProfile = app.LayoutProfile;
                state.ChannelViewMode = app.ChannelViewMode;
                state.PreferredVideoWidth = app.PreferredVideoWidth;
                state.ManualVideoWidth = app.ManualVideoWidth;
                state.ManualPanelWidths = app.ManualPanelWidths;
                state.VideoUserResized = app.VideoUserResized;
            catch
            end
        end

        function applyLayoutState(app, state)
            if ~isstruct(state), return; end
            try
                if isfield(state, 'LayoutProfile'), app.LayoutProfile = app.valueToChar(state.LayoutProfile); end
                if isfield(state, 'ChannelViewMode'), app.ChannelViewMode = app.valueToChar(state.ChannelViewMode); end
                if isfield(state, 'PreferredVideoWidth'), app.PreferredVideoWidth = double(state.PreferredVideoWidth); end
                if isfield(state, 'ManualVideoWidth'), app.ManualVideoWidth = double(state.ManualVideoWidth); end
                if isfield(state, 'ManualPanelWidths') && iscell(state.ManualPanelWidths)
                    app.ManualPanelWidths = state.ManualPanelWidths;
                end
                if isfield(state, 'VideoUserResized'), app.VideoUserResized = logical(state.VideoUserResized); end
            catch ME
                app.logCaught(ME, 'Studio:applyLayoutState');
            end
        end

        function out = mergeStructFields(~, base, updates)
            out = base;
            try
                if ~isstruct(base) || ~isstruct(updates), return; end
                names = fieldnames(updates);
                for k = 1:numel(names)
                    out.(names{k}) = updates.(names{k});
                end
            catch
                out = base;
            end
        end

        function pv = panelVisibleForChannel(~, panelVisible, ch)
            pv = struct();
            try
                if ~isstruct(panelVisible), return; end
                key = sprintf('Channel%d', ch);
                if isfield(panelVisible, key) && isstruct(panelVisible.(key))
                    pv = panelVisible.(key);
                elseif any(isfield(panelVisible, {'attitude', 'map', 'info', 'video'}))
                    pv = panelVisible;
                end
            catch
                pv = struct();
            end
        end

        function pos = currentFigurePosition(app)
            pos = [];
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                oldUnits = app.UIFigure.Units;
                app.UIFigure.Units = 'pixels';
                pos = app.UIFigure.Position;
                app.UIFigure.Units = oldUnits;
            catch
                pos = [];
            end
        end

        function value = finiteVectorOrEmpty(~, value)
            try
                if isempty(value) || ~all(isfinite(value(:)))
                    value = [];
                end
            catch
                value = [];
            end
        end

        function value = cellChar(app, cellValue, idx)
            value = '';
            try
                if idx <= numel(cellValue)
                    value = app.valueToChar(cellValue{idx});
                end
            catch
            end
        end

        function value = structChar(app, s, fieldName, defaultValue)
            value = defaultValue;
            try
                if isstruct(s) && isfield(s, fieldName)
                    value = app.valueToChar(s.(fieldName));
                    if isempty(value), value = defaultValue; end
                end
            catch
                value = defaultValue;
            end
        end

        function value = structNumber(~, s, fieldName, defaultValue)
            value = defaultValue;
            try
                if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                    value = double(s.(fieldName));
                end
            catch
                value = defaultValue;
            end
        end

        function value = structLogical(~, s, fieldName, defaultValue)
            value = defaultValue;
            try
                if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                    value = logical(s.(fieldName));
                end
            catch
                value = defaultValue;
            end
        end

        function value = valueToChar(~, value)
            if isempty(value)
                value = '';
            elseif isstring(value)
                value = char(value);
            elseif ischar(value)
                value = value;
            elseif isnumeric(value) || islogical(value)
                value = char(string(value));
            else
                try
                    value = char(value);
                catch
                    value = '';
                end
            end
        end

        function notifyUser(app, titleText, messageText, isError)
            if nargin < 4, isError = false; end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    if isError
                        uialert(app.UIFigure, messageText, titleText, 'Icon', 'error');
                    else
                        uialert(app.UIFigure, messageText, titleText, 'Icon', 'info');
                    end
                    return;
                end
            catch
            end
            if isError
                warning('flightdash:Notification', '%s: %s', titleText, messageText);
            else
                disp([titleText ': ' messageText]);
            end
        end

        function invalidateFrameCache(app, fIdx)
            if ~isempty(app.CacheModel) && fIdx <= numel(app.CacheModel)
                app.CacheModel(fIdx).invalidate();
            end
            app.LastDisplayedFrame(fIdx) = 0;
        end

        % [V3.22 #3-3] 비행데이터 첫 시간 추출 (시작 오프셋용)
        function startTime = computeStartTimeFromFlightData(app, fIdx)
            startTime = 0;
            if ~isempty(app.Models(fIdx).rawData) && isfield(app.Models(fIdx).mappedCols, 'Time')
                timeCol = app.Models(fIdx).mappedCols.Time;
                if ~isempty(timeCol) && ismember(timeCol, app.Models(fIdx).rawData.Properties.VariableNames)
                    startTime = app.Models(fIdx).rawData.(timeCol)(1);
                end
            end
        end

        % [V3.22 #3-4] 기존 VideoReader / 비동기 future 명시적 정리
        function cleanupVideoResources(app, fIdx)
            app.AsyncGen(fIdx) = app.AsyncGen(fIdx) + 1;
            app.AsyncTargetFrame(fIdx) = NaN;
            try
                if ~isempty(app.AsyncFutures{fIdx}) && isvalid(app.AsyncFutures{fIdx})
                    fut = app.AsyncFutures{fIdx};
                    cancel(fut);
                    try
                        wait(fut, 'finished', 0.5);
                    catch ME_wait
                        app.logCaught(ME_wait, 'Async:cancelWait:cleanupVideo');
                    end
                    app.AsyncFutures{fIdx} = [];
                end
            catch ME, app.logCaught(ME, 'silent'); end
            % [REFACTOR Step 2-B] VideoModel.cleanup 위임 + VideoState 호환 클리어
            try, app.VideoMdl(fIdx).cleanup(); catch ME, app.logCaught(ME, 'Video:cleanupModel'); end
            app.VideoState(fIdx).videoReader   = [];
            app.VideoState(fIdx).videoStartTime = 0;
            app.VideoFilePath{fIdx} = '';
            app.resetVideoWidthPreferences(fIdx);
        end

        % [V3.22 #3-5] VideoReader 생성 (실패 시 errordlg + [] 반환)
        function vr = openVideoReader(app, fIdx, fullPath, fname)
            vr = app.createVideoReader(fullPath, fname);
            if isempty(vr), return; end
            if ~app.attachVideoReader(fIdx, vr, fullPath, fname)
                app.deleteDetachedVideoReader(vr);
                vr = [];
            end
        end

        function vr = createVideoReader(app, fullPath, fname)
            vr = [];
            try
                vr = VideoReader(fullPath);
                if app.DebugMode
                    fprintf('[Video] reader opened: %s\n', fname);
                end
            catch e
                if app.DebugMode
                    fprintf('[Video] load failed: %s\n  %s\n', fullPath, e.message);
                end
                app.logCaught(e, 'Video:open');
                errordlg(['Video load failed: ', e.message], 'Error');
                vr = [];
            end
        end

        function ok = attachVideoReader(app, fIdx, vr, fullPath, fname)
            ok = false;
            try
                app.VideoState(fIdx).videoReader = vr;
                app.VideoFilePath{fIdx} = fullPath;
                % [REFACTOR Step 2-C] attachReader → VideoLoaded notify (cache 자동 recompute)
                app.VideoMdl(fIdx).attachReader(vr, fullPath, app.VideoState(fIdx).vidImageHandle);
                if app.DebugMode
                    fprintf('[Video] loaded: %s (fIdx=%d)\n', fname, fIdx);
                end
                ok = true;
            catch e
                app.VideoState(fIdx).videoReader = [];
                app.VideoFilePath{fIdx} = '';
                try, app.VideoMdl(fIdx).cleanup(); catch, end
                app.logCaught(e, 'Video:attach');
                errordlg(['Video attach failed: ', e.message], 'Error');
            end
        end

        function deleteDetachedVideoReader(app, vr)
            try
                if ~isempty(vr) && isvalid(vr)
                    delete(vr);
                end
            catch ME
                app.logCaught(ME, 'Video:deleteDetachedReader');
            end
        end

        % [V3.22 #3-6] TotalFrames 산정 + 관련 UI 위젯/스피너/슬라이더 동기화
        function applyVideoLoadedUI(app, fIdx, vr)
            % [FIX] TotalFrames 계산은 항상 먼저, UI 갱신 3종은 독립 try로 도달 보장
            totalFrames = 0;
            try, totalFrames = app.computeTotalFrames(fIdx, vr); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:total'); end
            if ~isfinite(totalFrames) || totalFrames < 1
                app.VideoSyncState(fIdx).TotalFrames = 0;
                app.VideoSyncState(fIdx).CurrentFrame = 0;
                try, app.VideoMdl(fIdx).TotalFrames = 0; catch, end
                ME = MException('flightdash:Video:TotalFramesUnavailable', ...
                    'Video frame count could not be computed. Video navigation and sync were disabled for channel %d.', fIdx);
                app.logCaught(ME, 'Video:totalFrames');
                try
                    if isfield(app.UI(fIdx), 'vidVdubLabel') && isvalid(app.UI(fIdx).vidVdubLabel)
                        app.UI(fIdx).vidVdubLabel.Text = 'Frame count unavailable';
                    end
                    controls = {'vidVdubSlider', 'vidSyncFrameInput', 'vidSyncBtn'};
                    for cIdx = 1:numel(controls)
                        fld = controls{cIdx};
                        if isfield(app.UI(fIdx), fld) && ~isempty(app.UI(fIdx).(fld)) && isvalid(app.UI(fIdx).(fld))
                            app.UI(fIdx).(fld).Enable = 'off';
                        end
                    end
                    app.notifyUser('Video Frame Count Failed', ME.message, true);
                catch ME_ui
                    app.logCaught(ME_ui, 'Video:totalFramesUI');
                end
                return;
            end
            app.VideoSyncState(fIdx).TotalFrames = totalFrames;
            try, app.VideoMdl(fIdx).TotalFrames = totalFrames; catch, end
            try
                controls = {'vidVdubSlider', 'vidSyncFrameInput', 'vidSyncBtn'};
                for cIdx = 1:numel(controls)
                    fld = controls{cIdx};
                    if isfield(app.UI(fIdx), fld) && ~isempty(app.UI(fIdx).(fld)) && isvalid(app.UI(fIdx).(fld))
                        app.UI(fIdx).(fld).Enable = 'on';
                    end
                end
            catch ME_ui
                app.logCaught(ME_ui, 'Video:totalFramesEnableUI');
            end

            try
                hasData = ~isempty(app.Models(fIdx).rawData) && isfield(app.Models(fIdx).mappedCols, 'Time');
                if hasData
                    timeCol = app.Models(fIdx).mappedCols.Time;
                    times = app.Models(fIdx).rawData.(timeCol);
                    timeSpan = times(end) - times(1);
                    if timeSpan > 0 && totalFrames > 1
                        actualFps = (totalFrames - 1) / timeSpan;
                    else
                        actualFps = 15;
                    end
                else
                    actualFps = 15;
                    if isprop(vr, 'FrameRate') && ~isempty(vr.FrameRate) && vr.FrameRate > 0
                        actualFps = vr.FrameRate;
                    end
                end
                app.VideoSyncState(fIdx).VideoFps = actualFps;
                if isfield(app.UI(fIdx), 'vidVideoFpsInput') && any(isvalid(app.UI(fIdx).vidVideoFpsInput))
                    app.UI(fIdx).vidVideoFpsInput.Value = round(actualFps);
                end
                %              FPS 재계산은 유지 (Case 4 요구사항), anchor는 사용자 명시 동기 시 설정
            catch ME, app.logCaught(ME, 'applyVideoLoadedUI:fps'); end

            app.VideoSyncState(fIdx).CurrentFrame = 1;
            try, app.adjustCacheSize(fIdx); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:cache'); end

            try
                if isfield(app.UI(fIdx), 'vidSyncFrameInput') && any(isvalid(app.UI(fIdx).vidSyncFrameInput))
                    maxF = max(1, app.VideoSyncState(fIdx).TotalFrames);
                    app.UI(fIdx).vidSyncFrameInput.Limits = [1 maxF];
                    if app.UI(fIdx).vidSyncFrameInput.Value > maxF
                        app.UI(fIdx).vidSyncFrameInput.Value = 1;
                    end
                end
            catch ME, app.logCaught(ME, 'applyVideoLoadedUI:syncSpinner'); end

            % [FIX] 핵심: 아래 3개는 어떤 경우에도 도달해야 함 → 각각 독립 try
            try, app.updateVdubSliderRange(fIdx); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:sliderRange'); end
            try, app.updateVdubFrameLabel(fIdx, 1); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:label'); end
            try, app.adjustVideoPanelWidth(fIdx); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:panelWidth'); end
        end

        % [V3.22 #3-7] TotalFrames 계산 (NumFrames 우선, 폴백: Duration*FrameRate)
        function totalFrames = computeTotalFrames(app, fIdx, vr)
            totalFrames = app.VideoMdl(fIdx).computeTotalFrames(app.DebugMode, vr);
        end

        % [V3.22 #3-8] 첫 프레임을 정확히 디코딩하여 표시 + 캐시 저장
        function loadFirstFrame(app, fIdx)
            % [REFACTOR Step 2-B] VideoModel 위임 + axes 보정/cache store는 메인 잔류
            firstFrame = app.VideoMdl(fIdx).loadFirstFrame();
            if isempty(firstFrame), return; end

            if isfield(app.UI(fIdx), 'vidAxes') && any(isvalid(app.UI(fIdx).vidAxes))
                app.UI(fIdx).vidAxes.XLim = [0.5, size(firstFrame, 2) + 0.5];
                app.UI(fIdx).vidAxes.YLim = [0.5, size(firstFrame, 1) + 0.5];
                app.UI(fIdx).vidAxes.DataAspectRatio = [1 1 1];
                app.UI(fIdx).vidAxes.PlotBoxAspectRatioMode = 'auto';
            end
            app.cacheStoreFrame(fIdx, 1, firstFrame);
            app.LastDisplayedFrame(fIdx) = 1;
        end

        % [V3.12 2.1] 영상 가로:세로 비율에 따라 비디오 패널 너비 동적 조정
        function adjustVideoPanelWidth(app, fIdx)
            try
                % [FIX] 사용자가 splitter로 조작한 경우 자동 리사이즈 차단 (충돌 방지)
                if app.VideoUserResized(fIdx), return; end
                if app.IsDraggingSplitter, return; end
                if isempty(app.VideoState(fIdx).videoReader), return; end
                vr = app.VideoState(fIdx).videoReader;
                if vr.Height <= 0, return; end
                aspectRatio = vr.Width / vr.Height;

                % 패널 내부 영상 영역 높이 약 280px 가정 (96 DPI 기준 디자인 값)
                % High-DPI 환경에서도 동일 비율을 유지하도록 UIScale.px 적용
                UIScale = flightdash.util.UIScale;
                targetWidth = UIScale.px(round(280 * aspectRatio) + 100);
                targetWidth = max(UIScale.px(400), min(targetWidth, UIScale.px(900)));  % 안전 범위 제한

                app.PreferredVideoWidth(fIdx) = targetWidth;
                app.LayoutMgr.applyLayout(app, 'videoWidth');
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function resetVideoWidthPreferences(app, fIdx)
            if isempty(fIdx) || ~isscalar(fIdx) || ~isfinite(fIdx), return; end
            fIdx = round(fIdx);
            if fIdx < 1 || fIdx > numel(app.VideoUserResized), return; end
            app.PreferredVideoWidth(fIdx) = NaN;
            app.ManualVideoWidth(fIdx) = NaN;
            app.VideoUserResized(fIdx) = false;
        end

        % [V3.14 항목 3 / REFACTOR Step 1] 동적 캐시 크기 계산: CacheModel.recomputeLimit으로 위임
        function adjustCacheSize(app, fIdx)
            try
                if isempty(app.CacheModel) || fIdx > numel(app.CacheModel), return; end
                cm = app.CacheModel(fIdx);
                cm.DebugMode = app.DebugMode;

                vr = app.VideoState(fIdx).videoReader;
                if isempty(vr) || ~isvalid(vr)
                    cm.FrameLimit = flightdash.util.AppConstants.MAX_CACHE_FRAMES;
                    return;
                end
                cm.recomputeLimit(vr.Width, vr.Height);

                if app.DebugMode
                    fprintf('[Cache] fIdx=%d (delegated to CacheModel)\n', fIdx);
                end
            catch ME_silent
                flightdash.util.ErrorLog.log(ME_silent, 'adjustCacheSize', app.DebugMode);
            end
        end

        % [V3.14 항목 3 / REFACTOR Step 1] 사용자가 GUI에서 캐시 예산 변경 시 호출
        function setCacheBudget(app, budgetMB)
            try
                if budgetMB <= 0, return; end
                app.CacheBudgetMB = budgetMB;
                % 각 CacheModel에 예산 전파 후 영상 로드된 경로만 한도 재계산
                for fIdx = 1:2
                    if ~isempty(app.CacheModel) && fIdx <= numel(app.CacheModel)
                        app.CacheModel(fIdx).setBudgetMB(budgetMB);
                    end
                    if app.isVideoReady(fIdx)
                        app.adjustCacheSize(fIdx);
                    end
                end
                if app.DebugMode
                    fprintf('[Cache] Budget changed to %d MB\n', budgetMB);
                end
            catch ME_silent
                flightdash.util.ErrorLog.log(ME_silent, 'silent', app.DebugMode);
            end
        end

        % [V3.15 항목 5-3] DebugMode GUI 체크박스 콜백
        function toggleDebugMode(app, val)
            try
                app.DebugMode = logical(val);
                fprintf('[Debug] DebugMode = %s\n', mat2str(app.DebugMode));
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function fitWindowToScreen(app)
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                pos = app.LayoutMgr.fitFigurePosition(app);
                oldUnits = app.UIFigure.Units;
                try
                    if isprop(app.UIFigure, 'WindowState')
                        app.UIFigure.WindowState = 'normal';
                    end
                catch
                end
                app.UIFigure.Units = 'pixels';
                app.UIFigure.Position = pos;
                app.UIFigure.Units = oldUnits;
                drawnow limitrate;
                app.LayoutMgr.applyLayout(app, 'fitScreen');
            catch ME
                app.logCaught(ME, 'Layout:fitScreen');
            end
        end

        function toggleWindowMaximized(app)
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                if app.isWindowMaximizedLike()
                    app.restoreWindowPosition();
                else
                    app.captureNormalFigurePosition();
                    try
                        if isprop(app.UIFigure, 'WindowState')
                            app.UIFigure.WindowState = 'maximized';
                            drawnow limitrate;
                            app.LayoutMgr.applyLayout(app, 'windowMaximized');
                            app.updateMaximizeButtonState();
                            return;
                        end
                    catch ME_state
                        app.logCaught(ME_state, 'Layout:windowStateMax');
                    end
                    app.fitWindowToScreen();
                end
                app.updateMaximizeButtonState();
            catch ME
                app.logCaught(ME, 'Layout:toggleMaximize');
            end
        end

        % [V3.14 항목 5] VideoReader 유효성 검사 헬퍼 (일관성 있는 가드)
        function tf = isVideoReady(app, fIdx)
            % [REFACTOR Step 2-B] VideoModel 위임
            tf = false;
            try
                if fIdx < 1 || fIdx > 2, return; end
                tf = app.VideoMdl(fIdx).isReady();
                tf = tf && app.VideoSyncState(fIdx).TotalFrames >= 1;
            catch ME_silent
                app.logCaught(ME_silent, 'isVideoReady');
                tf = false;
            end
        end

        % [REFACTOR Step 2-C] VideoLoaded 이벤트 핸들러
        % - cache 한도 재계산 (해상도 기반)
        function onVideoLoaded(app, fIdx, ~)
            try
                if ~isempty(app.CacheModel) && fIdx <= numel(app.CacheModel)
                    vr = app.VideoMdl(fIdx).Reader;
                    if ~isempty(vr) && isvalid(vr) && vr.Width > 0 && vr.Height > 0
                        app.CacheModel(fIdx).recomputeLimit(vr.Width, vr.Height);
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end
        end

        % [REFACTOR Step 2-C] VideoCleared 이벤트 핸들러 - cache 무효화
        function onVideoCleared(app, fIdx)
            try
                app.resetVideoWidthPreferences(fIdx);
                if ~isempty(app.CacheModel) && fIdx <= numel(app.CacheModel)
                    app.CacheModel(fIdx).invalidate();
                end
                app.LayoutMgr.applyLayout(app, 'videoCleared');
            catch ME, app.logCaught(ME, 'silent'); end
        end

        function updateVdubSliderRange(app, fIdx)
            try
                if isfield(app.UI(fIdx), 'vidVdubSlider') && isvalid(app.UI(fIdx).vidVdubSlider)
                    maxF = max(2, app.VideoSyncState(fIdx).TotalFrames);
                    sld = app.UI(fIdx).vidVdubSlider;
                    sld.Limits = [1, maxF];
                    sld.Value = 1;
                    ticks = round(linspace(1, maxF, 5));
                    sld.MajorTicks = ticks;
                    sld.MajorTickLabels = arrayfun(@num2str, ticks, 'UniformOutput', false); % 지수 표기 방지
                    sld.MinorTicks = [];
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.14 VirtualDub UI] Frame N / Total (HH:MM:SS.mmm) 라벨 갱신
        % [V3.15 항목 5-1 / REFACTOR Step 0] 시간 포맷팅을 util.TimeFormat으로 위임
        function updateVdubFrameLabel(app, fIdx, frameNo)
            try
                if ~isfield(app.UI(fIdx), 'vidVdubLabel') || ~isvalid(app.UI(fIdx).vidVdubLabel)
                    return;
                end
                total = app.VideoSyncState(fIdx).TotalFrames;
                fps = app.VideoSyncState(fIdx).VideoFps;

                hms = flightdash.util.TimeFormat.frameToHMSms(frameNo, fps);
                app.UI(fIdx).vidVdubLabel.Text = sprintf('Frame %d / %d  (%s)', ...
                    frameNo, total, hms);
                app.LayoutMgr.updatePanelRailSummaries(app, fIdx);
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.15 항목 2 / V3.16 / V3.17 (1)(9)] goToFrame() - 단일 공식 진입점
        % - V3.16: InGoToFrame 재진입 가드 + onCleanup
        % - V3.17 (1)(9): coalescing - 처리 중 새 요청은 PendingFrame에 저장 후
        %                 현재 처리 완료 시 자동 흡수 (최신 frame 누락 방지)
        % - V3.17 (8): State = 'UPDATING' 표시
        function goToFrame(app, fIdx, frameNo, mode)
            if nargin < 4, mode = 'final'; end

            % [REFACTOR] Coalesce recursive frame moves through PlaybackStateModel.
            if app.stateIsGoToFrame(fIdx)
                app.setStatePendingFrame(fIdx, frameNo, mode);
                return;
            end

            app.setStateGoToFrame(fIdx, true);
            app.State = 'UPDATING';
            cleanupObj = onCleanup(@() app.clearGoToFrameFlag(fIdx)); %#ok<NASGU>

            app.processFrameInternal(fIdx, frameNo, mode);

            maxIter = flightdash.util.AppConstants.MAX_PENDING_ITERS;
            iter = 0;
            [hasPending, pf, pm] = app.peekStatePendingFrame(fIdx);
            while hasPending && iter < maxIter
                if app.stateIsDecoding(fIdx)
                    break;
                end
                [~, pf, pm] = app.consumeStatePendingFrame(fIdx);
                iter = iter + 1;
                if pf == app.VideoSyncState(fIdx).CurrentFrame
                    [hasPending, pf, pm] = app.peekStatePendingFrame(fIdx);
                    continue;
                end
                app.processFrameInternal(fIdx, pf, pm);
                [hasPending, pf, pm] = app.peekStatePendingFrame(fIdx);
            end
            if iter >= maxIter && app.DebugMode
                fprintf('[goToFrame] Pending loop hit max iterations (fIdx=%d)\n', fIdx);
            end

            drawnow limitrate;
        end
        % [V3.17 (1)(9)] goToFrame의 핵심 처리 로직 (재진입 가드 우회 - coalescing 전용)
        function processFrameInternal(app, fIdx, frameNo, mode)
            if isempty(mode), mode = 'final'; end

            % 1. 범위 검증 + clamp
            totalF = app.VideoSyncState(fIdx).TotalFrames;
            if totalF < 1, return; end
            frameNo = round(frameNo);
            frameNo = max(1, min(frameNo, totalF));

            if app.VideoSyncState(fIdx).CurrentFrame == frameNo, return; end
            app.VideoSyncState(fIdx).CurrentFrame = frameNo;

            app.syncFrameMarkersAndLabel(fIdx, frameNo);

            % 4. 영상 갱신 (mode에 따라 source 선택)
            app.syncFrameMarkersAndLabel(fIdx, frameNo);
            if strcmp(mode, 'drag')
                app.updateVideoFrameByFrameNo(fIdx, frameNo, 'drag');
            else
                app.updateVideoFrameByFrameNo(fIdx, frameNo, 'sync');
            end

            if app.VideoSyncState(fIdx).IsSynced && ~isempty(app.Models(fIdx).rawData)
                try
                    targetTime = app.frameToTime(fIdx, frameNo);
                    timeCol = app.Models(fIdx).mappedCols.Time;
                    times = app.Models(fIdx).rawData.(timeCol);
                    targetTime = max(times(1), min(targetTime, times(end)));
                    idx = app.findClosestIndexByTime(times, targetTime);

                    if ~isequal(app.Models(fIdx).currentIndex, idx)
                        app.MarkerDragCtrl.setDraggedFromVideo(true);
                        try
                            if strcmp(mode, 'drag')
                                app.updateMarkersOnly(fIdx, idx);
                            else
                                app.setStateUpdating(fIdx, true);
                                cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
                                app.updateDashboard(fIdx, idx);
                                clear cleanup_;
                            end
                        catch e
                            app.logCaught(e, 'goToFrame:dashboard');
                        end
                        app.MarkerDragCtrl.setDraggedFromVideo(false);
                    end
                catch ME_silent, app.logCaught(ME_silent, 'silent'); end
            end
        end

        % [V3.15 항목 1] 슬라이더 드래그 중 콜백 (ValueChangingFcn)
        % - throttle 0.03s(33fps) 적용으로 디코딩 큐 적체 방지
        % - 'drag' 모드로 goToFrame 호출 → 경량 갱신만 수행
        function onVdubSliderChanging(app, fIdx, evtValue)
            % 슬라이더 throttle: 너무 자주 호출되면 무시
            if app.throttleHit('LastSliderUpdate', fIdx, flightdash.util.AppConstants.SLIDER_THROTTLE_S), return; end

            frameNo = round(evtValue);
            try, app.updateVdubFrameLabel(fIdx, frameNo); catch, end

            app.updateDragVelocity(fIdx, frameNo);

            app.goToFrame(fIdx, evtValue, 'drag');
        end

        % [V3.15 항목 1] 슬라이더 드래그 종료 시 콜백 (ValueChangedFcn)
        % - 'final' 모드로 goToFrame 호출 → 전체 패널 1회 동기화 보장
        function onVdubSliderChanged(app, fIdx, src)
            try
                target = round(src.Value);
                if app.VideoSyncState(fIdx).CurrentFrame == target
                    % final 모드 1회 강제 호출로 전체 동기화 보장
                    if app.VideoSyncState(fIdx).IsSynced && ~isempty(app.Models(fIdx).rawData)
                        app.setStateUpdating(fIdx, true);
                        cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
                        try, app.updateDashboard(fIdx, app.Models(fIdx).currentIndex); catch, end
                        clear cleanup_;
                    end
                    return;
                end
                app.goToFrame(fIdx, src.Value, 'final');
                % [V3.19 (2)] 슬라이더 드래그 종료 시 adaptive prefetch
                app.prefetchAdjacentFrames(fIdx);
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.16 / V3.17 (8)] goToFrame 재진입 플래그 해제 (onCleanup 콜백)
        function clearGoToFrameFlag(app, fIdx)
            app.setStateGoToFrame(fIdx, false);
            if ~app.anyStateGoToFrame(), app.State = 'IDLE'; end
        end

        % [V3.17 (7)] 디코딩 진행 중 플래그 해제 (onCleanup 콜백)
        function clearDecodingFlag(app, fIdx)
            app.setStateDecoding(fIdx, false);
            app.processPendingDecodeRequest(fIdx);
        end

        function queuePendingFrame(app, fIdx, frameNo, source)
            try
                app.setStatePendingFrame(fIdx, frameNo, source);
            catch ME
                app.logCaught(ME, 'Video:queuePending');
            end
        end

        function processPendingDecodeRequest(app, fIdx)
            try
                if app.IsDeleting || fIdx < 1 || fIdx > 2, return; end
                [hasPending, frameNo, source] = app.consumeStatePendingFrame(fIdx);
                if ~hasPending, return; end
                if isempty(source), source = 'force'; end
                if app.LastDisplayedFrame(fIdx) ~= frameNo
                    app.requestFrame(fIdx, frameNo, source);
                end
            catch ME
                app.logCaught(ME, 'Video:processPending');
            end
        end

        % [V3.18 (4) / V3.19 (2)] adaptive prefetch: 드래그 속도/방향 기반 prefetch 범위
        function prefetchAdjacentFrames(app, fIdx)
            try
                if ~app.isVideoReady(fIdx), return; end
                cur = app.VideoSyncState(fIdx).CurrentFrame;
                total = app.VideoSyncState(fIdx).TotalFrames;

                v = app.DragVelocity(fIdx);   % frames/sec (부호 = 방향)
                speed = abs(v);

                % [V3.19 (2)] 속도 기반 prefetch 범위
                if speed < 30
                    offsets = [-3:-1, 1:3];        % 느림: 균등 양방향
                elseif speed < 100
                    if v > 0
                        offsets = [-2, -1, 1:7];   % 정방향 우세
                    else
                        offsets = [-7:-1, 1, 2];   % 역방향 우세
                    end
                else
                    if v > 0
                        offsets = 1:12;            % 빠름: 진행방향만 깊게
                    else
                        offsets = -12:-1;
                    end
                end

                if app.DebugMode
                    fprintf('[Prefetch] fIdx=%d, v=%.1f f/s, %d offsets\n', fIdx, v, length(offsets));
                end

                % 다음 드래그용 reset
                app.DragVelocity(fIdx) = 0;
                app.DragVelocitySamples{fIdx} = [];

                targets = [];
                for offset = offsets
                    target = cur + offset;
                    if target < 1 || target > total, continue; end
                    if app.hasCachedFrame(fIdx, target), continue; end
                    targets(end+1) = target; %#ok<AGROW>
                end
                app.prefetchFramesToCache(fIdx, targets);
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function prefetchFramesToCache(app, fIdx, targets)
            if isempty(targets), return; end
            try
                filePath = app.VideoFilePath{fIdx};
                if isempty(filePath) || ~isfile(filePath), return; end
                vrPrefetch = VideoReader(filePath);
                cleanupReader = onCleanup(@() app.deleteReaderQuietly(vrPrefetch)); %#ok<NASGU>
                fps = app.VideoSyncState(fIdx).VideoFps;
                if fps <= 0 || isnan(fps), fps = 70; end

                targets = unique(round(targets), 'stable');
                total = max(1, app.VideoSyncState(fIdx).TotalFrames);
                for target = targets
                    target = max(1, min(target, total));
                    if app.hasCachedFrame(fIdx, target), continue; end
                    img = app.decodeFrameFromReader(vrPrefetch, target, fps);
                    if ~isempty(img)
                        app.cacheStoreFrame(fIdx, target, img);
                    end
                end
            catch ME
                app.logCaught(ME, 'prefetch');
            end
        end

        function img = decodeFrameFromReader(app, vr, frameNo, fps)
            img = [];
            try
                img = read(vr, frameNo);
            catch
                try
                    relTime = (frameNo - 1) / max(1, fps);
                    relTime = max(0, min(relTime, vr.Duration - 0.05));
                    vr.CurrentTime = relTime;
                    if hasFrame(vr), img = readFrame(vr); end
                catch ME
                    app.logCaught(ME, 'prefetch:decode');
                    img = [];
                end
            end
        end

        function deleteReaderQuietly(app, vr)
            try
                if ~isempty(vr) && isvalid(vr)
                    delete(vr);
                end
            catch ME
                app.logCaught(ME, 'prefetch:cleanup');
            end
        end

        % [V3.14 VirtualDub UI] ◄◄ ◄ ► ►► 네비게이션 버튼 콜백
        function onVdubNav(app, fIdx, action)
            try
                if ~app.isVideoReady(fIdx), return; end
                cur = app.VideoSyncState(fIdx).CurrentFrame;
                total = app.VideoSyncState(fIdx).TotalFrames;
                if total < 1, return; end

                switch action
                    case 'jumpBack',    newFrame = max(1, cur - 10);
                    case 'prev',        newFrame = max(1, cur - 1);
                    case 'next',        newFrame = min(total, cur + 1);
                    case 'jumpForward', newFrame = min(total, cur + 10);
                    otherwise,          newFrame = cur;
                end

                if newFrame == cur, return; end
                app.goToFrame(fIdx, newFrame, 'final');
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.14 VirtualDub UI] Frame 마커/슬라이더/라벨 일괄 동기화 헬퍼
        function syncFrameMarkersAndLabel(app, fIdx, frameNo)
            try

                if isfield(app.UI(fIdx), 'vidVdubSlider') && any(isvalid(app.UI(fIdx).vidVdubSlider))
                    if abs(app.UI(fIdx).vidVdubSlider.Value - frameNo) > 0.5
                        app.UI(fIdx).vidVdubSlider.Value = frameNo;
                    end
                end

                % 2. 라벨 텍스트 갱신 (에러 없이 안전하게 도달)
                app.updateVdubFrameLabel(fIdx, frameNo);

            catch ME_silent
                app.logCaught(ME_silent, 'silent');
            end
        end

        function resetVideoSync(app, fIdx)
            app.SyncMdl(fIdx).clear();
            app.VideoSyncState(fIdx).IsSynced = false;
            app.VideoSyncState(fIdx).AnchorFrame = 0;
            app.VideoSyncState(fIdx).AnchorOffset = 0;
            app.VideoSyncState(fIdx).AnchorTime = 0;
            try
                if isfield(app.UI(fIdx), 'vidSyncBtn') && isvalid(app.UI(fIdx).vidSyncBtn)
                    app.UI(fIdx).vidSyncBtn.Text = 'Sync';
                    app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.58 0.0 0.83];
                end
                if isfield(app.UI(fIdx), 'vidSyncStatus') && isvalid(app.UI(fIdx).vidSyncStatus)
                    app.UI(fIdx).vidSyncStatus.Text = 'Sync pending';
                    app.UI(fIdx).vidSyncStatus.FontColor = [0.5 0.5 0.5];
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.12 2.2.3] 동기 버튼 콜백 - 입력값 검증 및 동기 설정
        function applyVideoSync(app, fIdx)
            if app.VideoSyncState(fIdx).IsSynced
                app.resetVideoSync(fIdx);
                return;
            end

            % 1. 영상/데이터 로드 검증
            if isempty(app.VideoState(fIdx).videoReader)
                errordlg('Load AVI file first.', 'Sync Error'); return;
            end
            if isempty(app.Models(fIdx).rawData)
                errordlg('Load flight data (CSV) first.', 'Sync Error'); return;
            end

            frameNo = app.UI(fIdx).vidSyncFrameInput.Value;
            timeVal = app.UI(fIdx).vidSyncTimeInput.Value;

            totalFrames = app.VideoSyncState(fIdx).TotalFrames;
            timeCol = app.Models(fIdx).mappedCols.Time;
            times = app.Models(fIdx).rawData.(timeCol);

            if frameNo < 1 || frameNo > totalFrames
                errordlg(sprintf('Frame No must be in range 1 ~ %d', totalFrames), 'Range Error'); return;
            end
            if timeVal < times(1) || timeVal > times(end)
                errordlg(sprintf('Time(s) must be in range %.3f ~ %.3f', times(1), times(end)), 'Range Error'); return;
            end

            % 4. Hz 값 갱신
            vfpsUI = app.UI(fIdx).vidVideoFpsInput.Value;
            dfps = app.UI(fIdx).vidDataFpsInput.Value;
            if vfpsUI < 1 || dfps < 1
                errordlg('Hz value must be at least 1.', 'Input Error'); return;
            end

            % [수정 3] 소수점 정밀도 유실 방지 로직
            % 내부의 정확한 소수점 FPS를 반올림한 값과 현재 UI 스피너의 값이 같다면,
            if round(app.VideoSyncState(fIdx).VideoFps) == vfpsUI
                % do nothing (소수점 정밀도 유지)
            else
                app.VideoSyncState(fIdx).VideoFps = vfpsUI; % 사용자가 스피너를 바꾼 경우에만 갱신
            end

            app.VideoSyncState(fIdx).DataFps = dfps;

            % [V3.23 sub-frame / FIX] 수동 동기는 사용자 입력을 절대값으로 신뢰 → offset=0 고정
            anchorOffset = 0;

            app.SyncMdl(fIdx).setAnchor(frameNo, timeVal, anchorOffset);
            app.VideoSyncState(fIdx).IsSynced     = true;
            app.VideoSyncState(fIdx).AnchorFrame  = frameNo;
            app.VideoSyncState(fIdx).AnchorOffset = anchorOffset;
            app.VideoSyncState(fIdx).AnchorTime   = timeVal;

            % 6. UI 피드백
            app.UI(fIdx).vidSyncBtn.Text = 'Reset Sync';
            app.UI(fIdx).vidSyncBtn.Text = 'Sync Off';
            app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.8 0.2 0.2];
            app.UI(fIdx).vidSyncStatus.Text = sprintf('Sync OK (F%d -> %.3fs)', frameNo, timeVal);
            app.UI(fIdx).vidSyncStatus.FontColor = [0.06 0.65 0.50];

            % [V3.14 항목 4 / REFACTOR Step 1] 동기 재설정 시 캐시 무효화 - 래퍼 사용
            app.invalidateFrameCache(fIdx);
            if app.DebugMode
                fprintf('[VideoSync] fIdx=%d, anchor F%d ->%.3fs, vfps=%d, dfps=%d, cache cleared\n', ...
                    fIdx, frameNo, timeVal, vfpsUI, dfps);
            end
        end

        % [V3.12 2.2.3.1] Hz 입력 ± 화살표 버튼 콜백 (1Hz 단위)
        function adjustHzValue(app, fIdx, target, delta)
            try
                if strcmp(target, 'video')
                    fld = app.UI(fIdx).vidVideoFpsInput;
                else
                    fld = app.UI(fIdx).vidDataFpsInput;
                end
                newVal = fld.Value + delta;
                if newVal < 1, newVal = 1; end
                if newVal > 1000, newVal = 1000; end
                fld.Value = newVal;

                % 즉시 VideoSyncState에도 반영 (동기 설정 전이라도)
                if strcmp(target, 'video')
                    app.VideoSyncState(fIdx).VideoFps = newVal;
                else
                    app.VideoSyncState(fIdx).DataFps = newVal;
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function onHzInputChanged(app, fIdx, target, newVal)
            try
                if newVal < 1, newVal = 1; end
                if newVal > 1000, newVal = 1000; end
                if strcmp(target, 'video')
                    app.VideoSyncState(fIdx).VideoFps = newVal;
                else
                    app.VideoSyncState(fIdx).DataFps = newVal;
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.12 2.2.3] Frame No → Time 매핑 (앵커 기반 선형)
        function timeVal = frameToTime(app, fIdx, frameNo)
            % [REFACTOR Step 2 / V3.23] SyncModel 위임 - anchor/fps/offset 명시 전달
            s = app.VideoSyncState(fIdx);
            timeVal = app.SyncMdl(fIdx).frameToTime(frameNo, s.VideoFps, s.AnchorFrame, s.AnchorTime, s.AnchorOffset);
        end

        % [V3.12 2.2.3] Time → Frame No 매핑
        function frameNo = timeToFrame(app, fIdx, timeVal)
            % [REFACTOR Step 2 / V3.23] SyncModel 위임 - anchor/fps/total/offset 명시 전달
            s = app.VideoSyncState(fIdx);
            frameNo = app.SyncMdl(fIdx).timeToFrame(timeVal, s.VideoFps, s.TotalFrames, s.AnchorFrame, s.AnchorTime, s.AnchorOffset);
        end

        function img = cacheGetFrame(app, fIdx, frameNo)
            img = [];
            try
                if isempty(app.CacheModel) || fIdx > numel(app.CacheModel), return; end
                app.CacheModel(fIdx).setTotalFrames(app.VideoSyncState(fIdx).TotalFrames);
                img = app.CacheModel(fIdx).get(frameNo);
            catch ME_silent
                flightdash.util.ErrorLog.log(ME_silent, 'cacheGet', app.DebugMode);
                img = [];
            end
        end

        % - 가중 LRU + 메모리 예산 evict는 모두 모델 내부에서 처리
        function cacheStoreFrame(app, fIdx, frameNo, img)
            try
                if isempty(app.CacheModel) || fIdx > numel(app.CacheModel), return; end
                cm = app.CacheModel(fIdx);
                cm.DebugMode = app.DebugMode;
                cm.store(frameNo, img);
            catch e
                if app.DebugMode
                    fprintf('[Cache] cacheStoreFrame failed: %s\n', e.message);
                end
                flightdash.util.ErrorLog.log(e, 'cacheStore', app.DebugMode);
            end
        end

        % (필요 시 app.CacheModel(fIdx).stats() 로 캐시 상태 점검 가능)

        % =====================================================================
        % [V3.21 #3-A] 3계층 분리 구조 - 책임 명확화
        %
        %   Layer 1: requestFrame  - 진입점 + 캐시 lookup + 전략 선택
        %   Layer 2: decodeFrameSync - 동기 디코딩 (read or 폴백)
        %            startAsyncDecode - 비동기 디코딩 (별도 메서드, 기존)
        %   Layer 3: displayFrame  - 표시 + 캐시 store (단일 출구)
        %
        % =====================================================================

        % [V3.21 #3-A Layer 1] Frame 요청 진입점
        % source: 'drag' / 'autoplay' / 'sync' / 'force'
        function requestFrame(app, fIdx, frameNo, source)
            if nargin < 4, source = 'force'; end
            if ~app.isVideoReady(fIdx), return; end


            % autoplay throttle 분기
            if strcmp(source, 'autoplay')
                if app.throttleHit('LastVideoUpdate', fIdx, flightdash.util.AppConstants.VIDEO_THROTTLE_S), return; end
            end

            % clamp (lookup/store 키 일관성)
            totalF = app.VideoSyncState(fIdx).TotalFrames;
            clampedFrame = max(1, min(round(frameNo), max(1, totalF)));

            % [PATCH] 동일 프레임 조기 반환 - GUI/디코딩 부하 동시 절감
            if app.LastDisplayedFrame(fIdx) == clampedFrame, return; end

            % Layer 1: 캐시 lookup
            cached = app.cacheGetFrame(fIdx, clampedFrame);
            if ~isempty(cached)
                app.displayFrame(fIdx, clampedFrame, cached, true);  % cacheHit=true
                return;
            end

            if app.stateIsDecoding(fIdx)
                app.queuePendingFrame(fIdx, clampedFrame, source);
                return;
            end

            % 전략 선택: async vs sync
            if app.UseAsyncDecode && strcmp(source, 'drag')
                app.startAsyncDecode(fIdx, clampedFrame);
                return;
            end

            % Layer 2: 동기 디코딩
            app.setStateDecoding(fIdx, true);
            cleanup2 = onCleanup(@() app.clearDecodingFlag(fIdx)); %#ok<NASGU>

            img = app.decodeFrameSync(fIdx, clampedFrame);
            if ~isempty(img)
                app.displayFrame(fIdx, clampedFrame, img, false);  % cacheHit=false
            end
        end

        % [V3.21 #3-A Layer 2] 동기 디코딩 (read or 폴백)
        function img = decodeFrameSync(app, fIdx, clampedFrame)
            img = [];
            vr = app.VideoState(fIdx).videoReader;

            try
                img = read(vr, clampedFrame);
            catch
                % 폴백: CurrentTime + readFrame
                try
                    fps = app.VideoSyncState(fIdx).VideoFps;
                    if fps <= 0, fps = 70; end
                    relTime = (clampedFrame - 1) / fps;
                    if relTime < 0, relTime = 0; end
                    if relTime >= vr.Duration
                        relTime = max(0, vr.Duration - 0.05);
                    end
                    vr.CurrentTime = relTime;
                    if hasFrame(vr)
                        img = readFrame(vr);
                    end
                catch ME, app.logCaught(ME, 'decodeSync:fallback');
                    img = [];
                end
            end
        end

        % [V3.21 #3-A Layer 3] 단일 표시 출구 - 모든 디코딩 결과는 여기 통과
        function displayFrame(app, fIdx, frameNo, img, isCacheHit)
            try
                if ~app.isVideoReady(fIdx) || isempty(img), return; end
                set(app.VideoState(fIdx).vidImageHandle, 'CData', img);
                app.LastDisplayedFrame(fIdx) = frameNo;   % [PATCH] 조기반환 키

                % 캐시 store (히트 아닐 때만 - cache-first write-through)
                if ~isCacheHit
                    app.cacheStoreFrame(fIdx, frameNo, img);
                end
            catch ME
                app.logCaught(ME, 'displayFrame');
            end
        end

        % [V3.13 / V3.14 / V3.21 호환] 기존 updateVideoFrameByFrameNo는
        % requestFrame로 위임 (외부 호출처 호환 유지)
        function updateVideoFrameByFrameNo(app, fIdx, frameNo, source)
            if nargin < 4, source = 'force'; end
            app.requestFrame(fIdx, frameNo, source);
        end

        function updateVideoFrame(app, fIdx, currentTime, force)
            if nargin < 4, force = false; end

            try
                if isempty(app.VideoState(fIdx).videoReader) || isempty(app.VideoState(fIdx).vidImageHandle) || ~isvalid(app.VideoState(fIdx).vidImageHandle)
                    return;
                end
            catch
                return;
            end

            if ~force
                if app.throttleHit('LastVideoUpdate', fIdx, flightdash.util.AppConstants.VIDEO_THROTTLE_S), return; end
            end

            try
                relTime = currentTime - app.VideoState(fIdx).videoStartTime;
                if isnan(relTime) || ~isfinite(relTime), return; end
                if relTime < 0, relTime = 0; end
                if relTime >= app.VideoState(fIdx).videoReader.Duration
                    relTime = max(0, app.VideoState(fIdx).videoReader.Duration - 0.1);
                end

                app.VideoState(fIdx).videoReader.CurrentTime = relTime;
                if hasFrame(app.VideoState(fIdx).videoReader)
                    frame = readFrame(app.VideoState(fIdx).videoReader);
                    set(app.VideoState(fIdx).vidImageHandle, 'CData', frame);
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end


        function startPanelSplitterDrag(app, fIdx, kind)
            try
                if app.LayoutMgr.isSplitterRestricted(app)
                    app.LayoutMgr.applyLayout(app, 'panelSplitterRestricted');
                    return;
                end
                if fIdx < 1 || fIdx > numel(app.UI), return; end
                kind = char(kind);
                if isempty(kind), return; end
                app.PanelSplitterFIdx = fIdx;
                app.PanelSplitterKind = kind;
                app.IsDraggingPanelSplitter = true;
                if ~app.bindDragCallbacks(@(~,~) app.panelSplitterMotion(), ...
                        @(~,~) app.stopPanelSplitterDrag(), 'PanelSplitter:router')
                    app.IsDraggingPanelSplitter = false;
                    app.PanelSplitterFIdx = 0;
                    app.PanelSplitterKind = '';
                    return;
                end
                if ~app.IsEmbedded && isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'left-right'; end
            catch ME
                app.logCaught(ME, 'PanelSplitter:start');
            end
        end

        function panelSplitterMotion(app)
            if ~app.IsDraggingPanelSplitter, return; end
            try
                fIdx = app.PanelSplitterFIdx;
                if fIdx < 1 || fIdx > numel(app.UI), return; end
                [figW, figH] = app.LayoutMgr.currentFigureSizePx(app);
                profile = flightdash.util.UIScale.profileForSize(figW, figH);
                app.LayoutProfile = profile;
                if app.LayoutMgr.isSplitterRestrictedForProfile(profile)
                    app.LayoutMgr.applyResponsiveChannelLayout(app, fIdx, profile);
                    return;
                end

                dg = app.UI(fIdx).dataGrid;
                if isempty(dg) || ~isvalid(dg) || numel(dg.ColumnWidth) < 9, return; end
                figPos  = app.UIFigure.CurrentPoint;
                gridPos = getpixelposition(dg, true);
                gridW   = gridPos(3);
                mouseX  = figPos(1) - gridPos(1);
                if ~isfinite(mouseX) || ~isfinite(gridW) || gridW <= 0, return; end

                widths = app.numericDataGridWidths(dg.ColumnWidth, gridW, dg.ColumnSpacing);
                if numel(widths) < 9, return; end
                splitW = max(0, widths(2));
                kind = char(app.PanelSplitterKind);
                switch kind
                    case 'att-map'
                        panelName = 'attitude';
                        newW = mouseX - splitW / 2;
                    case 'map-info'
                        panelName = 'map';
                        newW = mouseX - sum(widths(1:2)) - widths(4) / 2;
                    case 'info-plot'
                        panelName = 'info';
                        newW = mouseX - sum(widths(1:4)) - widths(6) / 2;
                    otherwise
                        return;
                end

                app.LayoutMgr.setManualPanelWidth(app, fIdx, panelName, newW, profile, gridW);
                app.VideoUserResized(fIdx) = true;
                app.LayoutMgr.applyResponsiveChannelLayout(app, fIdx, profile);
                drawnow limitrate;
            catch ME
                app.logCaught(ME, 'PanelSplitter:motion');
            end
        end

        function stopPanelSplitterDrag(app)
            try
                if app.IsEmbedded
                    app.releaseEmbeddedDragLock();
                elseif ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = '';
                    app.UIFigure.WindowButtonUpFcn    = '';
                    if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'arrow'; end
                end
                app.IsDraggingPanelSplitter = false;
                app.PanelSplitterFIdx = 0;
                app.PanelSplitterKind = '';
                app.LayoutMgr.applyLayout(app, 'panelSplitterStop');
                drawnow limitrate;
            catch ME
                app.logCaught(ME, 'PanelSplitter:stop');
            end
        end

        function widths = numericDataGridWidths(~, columnWidths, gridW, spacing)
            widths = zeros(1, numel(columnWidths));
            fixedW = 0;
            flexIdx = [];
            for k = 1:numel(columnWidths)
                val = columnWidths{k};
                if isnumeric(val)
                    widths(k) = max(0, double(val));
                    fixedW = fixedW + widths(k);
                else
                    flexIdx(end+1) = k; %#ok<AGROW>
                end
            end
            if nargin < 4 || isempty(spacing), spacing = 0; end
            remW = max(0, gridW - fixedW - spacing * max(0, numel(columnWidths) - 1));
            if ~isempty(flexIdx)
                widths(flexIdx) = remW / numel(flexIdx);
            end
        end


        function startHISplitterDrag(app, fIdx)
            try
                if app.LayoutMgr.isSplitterRestricted(app)
                    app.LayoutMgr.applyLayout(app, 'splitterRestricted');
                    return;
                end
                if fIdx < 1 || fIdx > numel(app.UI) || ...
                        ~app.LayoutMgr.isPanelVisibleForLayout(app, fIdx, 'video')
                    return;
                end
                app.HISplitterFIdx = fIdx;
                app.IsDraggingSplitter = true;
                if ~app.bindDragCallbacks(@(~,~) app.hiSplitterMotion(), ...
                        @(~,~) app.stopHISplitterDrag(), 'HISplitter:router')
                    app.IsDraggingSplitter = false;
                    app.HISplitterFIdx = 0;
                    return;
                end
                if ~app.IsEmbedded && isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'left-right'; end
            catch ME, app.logCaught(ME, 'HISplitter:start'); end
        end

        function hiSplitterMotion(app)
            if ~app.IsDraggingSplitter, return; end
            try
                fIdx = app.HISplitterFIdx;
                if fIdx < 1 || fIdx > 2, return; end
                [figW, figH] = app.LayoutMgr.currentFigureSizePx(app);
                profile = flightdash.util.UIScale.profileForSize(figW, figH);
                app.LayoutProfile = profile;
                if app.LayoutMgr.isSplitterRestrictedForProfile(profile)
                    app.LayoutMgr.applyResponsiveChannelLayout(app, fIdx, profile);
                    return;
                end
                dg = app.UI(fIdx).dataGrid;
                if isempty(dg) || ~isvalid(dg) || numel(dg.ColumnWidth) < 9, return; end
                figPos  = app.UIFigure.CurrentPoint;
                gridPos = getpixelposition(dg, true);
                gridW   = gridPos(3);
                mouseX_in_grid = figPos(1) - gridPos(1);
                newVideoW = gridW - mouseX_in_grid;

                if ~isfinite(newVideoW), return; end
                app.ManualVideoWidth(fIdx) = max(0, round(newVideoW));

                % [FIX] 사용자가 splitter 조작 시 자동 리사이즈 차단 플래그
                app.VideoUserResized(fIdx) = true;
                app.LayoutMgr.applyResponsiveChannelLayout(app, fIdx, profile);
                drawnow limitrate;
            catch ME, app.logCaught(ME, 'HISplitter:motion'); end
        end

        function stopHISplitterDrag(app)
            try
                if app.IsEmbedded
                    app.releaseEmbeddedDragLock();
                elseif ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = '';
                    app.UIFigure.WindowButtonUpFcn    = '';
                    if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'arrow'; end
                end
                app.IsDraggingSplitter = false;
                app.LayoutMgr.applyLayout(app, 'splitterStop');
                app.HISplitterFIdx = 0;
                drawnow limitrate;
            catch ME, app.logCaught(ME, 'HISplitter:stop'); end
        end

        function handleDragMotion(app)
            % StudioMouseRouter entry point for embedded dashboard-level drags.
            if app.IsDraggingPanelSplitter
                app.panelSplitterMotion();
            elseif app.IsDraggingSplitter
                app.hiSplitterMotion();
            end
        end

        function stopDrag(app)
            % StudioMouseRouter entry point for embedded dashboard-level drags.
            if app.IsDraggingPanelSplitter
                app.stopPanelSplitterDrag();
            elseif app.IsDraggingSplitter
                app.stopHISplitterDrag();
            else
                app.releaseEmbeddedDragLock();
            end
        end

        function tf = bindDragCallbacks(app, motionFcn, stopFcn, logTag)
            tf = false;
            try
                if app.IsEmbedded
                    router = app.lookupStudioMouseRouter();
                    if isempty(router) || ~isvalid(router)
                        ME = MException('FlightDash:NoStudioMouseRouter', ...
                            'Embedded drag requires StudioMouseRouter.');
                        app.logCaught(ME, logTag);
                        return;
                    end
                    tf = router.requestDragLock(app.ActiveSessionId, app);
                    return;
                end
                app.UIFigure.WindowButtonMotionFcn = motionFcn;
                app.UIFigure.WindowButtonUpFcn = stopFcn;
                tf = true;
            catch ME
                app.logCaught(ME, logTag);
                tf = false;
            end
        end

        function router = lookupStudioMouseRouter(app)
            router = [];
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure) ...
                        && isappdata(app.UIFigure, 'StudioMouseRouter')
                    router = getappdata(app.UIFigure, 'StudioMouseRouter');
                end
            catch
            end
        end

        function releaseEmbeddedDragLock(app)
            try
                if ~app.IsEmbedded, return; end
                router = app.lookupStudioMouseRouter();
                if ~isempty(router) && isvalid(router)
                    router.releaseDragLock();
                end
            catch
            end
        end


        % ---------------------------------------------------------------------
        % ---------------------------------------------------------------------
        function setXLimListenersEnabled(app, fIdx, enabled)
            % H 패널 내 모든 탭의 XLim 리스너 제어
            try
                for tIdx = 1:length(app.UI(fIdx).xLimListeners)
                    listeners = app.UI(fIdx).xLimListeners{tIdx};
                    for k = 1:length(listeners)
                        L = listeners{k};
                        if ~isempty(L) && isvalid(L)
                            L.Enabled = enabled;
                        end
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end

            % Altitude 패널 XLim 리스너 제어
            try
                if isfield(app.UI(fIdx), 'altXLimListener')
                    L = app.UI(fIdx).altXLimListener;
                    if ~isempty(L) && isvalid(L)
                        L.Enabled = enabled;
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end
        end

        % ---------------------------------------------------------------------
        % [V3.11 C / V3.12 확장] 경량 업데이트 경로 (드래그 중 전용)
        % - V3.11: 마커/xline + 현재시간 라벨 + H 패널 책장 넘기기
        % - V3.12 1.1: Map 비행경로 + 빨간 삼각형 실시간 갱신 추가
        % - V3.12 2.2.3: 비디오 동기 설정 시 Frame 마커 갱신 + 영상 프레임 갱신
        % ---------------------------------------------------------------------
        function updateMarkersOnly(app, fIdx, idx)
            % [V3.17 (4)(11)] persistent inCascade → InCascade 인스턴스 속성으로 이동
            isOuter = ~app.InCascade;

            isOuter = ~app.InCascade;
            app.Models(fIdx).currentIndex = idx;
            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(idx);

            try
                altCol = app.Models(fIdx).mappedCols.Alt;
                alts = app.Models(fIdx).rawData.(altCol);

                % Altitude 패널 마커 + xline 갱신
                if isfield(app.UI(fIdx), 'hAltMarker') && isvalid(app.UI(fIdx).hAltMarker)
                    set(app.UI(fIdx).hAltMarker, 'XData', currTime, 'YData', alts(idx));
                end
                if isfield(app.UI(fIdx), 'timeLine') && isvalid(app.UI(fIdx).timeLine)
                    app.UI(fIdx).timeLine.Value = currTime;
                end

                if isfield(app.UI(fIdx), 'currentTimeLabel') && isvalid(app.UI(fIdx).currentTimeLabel)
                    app.UI(fIdx).currentTimeLabel.Text = sprintf('%.3f s', currTime);
                end

                if isfield(app.UI(fIdx), 'spinner') && isvalid(app.UI(fIdx).spinner)
                    if abs(app.UI(fIdx).spinner.Value - currTime) > eps
                        app.UI(fIdx).spinner.Value = currTime;
                    end
                end

                app.updateCurrentInfoTable(fIdx, idx);
                app.updateAttitudeGauges(fIdx, idx);
            catch ME, app.logCaught(ME, 'silent'); end

            % [V3.12 1.1] Map 비행경로 + 빨간 삼각형 실시간 갱신 (가벼움)
            try
                pathLon = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lon);
                pathLat = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lat);

                updateFullPath = ~app.MarkerDragCtrl.IsDraggingMarker || ...
                    ~app.throttleHit('MapPathDragUpdate', fIdx, flightdash.util.AppConstants.MAP_PATH_DRAG_THROTTLE_S);
                if updateFullPath && isfield(app.UI(fIdx), 'hMapPath') && isvalid(app.UI(fIdx).hMapPath)
                    set(app.UI(fIdx).hMapPath, 'XData', pathLon(1:idx), 'YData', pathLat(1:idx));
                end

                hdg = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Heading)(idx);
                lastValid = idx;
                if idx < 1 || idx > numel(pathLon) || idx > numel(pathLat)
                    lastValid = [];
                elseif isnan(pathLon(idx)) || isnan(pathLat(idx))
                    lastValid = find(~isnan(pathLon(1:idx)) & ~isnan(pathLat(1:idx)), 1, 'last');
                end
                if ~isempty(lastValid) && isfield(app.UI(fIdx), 'hgMapPlane') && isvalid(app.UI(fIdx).hgMapPlane)
                    T_map = makehgtform('translate', [pathLon(lastValid), pathLat(lastValid), 0]) * makehgtform('zrotate', -hdg * pi / 180);
                    set(app.UI(fIdx).hgMapPlane, 'Matrix', T_map);
                end
            catch ME, app.logCaught(ME, 'silent'); end

            if ~app.MarkerDragCtrl.IsDraggingMarker || ...
                    ~app.throttleHit('PlotDragTimelineUpdate', fIdx, flightdash.util.AppConstants.PLOT_DRAG_THROTTLE_S)
                app.updatePlotTimeLines(fIdx, idx, currTime);
            end

            % [V3.12 2.2.3] 비디오 동기 설정 시 Frame 마커 + 영상 프레임 갱신
            % [PATCH UX-1] Sync 명시 활성화 + 비디오 ready 동시 충족 시에만 갱신
            if app.VideoSyncState(fIdx).IsSynced && ~app.MarkerDragCtrl.DraggedFromVideo ...
                    && app.isVideoReady(fIdx) && app.VideoSyncState(fIdx).AnchorFrame > 0
                try
                    targetFrame = app.timeToFrame(fIdx, currTime);
                    app.VideoSyncState(fIdx).CurrentFrame = targetFrame;
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);

                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);

                    % [V3.13 절충] 비행데이터 드래그 시 영상 갱신은 throttle 유지
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);
                    app.updateVideoFrameByFrameNo(fIdx, targetFrame, 'autoplay');
                catch ME, app.logCaught(ME, 'silent'); end
            end

            % 동기화 모드: 경로 1 드래그 시 경로 2도 경량 업데이트
            if app.SyncState.IsSynced && fIdx == 1 && ~isempty(app.Models(2).rawData)
                targetT2 = app.SyncState.SyncT2 + (currTime - app.SyncState.SyncT1);
                timeCol2 = app.Models(2).mappedCols.Time;
                idx2 = app.findClosestIndexByTime(app.Models(2).rawData.(timeCol2), targetT2);
                if ~isequal(app.Models(2).currentIndex, idx2)
                    app.InCascade = true;
                    cascadeCleanup_ = onCleanup(@() resetInCascade(app)); %#ok<NASGU>
                    app.updateMarkersOnly(2, idx2);
                    clear cascadeCleanup_;
                end
            end

            try, app.LayoutMgr.updatePanelRailSummaries(app, fIdx); catch, end

            % [V3.17 (5)] cascade 외부 + goToFrame 미경유 시에만 drawnow
            % goToFrame은 자체 종료 시 drawnow 호출하므로 중복 방지
            if isOuter && ~app.anyStateGoToFrame()
                drawnow limitrate;
            end
        end

        function updateTimeFromScrub(app, fIdx, targetTime)
            timeCol = app.Models(fIdx).mappedCols.Time;
            times = app.Models(fIdx).rawData.(timeCol);
            if isempty(times), return; end

            targetTime = max(min(targetTime, times(end)), times(1));
            idx = app.findClosestIndexByTime(times, targetTime);

            app.applyTimeChange(fIdx, idx);
        end

        function idx = findClosestIndexByTime(~, timeArray, targetTime)
            if isempty(timeArray), idx = 1; return; end
            if isnan(targetTime), idx = 1; return; end

            left = 1; right = length(timeArray);
            while left <= right
                mid = floor((left + right) / 2);
                if timeArray(mid) == targetTime, idx = mid; return; end
                if timeArray(mid) < targetTime, left = mid + 1; else, right = mid - 1; end
            end
            if left > length(timeArray), idx = length(timeArray); return; end
            if right < 1, idx = 1; return; end
            if abs(timeArray(left) - targetTime) < abs(timeArray(right) - targetTime)
                idx = left;
            else
                idx = right;
            end
        end

        function onFlightPlayTick(app, fIdx)
            if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                app.PlaybackCtrl.onFlightPlayTick(fIdx);
            end
        end

        function periodS = resolveFlightPlayPeriod(app, fIdx)
            if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                periodS = app.PlaybackCtrl.resolveFlightPlayPeriod(fIdx);
            else
                periodS = 1;
            end
        end

        function dt = dataSamplePeriodS(app, fIdx)
            if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                dt = app.PlaybackCtrl.dataSamplePeriodS(fIdx);
            else
                dt = 0.001;
            end
        end

        function updateTabTimeLines(app, fIdx)
            if isempty(app.Models(fIdx).rawData), return; end
            currIdx = app.Models(fIdx).currentIndex;
            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(currIdx);
            app.updatePlotTimeLines(fIdx, currIdx, currTime);
            app.refreshPlotManager(fIdx);
            app.refreshPlotDetails(fIdx);
            app.PannerView.refresh(fIdx);
            app.RoiCtrl.drawBands(fIdx);
        end

        function updatePlotTimeLines(app, fIdx, currIdx, currTime)
            if app.hasPlotView(fIdx)
                app.PlotView(fIdx).updateTimeIndicators(currIdx, currTime);
            end
        end

        function restorePlotMarkerInteractions(app, fIdx)
            try
                if fIdx < 1 || fIdx > numel(app.UI), return; end

                app.setXLimListenersEnabled(fIdx, true);

                if isfield(app.UI(fIdx), 'altAxes')
                    app.restoreAxesInteractions(app.UI(fIdx).altAxes, []);
                end
                if isfield(app.UI(fIdx), 'hAltMarker')
                    app.restorePlotDragHandle(fIdx, 0, app.UI(fIdx).hAltMarker);
                end
                if isfield(app.UI(fIdx), 'timeLine')
                    app.restorePlotDragHandle(fIdx, 0, app.UI(fIdx).timeLine);
                end

                if isfield(app.UI(fIdx), 'plotAxes')
                    for tabIdx = 1:numel(app.UI(fIdx).plotAxes)
                        axArr = app.UI(fIdx).plotAxes{tabIdx};
                        for k = 1:numel(axArr)
                            app.restoreAxesInteractions(axArr{k}, []);
                        end
                    end
                end

                if isfield(app.UI(fIdx), 'timeMarkers')
                    for tabIdx = 1:numel(app.UI(fIdx).timeMarkers)
                        mkArr = app.UI(fIdx).timeMarkers{tabIdx};
                        for k = 1:numel(mkArr)
                            app.restorePlotDragHandle(fIdx, tabIdx, mkArr{k});
                        end
                    end
                end

                if isfield(app.UI(fIdx), 'timeLines')
                    for tabIdx = 1:numel(app.UI(fIdx).timeLines)
                        tlArr = app.UI(fIdx).timeLines{tabIdx};
                        for k = 1:numel(tlArr)
                            app.restorePlotDragHandle(fIdx, tabIdx, tlArr{k});
                        end
                    end
                end
            catch ME
                app.logCaught(ME, 'PlotMarker:restoreInteractions');
            end
        end

        function restorePlotDragHandle(app, fIdx, tabIdx, h)
            try
                if isempty(h) || ~isvalid(h), return; end
                if isprop(h, 'HitTest')
                    h.HitTest = 'on';
                end
                if isprop(h, 'PickableParts')
                    try
                        h.PickableParts = 'visible';
                    catch
                        h.PickableParts = 'all';
                    end
                end
                if isprop(h, 'ButtonDownFcn')
                    h.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, tabIdx, src, event);
                end
                app.restoreAxesInteractions(h.Parent, h);
            catch ME
                app.logCaught(ME, 'PlotMarker:restoreHandle');
            end
        end

        function restoreAxesInteractions(app, ax, sourceHandle)
            try
                if isempty(ax) || ~isvalid(ax) || ~isprop(ax, 'Interactions'), return; end

                restored = false;
                if nargin >= 3 && ~isempty(sourceHandle) && isvalid(sourceHandle) ...
                        && isprop(sourceHandle, 'UserData') && ~isempty(sourceHandle.UserData)
                    try
                        ax.Interactions = sourceHandle.UserData;
                        sourceHandle.UserData = [];
                        restored = true;
                    catch
                        restored = false;
                    end
                end

                if ~restored && isempty(ax.Interactions)
                    ax.Interactions = [panInteraction, zoomInteraction];
                end
            catch ME
                app.logCaught(ME, 'PlotMarker:restoreAxes');
            end
        end

        function tf = currentTabXAutoEnabled(app, fIdx, tabIdx)
            tf = true;
            try
                if isempty(tabIdx) || tabIdx > numel(app.UI(fIdx).plotMeta), return; end
                metaArr = app.UI(fIdx).plotMeta{tabIdx};
                for k = 1:numel(metaArr)
                    info = metaArr{k};
                    if isstruct(info) && isfield(info, 'XLimMode') && strcmpi(info.XLimMode, 'manual')
                        tf = false;
                        return;
                    end
                end
            catch
                tf = true;
            end
        end

        function tf = hasPlotView(app, fIdx)
            tf = false;
            try
                tf = ~isempty(app.PlotView) && fIdx >= 1 && fIdx <= numel(app.PlotView) && isvalid(app.PlotView(fIdx));
            catch
                tf = false;
            end
        end

        function setPlotProgrammaticXLim(app, fIdx, value)
            try
                if fIdx >= 1 && fIdx <= numel(app.IsProgrammaticXLim)
                    app.IsProgrammaticXLim(fIdx) = logical(value);
                end
            catch ME
                app.logCaught(ME, 'Plot:XLimGuard');
            end
        end

        function tabIdx = currentPlotTabIndex(app, fIdx)
            tabIdx = [];
            try
                if fIdx < 1 || fIdx > numel(app.UI), return; end
                if ~isfield(app.UI(fIdx), 'tabGroup') || isempty(app.UI(fIdx).tabGroup), return; end
                currTab = app.UI(fIdx).tabGroup.SelectedTab;
                if isempty(currTab), return; end
                tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            catch
                tabIdx = [];
            end
        end

        function refreshPlotManager(app, fIdx)
            try
                if ~isfield(app.UI(fIdx), 'plotManagerTable') || ...
                        isempty(app.UI(fIdx).plotManagerTable) || ~isvalid(app.UI(fIdx).plotManagerTable)
                    return;
                end
                tabIdx = app.currentPlotTabIndex(fIdx);
                if isempty(tabIdx) || tabIdx > numel(app.UI(fIdx).plotMeta)
                    app.UI(fIdx).plotManagerTable.Data = cell(0, 3);
                    app.UI(fIdx).selectedPlotIdx = 0;
                    return;
                end

                metaArr = app.UI(fIdx).plotMeta{tabIdx};
                nPlots = numel(metaArr);
                data = cell(nPlots, 3);
                for k = 1:nPlots
                    info = metaArr{k};
                    isVisible = true;
                    if isfield(info, 'Visible'), isVisible = logical(info.Visible); end
                    data{k, 1} = isVisible;
                    data{k, 2} = info.Name;
                    data{k, 3} = info.YColumn;
                end
                app.UI(fIdx).plotManagerTable.Data = data;
                app.AuxWindowMgr.refreshPlotManagerFigure(app, fIdx);
                if nPlots == 0
                    app.UI(fIdx).selectedPlotIdx = 0;
                elseif ~isfield(app.UI(fIdx), 'selectedPlotIdx') || app.UI(fIdx).selectedPlotIdx < 1 || app.UI(fIdx).selectedPlotIdx > nPlots
                    app.UI(fIdx).selectedPlotIdx = 1;
                end
            catch ME
                app.logCaught(ME, 'PlotManager:refresh');
            end
        end

        function refreshPlotDetails(app, fIdx)
            try
                tabIdx = app.currentPlotTabIndex(fIdx);
                plotIdx = app.selectedPlotIndex(fIdx);
                hasPlot = ~isempty(tabIdx) && plotIdx > 0 && ...
                    tabIdx <= numel(app.UI(fIdx).plotMeta) && ...
                    plotIdx <= numel(app.UI(fIdx).plotMeta{tabIdx});

                if ~hasPlot
                    app.setDetailValue(fIdx, 'detailName', '');
                    app.setDetailValue(fIdx, 'detailYLabel', '');
                    if isfield(app.UI(fIdx), 'detailLegend') && isvalid(app.UI(fIdx).detailLegend)
                        app.UI(fIdx).detailLegend.Value = false;
                    end
                    if isfield(app.UI(fIdx), 'detailSignalLabel') && isvalid(app.UI(fIdx).detailSignalLabel)
                        app.UI(fIdx).detailSignalLabel.Text = 'No plot selected';
                    end
                    app.setAxisDetailControls(fIdx, [], struct());
                    return;
                end

                info = app.UI(fIdx).plotMeta{tabIdx}{plotIdx};
                ax = app.UI(fIdx).plotAxes{tabIdx}{plotIdx};
                app.setDetailValue(fIdx, 'detailName', info.Name);
                app.setDetailValue(fIdx, 'detailYLabel', info.YLabel);
                if isfield(app.UI(fIdx), 'detailLegend') && isvalid(app.UI(fIdx).detailLegend)
                    app.UI(fIdx).detailLegend.Value = logical(info.Legend);
                end
                if isfield(app.UI(fIdx), 'detailSignalLabel') && isvalid(app.UI(fIdx).detailSignalLabel)
                    app.UI(fIdx).detailSignalLabel.Text = sprintf('Signal: %s', info.YColumn);
                end
                app.setAxisDetailControls(fIdx, ax, info);
            catch ME
                app.logCaught(ME, 'PlotDetails:refresh');
            end
        end

        function setDetailValue(app, fIdx, fieldName, value)
            try
                if isfield(app.UI(fIdx), fieldName) && ~isempty(app.UI(fIdx).(fieldName)) && isvalid(app.UI(fIdx).(fieldName))
                    app.UI(fIdx).(fieldName).Value = value;
                end
            catch
            end
        end

        function setAxisDetailControls(app, fIdx, ax, info)
            try
                hasPlot = ~isempty(ax) && isvalid(ax) && isstruct(info);
                xLim = [0 1];
                yLim = [0 1];
                xAuto = true;
                yAuto = true;
                if hasPlot
                    xLim = ax.XLim;
                    yLim = ax.YLim;
                    xAuto = strcmpi(app.structChar(info, 'XLimMode', 'auto'), 'auto');
                    yAuto = strcmpi(app.structChar(info, 'YLimMode', 'auto'), 'auto');
                end

                app.setDetailValue(fIdx, 'detailXMin', xLim(1));
                app.setDetailValue(fIdx, 'detailXMax', xLim(2));
                app.setDetailValue(fIdx, 'detailYMin', yLim(1));
                app.setDetailValue(fIdx, 'detailYMax', yLim(2));
                if isfield(app.UI(fIdx), 'detailXAuto') && isvalid(app.UI(fIdx).detailXAuto)
                    app.UI(fIdx).detailXAuto.Value = xAuto;
                end
                if isfield(app.UI(fIdx), 'detailYAuto') && isvalid(app.UI(fIdx).detailYAuto)
                    app.UI(fIdx).detailYAuto.Value = yAuto;
                end

                app.setAxisControlEnable(fIdx, 'detailXMin', hasPlot && ~xAuto);
                app.setAxisControlEnable(fIdx, 'detailXMax', hasPlot && ~xAuto);
                app.setAxisControlEnable(fIdx, 'detailYMin', hasPlot && ~yAuto);
                app.setAxisControlEnable(fIdx, 'detailYMax', hasPlot && ~yAuto);
                app.setAxisControlEnable(fIdx, 'detailXAuto', hasPlot);
                app.setAxisControlEnable(fIdx, 'detailYAuto', hasPlot);
            catch ME
                app.logCaught(ME, 'PlotAxis:detailControls');
            end
        end

        function setAxisControlEnable(app, fIdx, fieldName, enabled)
            try
                if isfield(app.UI(fIdx), fieldName) && ~isempty(app.UI(fIdx).(fieldName)) && isvalid(app.UI(fIdx).(fieldName))
                    if enabled
                        app.UI(fIdx).(fieldName).Enable = 'on';
                    else
                        app.UI(fIdx).(fieldName).Enable = 'off';
                    end
                end
            catch
            end
        end

        function plotIdx = selectedPlotIndex(app, fIdx)
            plotIdx = 0;
            try
                if isfield(app.UI(fIdx), 'selectedPlotIdx')
                    plotIdx = app.UI(fIdx).selectedPlotIdx;
                end
                if isempty(plotIdx) || ~isfinite(plotIdx), plotIdx = 0; end
                plotIdx = round(plotIdx);
            catch
                plotIdx = 0;
            end
        end

        function onPlotManagerSelected(app, fIdx, event)
            try
                if isempty(event) || isempty(event.Indices), return; end
                row = event.Indices(1, 1);
                tabIdx = app.currentPlotTabIndex(fIdx);
                if isempty(tabIdx), return; end
                if row < 1 || row > numel(app.UI(fIdx).plotAxes{tabIdx}), return; end
                app.UI(fIdx).selectedPlotIdx = row;
                app.refreshPlotDetails(fIdx);
                app.PannerView.refresh(fIdx);
            catch ME
                app.logCaught(ME, 'PlotManager:select');
            end
        end

        function onPlotVisibilityChanged(app, fIdx, event)
            try
                if isempty(event) || isempty(event.Indices), return; end
                row = event.Indices(1, 1);
                col = event.Indices(1, 2);
                if col ~= 1, return; end
                isVisible = logical(event.NewData);
                tabIdx = app.currentPlotTabIndex(fIdx);
                if isempty(tabIdx) || row < 1 || row > numel(app.UI(fIdx).plotAxes{tabIdx}), return; end

                vis = app.LayoutMgr.visibleState(isVisible);
                handles = {app.UI(fIdx).plotAxes{tabIdx}{row}, app.UI(fIdx).timeLines{tabIdx}{row}, app.UI(fIdx).timeMarkers{tabIdx}{row}};
                if isfield(app.UI(fIdx), 'plotValueLabels') && row <= numel(app.UI(fIdx).plotValueLabels{tabIdx})
                    handles{end+1} = app.UI(fIdx).plotValueLabels{tabIdx}{row};
                end
                for k = 1:numel(handles)
                    try
                        h = handles{k};
                        if ~isempty(h) && isvalid(h), h.Visible = vis; end
                    catch
                    end
                end
                try
                    info = app.UI(fIdx).plotMeta{tabIdx}{row};
                    if isfield(info, 'Panel') && ~isempty(info.Panel) && isvalid(info.Panel)
                        info.Panel.Visible = vis;
                    end
                    if isfield(info, 'MainLine') && ~isempty(info.MainLine) && isvalid(info.MainLine)
                        info.MainLine.Visible = vis;
                    end
                    info.Visible = isVisible;
                    app.UI(fIdx).plotMeta{tabIdx}{row} = info;
                catch
                end
                app.refreshPlotManager(fIdx);
                app.refreshPlotDetails(fIdx);
                app.PannerView.refresh(fIdx);
            catch ME
                app.logCaught(ME, 'PlotManager:visibility');
            end
        end


        function applyMainLineLegend(app, ax, info)
            try
                if isempty(ax) || ~isvalid(ax), return; end
                if ~isfield(info, 'MainLine') || isempty(info.MainLine) || ~isvalid(info.MainLine)
                    legend(ax, 'off');
                    return;
                end
                label = char(info.Name);
                if isempty(strtrim(label)), label = char(info.YColumn); end
                legend(ax, info.MainLine, {label}, 'Location', 'best', 'Interpreter', 'none');
            catch ME
                app.logCaught(ME, 'Legend:mainLineOnly');
            end
        end

        function excludeFromLegend(~, h)
            try
                if isempty(h) || ~isvalid(h), return; end
                h.HandleVisibility = 'off';
            catch
            end
            try
                h.Annotation.LegendInformation.IconDisplayStyle = 'off';
            catch
            end
        end

        function onPlotDetailChanged(app, fIdx, payload)
            try
                if isempty(payload) || ~isstruct(payload) || ~isfield(payload, 'Field'), return; end
                tabIdx = app.currentPlotTabIndex(fIdx);
                plotIdx = app.selectedPlotIndex(fIdx);
                if isempty(tabIdx) || plotIdx < 1 || plotIdx > numel(app.UI(fIdx).plotMeta{tabIdx}), return; end

                info = app.UI(fIdx).plotMeta{tabIdx}{plotIdx};
                ax = app.UI(fIdx).plotAxes{tabIdx}{plotIdx};
                switch char(payload.Field)
                    case 'Name'
                        newName = char(payload.Value);
                        if isempty(strtrim(newName)), return; end
                        info.Name = newName;
                        if ~isempty(ax) && isvalid(ax), title(ax, newName, 'Interpreter', 'none', 'FontWeight', 'bold'); end
                        if isfield(info, 'MainLine') && ~isempty(info.MainLine) && isvalid(info.MainLine)
                            info.MainLine.DisplayName = newName;
                        end
                        if isfield(info, 'Legend') && info.Legend
                            app.applyMainLineLegend(ax, info);
                        end
                    case 'YLabel'
                        newLabel = char(payload.Value);
                        info.YLabel = newLabel;
                        if ~isempty(ax) && isvalid(ax), ylabel(ax, newLabel, 'Interpreter', 'none'); end
                    case 'Legend'
                        info.Legend = logical(payload.Value);
                        if ~isempty(ax) && isvalid(ax)
                            if info.Legend
                                app.applyMainLineLegend(ax, info);
                            else
                                legend(ax, 'off');
                            end
                        end
                end
                app.UI(fIdx).plotMeta{tabIdx}{plotIdx} = info;
                app.refreshPlotManager(fIdx);
                app.refreshPlotDetails(fIdx);
            catch ME
                app.logCaught(ME, 'PlotDetails:changed');
            end
        end

        function onPlotAxisChanged(app, fIdx, payload)
            try
                if isempty(payload) || ~isstruct(payload) || ~isfield(payload, 'Field'), return; end
                tabIdx = app.currentPlotTabIndex(fIdx);
                plotIdx = app.selectedPlotIndex(fIdx);
                if isempty(tabIdx) || plotIdx < 1 || plotIdx > numel(app.UI(fIdx).plotMeta{tabIdx}), return; end

                info = app.UI(fIdx).plotMeta{tabIdx}{plotIdx};
                ax = app.UI(fIdx).plotAxes{tabIdx}{plotIdx};
                if isempty(ax) || ~isvalid(ax), return; end

                xLim = app.sanitizeAxisLim(app.structNumber(info, 'XLim', ax.XLim));
                yLim = app.sanitizeAxisLim(app.structNumber(info, 'YLim', ax.YLim));
                if isempty(xLim), xLim = ax.XLim; end
                if isempty(yLim), yLim = ax.YLim; end

                switch char(payload.Field)
                    case 'XAuto'
                        if logical(payload.Value)
                            info.XLimMode = 'auto';
                        else
                            info.XLimMode = 'manual';
                            info.XLim = ax.XLim;
                        end
                    case 'YAuto'
                        if logical(payload.Value)
                            info.YLimMode = 'auto';
                        else
                            info.YLimMode = 'manual';
                            info.YLim = ax.YLim;
                        end
                    case 'XMin'
                        xLim(1) = double(payload.Value);
                        xLim = app.sanitizeAxisLim(xLim);
                        if isempty(xLim), return; end
                        info.XLimMode = 'manual';
                        info.XLim = xLim;
                    case 'XMax'
                        xLim(2) = double(payload.Value);
                        xLim = app.sanitizeAxisLim(xLim);
                        if isempty(xLim), return; end
                        info.XLimMode = 'manual';
                        info.XLim = xLim;
                    case 'YMin'
                        yLim(1) = double(payload.Value);
                        yLim = app.sanitizeAxisLim(yLim);
                        if isempty(yLim), return; end
                        info.YLimMode = 'manual';
                        info.YLim = yLim;
                    case 'YMax'
                        yLim(2) = double(payload.Value);
                        yLim = app.sanitizeAxisLim(yLim);
                        if isempty(yLim), return; end
                        info.YLimMode = 'manual';
                        info.YLim = yLim;
                end

                app.applyPlotAxisSettings(ax, info);
                app.UI(fIdx).plotMeta{tabIdx}{plotIdx} = info;
                app.refreshPlotDetails(fIdx);
                app.PannerView.refresh(fIdx);
            catch ME
                app.logCaught(ME, 'PlotAxis:changed');
            end
        end

        function applyPlotAxisSettings(app, ax, info)
            try
                if isempty(ax) || ~isvalid(ax), return; end
                xMode = app.normalizeAxisMode(app.structChar(info, 'XLimMode', 'auto'));
                yMode = app.normalizeAxisMode(app.structChar(info, 'YLimMode', 'auto'));
                if strcmpi(xMode, 'manual')
                    xLim = app.sanitizeAxisLim(app.structNumber(info, 'XLim', ax.XLim));
                    if ~isempty(xLim)
                        ax.XLim = xLim;
                    end
                end
                if strcmpi(yMode, 'manual')
                    yLim = app.sanitizeAxisLim(app.structNumber(info, 'YLim', ax.YLim));
                    if ~isempty(yLim)
                        ax.YLim = yLim;
                    end
                else
                    try, ax.YLimMode = 'auto'; catch, end
                end
            catch ME
                app.logCaught(ME, 'PlotAxis:apply');
            end
        end

        function mode = normalizeAxisMode(~, mode)
            mode = char(mode);
            if strcmpi(mode, 'manual') || strcmpi(mode, 'fixed')
                mode = 'manual';
            else
                mode = 'auto';
            end
        end

        function lim = sanitizeAxisLim(~, lim)
            try
                lim = double(lim);
                lim = lim(:).';
                if numel(lim) < 2 || any(~isfinite(lim(1:2))) || lim(2) <= lim(1)
                    lim = [];
                else
                    lim = lim(1:2);
                end
            catch
                lim = [];
            end
        end

        function togglePlotManager(app, fIdx)
            app.AuxWindowMgr.openPlotManagerFigure(app, fIdx);
            if isfield(app.UI(fIdx), 'PlotManagerVisible') && logical(app.UI(fIdx).PlotManagerVisible)
                app.togglePlotSidePanel(fIdx, 'plotManagerPanel', 1, 160, 'PlotManagerVisible');
            end
        end

        function togglePlotDetails(app, fIdx)
            app.AuxWindowMgr.openDetailsFigure(app, fIdx);
        end

        function togglePlotSidePanel(app, fIdx, panelField, colIdx, designWidth, stateField)
            try
                if ~isfield(app.UI(fIdx), 'plotShellGrid') || ~isvalid(app.UI(fIdx).plotShellGrid), return; end
                if ~isfield(app.UI(fIdx), panelField) || ~isvalid(app.UI(fIdx).(panelField)), return; end
                curr = true;
                if isfield(app.UI(fIdx), stateField), curr = logical(app.UI(fIdx).(stateField)); end
                next = ~curr;
                app.UI(fIdx).(stateField) = next;
                app.UI(fIdx).(panelField).Visible = app.LayoutMgr.visibleState(next);
                cw = app.UI(fIdx).plotShellGrid.ColumnWidth;
                if next
                    cw{colIdx} = flightdash.util.UIScale.px(designWidth);
                else
                    cw{colIdx} = 0;
                end
                app.UI(fIdx).plotShellGrid.ColumnWidth = cw;
            catch ME
                app.logCaught(ME, 'PlotSidePanel:toggle');
            end
        end

        function y = pannerSignalData(app, fIdx)
            y = [];
            try
                tabIdx = app.currentPlotTabIndex(fIdx);
                plotIdx = app.selectedPlotIndex(fIdx);
                if ~isempty(tabIdx) && plotIdx > 0 && plotIdx <= numel(app.UI(fIdx).plotData{tabIdx})
                    y = app.UI(fIdx).plotData{tabIdx}{plotIdx};
                end
                if isempty(y) && isfield(app.Models(fIdx).mappedCols, 'Alt')
                    y = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Alt);
                end
                if isempty(y)
                    vars = app.Models(fIdx).rawData.Properties.VariableNames;
                    for k = 1:numel(vars)
                        candidate = app.Models(fIdx).rawData.(vars{k});
                        if isnumeric(candidate)
                            y = candidate;
                            break;
                        end
                    end
                end
            catch
                y = [];
            end
            if isempty(y)
                y = zeros(height(app.Models(fIdx).rawData), 1);
            end
        end

        function updatePannerViewport(app, fIdx)
            try
                if ~isempty(app.PannerView) && isvalid(app.PannerView)
                    app.PannerView.updateViewport(fIdx);
                end
            catch ME
                app.logCaught(ME, 'Panner:viewportWrapper');
            end
        end

        function xlims = currentPlotXLim(app, fIdx, times)
            xlims = [times(1), times(end)];
            try
                tabIdx = app.currentPlotTabIndex(fIdx);
                if ~isempty(tabIdx) && ~isempty(app.UI(fIdx).plotAxes{tabIdx})
                    ax = app.UI(fIdx).plotAxes{tabIdx}{1};
                    if ~isempty(ax) && isvalid(ax)
                        xlims = ax.XLim;
                    end
                end
            catch
                xlims = [times(1), times(end)];
            end
        end

        function onPannerClicked(app, fIdx)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.onPannerClicked(fIdx);
                end
            catch ME
                app.logCaught(ME, 'Panner:clickedWrapper');
            end
        end

        function startPannerHandleDrag(app, fIdx, side, event)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.startHandleDrag(fIdx, side, event);
                end
            catch ME
                app.logCaught(ME, 'PannerHandle:startWrapper');
            end
        end

        function pannerHandleDragMotion(app)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.handleDragMotion();
                end
            catch ME
                app.logCaught(ME, 'PannerHandle:motionWrapper');
            end
        end

        function stopPannerHandleDrag(app)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.stopHandleDrag();
                end
            catch ME
                app.logCaught(ME, 'PannerHandle:stopWrapper');
            end
        end

        function onPannerRangeChanged(app, fIdx, ~)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.onRangeChanged(fIdx);
                end
            catch ME
                app.logCaught(ME, 'Panner:rangeWrapper');
            end
        end

        function resetPannerRange(app, fIdx)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.resetRange(fIdx);
                end
            catch ME
                app.logCaught(ME, 'Panner:resetWrapper');
            end
        end

        function setCurrentTabXLim(app, fIdx, fromVal, toVal)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.setCurrentTabXLim(fIdx, fromVal, toVal);
                end
            catch ME
                app.logCaught(ME, 'Panner:setXLimWrapper');
            end
        end

        function resetProgrammaticXLim(app, fIdx)
            try
                if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
                    app.PannerCtrl.resetProgrammaticXLim(fIdx);
                end
            catch ME
                app.logCaught(ME, 'Panner:resetProgrammaticWrapper');
            end
        end

        function updateFlightModeBands(app, fIdx)
            try
                bands = app.computeFlightModeBands(fIdx);
                app.UI(fIdx).flightModeBands = bands;
                if isfield(app.UI(fIdx), 'flightModeTable') && isvalid(app.UI(fIdx).flightModeTable)
                    data = cell(numel(bands), 4);
                    for k = 1:numel(bands)
                        data{k, 1} = sprintf('%.3f', bands(k).Start);
                        data{k, 2} = sprintf('%.3f', bands(k).End);
                        data{k, 3} = bands(k).Mode;
                        data{k, 4} = mat2str(bands(k).Color, 2);
                    end
                    app.UI(fIdx).flightModeTable.Data = data;
                end
                app.drawModeAxes(fIdx);
            catch ME
                app.logCaught(ME, 'FlightModes:update');
            end
        end

        function bands = computeFlightModeBands(app, fIdx)
            bands = struct('Start', {}, 'End', {}, 'Mode', {}, 'Color', {});
            try
                if isempty(app.Models(fIdx).rawData), return; end
                bands = flightdash.model.FlightModeAnalyzer.computeBands(app.Models(fIdx).mappedCols, app.Models(fIdx).rawData);
            catch ME
                app.logCaught(ME, 'FlightModes:computeWrapper');
            end
        end

        function labels = flightModeLabelsFromData(app, fIdx, nRows)
            labels = {};
            try
                labels = flightdash.model.FlightModeAnalyzer.labelsFromData(app.Models(fIdx).rawData, nRows);
            catch ME
                app.logCaught(ME, 'FlightModes:labelsWrapper');
            end
        end

        function label = flightModeCodeLabel(~, value)
            label = flightdash.model.FlightModeAnalyzer.codeLabel(value);
        end

        function band = modeBand(~, t0, t1, modeName)
            band = flightdash.model.FlightModeAnalyzer.modeBand(t0, t1, modeName);
        end

        function drawModeAxes(app, fIdx)
            try
                if ~isempty(app.PannerView) && isvalid(app.PannerView)
                    app.PannerView.drawModeAxes(fIdx);
                end
            catch ME
                app.logCaught(ME, 'FlightModes:drawWrapper');
            end
        end

        function y = modelSeries(app, fIdx, keyName, defaultVal)
            y = defaultVal;
            try
                if isfield(app.Models(fIdx).mappedCols, keyName)
                    colName = app.Models(fIdx).mappedCols.(keyName);
                    y = app.Models(fIdx).rawData.(colName);
                end
            catch
                y = defaultVal;
            end
        end

        function y = rawSeries(app, fIdx, colName, defaultVal)
            y = defaultVal;
            try
                if ismember(colName, app.Models(fIdx).rawData.Properties.VariableNames)
                    y = app.Models(fIdx).rawData.(colName);
                end
            catch
                y = defaultVal;
            end
        end

        function rows = statsRowsForCurrentRange(app, fIdx)
            rows = cell(0, 8);
            try
                if isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                xlims = app.currentPlotXLim(fIdx, times);
                tabIdx = app.currentPlotTabIndex(fIdx);
                if isempty(tabIdx) || isempty(app.UI(fIdx).plotData{tabIdx}), return; end
                idx = times >= xlims(1) & times <= xlims(2);
                for pIdx = 1:numel(app.UI(fIdx).plotData{tabIdx})
                    y = app.UI(fIdx).plotData{tabIdx}{pIdx};
                    if isempty(y) || ~any(idx), continue; end
                    ySel = y(idx);
                    info = app.UI(fIdx).plotMeta{tabIdx}{pIdx};
                    rows(end+1, :) = {fIdx, app.UI(fIdx).plotTabs(tabIdx).Title, info.YColumn, ... %#ok<AGROW>
                        xlims(1), xlims(2), mean(ySel, 'omitnan'), std(ySel, 'omitnan'), ...
                        sprintf('%.6g / %.6g', min(ySel, [], 'omitnan'), max(ySel, [], 'omitnan'))};
                end
            catch ME
                app.logCaught(ME, 'Stats:rows');
            end
        end

        function fig = getAuxFigure(app, kind, fIdx, titleText, pos)
            fig = app.AuxWindowMgr.getAuxFigure(app, kind, fIdx, titleText, pos);
        end

        function fig = getExistingAuxFigure(app, kind, fIdx)
            fig = app.AuxWindowMgr.getExistingAuxFigure(kind, fIdx);
        end

        function closeAllAuxFigures(app)
            if ~isempty(app.AuxWindowMgr) && isvalid(app.AuxWindowMgr)
                app.AuxWindowMgr.closeAllAuxFigures();
            end
        end

        % ---------------------------------------------------------------------
        % ---------------------------------------------------------------------
        % - throttle 0.05s로 리사이즈 중 다발 호출 차단
        % - 모든 탭의 모든 row를 동일 높이로 통일 (4개 이상 시 자동 스크롤)
        function updatePlotRowHeights(app, fIdx)
            if app.throttleHit('PlotRowResize', fIdx, 0.05), return; end
            try
                if ~isfield(app.UI(fIdx), 'tabGroup') || ~isvalid(app.UI(fIdx).tabGroup), return; end
                pos = getpixelposition(app.UI(fIdx).tabGroup, true);
                visH = pos(4) - 30;  % 탭 헤더 ~30px 차감
                if visH < 90, visH = 90; end
                rowH = max(120, floor(visH / 3));  % 최소 120px, 한 화면 3개
                for t = 1:numel(app.UI(fIdx).plotLayouts)
                    L = app.UI(fIdx).plotLayouts{t};
                    if isempty(L) || ~isvalid(L) || isempty(L.RowHeight), continue; end
                    L.RowHeight = repmat({rowH}, 1, numel(L.RowHeight));
                end
            catch ME, app.logCaught(ME, 'silent'); end
        end

        % [FIX] UIFigure 리사이즈 시 두 채널 plot row 동시 갱신
        function onUIFigureResized(app)
            app.refreshLayout('resize');
        end

        function refreshLayout(app, reason)
            if nargin < 2 || isempty(reason)
                reason = 'refreshLayout';
            end
            try
                if app.IsDeleting, return; end
                if isempty(app.LayoutMgr) || ~isvalid(app.LayoutMgr), return; end
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                if ~isempty(app.RootContainer) && ~isvalid(app.RootContainer), return; end
                if isempty(app.UI), return; end
                app.LayoutMgr.applyLayout(app, char(reason));
            catch ME
                try, app.logCaught(ME, 'Layout:refreshLayout'); catch, end
            end
        end


        function captureNormalFigurePosition(app)
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                if app.isWindowMaximizedLike(), return; end
                oldUnits = app.UIFigure.Units;
                app.UIFigure.Units = 'pixels';
                pos = app.UIFigure.Position;
                app.UIFigure.Units = oldUnits;
                if numel(pos) >= 4 && all(isfinite(pos)) && pos(3) > 0 && pos(4) > 0
                    app.NormalFigurePosition = pos;
                end
            catch
            end
        end

        function restoreWindowPosition(app)
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                try
                    if isprop(app.UIFigure, 'WindowState')
                        app.UIFigure.WindowState = 'normal';
                    end
                catch
                end
                if all(isfinite(app.NormalFigurePosition)) && app.NormalFigurePosition(3) > 0 && app.NormalFigurePosition(4) > 0
                    oldUnits = app.UIFigure.Units;
                    app.UIFigure.Units = 'pixels';
                    app.UIFigure.Position = app.NormalFigurePosition;
                    app.UIFigure.Units = oldUnits;
                end
                drawnow limitrate;
                app.LayoutMgr.applyLayout(app, 'windowRestored');
            catch ME
                app.logCaught(ME, 'Layout:restoreWindow');
            end
        end

        function tf = isWindowMaximizedLike(app)
            tf = false;
            try
                if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
                if isprop(app.UIFigure, 'WindowState') && strcmpi(app.UIFigure.WindowState, 'maximized')
                    tf = true;
                    return;
                end
                oldUnits = app.UIFigure.Units;
                app.UIFigure.Units = 'pixels';
                pos = app.UIFigure.Position;
                app.UIFigure.Units = oldUnits;
                fitPos = app.LayoutMgr.fitFigurePosition(app);
                tf = numel(pos) >= 4 && numel(fitPos) >= 4 && ...
                    abs(pos(3) - fitPos(3)) <= 8 && abs(pos(4) - fitPos(4)) <= 8;
            catch
                tf = false;
            end
        end

        function updateMaximizeButtonState(app)
            try
                if ~isfield(app.LayoutHandles, 'header'), return; end
                h = app.LayoutHandles.header;
                if ~isfield(h, 'FitScreenButton') || isempty(h.FitScreenButton) || ~isvalid(h.FitScreenButton), return; end
                if app.isWindowMaximizedLike()
                    h.FitScreenButton.Text = 'Rst';
                    h.FitScreenButton.Tooltip = 'Restore previous size';
                else
                    h.FitScreenButton.Text = 'Max';
                    h.FitScreenButton.Tooltip = 'Maximize';
                end
            catch
            end
        end

        function deleteGraphicsHandles(app, handleCell)
            if isempty(handleCell), return; end
            for k = 1:length(handleCell)
                h = handleCell{k};
                try
                    if ~isempty(h) && isvalid(h)
                        delete(h);
                    end
                catch ME_silent, app.logCaught(ME_silent, 'silent'); end
            end
        end

        function deleteListeners(app, listenerCell)
            if isempty(listenerCell), return; end
            for k = 1:length(listenerCell)
                L = listenerCell{k};
                try
                    if ~isempty(L) && isvalid(L)
                        delete(L);
                    end
                catch ME_silent, app.logCaught(ME_silent, 'silent'); end
            end
        end

        function handlePlotXLimChange(app, fIdx, ax)
            % [V3.11 A] 프로그래밍적 XLim 변경(책장 넘기기 등)인 경우 리스너 무시
            if app.IsProgrammaticXLim(fIdx), return; end

            % =======================================================
            % [V3.8 보강] 툴바의 Zoom/Pan 모드를 프로그래밍적으로 강제 Off
            % - 혹시 외부 API나 다른 경로를 통해 zoom/pan 모드가 켜졌을 경우
            %   WindowButtonUp 이벤트 가로채기로 인한 마커 스턱 현상 원천 차단
            % =======================================================
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    zoom(app.UIFigure, 'off');
                    pan(app.UIFigure, 'off');
                    if app.DebugMode
                        fprintf('[XLim] zoom/pan off forced (fIdx=%d)\n', fIdx);
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end

            if app.MarkerDragCtrl.IsDraggingMarker
                app.MarkerDragCtrl.stopDrag();
            end

            if app.stateIsUpdating(fIdx), return; end
            try
                if isempty(ax) || ~isvalid(ax), return; end
            catch
                return;
            end

            xlims = ax.XLim;
            centerTime = mean(xlims);

            timeCol = app.Models(fIdx).mappedCols.Time;
            times = app.Models(fIdx).rawData.(timeCol);
            idx = app.findClosestIndexByTime(times, centerTime);

            ax.YLimMode = 'auto';
            app.updatePannerViewport(fIdx);

            if isequal(app.Models(fIdx).currentIndex, idx), return; end
            app.applyTimeChange(fIdx, idx);
        end
    end

    % =========================================================================
    % =========================================================================
    methods (Access = public)
        function parseFlightData(app, fIdx, filepath)
            modelState = app.DataLoader.parseFlightData(fIdx, filepath);
            app.applyFlightDataState(fIdx, modelState);
        end

        function applyOptionFile(app, fIdx, dataTbl, isMock)
            modelState = app.DataLoader.applyOptionFile(fIdx, dataTbl, isMock);
            app.applyFlightDataState(fIdx, modelState);
        end

        function applyFlightDataState(app, fIdx, modelState)
            app.Models(fIdx).rawData = modelState.rawData;
            app.Models(fIdx).mappedCols = modelState.mappedCols;
            app.Models(fIdx).displayMeta = modelState.displayMeta;
            app.Models(fIdx).selectedRow = modelState.selectedRow;
            app.Models(fIdx).isMockData = modelState.isMockData;
        end

        function normalized = normalizeHeaderName(~, value)
            normalized = lower(regexprep(char(value), '[^A-Za-z0-9]', ''));
        end

        function markInvalidGpsAsNaN(app, fIdx)
            app.Models(fIdx).rawData = app.DataLoader.markInvalidGpsAsNaN( ...
                app.Models(fIdx).rawData, app.Models(fIdx).mappedCols);
        end

        function generateMockFlightData(app, fIdx)
            modelState = app.DataLoader.generateMockFlightData(fIdx, app.Models(fIdx).bounds);
            app.applyFlightDataState(fIdx, modelState);
            app.setupDataUI(fIdx);
            app.UI(fIdx).fileNameLabel.Text = 'No data loaded (Auto)';
        end

        function calculateBounds(app, fIdx)
            [bounds, altBounds] = app.DataLoader.calculateBounds( ...
                app.Models(fIdx).rawData, app.Models(fIdx).mappedCols, ...
                app.CoastlineData, app.FixedAreaBounds, ...
                app.Models(fIdx).bounds, app.Models(fIdx).altBounds);
            app.Models(fIdx).bounds = bounds;
            app.Models(fIdx).altBounds = altBounds;
        end

        function setupDataUI(app, fIdx)
            if height(app.Models(fIdx).rawData) > 0
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                dt = mean(diff(times(1:min(100, end))));
                if dt <= 0, dt = 1; end

                app.UI(fIdx).spinner.Limits = [times(1), times(end)];
                app.UI(fIdx).spinner.Step = dt;
                app.UI(fIdx).spinner.Value = times(1);

                if ~(app.SyncState.IsSynced && fIdx == 2)
                    app.UI(fIdx).spinner.Enable = 'on';
                end

                app.Models(fIdx).currentIndex = 1;
                app.calculateBounds(fIdx);

                app.initPlots(fIdx);
                app.updateFlightModeBands(fIdx);
                app.refreshPlotManager(fIdx);
                app.refreshPlotDetails(fIdx);
                app.PannerView.refresh(fIdx);
                app.RoiCtrl.refreshTable(fIdx);
                app.updateDashboard(fIdx, 1);
            end
        end

        function initPlots(app, fIdx)
            if isempty(app.Models(fIdx).rawData), return; end
            bnds = app.Models(fIdx).bounds;

            % --- Map 설정 ---
            axMap = app.UI(fIdx).mapAxes; cla(axMap);
            hold(axMap, 'on');
            if bnds.isValid
                xlim(axMap, [bnds.minLon, bnds.maxLon]);
                ylim(axMap, [bnds.minLat, bnds.maxLat]);
                axMap.DataAspectRatioMode = 'auto';
                axMap.PlotBoxAspectRatioMode = 'auto';
            end

            if ~isempty(app.CoastlineData)
                plot(axMap, app.CoastlineData(:,2), app.CoastlineData(:,1), 'LineStyle', 'none', ...
                     'Marker', '.', 'MarkerSize', 0.5, 'Color', [0.6 0.6 0.6]);
            end

            pathLon = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lon);
            pathLat = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lat);
            % [PERF] NaN 전처리 → 직접 plot (NaN에서 자동 끊김)
            plot(axMap, pathLon, pathLat, 'Color', [0.8 0.8 0.8], 'LineWidth', 1);

            lineColor = [0.23 0.51 0.96];
            if fIdx == 2, lineColor = [0.31 0.27 0.90]; end

            firstValid = find(~isnan(pathLon) & ~isnan(pathLat), 1);
            if isempty(firstValid), firstValid = 1; end

            app.UI(fIdx).hMapPath = plot(axMap, pathLon(firstValid), pathLat(firstValid), 'Color', lineColor, 'LineWidth', 2);
            app.UI(fIdx).hgMapPlane = hgtransform('Parent', axMap);
            scale = max(bnds.maxLon - bnds.minLon, bnds.maxLat - bnds.minLat) * 0.03;
            if scale <= 0, scale = 0.01; end
            x_base = [0, -0.5, 0.5, 0] * scale; y_base = [1, -1, -1, 1] * scale;
            patch('Parent', app.UI(fIdx).hgMapPlane, 'XData', x_base, 'YData', y_base, 'FaceColor', 'r', 'EdgeColor', [0.5 0 0], 'LineWidth', 1);

            % --- Altitude 설정 및 Y축 동적 스케일링 활성화 ---
            axAlt = app.UI(fIdx).altAxes; cla(axAlt);
            times = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Time);
            alts = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Alt);

            % 에러 방어: altXLimListener가 유효한지 체크
            if isfield(app.UI(fIdx), 'altXLimListener')
                try
                    if ~isempty(app.UI(fIdx).altXLimListener) && isvalid(app.UI(fIdx).altXLimListener)
                        delete(app.UI(fIdx).altXLimListener);
                    end
                catch ME, app.logCaught(ME, 'silent'); end
            end

            % X축을 데이터 전체로 잡고, Y축은 auto 모드로 설정하여 GUI 리사이즈 시 동적으로 적응하도록 보장
            axAlt.XLim = [min(times) max(times)];
            axAlt.YLimMode = 'auto';
            plot(axAlt, times, alts, 'Color', [0.8 0.8 0.8], 'LineWidth', 1, 'HitTest', 'off');

            % [V3.10] Altitude axes는 툴바 숨김 (휠 줌/드래그 팬만 사용)
            app.UI(fIdx).altAxes.Toolbar.Visible = 'off';
            app.UI(fIdx).altAxes.Interactions = [panInteraction, zoomInteraction];

            app.UI(fIdx).hAltPath = plot(axAlt, times(1), alts(1), 'Color', [0.06 0.72 0.51], 'LineWidth', 2, 'HitTest', 'off');
            app.UI(fIdx).hAltMarker = plot(axAlt, times(1), alts(1), 'p', 'MarkerFaceColor', [0.98 0.75 0.14], 'MarkerEdgeColor', [0.71 0.33 0.04], 'MarkerSize', 14, 'HitTest', 'on');
            app.UI(fIdx).timeLine = xline(axAlt, times(1), 'r', 'LineWidth', 3.0, 'Alpha', 0.5, 'HitTest', 'on');

            app.UI(fIdx).hAltMarker.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, 0, src, event);
            app.UI(fIdx).timeLine.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, 0, src, event);

            % Altitude 패널의 Zoom/Pan 시 동기화 리스너 추가
            app.UI(fIdx).altXLimListener = addlistener(axAlt, 'XLim', 'PostSet', @(~,~) app.handlePlotXLimChange(fIdx, axAlt));

            theta = linspace(0, 2*pi, 100);
            angles = 0:30:330;
            for gaugeType = 1:3
                if gaugeType == 1
                    ax = app.UI(fIdx).pitchAxes; cla(ax); app.UI(fIdx).hgPitch = hgtransform('Parent', ax); hg = app.UI(fIdx).hgPitch; offsetDeg = 180; bgColor = [0.15 0.25 0.35];
                elseif gaugeType == 2
                    ax = app.UI(fIdx).rollAxes; cla(ax); app.UI(fIdx).hgRoll = hgtransform('Parent', ax); hg = app.UI(fIdx).hgRoll; offsetDeg = 90; bgColor = [0.35 0.20 0.20];
                else
                    ax = app.UI(fIdx).hdgAxes; cla(ax); app.UI(fIdx).hgHdg = hgtransform('Parent', ax); hg = app.UI(fIdx).hgHdg; offsetDeg = 90; bgColor = [0.20 0.35 0.20];
                end

                patch(ax, cos(theta), sin(theta), bgColor, 'EdgeColor', 'k', 'LineWidth', 2);
                for i = 1:length(angles)
                    val = angles(i); if val > 180, val = val - 360; end
                    angRad = (offsetDeg - angles(i)) * pi / 180;
                    plot(ax, [0.85*cos(angRad) 1.0*cos(angRad)], [0.85*sin(angRad) 1.0*sin(angRad)], 'w', 'LineWidth', 1.5);
                    if gaugeType == 3
                        if val == 0, str = 'N'; elseif val == 90, str = 'E'; elseif val == 180 || val == -180, str = 'S'; elseif val == -90, str = 'W'; else, str = num2str(val); end
                    else
                        str = num2str(val);
                    end
                    text(ax, 0.65*cos(angRad), 0.65*sin(angRad), str, 'Color', 'w', ...
                         'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
                         'FontUnits', 'normalized', 'FontSize', 0.06);
                end

                if gaugeType == 1
                    patch(hg, [-1.15 -1.15 -1.0], [-0.08 0.08 0], bgColor, 'EdgeColor', 'k', 'LineWidth', 1);
                    plot(hg, [-0.4 0.4], [0 0], 'y', 'LineWidth', 4);
                    plot(hg, [0.2 0.3], [0 0.2], 'y', 'LineWidth', 3);
                elseif gaugeType == 2
                    patch(hg, [-0.08 0.08 0], [1.15 1.15 1.0], bgColor, 'EdgeColor', 'k', 'LineWidth', 1);
                    plot(hg, [-0.4 0.4], [0 0], 'y', 'LineWidth', 3);
                    plot(hg, [0 0], [0 0.3], 'y', 'LineWidth', 3);
                else
                    patch(hg, [-0.08 0.08 0], [1.15 1.15 1.0], bgColor, 'EdgeColor', 'k', 'LineWidth', 1);
                    plot(hg, [0 0], [-0.4 0.4], 'y', 'LineWidth', 3);
                    plot(hg, [-0.3 0.3], [0.1 0.1], 'y', 'LineWidth', 3);
                    plot(hg, [-0.15 0.15], [-0.3 -0.3], 'y', 'LineWidth', 2);
                end
                axis(ax, 'equal'); axis(ax, [-1.35 1.35 -1.35 1.35]); axis(ax, 'off');
            end
            try
                app.buildUIGroups();
            catch ME
                app.logCaught(ME, 'UIGroup:initPlots');
            end
        end

        function updateCurrentInfoTable(app, fIdx, index)
            try
                if fIdx < 1 || fIdx > numel(app.Models), return; end
                if isempty(app.Models(fIdx).rawData), return; end
                if ~isfield(app.UI(fIdx), 'dataTable') || isempty(app.UI(fIdx).dataTable) || ...
                        ~isvalid(app.UI(fIdx).dataTable)
                    return;
                end

                nRows = height(app.Models(fIdx).rawData);
                if nRows < 1, return; end
                index = max(1, min(nRows, round(index)));

                metaList = app.Models(fIdx).displayMeta;
                dataCell = cell(length(metaList), 2);
                varNames = app.Models(fIdx).rawData.Properties.VariableNames;

                for i = 1:length(metaList)
                    m = metaList(i);
                    dataCell{i, 1} = sprintf('%s (%s)', m.header, m.unit);

                    if ismember(m.header, varNames)
                        colData = app.Models(fIdx).rawData.(m.header);
                        if index <= numel(colData)
                            val = colData(index);
                            if iscell(val), val = val{1}; end
                            dataCell{i, 2} = app.formatInfoValue(val, m.format, app.infoFormatModeForHeader(fIdx, m.header));
                        else
                            dataCell{i, 2} = '--';
                        end
                    else
                        dataCell{i, 2} = '--';
                    end
                end

                app.UI(fIdx).dataTable.Data = dataCell;
            catch ME
                app.logCaught(ME, 'InfoTable:update');
            end
        end

        function txt = formatInfoValue(app, val, fmt, mode)
            if nargin < 3 || isempty(fmt), fmt = '%.6g'; end
            if nargin < 4 || isempty(mode), mode = 'float'; end
            try
                if isnumeric(val) || islogical(val)
                    if isempty(val)
                        txt = '--';
                    elseif isscalar(val)
                        switch lower(char(mode))
                            case 'hex'
                                txt = app.integerLikeToHex(val);
                            case {'bitmap', 'bit', 'bits'}
                                txt = app.integerLikeToBits(val);
                            otherwise
                                txt = sprintf(fmt, val);
                        end
                    else
                        txt = mat2str(val);
                    end
                elseif isstring(val)
                    txt = char(val);
                elseif ischar(val)
                    txt = val;
                elseif isdatetime(val) || isduration(val)
                    txt = char(val);
                else
                    txt = char(string(val));
                end
            catch
                try
                    if isnumeric(val) && isscalar(val)
                        txt = sprintf('%.6g', val);
                    else
                        txt = char(string(val));
                    end
                catch
                    txt = '--';
                end
            end
        end

        function txt = plotValueLabelText(app, name, val, fmt)
            if nargin < 4 || isempty(fmt), fmt = '%.6g'; end
            txt = sprintf('%s: %s', char(name), app.formatInfoValue(val, fmt, 'float'));
        end

        function mode = infoFormatModeForHeader(app, fIdx, header)
            mode = 'float';
            try
                key = app.infoFormatKey(header);
                modes = app.infoFormatStruct(fIdx);
                if isfield(modes, key) && ~isempty(modes.(key))
                    mode = char(modes.(key));
                end
            catch
                mode = 'float';
            end
        end

        function key = infoFormatKey(app, header)
            key = ['v_' app.normalizeHeaderName(header)];
            if strcmp(key, 'v_'), key = 'v_value'; end
        end

        function txt = integerLikeToHex(~, val)
            try
                n = round(double(val));
                if ~isfinite(n), txt = '--'; return; end
                if n < 0
                    txt = ['-0x' dec2hex(uint64(abs(n)))];
                else
                    txt = ['0x' dec2hex(uint64(n))];
                end
            catch
                txt = '--';
            end
        end

        function txt = integerLikeToBits(~, val)
            try
                n = round(double(val));
                if ~isfinite(n), txt = '--'; return; end
                if n < 0
                    txt = ['-0b' dec2bin(uint64(abs(n)))];
                else
                    txt = ['0b' dec2bin(uint64(n))];
                end
            catch
                txt = '--';
            end
        end

        function updateAttitudeGauges(app, fIdx, index)
            try
                if fIdx < 1 || fIdx > numel(app.Models), return; end
                if isempty(app.Models(fIdx).rawData), return; end
                required = {'Pitch', 'Roll', 'Heading'};
                for k = 1:numel(required)
                    if ~isfield(app.Models(fIdx).mappedCols, required{k})
                        return;
                    end
                end

                nRows = height(app.Models(fIdx).rawData);
                if nRows < 1, return; end
                index = max(1, min(nRows, round(index)));

                pitch = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Pitch)(index);
                roll = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Roll)(index);
                hdg = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Heading)(index);
                deg = char(176);

                if isfield(app.UI(fIdx), 'pitchLabel') && ~isempty(app.UI(fIdx).pitchLabel) && isvalid(app.UI(fIdx).pitchLabel)
                    app.UI(fIdx).pitchLabel.Text = sprintf(['Pitch %+.3f' deg], pitch);
                end
                if isfield(app.UI(fIdx), 'rollLabel') && ~isempty(app.UI(fIdx).rollLabel) && isvalid(app.UI(fIdx).rollLabel)
                    app.UI(fIdx).rollLabel.Text = sprintf(['Roll %+.3f' deg], roll);
                end
                if isfield(app.UI(fIdx), 'hdgLabel') && ~isempty(app.UI(fIdx).hdgLabel) && isvalid(app.UI(fIdx).hdgLabel)
                    app.UI(fIdx).hdgLabel.Text = sprintf(['Heading %+.3f' deg], hdg);
                end

                if isfield(app.UI(fIdx), 'hgPitch') && ~isempty(app.UI(fIdx).hgPitch) && isvalid(app.UI(fIdx).hgPitch)
                    set(app.UI(fIdx).hgPitch, 'Matrix', makehgtform('zrotate', -pitch * pi / 180));
                end
                if isfield(app.UI(fIdx), 'hgRoll') && ~isempty(app.UI(fIdx).hgRoll) && isvalid(app.UI(fIdx).hgRoll)
                    set(app.UI(fIdx).hgRoll, 'Matrix', makehgtform('zrotate', -roll * pi / 180));
                end
                if isfield(app.UI(fIdx), 'hgHdg') && ~isempty(app.UI(fIdx).hgHdg) && isvalid(app.UI(fIdx).hgHdg)
                    set(app.UI(fIdx).hgHdg, 'Matrix', makehgtform('zrotate', -hdg * pi / 180));
                end
            catch ME
                app.logCaught(ME, 'AttitudeGauges:update');
            end
        end

        function updateDashboard(app, fIdx, index)
            if isempty(app.Models(fIdx).rawData), return; end

            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(index);
            app.UI(fIdx).currentTimeLabel.Text = sprintf('%.3f s', currTime);

            app.updateCurrentInfoTable(fIdx, index);

            % Spatial
            pathLon = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lon);
            pathLat = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lat);
            currLon = pathLon(1:index);
            currLat = pathLat(1:index);

            % [PERF] NaN 전처리 → 직접 set
            set(app.UI(fIdx).hMapPath, 'XData', currLon, 'YData', currLat);

            hdg = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Heading)(index);
            roll = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Roll)(index);
            pitch = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Pitch)(index);

            lastValid = find(~isnan(currLon) & ~isnan(currLat), 1, 'last');
            if ~isempty(lastValid)
                T_map = makehgtform('translate', [currLon(lastValid), currLat(lastValid), 0]) * makehgtform('zrotate', -hdg * pi / 180);
                set(app.UI(fIdx).hgMapPlane, 'Matrix', T_map);
            end

            times = app.Models(fIdx).rawData.(timeCol);
            alts = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Alt);

            set(app.UI(fIdx).hAltPath, 'XData', times(1:index), 'YData', alts(1:index));
            set(app.UI(fIdx).hAltMarker, 'XData', times(index), 'YData', alts(index));
            app.UI(fIdx).timeLine.Value = times(index);

            app.updateAttitudeGauges(fIdx, index);

            % [V3.12 2.2.3] 비디오 동기 설정 시 Frame No 기반 갱신 (정확한 매핑)
            if app.VideoSyncState(fIdx).IsSynced
                try
                    targetFrame = app.timeToFrame(fIdx, currTime);
                    app.VideoSyncState(fIdx).CurrentFrame = targetFrame;
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);
                    app.updateVideoFrameByFrameNo(fIdx, targetFrame, 'sync');  % 정확한 동기화
                catch
                    app.updateVideoFrame(fIdx, currTime);  % 폴백
                end
            else
                % app.updateVideoFrame(fIdx, currTime);  % <--- 이 줄을 주석 처리하여 완전 분리
            end
            app.updatePlotTimeLines(fIdx, index, currTime);
            app.LayoutMgr.updatePanelRailSummaries(app, fIdx);

            drawnow limitrate;
        end
    end

    % =========================================================================
    % UI 레이아웃 생성 팩토리 (Create Layout)
    % =========================================================================
    methods (Access = public)
        function createLayout(app)
            % [REFACTOR Step 3] 메인 골격 + 채널별 빌드는 view 패키지로 위임
            % - 헤더: buildHeaderBar (기존 유지)
            % - 채널: flightdash.view.ChannelLayout.build (6컬럼 위임)
            % [PHASE 3b] Layout parent is RootContainer:
            %   standalone -> UIFigure
            %   embedded   -> the parent uitab/uipanel from Studio
            mainLayout = uigridlayout(app.RootContainer, [2 1]);
            app.LayoutHandles.mainLayout = mainLayout;
            mainLayout.RowHeight = {'fit', '1x'};
            mainLayout.Padding = [2 2 2 2];
            mainLayout.RowSpacing = 2;

            app.buildHeaderBar(mainLayout);

            scrollBody = uipanel(mainLayout, 'Scrollable', 'on', ...
                'BorderType', 'none', 'BackgroundColor', [0.94 0.94 0.96]);
            app.LayoutHandles.scrollBody = scrollBody;
            bodyGrid = uigridlayout(scrollBody, [2 1]);
            app.LayoutHandles.bodyGrid = bodyGrid;
            bodyGrid.ColumnWidth = {'1x'};
            bodyGrid.RowHeight = {'1x', '1x'};
            try, bodyGrid.Scrollable = 'on'; catch, end
            bodyGrid.Padding = [2 2 2 2];
            bodyGrid.RowSpacing = 5;

            titleStrs = {'Flight Data 1', 'Flight Data 2'};
            panelColors = {[0.98 0.98 0.98], [0.98 0.98 0.98]};

            UI_temp = struct([]);
            for fIdx = 1:2
                ui_f = flightdash.view.ChannelLayout.build( ...
                    bodyGrid, fIdx, titleStrs{fIdx}, panelColors{fIdx});
                if isempty(UI_temp)
                    UI_temp = ui_f;
                else
                    UI_temp(fIdx) = ui_f;
                end
            end

            linkaxes([UI_temp(1).mapAxes, UI_temp(2).mapAxes], 'xy');
            app.UI = UI_temp;

            app.buildUIGroups();
            app.LayoutMgr.applyLayout(app, 'createLayout');
        end

        % [V3.22 #5] 평면 UI struct를 그룹화된 view(struct)로 묶어 별도 속성에 저장
        % - app.UIGroup(fIdx).attitude.rollAxes = app.UI(fIdx).rollAxes  (alias)
        % - 새 코드는 app.UIGroup(...) 경로를 권장; 기존 코드는 app.UI(...) 그대로
        function buildUIGroups(app)
            % [V3.22 #5] 평면 UI struct를 그룹화된 view(struct array, 1x2)로 묶음
            UIGroup_temp = struct([]);
            for fIdx = 1:2
                u = app.UI(fIdx);
                grp = struct();

                % 자세(Attitude) 그룹
                grp.attitude = struct( ...
                    'panel',      u.panelAttitude, ...
                    'pitchAxes',  u.pitchAxes,  'pitchLabel', u.pitchLabel, 'hgPitch', app.uiFieldOr(u, 'hgPitch', gobjects(0)), ...
                    'rollAxes',   u.rollAxes,   'rollLabel',  u.rollLabel,  'hgRoll',  app.uiFieldOr(u, 'hgRoll',  gobjects(0)), ...
                    'hdgAxes',    u.hdgAxes,    'hdgLabel',   u.hdgLabel,   'hgHdg',   app.uiFieldOr(u, 'hgHdg',   gobjects(0)));

                grp.map = struct( ...
                    'panel',      u.panelMapAlt, ...
                    'mapAxes',    u.mapAxes, ...
                    'altAxes',    u.altAxes, ...
                    'hMapPath',   app.uiFieldOr(u, 'hMapPath',   gobjects(0)), ...
                    'hgMapPlane', app.uiFieldOr(u, 'hgMapPlane', gobjects(0)), ...
                    'hAltPath',   app.uiFieldOr(u, 'hAltPath',   gobjects(0)), ...
                    'hAltMarker', app.uiFieldOr(u, 'hAltMarker', gobjects(0)), ...
                    'timeLine',   app.uiFieldOr(u, 'timeLine',   gobjects(0)), ...
                    'altXLimListener', app.uiFieldOr(u, 'altXLimListener', []));

                % 비디오 + Frame Navigator 그룹
                grp.video = struct( ...
                    'panel',           u.panelVideo, ...
                    'vidAxes',         u.vidAxes, ...
                    'imageHandle',     u.vidImageHandle, ...
                    'syncFrameInput',  u.vidSyncFrameInput, ...
                    'syncTimeInput',   u.vidSyncTimeInput, ...
                    'syncBtn',         u.vidSyncBtn, ...
                    'syncStatus',      u.vidSyncStatus, ...
                    'videoFpsInput',   u.vidVideoFpsInput, ...
                    'dataFpsInput',    u.vidDataFpsInput, ...
                    'cacheBudget',     u.vidCacheBudget, ...
                    'vdubSlider',      u.vidVdubSlider, ...
                    'vdubLabel',       u.vidVdubLabel, ...
                    'frameAxes',       app.uiFieldOr(u, 'vidFrameAxes',   gobjects(0)), ...
                    'frameXLine',      app.uiFieldOr(u, 'vidFrameXLine',  gobjects(0)), ...
                    'frameMarker',     app.uiFieldOr(u, 'vidFrameMarker', gobjects(0)));

                grpPlots = struct();
                grpPlots.tabGroup       = u.tabGroup;
                grpPlots.plotTabs       = u.plotTabs;
                grpPlots.plotLayouts    = u.plotLayouts;
                grpPlots.plotAxes       = u.plotAxes;
                grpPlots.timeLines      = u.timeLines;
                grpPlots.timeMarkers    = u.timeMarkers;
                grpPlots.plotData       = u.plotData;
                grpPlots.plotMeta       = app.uiFieldOr(u, 'plotMeta', cell(1, flightdash.util.AppConstants.MAX_TABS));
                grpPlots.xLimListeners  = u.xLimListeners;
                grpPlots.managerTable   = app.uiFieldOr(u, 'plotManagerTable', gobjects(0));
                grpPlots.detailsPanel   = app.uiFieldOr(u, 'plotDetailsPanel', gobjects(0));
                grpPlots.pannerAxes     = app.uiFieldOr(u, 'pannerAxes', gobjects(0));
                grpPlots.modeAxes       = app.uiFieldOr(u, 'modeAxes', gobjects(0));
                grpPlots.roiTable       = app.uiFieldOr(u, 'roiTable', gobjects(0));
                grp.plots = grpPlots;

                grp.controls = struct( ...
                    'spinner',          u.spinner, ...
                    'currentTimeLabel', u.currentTimeLabel, ...
                    'fileNameLabel',    u.fileNameLabel, ...
                    'btnAtt',           u.btnAtt, ...
                    'btnMap',           u.btnMap, ...
                    'btnVid',           u.btnVid);

                grp.data = struct( ...
                    'panel',     u.panel, ...
                    'dataTable', u.dataTable, ...
                    'dataGrid',  u.dataGrid);

                if isempty(UIGroup_temp)
                    UIGroup_temp = grp;
                else
                    UIGroup_temp(fIdx) = grp; %#ok<AGROW>
                end
            end
            app.UIGroup = UIGroup_temp;
        end

        function val = uiFieldOr(~, u, fieldName, defaultVal)
            if isfield(u, fieldName)
                val = u.(fieldName);
            else
                val = defaultVal;
            end
        end

        % [V3.22 #7] 메인 윈도우 상단 헤더 바 (파일 선택 / Debug / Sync 입력)
        % - createLayout에서 분리하여 헤더 영역 변경이 메인 빌더에 영향 없도록 함
        function buildHeaderBar(app, mainLayout)
            % [REFACTOR Step 6-1] flightdash.view.HeaderBar로 위임
            % [PHASE 3c] Pass app reference so HeaderBar buttons can
            % bypass the singleton EventBus and target only THIS
            % dashboard. Without this, multi-session Studio embeds
            % broadcast Flight/Coast/Sync clicks to every dashboard.
            % Fallback to the legacy 1-arg signature so older cached
            % copies of HeaderBar do not break dashboard construction.
            try
                ui = flightdash.view.HeaderBar.build(mainLayout, app);
            catch ME
                if strcmp(ME.identifier, 'MATLAB:TooManyInputs')
                    warning('FlightDataDashboard:LegacyHeaderBar', ...
                        ['flightdash.view.HeaderBar.build does not accept ' ...
                         'an app argument. Multi-session Studio embeds may ' ...
                         'broadcast button clicks. Refresh HeaderBar.m and ' ...
                         'run "clear classes" to enable scoped callbacks.']);
                    ui = flightdash.view.HeaderBar.build(mainLayout);
                else
                    rethrow(ME);
                end
            end
            app.LayoutHandles.header = ui;
            app.SyncInput = ui.SyncInput;
            app.SyncBtn   = ui.SyncBtn;
        end

        %            (View가 자체 게이지 구성 - app 의존 완전 제거)
    end

    % [REFACTOR Step 5-C] 이전 Static wrapper(workerDecodeFrame/workerCleanupCache)는
    % 사용처 0 → 완전 제거. parfeval은 이제 file-level 함수를 직접 참조:
    %   parfeval(pool, @asyncDecodeFramePersistent, ...)
    %   parfevalOnAll(pool, @cleanupAsyncDecodeCache, 0)
end

% =========================================================================
% [REFACTOR Step 5-B] file-level worker 함수는 별도 .m 파일로 분리됨:
%   - asyncDecodeFrame.m
%   - asyncDecodeFramePersistent.m  (parfeval worker 핫패스)
%   - cleanupAsyncDecodeCache.m
% =========================================================================
