classdef FlightDataDashboard < matlab.apps.AppBase
    % =========================================================================
    % 비행 데이터 리뷰 대시보드 - V3.22 (리팩토링: 모듈 분해 + 캐시 자료구조 개선)
    % 설명: 
    %   [V3.22 변경사항]
    %   - #1 ErrorLog ring buffer (silent catch도 사후 조사 가능)
    %        + dumpErrorLog(n, filterTag) 헬퍼 메서드
    %   - #2 cacheGetFrame을 lastUse 카운터 기반 O(1) lookup으로 전환
    %        (cell 배열 reference shuffle 제거 → 큰 프레임 lookup 시 GC 압력 감소)
    %        cacheStoreFrame은 in-place 갱신 + lastUse 동기 관리
    %        evictByScore에 lastUse 인자 추가 → score = (hits * recency) / bytes
    %   - #3 loadAviFile을 6개 헬퍼로 분해:
    %        confirmVideoReplace / invalidateFrameCache / computeStartTimeFromFlightData
    %        cleanupVideoResources / openVideoReader / applyVideoLoadedUI
    %        computeTotalFrames / loadFirstFrame
    %   - #4 매직 넘버 상수화: ASYNC_WORKER_COUNT, WORKER_VR_CACHE_SLOTS,
    %        MAX_SEQ_READ_STEP, MAX_PENDING_ITERS
    %   - #5 UIGroup alias: 평면 UI struct를 attitude/map/video/plots/controls/data
    %        로 그룹화. 기존 평면 필드는 그대로 유지(100% 호환), 신규 코드는 그룹 사용
    %   - #6 Static wrapper: workerDecodeFrame / workerCleanupCache
    %        → 향후 +flightdash 패키지 마이그레이션 옵션 확보
    %   - #7 createLayout 분해: buildHeaderBar 추출 + 비행경로 루프 섹션 가이드 추가
    %
    %   [V3.21 #1-A] Generation counter (AsyncGen): 매 startAsyncDecode 호출 시
    %     증가, future에 myGen 캡처 → onAsyncDecodeComplete에서 비교하여 stale
    %     결과 폐기. 같은 frame이라도 generation mismatch면 무시 → race 차단.
    %   [V3.21 #3-A] 3계층 분리:
    %     Layer 1 requestFrame: 진입점 + 캐시 lookup + sync/async 전략 선택
    %     Layer 2 decodeFrameSync / startAsyncDecode: 디코딩 (전략 패턴)
    %     Layer 3 displayFrame: 표시 + 캐시 store (write-through 단일 출구)
    %     기존 updateVideoFrameByFrameNo는 requestFrame로 위임 (호환).
    %   [V3.21 #2-A] persistent VideoReader in worker:
    %     asyncDecodeFramePersistent 외부 함수에서 persistent 변수로 VR 재사용
    %     → 호출당 ~50ms→3ms로 단축. 파일 변경 시에만 VR 재생성.
    %   [V3.20 유지] 명시적 리소스 정리, 동기화 로그 prefix 표준화.
    %   [V3.19 유지] 비동기 디코딩, adaptive prefetch, 가중 LRU.
    %   [V3.18 유지] cache lookup clamp, Pending 완전 소진, hard limit 1.0.
    %   [V3.17 유지] InGoToFrame coalescing, IsDecoding 가드.
    % =========================================================================

    % Shared constants live in flightdash.util.AppConstants.

    properties (Access = public)
        UIFigure          
        UI                
        UIGroup           % [V3.22 #5] UI를 attitude/map/video/plots/controls/data로 그룹화한 alias
        SyncInput         
        SyncBtn           
        
        Models            
        SyncState         
        VideoState        
        VideoSyncState    % [V3.12] 비디오-비행데이터 동기화 정보 (배열 [1x2])
        
        CoastlineData     
        FixedAreaBounds   
        
        DebugMode         = false   % [V3.14 항목 6] true 시 zoom/pan off 등 로그 출력
        State             = 'IDLE'  % [V3.17 (8)] 'IDLE' | 'DRAGGING' | 'UPDATING' | 'DECODING'
        UseAsyncDecode    = false   % [V3.19 (1)] 비동기 디코딩 활성화 (Parallel Toolbox 필요)
    end

    properties (Access = private)
        IsUpdating          = [false, false] % 재귀 방지 플래그
        IsDraggingMarker    = false         % 마커 드래그 상태 플래그
        DraggedMarker       = []            % 현재 드래그 중인 그래픽 객체 핸들
        IsProgrammaticXLim  = [false, false] % [V3.11 A] 책장 넘기기 등 프로그래밍 XLim 변경 시 리스너 차단
        DraggedFIdx         = 0             % [V3.11 B] 드래그 중인 fIdx
        DraggedFromVideo    = false         % [V3.12] 비디오 Frame 마커에서 드래그 시작 여부
        VideoThrottleDyn    = 0.05          % [V3.12] (V3.13에서 미사용, 보존)
        LastDragTime        = {uint64(0), uint64(0)}  % [PATCH] 채널별 tic 핸들
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
        VideoListeners      = {[], []}        % [REFACTOR Step 2-C] event.listener 핸들 보관 (GC 방지)
        % [REFACTOR Step 4] 콜백 진입점 컨트롤러
        FileCtrl            = []
        VideoSyncCtrl       = []
        PlaybackCtrl        = []
        PanelCtrl           = []
        DragCtrl            = []
        CacheBudgetMB       = 30              % [V3.14 항목 3] 호환 유지: setCacheBudget 진입점이 사용
        % --- 비-캐시 속성 (그대로 유지) ---
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
        % [REFACTOR Step 0] ErrorLog는 flightdash.util.ErrorLog 싱글톤으로 위임
        % - 기존 ErrorLog/ErrorLogCapacity 속성은 더 이상 사용하지 않으나 호환을 위해 유지하지 않고 제거
    end

    methods (Access = public)
        % ---------------------------------------------------------------------
        % 생성자 및 초기화
        % ---------------------------------------------------------------------
        function app = FlightDataDashboard()
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
            
            % [REFACTOR Step 1] FrameCacheModel 인스턴스 생성 (채널별 1개씩)
            app.CacheModel = [flightdash.model.FrameCacheModel(app.CacheBudgetMB), ...
                              flightdash.model.FrameCacheModel(app.CacheBudgetMB)];
            
            % [REFACTOR Step 2] VideoModel/SyncModel 인스턴스 생성 (채널별 1개씩)
            app.VideoMdl = [flightdash.model.VideoModel(), flightdash.model.VideoModel()];
            app.SyncMdl  = [flightdash.model.SyncModel(),  flightdash.model.SyncModel()];
            
            app.CoastlineData = [];
            app.FixedAreaBounds = [];
            
            if isfile('option_flight_area.dat')
                try
                    areaData = readmatrix('option_flight_area.dat');
                    if size(areaData, 2) >= 2
                        app.FixedAreaBounds = struct('minLat', min(areaData(:,1)), 'maxLat', max(areaData(:,1)), ...
                                                     'minLon', min(areaData(:,2)), 'maxLon', max(areaData(:,2)));
                    end
                catch e
                    disp(['option_flight_area.dat 로드 실패: ', e.message]);
                end
            end
            
            close(findobj('Type', 'figure', 'Name', '비행 데이터 리뷰 대시보드 (Dual)'));
            % [FIX] AutoResizeChildren='on' 시 SizeChangedFcn이 무시되는 경고 차단
            % - uigridlayout이 자식 리사이즈를 담당하므로 AutoResizeChildren은 불필요
            app.UIFigure = uifigure('Name', '비행 데이터 리뷰 대시보드 (Dual)', ...
                                    'Units', 'normalized', ...
                                    'Position', [0.05, 0.05, 0.9, 0.9], ...
                                    'Color', [0.94 0.94 0.96]);
            try
                app.UIFigure.AutoResizeChildren = 'off';
            catch ME
                app.logCaught(ME, 'UI:AutoResizeChildren');
            end
            app.UIFigure.CloseRequestFcn = @app.UIFigureCloseRequest;
            app.UIFigure.SizeChangedFcn = @(~,~) app.onUIFigureResized();
            
            % [REFACTOR Step 4] 컨트롤러 인스턴스 (createLayout 전 필수)
            app.FileCtrl      = flightdash.controller.FileController(app);
            app.VideoSyncCtrl = flightdash.controller.VideoSyncController(app);
            app.PlaybackCtrl  = flightdash.controller.PlaybackController(app);
            app.PanelCtrl     = flightdash.controller.PanelToggleController(app);
            app.DragCtrl      = flightdash.controller.DragController(app);
            
            app.createLayout();
            
            for i = 1:2
                app.addPlotTab(i);
                app.VideoState(i).vidImageHandle = app.UI(i).vidImageHandle;
                % [REFACTOR Step 2-B] VideoModel에도 핸들 set
                app.VideoMdl(i).ImageHandle = app.UI(i).vidImageHandle;
                % [REFACTOR Step 2-C] 이벤트 구독: VideoLoaded → cache recompute, VideoCleared → invalidate
                app.VideoListeners{i} = { ...
                    addlistener(app.VideoMdl(i), 'VideoLoaded',  @(src,~) app.onVideoLoaded(i, src)), ...
                    addlistener(app.VideoMdl(i), 'VideoCleared', @(~,~)   app.onVideoCleared(i)) };
            end
        end
        
        function delete(app)
            % [FIX] 중복 진입 방어 - CloseRequestFcn → delete → 소멸 중 재호출 차단
            if app.IsDeleting, return; end
            app.IsDeleting = true;
            % [V3.20 (5)] 명시적 리소스 정리: VideoReader, AsyncPool, futures
            try
                for fIdx = 1:2
                    % [FIX] Future cancel을 VR delete보다 먼저 → worker hang 방지
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
                % - EventBus는 persistent 싱글톤이라 listener가 controller를 영구 보유
                % - delete(ctrl) 호출 → controller.delete() → Listeners cell 정리
                % - 단순 [] 대입은 listener leak 발생 → 다음 실행 시 좀비 controller crash
                try, delete(app.FileCtrl);      catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.VideoSyncCtrl); catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PlaybackCtrl);  catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.PanelCtrl);     catch ME, app.logCaught(ME, 'silent'); end
                try, delete(app.DragCtrl);      catch ME, app.logCaught(ME, 'silent'); end
                app.FileCtrl      = [];
                app.VideoSyncCtrl = [];
                app.PlaybackCtrl  = [];
                app.PanelCtrl     = [];
                app.DragCtrl      = [];
            catch ME, app.logCaught(ME, 'silent'); end
            
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
                        % [FIX] timeout 시 pending future cancel (worker hang 차단)
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
            
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch ME, app.logCaught(ME, 'silent'); end
        end
        
        function model = createEmptyModel(~)
            model = struct('rawData', table(), 'mappedCols', struct(), 'displayMeta', struct(), ...
                           'bounds', struct('minLat',0, 'maxLat',0, 'minLon',0, 'maxLon',0, 'isValid', false), ...
                           'altBounds', struct('minAlt',0, 'maxAlt',0), ...
                           'currentIndex', 1, 'selectedRow', 1, 'isMockData', false);
        end
    end

    % =========================================================================
    % 시간 변경 단일 진입점 (동기화/업데이트/재귀방지를 한 곳에서 처리)
    % =========================================================================
    methods (Access = private)
        function applyTimeChange(app, fIdx, index)
            if app.IsUpdating(fIdx), return; end
            if isempty(app.Models(fIdx).rawData), return; end
            
            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(index);
            app.Models(fIdx).currentIndex = index;
            
            % --- 해당 경로 뷰 갱신 ---
            % [FIX] IsUpdating 플래그를 onCleanup으로 보장 - 예외/return/error 모두 안전
            app.IsUpdating(fIdx) = true;
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
            
            % --- 동기화: 경로 1 변경 시 경로 2도 연동 ---
            if app.SyncState.IsSynced && fIdx == 1 && ~isempty(app.Models(2).rawData)
                targetT2 = app.SyncState.SyncT2 + (currTime - app.SyncState.SyncT1);
                
                timeCol2 = app.Models(2).mappedCols.Time;
                idx2 = app.findClosestIndexByTime(app.Models(2).rawData.(timeCol2), targetT2);
                
                if ~isequal(app.Models(2).currentIndex, idx2)
                    app.applyTimeChange(2, idx2); 
                end
            end
        end
        
        function resetIsUpdating(app, fIdx)
            % [FIX] applyTimeChange의 IsUpdating 플래그 리셋 (onCleanup 콜백)
            try
                if isvalid(app), app.IsUpdating(fIdx) = false; end
            catch
            end
        end
        
        function resetInCascade(app)
            % [FIX] updateMarkersOnly의 InCascade 플래그 리셋 (onCleanup 콜백)
            try
                if isvalid(app), app.InCascade = false; end
            catch
            end
        end
    end

    % =========================================================================
    % Controller/EventBus 진입점 및 메인 UI 로직
    % =========================================================================
    methods (Access = public)
        function handleFlightFile(app, fIdx)
            [filename, pathname] = uigetfile('*.csv', sprintf('비행경로 %d 파일 선택', fIdx));
            if isequal(filename, 0), return; end 
            
            % [V3.12] 기존 비디오 동기 설정이 있으면 사용자 확인 후 해제
            if app.VideoSyncState(fIdx).IsSynced
                sel = uiconfirm(app.UIFigure, ...
                    '새 비행데이터를 로드하면 기존 비디오-비행데이터 동기 설정이 해제됩니다. 계속하시겠습니까?', ...
                    '동기 해제 확인', ...
                    'Options', {'계속', '취소'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(sel, '취소'), return; end
                app.resetVideoSync(fIdx);
            end
            
            d = uiprogressdlg(app.UIFigure, 'Title', '데이터 로딩 중', ...
                'Message', sprintf('비행경로 %d 데이터를 파싱하고 있습니다...', fIdx), ...
                'Indeterminate', 'on');
            try
                fullpath = fullfile(pathname, filename);
                app.parseFlightData(fIdx, fullpath);
                
                timeCol = app.Models(fIdx).mappedCols.Time;
                if ~issorted(app.Models(fIdx).rawData.(timeCol), 'strictascend')
                    errordlg('시간 데이터가 순차적으로 증가하지 않거나 중복되었습니다.', '데이터 오류'); 
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
                
                % [수정 2] 비행 데이터 파싱 후, 이미 영상이 열려있다면 Video FPS 강제 재계산
                % [FIX Case 2] 자동 동기(IsSynced=true) 제거 - "동기" 버튼 클릭 시에만 활성화
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
                errordlg(['오류 발생: ', e.message], '오류'); 
            end
        end
        
        function handleCoastFile(app)
            [filename, pathname] = uigetfile('*.csv', '해안선 정보 파일 선택');
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
                errordlg(['오류 발생: ', e.message], '오류'); 
            end
        end

        function handleSpinnerChange(app, fIdx, newTime)
            if isempty(app.Models(fIdx).rawData), return; end
            if app.IsUpdating(fIdx), return; end 
            
            timeCol = app.Models(fIdx).mappedCols.Time;
            idx = app.findClosestIndexByTime(app.Models(fIdx).rawData.(timeCol), newTime);
            
            if isequal(app.Models(fIdx).currentIndex, idx), return; end
            
            app.applyTimeChange(fIdx, idx);
        end

        function handleTableSelection(app, fIdx, event)
            if ~isempty(event.Indices)
                app.Models(fIdx).selectedRow = event.Indices(1, 1); 
            end
        end

        function UIFigureCloseRequest(app, ~, ~)
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = ''; 
                    app.UIFigure.WindowButtonUpFcn = ''; 
                end
                % [FIX] drag/splitter 상태 명시 클리어 (close 중 stale callback 차단)
                app.IsDraggingSplitter = false;
                app.DraggedMarker      = [];
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
            try
                delete(app);
            catch ME
                app.logCaught(ME, 'CloseRequest:delete');
                try
                    if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                        delete(app.UIFigure);
                    end
                catch ME_ui
                    app.logCaught(ME_ui, 'CloseRequest:forceFigureDelete');
                end
            end
        end

        function togglePanel(app, fIdx, pnlName)
            % 패널 표시/숨김 토글 (픽셀 고정 기반 리사이징)
            state = app.UI(fIdx).PanelVisible.(pnlName);
            newState = ~state;
            app.UI(fIdx).PanelVisible.(pnlName) = newState;
            
            widths = app.UI(fIdx).dataGrid.ColumnWidth;
            
            UIScale = flightdash.util.UIScale;   % DPI 스케일 헬퍼
            if strcmp(pnlName, 'attitude')
                app.UI(fIdx).panelAttitude.Visible = newState;
                if newState
                    widths{1} = UIScale.px(200); % DPI 스케일 적용 복구
                    app.UI(fIdx).btnAtt.Text = '자세 ▾';
                else
                    widths{1} = 0;
                    app.UI(fIdx).btnAtt.Text = '자세 ▸';
                end
            elseif strcmp(pnlName, 'map')
                app.UI(fIdx).panelMapAlt.Visible = newState;
                if newState
                    widths{2} = UIScale.px(500); % DPI 스케일 적용 복구
                    app.UI(fIdx).btnMap.Text = '지도/고도 ▾';
                else
                    widths{2} = 0;
                    app.UI(fIdx).btnMap.Text = '지도/고도 ▸';
                end
            elseif strcmp(pnlName, 'video')
                app.UI(fIdx).panelVideo.Visible = newState;
                if newState
                    % [V3.12 2.1] 영상 로드되어 있으면 영상 비율 기반 너비 사용
                    targetWidth = UIScale.px(500);  % 기본값
                    try
                        if ~isempty(app.VideoState(fIdx).videoReader)
                            vr = app.VideoState(fIdx).videoReader;
                            if vr.Height > 0
                                aspectRatio = vr.Width / vr.Height;
                                % 디자인 기준값(280, 100, 400~900)에 DPI 스케일 적용
                                targetWidth = UIScale.px(round(280 * aspectRatio) + 100);
                                targetWidth = max(UIScale.px(400), min(targetWidth, UIScale.px(900)));
                            end
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                    widths{6} = app.constrainVideoPanelWidth(fIdx, targetWidth); % 5를 6으로 수정
                    app.UI(fIdx).btnVid.Text = '비디오 ▾';
                else
                    widths{6} = 0;           % 5를 6으로 수정
                    app.UI(fIdx).btnVid.Text = '비디오 ▸';
                end
            end
            app.UI(fIdx).dataGrid.ColumnWidth = widths;
        end

        % ---------------------------------------------------------------------
        % 비디오 및 동기화
        % ---------------------------------------------------------------------
        function toggleSync(app)
            if app.SyncState.IsSynced
                app.SyncState.IsSynced = false;
                app.SyncBtn.Text = '비행시간 동기'; 
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
                errordlg('입력 형식이 올바르지 않습니다. 예: "23.4, 34.4"', '형식 오류'); 
                return; 
            end
            if isempty(app.Models(1).rawData) || isempty(app.Models(2).rawData)
                errordlg('두 경로 데이터가 모두 로드되어야 합니다.', '데이터 부족'); 
                return; 
            end

            t1 = str2double(tokens{1}{1}); 
            t2 = str2double(tokens{1}{2});
            app.SyncState.SyncT1 = t1;
            app.SyncState.SyncT2 = t2;
            app.SyncState.IsSynced = true;
            
            app.SyncBtn.Text = '비행시간 동기 해제'; 
            app.SyncBtn.BackgroundColor = [0.8 0.2 0.2]; 
            app.SyncInput.Enable = 'off'; 
            app.UI(2).spinner.Enable = 'off';

            timeCol1 = app.Models(1).mappedCols.Time;
            idx1 = app.findClosestIndexByTime(app.Models(1).rawData.(timeCol1), t1);
            app.applyTimeChange(1, idx1);
            
            % [V3.20 (2)] 동기화 디버그 로그 (SyncState - 두 비행데이터 시간축 매핑)
            if app.DebugMode
                fprintf('[FlightSync] enabled: T1=%.3fs ↔ T2=%.3fs (offset=%.3fs)\n', ...
                    t1, t2, t2 - t1);
            end
        end

        % [V3.22 #3] loadAviFile 분해 - 오케스트레이터 + 6단계 헬퍼
        % 단계: 1) 사용자 확인 → 2) 캐시 무효화 → 3) 기존 자원 정리
        %       4) VR 생성 → 5) TotalFrames + UI 동기화 → 6) 첫 프레임 로드
        % 각 단계는 실패 시 명확한 종료 조건을 가지며 책임이 한정됨
        %
        % [기술적 권장사항] 원활한 스크러빙(슬라이더 임의 이동) 성능을 위해
        % All-Intra 포맷 사용 권장:
        %   - 권장: AVI (Motion JPEG / Uncompressed), MP4 (All-Intra)
        %   - 비권장: H.264/H.265 Long-GOP MP4
        % Long-GOP 영상은 임의 위치로 seek 시 가장 가까운 키프레임(I-Frame)부터
        % 다시 디코딩해야 하므로, 슬라이더 드래그 시 지연이 심해질 수 있음.
        function loadAviFile(app, fIdx)
            [fname, pname] = uigetfile({'*.avi;*.mp4;*.mkv', 'Video Files (*.avi, *.mp4)'}, sprintf('비디오 선택 %d', fIdx));
            if isequal(fname, 0), return; end
            fullPath = fullfile(pname, fname);
            
            % 1) 사용자 확인 (기존 동기 설정 해제)
            if ~app.confirmVideoReplace(fIdx), return; end
            
            % 2) 프레임 캐시 무효화
            app.invalidateFrameCache(fIdx);
            
            % 3) 기존 VR/Future 정리 + startTime 산출
            startTime = app.computeStartTimeFromFlightData(fIdx);
            app.cleanupVideoResources(fIdx);
            
            % 4) VideoReader 생성
            vr = app.openVideoReader(fIdx, fullPath, fname);
            if isempty(vr), return; end
            app.VideoState(fIdx).videoStartTime = startTime;
            app.VideoState(fIdx).videoReader.CurrentTime = 0;
            flightdash.util.Throttle.instance().reset('LastVideoUpdate', fIdx);
            
            % 5) TotalFrames 산정 + UI 위젯 동기화
            app.applyVideoLoadedUI(fIdx, vr);
            
            % 6) 첫 프레임 로드 + 표시 + 캐시 저장
            app.loadFirstFrame(fIdx);
        end
        
        % --------- loadAviFile 헬퍼들 (V3.22 #3) ---------
        
        % [V3.22 #3-1] 기존 동기 설정이 있을 때 사용자 확인 다이얼로그
        function ok = confirmVideoReplace(app, fIdx)
            ok = true;
            if app.VideoSyncState(fIdx).IsSynced
                sel = uiconfirm(app.UIFigure, ...
                    '새 영상을 로드하면 기존 비디오-비행데이터 동기 설정이 해제됩니다. 계속하시겠습니까?', ...
                    '동기 해제 확인', ...
                    'Options', {'계속', '취소'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(sel, '취소'), ok = false; return; end
                app.resetVideoSync(fIdx);
            end
        end
        
        % [V3.22 #3-2 / REFACTOR Step 1] 프레임 캐시 비우기 - CacheModel로 위임
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
            % Future를 먼저 무효화/취소한 뒤 reader를 닫아 파일락과 stale callback을 줄인다.
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
            try, app.VideoMdl(fIdx).cleanup(); catch ME, app.logCaught(ME, 'silent'); end
            app.VideoState(fIdx).videoReader   = [];
            app.VideoState(fIdx).videoStartTime = 0;
        end
        
        % [V3.22 #3-5] VideoReader 생성 (실패 시 errordlg + [] 반환)
        function vr = openVideoReader(app, fIdx, fullPath, fname)
            vr = [];
            try
                vr = VideoReader(fullPath);
                app.VideoState(fIdx).videoReader = vr;
                app.VideoFilePath{fIdx} = fullPath;
                % [REFACTOR Step 2-C] attachReader → VideoLoaded notify (cache 자동 recompute)
                app.VideoMdl(fIdx).attachReader(vr, fullPath, app.VideoState(fIdx).vidImageHandle);
                if app.DebugMode
                    fprintf('[Video] loaded: %s (fIdx=%d)\n', fname, fIdx);
                end
            catch e
                if app.DebugMode
                    fprintf('[Video] load failed: %s\n  %s\n', fullPath, e.message);
                end
                app.logCaught(e, 'Video:open');
                errordlg(['영상 로드 실패: ', e.message], '오류');
                vr = [];
            end
        end
        
        % [V3.22 #3-6] TotalFrames 산정 + 관련 UI 위젯/스피너/슬라이더 동기화
        function applyVideoLoadedUI(app, fIdx, vr)
            % [FIX] TotalFrames 계산은 항상 먼저, UI 갱신 3종은 독립 try로 도달 보장
            totalFrames = 0;
            try, totalFrames = app.computeTotalFrames(fIdx, vr); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:total'); end
            app.VideoSyncState(fIdx).TotalFrames = max(1, totalFrames);
            
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
                % [FIX Case 2] 자동 동기(IsSynced=true) 제거 - "동기" 버튼 클릭 시에만 활성화
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
            % [REFACTOR Step 2] VideoModel 위임 - vr는 호환용 override
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

                if app.UI(fIdx).PanelVisible.video
                    widths = app.UI(fIdx).dataGrid.ColumnWidth;
                    widths{6} = app.constrainVideoPanelWidth(fIdx, targetWidth);
                    app.UI(fIdx).dataGrid.ColumnWidth = widths;
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end
        
        function targetWidth = constrainVideoPanelWidth(app, fIdx, targetWidth)
            % H 데이터 패널 최소폭을 보존하도록 비디오 패널 자동 폭을 제한한다.
            % Splitter drag와 동일한 fixed column 산식으로 자동 리사이즈 경로도 보호.
            try
                dg = app.UI(fIdx).dataGrid;
                if isempty(dg) || ~isvalid(dg) || numel(dg.ColumnWidth) < 6, return; end
                cw = dg.ColumnWidth;
                gridPos = getpixelposition(dg, true);
                gridW = gridPos(3);
                
                fixedSum = 0;
                for k = [1 2 3 5]
                    v = cw{k};
                    if isnumeric(v), fixedSum = fixedSum + v; end
                end
                colSpacing = 0;
                try, colSpacing = dg.ColumnSpacing; catch, end
                fixedSum = fixedSum + colSpacing * max(0, numel(cw) - 1);
                
                UIScale = flightdash.util.UIScale;
                hMin = UIScale.px(320);
                maxVideoW = gridW - fixedSum - hMin;
                if maxVideoW <= 0
                    targetWidth = 0;
                    return;
                end
                videoMin = min(UIScale.px(280), maxVideoW);
                targetWidth = round(max(videoMin, min(maxVideoW, targetWidth)));
            catch ME
                app.logCaught(ME, 'VideoPanel:constrainWidth');
            end
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
        
        % [V3.14 항목 5] VideoReader 유효성 검사 헬퍼 (일관성 있는 가드)
        function tf = isVideoReady(app, fIdx)
            % [REFACTOR Step 2-B] VideoModel 위임
            tf = false;
            try
                if fIdx < 1 || fIdx > 2, return; end
                tf = app.VideoMdl(fIdx).isReady();
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
                if ~isempty(app.CacheModel) && fIdx <= numel(app.CacheModel)
                    app.CacheModel(fIdx).invalidate();
                end
            catch ME, app.logCaught(ME, 'silent'); end
        end
        
        % [V3.14 VirtualDub UI] Frame 슬라이더 범위 갱신 (영상 로드 시)
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
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end
        
        % [V3.15 항목 2 / V3.16 / V3.17 (1)(9)] goToFrame() - 단일 공식 진입점
        % - V3.16: InGoToFrame 재진입 가드 + onCleanup
        % - V3.17 (1)(9): coalescing - 처리 중 새 요청은 PendingFrame에 저장 후
        %                 현재 처리 완료 시 자동 흡수 (최신 frame 누락 방지)
        % - V3.17 (8): State = 'UPDATING' 표시
        function goToFrame(app, fIdx, frameNo, mode)
            if nargin < 4, mode = 'final'; end
            
            % [V3.17 (1)(9)] 처리 중이면 최신 요청을 Pending에 저장 후 종료
            % 현재 처리 완료 직전 coalescing 루프에서 자동 처리됨
            if app.InGoToFrame(fIdx)
                app.PendingFrame(fIdx) = frameNo;
                app.PendingMode{fIdx}  = mode;
                return;
            end
            
            app.InGoToFrame(fIdx) = true;
            app.State = 'UPDATING';
            cleanupObj = onCleanup(@() app.clearGoToFrameFlag(fIdx)); %#ok<NASGU>
            
            % 핵심 처리 루프 (coalescing 지원)
            app.processFrameInternal(fIdx, frameNo, mode);
            
            % [V3.17 (1)(9) / V3.18 (3) / V3.22 #4] Pending 완전 소진 루프
            % - break 대신 continue로 누적된 모든 Pending 처리
            % - MAX_PENDING_ITERS 안전망으로 무한 루프 방지
            maxIter = flightdash.util.AppConstants.MAX_PENDING_ITERS;
            iter = 0;
            while ~isnan(app.PendingFrame(fIdx)) && iter < maxIter
                pf = app.PendingFrame(fIdx);
                pm = app.PendingMode{fIdx};
                app.PendingFrame(fIdx) = NaN;
                app.PendingMode{fIdx}  = '';
                iter = iter + 1;
                % 같은 frame이라도 break 대신 continue → 다음 Pending 누적분 처리
                if pf == app.VideoSyncState(fIdx).CurrentFrame
                    continue;
                end
                app.processFrameInternal(fIdx, pf, pm);
            end
            if iter >= maxIter && app.DebugMode
                fprintf('[goToFrame] Pending loop hit max iterations (fIdx=%d)\n', fIdx);
            end
            
            % [V3.17 (5)] goToFrame 종료 시 단일 drawnow (drag/final 모두)
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
            
            % 2. 변경 없으면 종료
            if app.VideoSyncState(fIdx).CurrentFrame == frameNo, return; end
            app.VideoSyncState(fIdx).CurrentFrame = frameNo;
            
            % 3. 모든 표시 요소 일괄 동기화
            app.syncFrameMarkersAndLabel(fIdx, frameNo);
            
            % 4. 영상 갱신 (mode에 따라 source 선택)
            if strcmp(mode, 'drag')
                app.updateVideoFrameByFrameNo(fIdx, frameNo, 'drag');
            else
                app.updateVideoFrameByFrameNo(fIdx, frameNo, 'sync');
            end
            
            % 5. 동기 모드일 때 비행데이터 측도 갱신
            if app.VideoSyncState(fIdx).IsSynced && ~isempty(app.Models(fIdx).rawData)
                try
                    targetTime = app.frameToTime(fIdx, frameNo);
                    timeCol = app.Models(fIdx).mappedCols.Time;
                    times = app.Models(fIdx).rawData.(timeCol);
                    targetTime = max(times(1), min(targetTime, times(end)));
                    idx = app.findClosestIndexByTime(times, targetTime);
                    
                    if ~isequal(app.Models(fIdx).currentIndex, idx)
                        app.DraggedFromVideo = true;
                        try
                            if strcmp(mode, 'drag')
                                app.updateMarkersOnly(fIdx, idx);
                            else
                                % [FIX] IsUpdating onCleanup 보장
                                app.IsUpdating(fIdx) = true;
                                cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
                                app.updateDashboard(fIdx, idx);
                                clear cleanup_;
                            end
                        catch e
                            app.logCaught(e, 'goToFrame:dashboard');
                        end
                        app.DraggedFromVideo = false;
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
            % [FIX] 드래그 중 시각 피드백 즉시화: goToFrame 진입 전 라벨/슬라이더 라벨만 1회 갱신
            try, app.updateVdubFrameLabel(fIdx, frameNo); catch, end
            
            % [V3.19 (2)] 드래그 속도 측정 (adaptive prefetch용)
            app.updateDragVelocity(fIdx, frameNo);
            
            app.goToFrame(fIdx, evtValue, 'drag');
        end
        
        % [V3.15 항목 1] 슬라이더 드래그 종료 시 콜백 (ValueChangedFcn)
        % - 'final' 모드로 goToFrame 호출 → 전체 패널 1회 동기화 보장
        % - [V3.16] 같은 frame이라도 drag 모드 종료 직후일 수 있으므로 updateDashboard 강제
        function onVdubSliderChanged(app, fIdx, src)
            try
                target = round(src.Value);
                if app.VideoSyncState(fIdx).CurrentFrame == target
                    % drag 모드는 updateMarkersOnly만 호출 → 테이블/게이지 stale 가능
                    % final 모드 1회 강제 호출로 전체 동기화 보장
                    if app.VideoSyncState(fIdx).IsSynced && ~isempty(app.Models(fIdx).rawData)
                        % [FIX] IsUpdating onCleanup 보장
                        app.IsUpdating(fIdx) = true;
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
            app.InGoToFrame(fIdx) = false;
            if ~any(app.InGoToFrame), app.State = 'IDLE'; end
        end
        
        % [V3.17 (7)] 디코딩 진행 중 플래그 해제 (onCleanup 콜백)
        function clearDecodingFlag(app, fIdx)
            app.IsDecoding(fIdx) = false;
        end
        
        % [V3.17 (2) / REFACTOR Step 1] 캐시 존재 여부만 확인 (LRU 갱신 안 함) - CacheModel 위임
        function tf = hasCachedFrame(app, fIdx, frameNo)
            tf = false;
            try
                if isempty(app.CacheModel) || fIdx > numel(app.CacheModel), return; end
                % VideoSyncState의 TotalFrames와 동기화 (clamp 보호)
                app.CacheModel(fIdx).setTotalFrames(app.VideoSyncState(fIdx).TotalFrames);
                tf = app.CacheModel(fIdx).has(frameNo);
            catch
                tf = false;
            end
        end
        
        % [V3.19 (2)] 드래그 속도 추적 (지수 이동평균)
        function updateDragVelocity(app, fIdx, newFrame)
            try
                if app.LastDragTime{fIdx} == 0, app.LastDragTime{fIdx} = tic; end
                nowT = toc(app.LastDragTime{fIdx});   % [PATCH] 채널별 상대초
                samples = app.DragVelocitySamples{fIdx};
                
                if isempty(samples)
                    samples = struct('time', nowT, 'frame', newFrame);
                else
                    last = samples(end);
                    dt = nowT - last.time;
                    if dt > 0.001
                        instantV = (newFrame - last.frame) / dt;
                        % 지수 이동평균 (alpha=0.3)
                        app.DragVelocity(fIdx) = 0.7 * app.DragVelocity(fIdx) + 0.3 * instantV;
                    end
                    samples(end+1) = struct('time', nowT, 'frame', newFrame);
                    if length(samples) > 5, samples(1) = []; end
                end
                app.DragVelocitySamples{fIdx} = samples;
            catch ME
                app.logCaught(ME, 'updateDragVelocity');
            end
        end

        % [REFACTOR Step 0] util.Throttle 싱글톤 위임 - 호환성 100% 유지
        function hit = throttleHit(~, slotName, fIdx, limitS)
            hit = flightdash.util.Throttle.instance().hit(slotName, fIdx, limitS);
        end

        % [PATCH / REFACTOR Step 0] DebugMode 게이팅 catch 로깅 헬퍼 - util.ErrorLog 위임
        % - 모든 호출처는 그대로 동작 (호환성 100%)
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
        
        % [V3.19 (1) / V3.20 (5-2)] 비동기 디코딩 시작
        % - thread pool 우선 (직렬화 비용 0), 미지원 시 process pool 폴백
        % - 둘 다 실패하면 UseAsyncDecode=false로 자동 폴백 (재시도 안 함)
        % [PATCH Async 1.1] thread pool 사용 금지 - persistent VR이 워커 간 공유되어
        %                   race condition 발생. process pool은 워커별 독립 메모리.
        function startAsyncDecode(app, fIdx, frameNo)
            try
                % parallel pool 준비 (없으면 지연 생성)
                if isempty(app.AsyncPool) || ~isvalid(app.AsyncPool)
                    poolOk = false;
                    % [PATCH] 기존 pool 재사용 가능하면 사용 (단, threads는 거부)
                    try
                        existing = gcp('nocreate');
                        if ~isempty(existing) && isvalid(existing)
                            poolType = class(existing);
                            if contains(poolType, 'Thread', 'IgnoreCase', true)
                                if app.DebugMode
                                    fprintf('[Async] existing thread pool rejected (race risk)\n');
                                end
                            else
                                app.AsyncPool = existing;
                                poolOk = true;
                            end
                        end
                    catch ME, app.logCaught(ME, 'Async:gcp'); end
                    
                    % process pool 신규 생성
                    if ~poolOk
                        try
                            app.AsyncPool = parpool('local', flightdash.util.AppConstants.ASYNC_WORKER_COUNT);
                            try
                                if isprop(app.AsyncPool, 'IdleTimeout')
                                    app.AsyncPool.IdleTimeout = 30;
                                end
                            catch ME_idle
                                app.logCaught(ME_idle, 'Async:IdleTimeout');
                            end
                            poolOk = true;
                            if app.DebugMode
                                fprintf('[Async] process pool ready (%d workers)\n', flightdash.util.AppConstants.ASYNC_WORKER_COUNT);
                            end
                        catch e2
                            if app.DebugMode
                                fprintf('[Async] process pool failed: %s\n', e2.message);
                            end
                        end
                    end
                    
                    % 실패: 영구 비활성화
                    if ~poolOk
                        app.UseAsyncDecode = false;
                        if app.DebugMode
                            fprintf('[Async] disabled - falling back to sync decode\n');
                        end
                        return;
                    end
                end
                
                % [V3.21 #1-A] generation counter 증가 - 신규 요청 발행
                app.AsyncGen(fIdx) = app.AsyncGen(fIdx) + 1;
                myGen = app.AsyncGen(fIdx);
                
                % 이전 future 취소 (구식 결과 폐기)
                try
                    if ~isempty(app.AsyncFutures{fIdx}) && isvalid(app.AsyncFutures{fIdx})
                        fut = app.AsyncFutures{fIdx};
                        cancel(fut);
                        try
                            wait(fut, 'finished', 0.25);
                        catch ME_wait
                            app.logCaught(ME_wait, 'Async:cancelWait:replaceFuture');
                        end
                    end
                catch ME_silent, app.logCaught(ME_silent, 'silent'); end
                app.AsyncTargetFrame(fIdx) = frameNo;
                fps = app.VideoSyncState(fIdx).VideoFps;
                filePath = app.VideoFilePath{fIdx};
                
                % [V3.21 #2-A / V3.22 #4 / V3.22 #6] persistent VR worker 함수 사용
                % static wrapper를 통해 향후 +flightdash 패키지 마이그레이션 가능
                fut = parfeval(app.AsyncPool, @asyncDecodeFramePersistent, 1, ...
                    filePath, frameNo, fps, flightdash.util.AppConstants.WORKER_VR_CACHE_SLOTS);
                app.AsyncFutures{fIdx} = fut;
                
                % [V3.21 #1-A] afterEach에 myGen 캡처 → 완료 시 generation 비교
                afterEach(fut, @(img) app.onAsyncDecodeComplete(fIdx, frameNo, myGen, img), 1, ...
                    'PassFuture', false);
            catch e
                if app.DebugMode
                    fprintf('[Async] startAsyncDecode error: %s\n', e.message);
                end
                app.logCaught(e, 'Async:startAsyncDecode');
            end
        end
        
        % [V3.19 (1) / V3.21 #1-A / V3.21 #3-A] 비동기 디코딩 완료 콜백 (main thread)
        % - generation 비교로 stale 결과 차단
        % - displayFrame 단일 출구 통과 (write-through)
        function onAsyncDecodeComplete(app, fIdx, frameNo, gen, img)
            try
                if isempty(img), return; end
                if gen ~= app.AsyncGen(fIdx)
                    if app.DebugMode
                        fprintf('[Async] stale result discarded (gen=%d, current=%d)\n', ...
                            gen, app.AsyncGen(fIdx));
                    end
                    return;
                end
                % [FIX] PendingFrame 체크 - 더 최신 요청이 큐잉됐다면 displayFrame 스킵
                % (즉시 덮어쓰여질 UI 작업 방지, race-safe)
                if ~isnan(app.PendingFrame(fIdx)) && app.PendingFrame(fIdx) ~= frameNo
                    if app.DebugMode
                        fprintf('[Async] superseded by pending frame %d (this=%d)\n', ...
                            app.PendingFrame(fIdx), frameNo);
                    end
                    app.AsyncFutures{fIdx} = [];
                    return;
                end
                % [V3.21 #3-A] Layer 3 단일 출구 통과
                app.displayFrame(fIdx, frameNo, img, false);
                app.AsyncTargetFrame(fIdx) = NaN;
                app.AsyncFutures{fIdx} = [];   % [FIX] 완료된 future 즉시 해제 (메모리 누적 차단)
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
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
            % 화면 상태와 main VideoReader 위치를 건드리지 않고 별도 reader로 cache만 예열.
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
        % [V3.15 항목 2] goToFrame 단일 진입점 사용
        function onVdubNav(app, fIdx, action)
            try
                if ~app.isVideoReady(fIdx), return; end
                cur = app.VideoSyncState(fIdx).CurrentFrame;
                total = app.VideoSyncState(fIdx).TotalFrames;
                if total < 1, return; end
                
                switch action
                    % [수정 2] 10 프레임씩 뒤로/앞으로 이동하도록 변경
                    case 'first',  newFrame = max(1, cur - 10);
                    case 'prev',   newFrame = max(1, cur - 1);
                    case 'next',   newFrame = min(total, cur + 1);
                    case 'last',   newFrame = min(total, cur + 10);
                    otherwise,     newFrame = cur;
                end
                
                if newFrame == cur, return; end
                app.goToFrame(fIdx, newFrame, 'final');
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end
        
        % [V3.14 VirtualDub UI] Frame 마커/슬라이더/라벨 일괄 동기화 헬퍼
        function syncFrameMarkersAndLabel(app, fIdx, frameNo)
            try
                % [수정] 사용하지 않는 옛날 마커 갱신 코드는 완전히 삭제하여 에러 원천 차단
                
                % 1. 슬라이더 위치 갱신
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
        
        % [V3.12] 비디오 동기 상태 초기화
        function resetVideoSync(app, fIdx)
            app.VideoSyncState(fIdx).IsSynced = false;
            app.VideoSyncState(fIdx).AnchorFrame = 0;
            app.VideoSyncState(fIdx).AnchorOffset = 0;
            app.VideoSyncState(fIdx).AnchorTime = 0;
            % [REFACTOR Step 2-B] SyncModel도 동기 clear
            app.SyncMdl(fIdx).clear();
            try
                if isfield(app.UI(fIdx), 'vidSyncBtn') && isvalid(app.UI(fIdx).vidSyncBtn)
                    app.UI(fIdx).vidSyncBtn.Text = '동기';
                    app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.58 0.0 0.83];
                end
                if isfield(app.UI(fIdx), 'vidSyncStatus') && isvalid(app.UI(fIdx).vidSyncStatus)
                    app.UI(fIdx).vidSyncStatus.Text = '동기 미설정';
                    app.UI(fIdx).vidSyncStatus.FontColor = [0.5 0.5 0.5];
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end
        
        % [V3.12 2.2.3] 동기 버튼 콜백 - 입력값 검증 및 동기 설정
        function applyVideoSync(app, fIdx)
            % 동기 해제 모드
            if app.VideoSyncState(fIdx).IsSynced
                app.resetVideoSync(fIdx);
                return;
            end
            
            % 1. 영상/데이터 로드 검증
            if isempty(app.VideoState(fIdx).videoReader)
                errordlg('먼저 AVI 파일을 로드하세요.', '동기 오류'); return;
            end
            if isempty(app.Models(fIdx).rawData)
                errordlg('먼저 비행데이터(CSV)를 로드하세요.', '동기 오류'); return;
            end
            
            % 2. 입력값 추출
            frameNo = app.UI(fIdx).vidSyncFrameInput.Value;
            timeVal = app.UI(fIdx).vidSyncTimeInput.Value;
            
            % 3. 범위 검증
            totalFrames = app.VideoSyncState(fIdx).TotalFrames;
            timeCol = app.Models(fIdx).mappedCols.Time;
            times = app.Models(fIdx).rawData.(timeCol);
            
            if frameNo < 1 || frameNo > totalFrames
                errordlg(sprintf('Frame No는 1 ~ %d 범위여야 합니다.', totalFrames), '범위 오류'); return;
            end
            if timeVal < times(1) || timeVal > times(end)
                errordlg(sprintf('Time(s)는 %.3f ~ %.3f 범위여야 합니다.', times(1), times(end)), '범위 오류'); return;
            end
            
            % 4. Hz 값 갱신
            vfpsUI = app.UI(fIdx).vidVideoFpsInput.Value;
            dfps = app.UI(fIdx).vidDataFpsInput.Value;
            if vfpsUI < 1 || dfps < 1
                errordlg('Hz 값은 1 이상이어야 합니다.', '입력 오류'); return;
            end
            
            % [수정 3] 소수점 정밀도 유실 방지 로직
            % 내부의 정확한 소수점 FPS를 반올림한 값과 현재 UI 스피너의 값이 같다면,
            % 사용자가 스피너를 수동 조작하지 않은 것으로 간주하여 정확한 내부 소수점 FPS를 유지함.
            if round(app.VideoSyncState(fIdx).VideoFps) == vfpsUI
                % do nothing (소수점 정밀도 유지)
            else
                app.VideoSyncState(fIdx).VideoFps = vfpsUI; % 사용자가 스피너를 바꾼 경우에만 갱신
            end
            
            app.VideoSyncState(fIdx).DataFps = dfps;
            
            % 5. 동기 정보 저장
            % [V3.23 sub-frame / FIX] 수동 동기는 사용자 입력을 절대값으로 신뢰 → offset=0 고정
            % (sub-frame offset은 자동 anchor에서만 의미. 수동 입력에서는 frameNo↔timeVal이 곧 진실)
            anchorOffset = 0;
            
            app.VideoSyncState(fIdx).IsSynced     = true;
            app.VideoSyncState(fIdx).AnchorFrame  = frameNo;
            app.VideoSyncState(fIdx).AnchorOffset = anchorOffset;
            app.VideoSyncState(fIdx).AnchorTime   = timeVal;
            % [REFACTOR Step 2-B] SyncModel에도 동기 set (병행, offset 포함)
            app.SyncMdl(fIdx).setAnchor(frameNo, timeVal, anchorOffset);
            
            % 6. UI 피드백
            app.UI(fIdx).vidSyncBtn.Text = '동기 해제';
            app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.8 0.2 0.2];
            app.UI(fIdx).vidSyncStatus.Text = sprintf('동기 완료 (F%d ↔ %.3fs)', frameNo, timeVal);
            app.UI(fIdx).vidSyncStatus.FontColor = [0.06 0.65 0.50];
            
            % [V3.14 항목 4 / REFACTOR Step 1] 동기 재설정 시 캐시 무효화 - 래퍼 사용
            app.invalidateFrameCache(fIdx);
            if app.DebugMode
                fprintf('[VideoSync] fIdx=%d, anchor F%d ↔ %.3fs, vfps=%d, dfps=%d, cache cleared\n', ...
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
        
        % [V3.12 2.2.3.1] Hz 직접 입력 시 콜백 (스피너 ValueChangedFcn)
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
        
        % [V3.13 C-1 / REFACTOR Step 1] 프레임 캐시 조회 - CacheModel 위임
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
        
        % [V3.13 C-1 / REFACTOR Step 1] 프레임 캐시 저장 - CacheModel 위임
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
        
        % [REFACTOR Step 1] evictByScore는 CacheModel 내부 메서드로 이전됨.
        % 외부에서 직접 호출하는 코드가 없으므로 본 클래스에서 완전 제거.
        % (필요 시 app.CacheModel(fIdx).stats() 로 캐시 상태 점검 가능)
        
        % =====================================================================
        % [V3.21 #3-A] 3계층 분리 구조 - 책임 명확화
        % 
        %   Layer 1: requestFrame  - 진입점 + 캐시 lookup + 전략 선택
        %   Layer 2: decodeFrameSync - 동기 디코딩 (read or 폴백)
        %            startAsyncDecode - 비동기 디코딩 (별도 메서드, 기존)
        %   Layer 3: displayFrame  - 표시 + 캐시 store (단일 출구)
        %
        % 기존 updateVideoFrameByFrameNo는 호환을 위해 requestFrame로 위임.
        % =====================================================================
        
        % [V3.21 #3-A Layer 1] Frame 요청 진입점
        % source: 'drag' / 'autoplay' / 'sync' / 'force'
        function requestFrame(app, fIdx, frameNo, source)
            if nargin < 4, source = 'force'; end
            
            % 유효성 검사
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
            
            % 디코딩 진행 중이면 skip (coalescing으로 후처리)
            if app.IsDecoding(fIdx), return; end
            
            % 전략 선택: async vs sync
            if app.UseAsyncDecode && strcmp(source, 'drag')
                app.startAsyncDecode(fIdx, clampedFrame);
                return;
            end
            
            % Layer 2: 동기 디코딩
            app.IsDecoding(fIdx) = true;
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
            
            % [PATCH Async 1.2 / V3.22 #4] 작은 step 휴리스틱 - 직전 표시 프레임 근처면 readFrame 순차
            % MP4 역방향 seek는 매우 비싸므로 전진 방향 작은 step만 readFrame 사용
            try
                lastF = app.LastDisplayedFrame(fIdx);
                fps = app.VideoSyncState(fIdx).VideoFps;
                if fps <= 0, fps = 70; end
                step = clampedFrame - lastF;
                if lastF > 0 && step >= 1 && step <= flightdash.util.AppConstants.MAX_SEQ_READ_STEP
                    for k = 1:step
                        if hasFrame(vr), img = readFrame(vr); else, img = []; break; end
                    end
                    if ~isempty(img), return; end
                end
            catch ME, app.logCaught(ME, 'decodeSync:seq'); end
            
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

        % ---------------------------------------------------------------------
        % 마커 클릭 & 드래그 이벤트 전용 핸들러 (스턱 방어 강화)
        % ---------------------------------------------------------------------
        function startPlotMarkerDrag(app, fIdx, ~, src, event)
            % 마우스 왼쪽 버튼 클릭 시에만 실행 (우클릭 등 제외)
            if event.Button ~= 1, return; end 
            if isempty(app.Models(fIdx).rawData), return; end
            if app.SyncState.IsSynced && fIdx == 2, return; end 
            
            % 드래그 상태 활성화 및 객체 HitTest 끄기
            app.IsDraggingMarker = true;
            app.DraggedMarker = src;
            app.DraggedFIdx = fIdx;   % [V3.11 B] 드래그 종료 시 전체 동기화용
            app.DraggedFromVideo = false;   % [V3.12] 비행데이터 측에서 시작
            app.VideoThrottleDyn = 0.05;    % [V3.12] 동적 throttle 초기값 20fps
            app.LastDragTime{fIdx} = tic;
            try
                throttle = flightdash.util.Throttle.instance();
                throttle.reset('MapPathDragUpdate', fIdx);
                throttle.reset('PlotDragTimelineUpdate', fIdx);
            catch ME, app.logCaught(ME, 'silent'); end
            app.State = 'DRAGGING';   % [V3.17 (8)]
            src.HitTest = 'off'; 
            
            % 드래그 중 Axes의 기본 조작(Pan/Zoom) 끄기 (마우스 뗌 씹힘 방지)
            try
                ax = src.Parent;
                if isvalid(ax) && isprop(ax, 'Interactions')
                    app.DraggedMarker.UserData = ax.Interactions; % 기존 설정 백업
                    ax.Interactions = []; % 드래그 중 내장 Pan 비활성화
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            % [V3.11 B] 드래그 중 XLim 리스너 일시 중단 
            app.setXLimListenersEnabled(fIdx, false);
            
            % [V3.11 C] 드래그 중 xline을 불투명(Alpha=1)으로 전환 → 렌더링 가속
            try
                for tIdx = 1:length(app.UI(fIdx).timeLines)
                    tlArr = app.UI(fIdx).timeLines{tIdx};
                    for k = 1:length(tlArr)
                        if ~isempty(tlArr{k}) && isvalid(tlArr{k})
                            tlArr{k}.Alpha = 1.0;
                        end
                    end
                end
                if isfield(app.UI(fIdx), 'timeLine') && ~isempty(app.UI(fIdx).timeLine) && isvalid(app.UI(fIdx).timeLine)
                    app.UI(fIdx).timeLine.Alpha = 1.0;
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            app.UIFigure.WindowButtonMotionFcn = @(~,~) app.plotMarkerDragMotion(fIdx);
            app.UIFigure.WindowButtonUpFcn = @(~,~) app.stopPlotMarkerDrag();
        end
        
        % [V3.12 2.2.2] 비디오 Frame 마커 드래그 시작 핸들러
        function startVideoFrameDrag(app, fIdx, src, event)
            if event.Button ~= 1, return; end
            if isempty(app.VideoState(fIdx).videoReader), return; end
            
            app.IsDraggingMarker = true;
            app.DraggedMarker = src;
            app.DraggedFIdx = fIdx;
            app.DraggedFromVideo = true;   % ⭐ 비디오 측에서 드래그 시작
            app.VideoThrottleDyn = 0.05;
            app.LastDragTime{fIdx} = tic;
            app.State = 'DRAGGING';   % [V3.17 (8)]
            src.HitTest = 'off';
            
            try
                ax = src.Parent;
                if isvalid(ax) && isprop(ax, 'Interactions')
                    app.DraggedMarker.UserData = ax.Interactions;
                    ax.Interactions = [];
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            % XLim 리스너 중단 (비행데이터와 동일 정책)
            app.setXLimListenersEnabled(fIdx, false);
            
            app.UIFigure.WindowButtonMotionFcn = @(~,~) app.videoFrameDragMotion(fIdx);
            app.UIFigure.WindowButtonUpFcn = @(~,~) app.stopPlotMarkerDrag();
        end
        
        function plotMarkerDragMotion(app, fIdx)
            if ~app.IsDraggingMarker, return; end
            try
                if isempty(app.DraggedMarker) || ~isvalid(app.DraggedMarker), return; end
                
                ax = app.DraggedMarker.Parent; 
                if isempty(ax) || ~isvalid(ax), return; end
                
                pt = ax.CurrentPoint;
                if isempty(pt) || any(isnan(pt(:))) || any(~isfinite(pt(:)))
                    return;
                end
                
                % [V3.13] V3.12 동적 throttle 호출 제거 - source 기반 절충 throttle 사용
                
                % [V3.11 C] 드래그 중에는 경량 경로로만 업데이트
                targetTime = pt(1,1);
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isempty(times), return; end
                
                targetTime = max(min(targetTime, times(end)), times(1));
                idx = app.findClosestIndexByTime(times, targetTime);
                
                if isequal(app.Models(fIdx).currentIndex, idx), return; end
                app.updateMarkersOnly(fIdx, idx);
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end
        
        % [V3.12 2.2.2] 비디오 Frame 마커 드래그 모션 핸들러
        % [V3.12 2.2.2] 비디오 Frame 마커 별표 드래그 모션 핸들러
        % [V3.15 항목 2] goToFrame 단일 진입점 사용으로 리팩토링
        function videoFrameDragMotion(app, fIdx)
            if ~app.IsDraggingMarker, return; end
            try
                if isempty(app.DraggedMarker) || ~isvalid(app.DraggedMarker), return; end
                
                ax = app.DraggedMarker.Parent;
                if isempty(ax) || ~isvalid(ax), return; end
                
                pt = ax.CurrentPoint;
                if isempty(pt) || any(isnan(pt(:))) || any(~isfinite(pt(:)))
                    return;
                end
                
                targetFrame = round(pt(1,1));
                totalFrames = app.VideoSyncState(fIdx).TotalFrames;
                if totalFrames < 1, return; end
                
                % [V3.19 (2)] 드래그 속도 측정 (adaptive prefetch용)
                app.updateDragVelocity(fIdx, targetFrame);
                
                % [V3.15 항목 2] 단일 진입점 통과 - 'drag' 모드로 경량 갱신
                app.goToFrame(fIdx, targetFrame, 'drag');
                drawnow limitrate;
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end
        
        % [V3.12 영상 동적 throttle 계산]
        % - 드래그 이동이 빠르면 throttle 간격을 늘려 영상 갱신 빈도를 줄임 (5fps까지)
        % - 느리면 간격을 줄여 영상이 부드럽게 따라오게 함 (20fps까지)
        function computeDynamicVideoThrottle(app)
            try
                fIdx = app.DraggedFIdx;
                if fIdx < 1 || fIdx > 2, return; end
                if app.LastDragTime{fIdx} == 0, app.LastDragTime{fIdx} = tic; return; end
                dt = toc(app.LastDragTime{fIdx});
                app.LastDragTime{fIdx} = tic;
                
                if dt <= 0, return; end
                
                % 이동 빈도가 60fps에 가까울수록(dt 작을수록) 영상은 적게 갱신
                % dt=0.016(60fps) → throttle 0.20 (5fps)
                % dt=0.05 (20fps) → throttle 0.10 (10fps)
                % dt=0.1+(10fps 이하) → throttle 0.05 (20fps)
                if dt < 0.025
                    target = 0.20;
                elseif dt < 0.06
                    target = 0.10;
                else
                    target = 0.05;
                end
                
                % 부드러운 전이 (지수 가중 이동평균)
                app.VideoThrottleDyn = 0.7 * app.VideoThrottleDyn + 0.3 * target;
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [PATCH UX-3] H↔I 패널 경계 splitter 드래그 핸들러
        function startHISplitterDrag(app, fIdx)
            try
                app.HISplitterFIdx = fIdx;
                app.IsDraggingSplitter = true;
                app.UIFigure.WindowButtonMotionFcn = @(~,~) app.hiSplitterMotion();
                app.UIFigure.WindowButtonUpFcn    = @(~,~) app.stopHISplitterDrag();
                if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'left-right'; end
            catch ME, app.logCaught(ME, 'HISplitter:start'); end
        end
        
        function hiSplitterMotion(app)
            if ~app.IsDraggingSplitter, return; end
            try
                fIdx = app.HISplitterFIdx;
                if fIdx < 1 || fIdx > 2, return; end
                dg = app.UI(fIdx).dataGrid;
                if isempty(dg) || ~isvalid(dg) || numel(dg.ColumnWidth) < 6, return; end
                figPos  = app.UIFigure.CurrentPoint;
                gridPos = getpixelposition(dg, true);
                gridW   = gridPos(3);
                mouseX_in_grid = figPos(1) - gridPos(1);
                newVideoW = gridW - mouseX_in_grid;
                
                % [FIX] 고정 합산을 동적 계산: 현재 컬럼 폭 1/2/3/5(splitter)을 그대로 사용
                % [3B] ColumnSpacing은 dg에서 직접 읽어 DPI/사용자 변경에 자동 추종
                cw = dg.ColumnWidth;
                fixedSum = 0;
                for k = [1 2 3 5]
                    v = cw{k};
                    if isnumeric(v), fixedSum = fixedSum + v; end
                end
                colSpacing = 0;
                try, colSpacing = dg.ColumnSpacing; catch, end
                nGaps = max(0, numel(cw) - 1);
                fixedSum = fixedSum + colSpacing * nGaps;
                
                % [FIX Case 8] H 보호 우선화 + [3B] DPI 스케일 적용
                % - 기존: max(280, gridW-fixedSum-hMin) → 좁은 창에서 video 280이 H 320을 침범
                % - 수정: H 최소폭(디자인 320)을 절대 보장, video는 잔여 한도 내에서만 양보
                % - DPI: gridW/cw는 모두 실효 픽셀 단위이므로 임계값도 UIScale.px로 통일
                UIScale = flightdash.util.UIScale;
                hMin = UIScale.px(320);   % H패널 최소 폭 (디자인 320 → DPI 스케일)
                maxVideoW = gridW - fixedSum - hMin;
                if maxVideoW <= 0
                    % 창이 너무 작아 H 최소폭 보장 불가 → splitter 이동 차단
                    return;
                end
                videoMinDesign = UIScale.px(280);  % 디자인 280 → DPI 스케일
                videoMin = min(videoMinDesign, maxVideoW);  % H 보호선 아래로는 video 양보
                newVideoW = round(max(videoMin, min(maxVideoW, newVideoW)));
                if isequal(cw{6}, newVideoW), return; end
                cw{6} = newVideoW;
                dg.ColumnWidth = cw;
                
                % [FIX] 사용자가 splitter 조작 시 자동 리사이즈 차단 플래그
                app.VideoUserResized(fIdx) = true;
            catch ME, app.logCaught(ME, 'HISplitter:motion'); end
        end
        
        function stopHISplitterDrag(app)
            try
                app.UIFigure.WindowButtonMotionFcn = '';
                app.UIFigure.WindowButtonUpFcn    = '';
                if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'arrow'; end
                app.IsDraggingSplitter = false;
                app.HISplitterFIdx = 0;
                drawnow limitrate;
            catch ME, app.logCaught(ME, 'HISplitter:stop'); end
        end

        function stopPlotMarkerDrag(app)
            % 콜백 및 드래그 상태 완벽 초기화
            wasDraggingFIdx = app.DraggedFIdx;
            app.IsDraggingMarker = false;
            app.State = 'IDLE';   % [V3.17 (8)] 드래그 종료 시 IDLE 복원
            
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = ''; 
                    app.UIFigure.WindowButtonUpFcn = '';
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            try
                if ~isempty(app.DraggedMarker) && isvalid(app.DraggedMarker)
                    app.DraggedMarker.HitTest = 'on';
                    % 기존 Axes 상호작용(Pan/Zoom) 복원
                    ax = app.DraggedMarker.Parent;
                    if isvalid(ax) && isprop(ax, 'Interactions') && ~isempty(app.DraggedMarker.UserData)
                        ax.Interactions = app.DraggedMarker.UserData;
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            app.DraggedMarker = [];
            app.DraggedFIdx = 0;
            app.DraggedFromVideo = false;   % [V3.12] 비디오 드래그 플래그 리셋
            app.VideoThrottleDyn = 0.05;    % [V3.12] throttle 기본값 복원
            
            % [V3.11 C] xline Alpha를 0.5로 복원
            for fIdx = 1:2
                try
                    for tIdx = 1:length(app.UI(fIdx).timeLines)
                        tlArr = app.UI(fIdx).timeLines{tIdx};
                        for k = 1:length(tlArr)
                            if ~isempty(tlArr{k}) && isvalid(tlArr{k})
                                tlArr{k}.Alpha = 0.5;
                            end
                        end
                    end
                    if isfield(app.UI(fIdx), 'timeLine') && ~isempty(app.UI(fIdx).timeLine) && isvalid(app.UI(fIdx).timeLine)
                        app.UI(fIdx).timeLine.Alpha = 0.5;
                    end
                catch ME, app.logCaught(ME, 'silent'); end
            end
            
            % [V3.11 B] XLim 리스너 복원 (드래그 시작 시 중단했던 리스너 복구)
            if wasDraggingFIdx >= 1 && wasDraggingFIdx <= 2
                app.setXLimListenersEnabled(wasDraggingFIdx, true);
            end
            
            % [V3.11 C] 드래그 종료 시 전체 대시보드 1회 동기화 
            % (드래그 중 경량 경로로만 갱신했던 테이블/게이지/맵/비디오 최종 반영)
            for fIdx = 1:2
                if ~isempty(app.Models(fIdx).rawData)
                    idx = app.Models(fIdx).currentIndex;
                    % [FIX] IsUpdating onCleanup 보장 + warning → ErrorLog
                    app.IsUpdating(fIdx) = true;
                    cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
                    try
                        app.updateDashboard(fIdx, idx);
                    catch e
                        app.logCaught(e, 'stopPlotMarkerDrag:sync');
                    end
                    clear cleanup_;
                    % [V3.18 (4)] 드래그 종료 후 인접 frame 워밍업 (idle CPU 활용)
                    app.prefetchAdjacentFrames(fIdx);
                end
            end
        end
        
        % ---------------------------------------------------------------------
        % [V3.11 B] XLim 리스너 일괄 제어 (드래그 중 중단/복원)
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
        % - 테이블/게이지는 여전히 드래그 종료 시 1회만 갱신 (현 정책 유지)
        % ---------------------------------------------------------------------
        function updateMarkersOnly(app, fIdx, idx)
            % [V3.17 (4)(11)] persistent inCascade → InCascade 인스턴스 속성으로 이동
            % [V3.17 (5)] drawnow를 외부(goToFrame)에서 처리하므로 자체 호출은 가드
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
                
                % 현재시간 라벨 (매우 가벼움)
                if isfield(app.UI(fIdx), 'currentTimeLabel') && isvalid(app.UI(fIdx).currentTimeLabel)
                    app.UI(fIdx).currentTimeLabel.Text = sprintf('%.3f s', currTime);
                end
                
                % 스피너 갱신 (가벼움)
                if isfield(app.UI(fIdx), 'spinner') && isvalid(app.UI(fIdx).spinner)
                    if abs(app.UI(fIdx).spinner.Value - currTime) > eps
                        app.UI(fIdx).spinner.Value = currTime;
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            % [V3.12 1.1] Map 비행경로 + 빨간 삼각형 실시간 갱신 (가벼움)
            % [PERF] validIdx 제거 - load 시 NaN 전처리됨, plot이 NaN에서 자동 끊김
            try
                pathLon = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lon);
                pathLat = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lat);
                
                updateFullPath = ~app.IsDraggingMarker || ...
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
            
            % H 패널 책장 넘기기 + 마커 갱신 (개선안 A의 IsProgrammaticXLim 가드 작동)
            if ~app.IsDraggingMarker || ...
                    ~app.throttleHit('PlotDragTimelineUpdate', fIdx, flightdash.util.AppConstants.PLOT_DRAG_THROTTLE_S)
                app.updatePlotTimeLines(fIdx, idx, currTime);
            end
            
            % [V3.12 2.2.3] 비디오 동기 설정 시 Frame 마커 + 영상 프레임 갱신
            % (단, 비디오 측에서 시작된 드래그가 아닐 때만 - 무한 루프 방지)
            % [PATCH UX-1] Sync 명시 활성화 + 비디오 ready 동시 충족 시에만 갱신
            if app.VideoSyncState(fIdx).IsSynced && ~app.DraggedFromVideo ...
                    && app.isVideoReady(fIdx) && app.VideoSyncState(fIdx).AnchorFrame > 0
                try
                    targetFrame = app.timeToFrame(fIdx, currTime);
                    app.VideoSyncState(fIdx).CurrentFrame = targetFrame;
                    
                    % [V3.14] Frame 마커 + xline + 슬라이더 + 라벨 일괄 동기화
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);
                    
                    % [V3.13 절충] 비행데이터 드래그 시 영상 갱신은 throttle 유지
                    app.updateVideoFrameByFrameNo(fIdx, targetFrame, 'autoplay');
                catch ME, app.logCaught(ME, 'silent'); end
            end
            
            % 동기화 모드: 경로 1 드래그 시 경로 2도 경량 업데이트
            if app.SyncState.IsSynced && fIdx == 1 && ~isempty(app.Models(2).rawData)
                targetT2 = app.SyncState.SyncT2 + (currTime - app.SyncState.SyncT1);
                timeCol2 = app.Models(2).mappedCols.Time;
                idx2 = app.findClosestIndexByTime(app.Models(2).rawData.(timeCol2), targetT2);
                if ~isequal(app.Models(2).currentIndex, idx2)
                    % [V3.17 (4)(11) / FIX] InCascade를 onCleanup으로 보장 (예외 시 스턱 방지)
                    app.InCascade = true;
                    cascadeCleanup_ = onCleanup(@() resetInCascade(app)); %#ok<NASGU>
                    app.updateMarkersOnly(2, idx2);
                    clear cascadeCleanup_;
                end
            end
            
            % [V3.17 (5)] cascade 외부 + goToFrame 미경유 시에만 drawnow
            % goToFrame은 자체 종료 시 drawnow 호출하므로 중복 방지
            if isOuter && ~any(app.InGoToFrame)
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

        function updateTabTimeLines(app, fIdx)
            if isempty(app.Models(fIdx).rawData), return; end
            currIdx = app.Models(fIdx).currentIndex;
            timeCol = app.Models(fIdx).mappedCols.Time; 
            currTime = app.Models(fIdx).rawData.(timeCol)(currIdx);
            app.updatePlotTimeLines(fIdx, currIdx, currTime);
        end

        function updatePlotTimeLines(app, fIdx, currIdx, currTime)
            currTab = app.UI(fIdx).tabGroup.SelectedTab;
            if isempty(currTab), return; end
            
            tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            if isempty(tabIdx), return; end

            % [기능 유지] H 패널 자동 화면 넘김 (Auto-Page Panning)
            % 확대된 상태에서 마커가 화면 밖을 벗어나면 기존 확대 폭을 유지한 채 X축 이동
            % [V3.11 A] XLim 변경 시 handlePlotXLimChange 리스너 무한 재귀 차단
            if ~isempty(app.UI(fIdx).plotAxes{tabIdx})
                firstAx = app.UI(fIdx).plotAxes{tabIdx}{1};
                try
                    if isvalid(firstAx)
                        xlims = firstAx.XLim;
                        xMin = xlims(1);
                        xMax = xlims(2);
                        xWidth = xMax - xMin;
                        
                        if currTime > xMax
                            newMin = xMax;
                            newMax = xMax + xWidth;
                            while currTime > newMax
                                newMin = newMax;
                                newMax = newMax + xWidth;
                            end
                            app.IsProgrammaticXLim(fIdx) = true;   % ⭐ 리스너 가드 ON
                            firstAx.XLim = [newMin, newMax];
                            app.IsProgrammaticXLim(fIdx) = false;  % ⭐ 리스너 가드 OFF
                        elseif currTime < xMin
                            newMax = xMin;
                            newMin = xMin - xWidth;
                            while currTime < newMin
                                newMax = newMin;
                                newMin = newMin - xWidth;
                            end
                            app.IsProgrammaticXLim(fIdx) = true;   % ⭐ 리스너 가드 ON
                            firstAx.XLim = [newMin, newMax];
                            app.IsProgrammaticXLim(fIdx) = false;  % ⭐ 리스너 가드 OFF
                        end
                    end
                catch
                    app.IsProgrammaticXLim(fIdx) = false;  % 예외 시 플래그 복원
                end
            end

            tlArr = app.UI(fIdx).timeLines{tabIdx};
            mkArr = app.UI(fIdx).timeMarkers{tabIdx};
            dataArr = app.UI(fIdx).plotData{tabIdx};

            for i = 1:length(tlArr)
                try
                    if ~isempty(tlArr{i}) && isvalid(tlArr{i})
                        set(tlArr{i}, 'Value', currTime);
                    end
                    if ~isempty(mkArr{i}) && isvalid(mkArr{i})
                        yData = dataArr{i};
                        set(mkArr{i}, 'XData', currTime, 'YData', yData(currIdx));
                    end
                catch ME_silent, app.logCaught(ME_silent, 'silent'); end
            end
        end

        % ---------------------------------------------------------------------
        % H 영역 탭 및 다중 플롯 관리
        % ---------------------------------------------------------------------
        function addPlotTab(app, fIdx)
            nTabs = length(app.UI(fIdx).plotTabs);
            if nTabs >= flightdash.util.AppConstants.MAX_TABS
                errordlg(sprintf('최대 %d개의 탭만 생성할 수 있습니다.', flightdash.util.AppConstants.MAX_TABS), '알림');
                return;
            end
            
            newTab = uitab(app.UI(fIdx).tabGroup, 'Title', sprintf('Tab %d', nTabs+1));
            app.UI(fIdx).plotTabs(end+1) = newTab;

            plotLayout = uigridlayout(newTab, 'ColumnWidth', {'1x'}, 'RowHeight', {}, ...
                                      'Padding', [5 5 5 5], 'RowSpacing', 5, 'Scrollable', 'on');
            
            app.UI(fIdx).plotLayouts{end+1} = plotLayout;

            tabIdx = nTabs + 1;
            app.UI(fIdx).plotAxes{tabIdx} = {};
            app.UI(fIdx).timeLines{tabIdx} = {};
            app.UI(fIdx).timeMarkers{tabIdx} = {};
            app.UI(fIdx).plotData{tabIdx} = {};
            app.UI(fIdx).xLimListeners{tabIdx} = {};

            app.UI(fIdx).tabGroup.SelectedTab = newTab;
        end

        % [FIX] 한 화면 최대 3개 보장: tabGroup 가시 높이를 3등분해 RowHeight 동적 갱신
        % - throttle 0.05s로 리사이즈 중 다발 호출 차단
        % - 모든 탭의 모든 row를 동일 높이로 통일 (4개 이상 시 자동 스크롤)
        function updatePlotRowHeights(app, fIdx)
            if flightdash.util.Throttle.instance().hit('PlotRowResize', fIdx, 0.05), return; end
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
            for fIdx = 1:2
                try, app.updatePlotRowHeights(fIdx); catch, end
            end
        end

        function clearCurrentTab(app, fIdx)
            currTab = app.UI(fIdx).tabGroup.SelectedTab;
            if isempty(currTab), return; end
            tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            if isempty(tabIdx), return; end
            
            app.deleteListeners(app.UI(fIdx).xLimListeners{tabIdx});
            app.deleteGraphicsHandles(app.UI(fIdx).timeLines{tabIdx});
            app.deleteGraphicsHandles(app.UI(fIdx).timeMarkers{tabIdx});
            app.deleteGraphicsHandles(app.UI(fIdx).plotAxes{tabIdx});
            
            targetLayout = app.UI(fIdx).plotLayouts{tabIdx};
            try
                if ~isempty(targetLayout) && isvalid(targetLayout)
                    delete(targetLayout.Children);
                    targetLayout.RowHeight = {};
                end
            catch ME, app.logCaught(ME, 'silent'); end
            
            app.UI(fIdx).plotAxes{tabIdx} = {};
            app.UI(fIdx).timeLines{tabIdx} = {};
            app.UI(fIdx).timeMarkers{tabIdx} = {};
            app.UI(fIdx).plotData{tabIdx} = {};
            app.UI(fIdx).xLimListeners{tabIdx} = {};
        end

        function clearAllTabs(app, fIdx)
            for i = 1:length(app.UI(fIdx).plotTabs)
                if i <= length(app.UI(fIdx).xLimListeners)
                    app.deleteListeners(app.UI(fIdx).xLimListeners{i});
                end
                try
                    if ~isempty(app.UI(fIdx).plotTabs(i)) && isvalid(app.UI(fIdx).plotTabs(i))
                        delete(app.UI(fIdx).plotTabs(i));
                    end
                catch ME, app.logCaught(ME, 'silent'); end
            end
            app.UI(fIdx).plotTabs = [];
            app.UI(fIdx).plotLayouts = {};
            app.UI(fIdx).plotAxes = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).timeLines = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).timeMarkers = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).plotData = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).xLimListeners = cell(1, flightdash.util.AppConstants.MAX_TABS);
            
            app.addPlotTab(fIdx);
        end

        function deleteGraphicsHandles(~, handleCell)
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

        function deleteListeners(~, listenerCell)
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
            %           → 사용자가 드래그한 마커 위치가 중앙으로 강제 점프되는 현상 차단
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

            % [버그 완벽 수정] 줌/팬 등에 의해 X축 범위가 변경되었을 때 
            % 혹시 남아있을지 모르는 드래그 상태를 안전하게 강제 초기화
            if app.IsDraggingMarker
                app.stopPlotMarkerDrag();
            end

            % [줌 동기화 핵심] 확대/이동 발생 시 중앙 시간 획득 후 대시보드 동기화
            if app.IsUpdating(fIdx), return; end
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
            
            % Y축 자동 스케일: 확대 시 마커가 Y축 밖으로 벗어나 사라지는 것을 완벽 방지
            ax.YLimMode = 'auto'; 
            
            if isequal(app.Models(fIdx).currentIndex, idx), return; end
            app.applyTimeChange(fIdx, idx);
        end

        function plotSelectedVariable(app, fIdx)
            selRow = app.Models(fIdx).selectedRow; 
            if isempty(selRow) || selRow < 1, return; end
            if isempty(app.Models(fIdx).rawData), return; end
            
            currTab = app.UI(fIdx).tabGroup.SelectedTab;
            if isempty(currTab)
                app.addPlotTab(fIdx);
                currTab = app.UI(fIdx).tabGroup.SelectedTab;
            end
            
            tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            if isempty(tabIdx)
                errordlg('현재 탭이 유효하지 않습니다. "+ 빈 탭 추가"를 먼저 눌러주세요.', '탭 오류');
                return;
            end
            
            numPlots = length(app.UI(fIdx).plotAxes{tabIdx});
            if numPlots >= flightdash.util.AppConstants.MAX_PLOTS_PER_TAB
                errordlg(sprintf('한 탭에는 최대 %d개의 플롯만 추가할 수 있습니다.', flightdash.util.AppConstants.MAX_PLOTS_PER_TAB), '알림');
                return;
            end
            
            if selRow > length(app.Models(fIdx).displayMeta)
                errordlg('선택된 행이 유효하지 않습니다.', '선택 오류');
                return;
            end
            
            meta = app.Models(fIdx).displayMeta(selRow); 
            yCol = meta.header; 
            yLabelStr = sprintf('%s (%s)', meta.header, meta.unit); 
            timeCol = app.Models(fIdx).mappedCols.Time;
            
            if ~ismember(yCol, app.Models(fIdx).rawData.Properties.VariableNames)
                errordlg(sprintf('컬럼 "%s"을(를) 찾을 수 없습니다.', yCol), '데이터 오류');
                return;
            end
            
            tData = app.Models(fIdx).rawData.(timeCol); 
            yData = app.Models(fIdx).rawData.(yCol);
            
            targetLayout = app.UI(fIdx).plotLayouts{tabIdx};
            targetLayout.RowHeight{end+1} = flightdash.util.AppConstants.PLOT_ROW_HEIGHT; 
            newRowIdx = numel(targetLayout.RowHeight);
            % [FIX] 한 화면 3개 정책에 맞춰 즉시 row height 정규화
            app.updatePlotRowHeights(fIdx);
            
            p = uipanel(targetLayout, 'BorderType', 'line', 'BackgroundColor', 'w');
            p.Layout.Row = newRowIdx;
            p.Layout.Column = 1;
            
            axGrid = uigridlayout(p, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}, 'Padding', [5 5 5 5]);
            ax = uiaxes(axGrid);
            ax.Layout.Row = 1;
            ax.Layout.Column = 1;
            
            % [V3.10] H 패널 Tab 플롯 전용 커스텀 툴바 (Restore/ZoomIn/ZoomOut/Pan)
            %         Map/Altitude/비디오/게이지 axes는 툴바 숨김 유지
            %         휠 줌/드래그 팬 기본 상호작용도 함께 허용
            %         스턱 방어는 handlePlotXLimChange의 zoom/pan off 로직이 담당
            ax.Interactions = [panInteraction, zoomInteraction]; 
            tb = axtoolbar(ax, {'restoreview', 'zoomin', 'zoomout', 'pan'});
            tb.Visible = 'on'; 
            
            grid(ax, 'on'); set(ax, 'XMinorGrid', 'on', 'YMinorGrid', 'on');
            plot(ax, tData, yData, 'LineWidth', 1.5, 'Color', [0.15 0.38 0.82]);
            xlabel(ax, 'Time(s)', 'FontWeight', 'bold', 'FontSize', 9); 
            ylabel(ax, yLabelStr, 'FontWeight', 'bold', 'FontSize', 10, 'Interpreter', 'none');
            
            hold(ax, 'on');
            currIdx = app.Models(fIdx).currentIndex;
            currTime = tData(currIdx);
            currY = yData(currIdx);
            
            % [개선안 3] 라인 두께(3.0) 및 반투명(0.5), 마커 크기(14) 대폭 확대
            tl = xline(ax, currTime, 'r', 'LineWidth', 3.0, 'Alpha', 0.5, 'HitTest', 'on');
            mk = plot(ax, currTime, currY, 'p', 'MarkerFaceColor', [0.98 0.75 0.14], ...
                      'MarkerEdgeColor', [0.71 0.33 0.04], 'MarkerSize', 14, 'HitTest', 'on');
            
            tl.ButtonDownFcn = @(src, event) app.startPlotMarkerDrag(fIdx, tabIdx, src, event);
            mk.ButtonDownFcn = @(src, event) app.startPlotMarkerDrag(fIdx, tabIdx, src, event);
            
            app.UI(fIdx).plotAxes{tabIdx}{end+1} = ax;
            app.UI(fIdx).timeLines{tabIdx}{end+1} = tl;
            app.UI(fIdx).timeMarkers{tabIdx}{end+1} = mk;
            app.UI(fIdx).plotData{tabIdx}{end+1} = yData;
            
            L = addlistener(ax, 'XLim', 'PostSet', @(~,~) app.handlePlotXLimChange(fIdx, ax));
            app.UI(fIdx).xLimListeners{tabIdx}{end+1} = L;
            
            allAxes = [app.UI(fIdx).plotAxes{tabIdx}{:}];
            if numel(allAxes) > 1
                linkaxes(allAxes, 'x');
            end
            
            drawnow;
        end
    end

    % =========================================================================
    % 데이터 파서 및 시각화 업데이트
    % =========================================================================
    methods (Access = private)
        function parseFlightData(app, fIdx, filepath)
            opts = detectImportOptions(filepath);
            opts.DataLines = [2 Inf];
            opts.VariableNamingRule = 'preserve'; 
            
            if ~isempty(opts.VariableNames)
                opts.VariableNames{1} = 'time'; 
            end
            
            validTypes = {'double', 'single', 'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'};
            for k = 1:length(opts.VariableTypes)
                if ismember(opts.VariableTypes{k}, validTypes)
                    opts = setvartype(opts, opts.VariableNames{k}, 'double');
                end
            end
            
            dataTbl = readtable(filepath, opts);
            app.applyOptionFile(fIdx, dataTbl, false);
            
            if any(ismissing(app.Models(fIdx).rawData), 'all')
                app.Models(fIdx).rawData = fillmissing(app.Models(fIdx).rawData, 'linear', 'DataVariables', @isnumeric); 
            end
            app.markInvalidGpsAsNaN(fIdx);
        end
        
        function applyOptionFile(app, fIdx, dataTbl, isMock)
            csvHeaders = dataTbl.Properties.VariableNames;
            numHeaders = length(csvHeaders);
            optFileName = sprintf('option%d.dat', fIdx);
            
            reqKeys = flightdash.util.AppConstants.REQ_KEYS;
            mappedCols = struct();
            for i = 1:length(reqKeys)
                mappedCols.(reqKeys{i}) = ''; 
            end
            
            displayMeta = struct('header', {}, 'unit', {}, 'format', {}, 'scale', {}, 'order', {});
            
            if isfile(optFileName)
                lines = readlines(optFileName, 'EmptyLineRule', 'skip');
                section = 0;
                for i = 1:length(lines)
                    lineStr = strtrim(lines(i));
                    if startsWith(lineStr, '#'), section = section + 1; continue; end
                    if section == 1 
                        parts = split(lineStr, ':');
                        if length(parts) >= 2
                            k = char(strtrim(parts(1))); 
                            v = char(strtrim(parts(2)));
                            if isfield(mappedCols, k) && ismember(v, csvHeaders)
                                mappedCols.(k) = v; 
                            end
                        end
                    elseif section == 2 
                        parts = split(lineStr, ',');
                        if length(parts) >= 4
                            hdr   = char(strtrim(parts(1)));
                            unit  = char(strtrim(parts(2)));
                            fmt   = char(strtrim(parts(3)));
                            order = str2double(strtrim(parts(4)));
                            if length(parts) >= 5
                                scale = str2double(strtrim(parts(5)));
                            else
                                scale = 1.0;
                            end
                            if ~isnan(order) && ismember(hdr, csvHeaders)
                                newEntry = struct('header', hdr, 'unit', unit, 'format', fmt, ...
                                                  'scale', scale, 'order', order);
                                displayMeta(end+1) = newEntry; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
            
            for i = 1:length(reqKeys)
                if isempty(mappedCols.(reqKeys{i})) && (i <= numHeaders)
                    mappedCols.(reqKeys{i}) = csvHeaders{i};
                end
            end
            
            if isempty(displayMeta)
                for i = 1:numHeaders
                    displayMeta(end+1) = struct('header', csvHeaders{i}, 'unit', '-', ...
                                                'format', '%.6f', 'scale', 1.0, 'order', i); %#ok<AGROW>
                end
            else
                orders = [displayMeta.order];
                if (length(unique(orders)) == length(orders)) && (min(orders) == 1) && (max(orders) == length(orders))
                    [~, sortIdx] = sort([displayMeta.order]); 
                    displayMeta = displayMeta(sortIdx);
                else
                    for i = 1:length(displayMeta)
                        displayMeta(i).order = i; 
                    end
                end
                
                existingHeaders = {displayMeta.header};
                missingHeaders = setdiff(csvHeaders, existingHeaders, 'stable');
                for i = 1:length(missingHeaders)
                    displayMeta(end+1) = struct('header', missingHeaders{i}, 'unit', '-', ...
                                                'format', '%.6f', 'scale', 1.0, ...
                                                'order', length(displayMeta) + i); %#ok<AGROW>
                end
            end
            
            for i = 1:length(displayMeta)
                if isMock, displayMeta(i).scale = 1.0; end
                colName = displayMeta(i).header;
                if displayMeta(i).scale ~= 1.0
                    dataTbl.(colName) = dataTbl.(colName) * displayMeta(i).scale;
                end
            end
            
            app.Models(fIdx).rawData = dataTbl; 
            app.Models(fIdx).mappedCols = mappedCols; 
            app.Models(fIdx).displayMeta = displayMeta; 
            app.Models(fIdx).selectedRow = 1; 
            app.Models(fIdx).isMockData = isMock;
            
            % GPS invalid marker 처리는 parseFlightData의 fillmissing 이후 수행한다.
            % 여기서 NaN으로 바꾸면 fillmissing이 다시 보간해 잘못된 경로가 생길 수 있다.
        end
        
        function markInvalidGpsAsNaN(app, fIdx)
            % [PERF] 잘못된 좌표(0,0) 1회 NaN 전처리
            % - fillmissing 이후 수행해 invalid point가 보간으로 복원되지 않게 한다.
            % - plot은 NaN 만나면 자동으로 선을 끊음 → 동작 동일
            try
                mappedCols = app.Models(fIdx).mappedCols;
                if isfield(mappedCols, 'Lat') && isfield(mappedCols, 'Lon')
                    if isempty(mappedCols.Lat) || isempty(mappedCols.Lon), return; end
                    lats = app.Models(fIdx).rawData.(mappedCols.Lat);
                    lons = app.Models(fIdx).rawData.(mappedCols.Lon);
                    % [STABILITY] (0,0) 좌표 + 비유한값(NaN/Inf) 모두 NaN 처리
                    % - 센서 이상으로 Inf가 유입되거나 한쪽 좌표만 NaN인 경우도 같은 지점으로 정리
                    invalid = ((lats == 0) & (lons == 0)) | ~isfinite(lats) | ~isfinite(lons);
                    if any(invalid)
                        lats(invalid) = NaN;
                        lons(invalid) = NaN;
                        app.Models(fIdx).rawData.(mappedCols.Lat) = lats;
                        app.Models(fIdx).rawData.(mappedCols.Lon) = lons;
                    end
                end
            catch ME, app.logCaught(ME, 'NaN preprocess'); end
        end

        function generateMockFlightData(app, fIdx)
            latRange = app.Models(fIdx).bounds.maxLat - app.Models(fIdx).bounds.minLat; 
            lonRange = app.Models(fIdx).bounds.maxLon - app.Models(fIdx).bounds.minLon;
            if latRange <= 0, latRange = 0.1; end 
            if lonRange <= 0, lonRange = 0.1; end
            
            minLat = app.Models(fIdx).bounds.minLat;
            maxLat = app.Models(fIdx).bounds.maxLat;
            minLon = app.Models(fIdx).bounds.minLon;
            maxLon = app.Models(fIdx).bounds.maxLon;
            
            currLat = minLat + latRange / 2 + (fIdx * 0.02); 
            currLon = minLon + lonRange / 2 - (fIdx * 0.02);
            currAlt = 5000 + (fIdx * 500); 
            currHdg = (rand() * 360) - 180; 
            currRoll = 0; 
            currPitch = 5;
            speed = min(latRange, lonRange) * 0.005;
            
            N = flightdash.util.AppConstants.MOCK_STEP_COUNT;
            time_s   = zeros(N, 1); lat_deg = zeros(N, 1); lon_deg = zeros(N, 1);
            alt_ft   = zeros(N, 1); hdg_deg = zeros(N, 1); roll_deg = zeros(N, 1); 
            pitch_deg = zeros(N, 1);
            
            for i = 1:N
                time_s(i) = i-1; lat_deg(i) = currLat; lon_deg(i) = currLon;
                alt_ft(i) = currAlt; hdg_deg(i) = currHdg; roll_deg(i) = currRoll; pitch_deg(i) = currPitch;
                
                if i > 50 && i < 100
                    currRoll = min(currRoll + 2, 45); currHdg = currHdg + currRoll * 0.1;
                elseif i >= 100 && i < 130
                    currRoll = currRoll * 0.9;
                elseif i > 150
                    currRoll = max(currRoll - 2, -45); currHdg = currHdg + currRoll * 0.1;
                else
                    currRoll = currRoll * 0.9; 
                end
                
                if currHdg > 180, currHdg = currHdg - 360; end
                if currHdg <= -180, currHdg = currHdg + 360; end
                
                if i < 80
                    currPitch = 5; currAlt = currAlt + 20; 
                elseif i > 120
                    currPitch = -3; currAlt = currAlt - 15; 
                else
                    currPitch = 0; 
                end
                
                currPitch = currPitch + (rand() - 0.5) * 1; 
                currRoll = currRoll + (rand() - 0.5) * 2;
                
                if currPitch > 180, currPitch = currPitch - 360; end
                if currPitch <= -180, currPitch = currPitch + 360; end
                if currRoll > 180, currRoll = currRoll - 360; end
                if currRoll <= -180, currRoll = currRoll + 360; end
                
                mathAngle = (90 - currHdg) * pi / 180;
                currLon = currLon + cos(mathAngle) * speed; 
                currLat = currLat + sin(mathAngle) * speed;
                
                if currLat > maxLat
                    currLat = maxLat - (currLat - maxLat);
                    currHdg = -currHdg;  
                elseif currLat < minLat
                    currLat = minLat + (minLat - currLat);
                    currHdg = -currHdg;
                end
                if currLon > maxLon
                    currLon = maxLon - (currLon - maxLon);
                    currHdg = 180 - currHdg;
                elseif currLon < minLon
                    currLon = minLon + (minLon - currLon);
                    currHdg = 180 - currHdg;
                end
                
                if currHdg > 180, currHdg = currHdg - 360; end
                if currHdg <= -180, currHdg = currHdg + 360; end
            end
            
            optFileName = sprintf('option%d.dat', fIdx); 
            baseKeys = flightdash.util.AppConstants.REQ_KEYS;
            varNames = baseKeys;
            
            if isfile(optFileName)
                lines = readlines(optFileName, 'EmptyLineRule', 'skip'); 
                section = 0;
                for idxLine = 1:length(lines)
                    lineStr = strtrim(lines(idxLine));
                    if startsWith(lineStr, '#'), section = section + 1; continue; end
                    if section == 1
                        parts = split(lineStr, ':');
                        if length(parts) >= 2
                            k = char(strtrim(parts(1))); v = char(strtrim(parts(2))); 
                            matchIdx = find(strcmp(baseKeys, k));
                            if ~isempty(matchIdx), varNames{matchIdx} = v; end
                        end
                    end
                end
            end
            
            mockTbl = table(time_s, roll_deg, pitch_deg, hdg_deg, alt_ft, lat_deg, lon_deg, 'VariableNames', varNames);
            app.applyOptionFile(fIdx, mockTbl, true);
            
            app.setupDataUI(fIdx);
            app.UI(fIdx).fileNameLabel.Text = '모의 데이터 (Auto)';
        end

        function calculateBounds(app, fIdx)
            minLat = 90; maxLat = -90; minLon = 180; maxLon = -180; 
            minAlt = 99999; maxAlt = -99999; hasData = false;
            
            if ~isempty(app.CoastlineData)
                minLat = min(minLat, min(app.CoastlineData(:,1))); maxLat = max(maxLat, max(app.CoastlineData(:,1)));
                minLon = min(minLon, min(app.CoastlineData(:,2))); maxLon = max(maxLon, max(app.CoastlineData(:,2))); 
                hasData = true;
            end
            
            if ~isempty(app.Models(fIdx).rawData)
                lats = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lat); 
                lons = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Lon); 
                alts = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Alt);
                
                % [PERF] NaN 전처리 적용 → omitnan 사용 (validIdx 별도 계산 불필요)
                if any(~isnan(lats))
                    minLat = min(minLat, min(lats, [], 'omitnan')); 
                    maxLat = max(maxLat, max(lats, [], 'omitnan')); 
                    minLon = min(minLon, min(lons, [], 'omitnan')); 
                    maxLon = max(maxLon, max(lons, [], 'omitnan')); 
                end
                minAlt = min(minAlt, min(alts)); maxAlt = max(maxAlt, max(alts)); 
                hasData = true;
            end
            
            if ~isempty(app.FixedAreaBounds)
                app.Models(fIdx).bounds.minLat = app.FixedAreaBounds.minLat; 
                app.Models(fIdx).bounds.maxLat = app.FixedAreaBounds.maxLat;
                app.Models(fIdx).bounds.minLon = app.FixedAreaBounds.minLon; 
                app.Models(fIdx).bounds.maxLon = app.FixedAreaBounds.maxLon;
                app.Models(fIdx).bounds.isValid = true;
            elseif hasData
                latPad = max((maxLat - minLat) * 0.05, 0.01); lonPad = max((maxLon - minLon) * 0.05, 0.01);
                app.Models(fIdx).bounds.minLat = minLat - latPad; app.Models(fIdx).bounds.maxLat = maxLat + latPad;
                app.Models(fIdx).bounds.minLon = minLon - lonPad; app.Models(fIdx).bounds.maxLon = maxLon + lonPad;
                app.Models(fIdx).bounds.isValid = true;
            end
            
            if hasData
                altPad = max((maxAlt - minAlt) * 0.1, 100);
                app.Models(fIdx).altBounds.minAlt = minAlt - altPad; app.Models(fIdx).altBounds.maxAlt = maxAlt + altPad;
            end
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
                app.updateDashboard(fIdx, 1);
            end
        end

        function initPlots(app, fIdx)
            if isempty(app.Models(fIdx).rawData), return; end
            bnds = app.Models(fIdx).bounds;
            
            % --- Map 설정 ---
            axMap = app.UI(fIdx).mapAxes; cla(axMap);
            if bnds.isValid
                axis(axMap, [bnds.minLon, bnds.maxLon, bnds.minLat, bnds.maxLat]); 
                daspect(axMap, [1 1 1]); 
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
            
            % 첫 NaN 아닌 위치
            firstValid = find(~isnan(pathLon) & ~isnan(pathLat), 1); 
            if isempty(firstValid), firstValid = 1; end
            
            app.UI(fIdx).hMapPath = plot(axMap, pathLon(firstValid), pathLat(firstValid), 'Color', lineColor, 'LineWidth', 2);
            app.UI(fIdx).hgMapPlane = hgtransform('Parent', axMap);
            scale = (bnds.maxLon - bnds.minLon) * 0.03; 
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
            
            % [개선안 3] 타임라인 두께 증가 및 투명도 반영, 마커 크기 14로 고정
            app.UI(fIdx).hAltPath = plot(axAlt, times(1), alts(1), 'Color', [0.06 0.72 0.51], 'LineWidth', 2, 'HitTest', 'off');
            app.UI(fIdx).hAltMarker = plot(axAlt, times(1), alts(1), 'p', 'MarkerFaceColor', [0.98 0.75 0.14], 'MarkerEdgeColor', [0.71 0.33 0.04], 'MarkerSize', 14, 'HitTest', 'on');
            app.UI(fIdx).timeLine = xline(axAlt, times(1), 'r', 'LineWidth', 3.0, 'Alpha', 0.5, 'HitTest', 'on');
            
            app.UI(fIdx).hAltMarker.ButtonDownFcn = @(src, event) app.startPlotMarkerDrag(fIdx, 0, src, event);
            app.UI(fIdx).timeLine.ButtonDownFcn = @(src, event) app.startPlotMarkerDrag(fIdx, 0, src, event);
            
            % Altitude 패널의 Zoom/Pan 시 동기화 리스너 추가
            app.UI(fIdx).altXLimListener = addlistener(axAlt, 'XLim', 'PostSet', @(~,~) app.handlePlotXLimChange(fIdx, axAlt));

            % --- 비행자세 게이지 설정 ---
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
                    % FontSize를 0.06으로 유지하여 원안의 숫자 크기를 적절하게 설정
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

        function updateDashboard(app, fIdx, index)
            if isempty(app.Models(fIdx).rawData), return; end
            
            timeCol = app.Models(fIdx).mappedCols.Time; 
            currTime = app.Models(fIdx).rawData.(timeCol)(index); 
            app.UI(fIdx).currentTimeLabel.Text = sprintf('%.3f s', currTime);
            
            % Table 
            metaList = app.Models(fIdx).displayMeta; 
            dataCell = cell(length(metaList), 2);
            for i = 1:length(metaList)
                m = metaList(i); 
                val = app.Models(fIdx).rawData.(m.header)(index); 
                dataCell{i, 1} = sprintf('%s (%s)', m.header, m.unit); 
                dataCell{i, 2} = sprintf(m.format, val);
            end
            app.UI(fIdx).dataTable.Data = dataCell;

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
            
            % Gauges
            app.UI(fIdx).pitchLabel.Text = sprintf('Pitch %+.3f°', pitch); 
            app.UI(fIdx).rollLabel.Text  = sprintf('Roll %+.3f°', roll); 
            app.UI(fIdx).hdgLabel.Text   = sprintf('Heading %+.3f°', hdg);
            
            set(app.UI(fIdx).hgPitch, 'Matrix', makehgtform('zrotate', -pitch * pi / 180)); 
            set(app.UI(fIdx).hgRoll,  'Matrix', makehgtform('zrotate', -roll * pi / 180)); 
            set(app.UI(fIdx).hgHdg,   'Matrix', makehgtform('zrotate', -hdg * pi / 180));
            
            % 비디오 및 H 영역 갱신
            % [V3.12 2.2.3] 비디오 동기 설정 시 Frame No 기반 갱신 (정확한 매핑)
            if app.VideoSyncState(fIdx).IsSynced
                try
                    targetFrame = app.timeToFrame(fIdx, currTime);
                    app.VideoSyncState(fIdx).CurrentFrame = targetFrame;
                    % [V3.14] Frame 마커 + xline + 슬라이더 + 라벨 일괄 동기화
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);
                    app.updateVideoFrameByFrameNo(fIdx, targetFrame, 'sync');  % 정확한 동기화
                catch
                    app.updateVideoFrame(fIdx, currTime);  % 폴백
                end
            else
                % 동기 미설정: 기존 방식대로 시간 기반 갱신
                % app.updateVideoFrame(fIdx, currTime);  % <--- 이 줄을 주석 처리하여 완전 분리
            end
            app.updatePlotTimeLines(fIdx, index, currTime);
            
            drawnow limitrate;
        end
    end

    % =========================================================================
    % UI 레이아웃 생성 팩토리 (Create Layout)
    % =========================================================================
    methods (Access = private)
        function createLayout(app)
            % [REFACTOR Step 3] 메인 골격 + 채널별 빌드는 view 패키지로 위임
            % - 헤더: buildHeaderBar (기존 유지)
            % - 채널: flightdash.view.ChannelLayout.build (6컬럼 위임)
            mainLayout = uigridlayout(app.UIFigure, [2 1]);
            mainLayout.RowHeight = {'fit', '1x'};
            mainLayout.Padding = [2 2 2 2];
            mainLayout.RowSpacing = 2;
            
            app.buildHeaderBar(mainLayout);
            
            scrollBody = uipanel(mainLayout, 'Scrollable', 'on', ...
                'BorderType', 'none', 'BackgroundColor', [0.94 0.94 0.96]);
            bodyGrid = uigridlayout(scrollBody, [2 1]);
            bodyGrid.ColumnWidth = {'1x'};
            bodyGrid.RowHeight = {'1x', '1x'};
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
            
            % [V3.22 #5] UI 평면 struct를 그룹화된 view로 alias (호환 유지)
            app.buildUIGroups();
        end
        
        
        % [V3.22 #5] 평면 UI struct를 그룹화된 view(struct)로 묶어 별도 속성에 저장
        % - app.UIGroup(fIdx).attitude.rollAxes = app.UI(fIdx).rollAxes  (alias)
        % - 새 코드는 app.UIGroup(...) 경로를 권장; 기존 코드는 app.UI(...) 그대로
        % - 핸들 객체이므로 alias가 동일 객체를 가리켜 변경 시 양쪽 모두 동기됨
        function buildUIGroups(app)
            % [V3.22 #5] 평면 UI struct를 그룹화된 view(struct array, 1x2)로 묶음
            % - 핸들 객체이므로 alias가 동일 객체를 가리켜 변경 시 양쪽 모두 동기됨
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
                
                % 지도/고도(MapAlt) 그룹
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
                
                % 플롯(H 영역) 그룹 - cell array는 struct() ctor 회피
                grpPlots = struct();
                grpPlots.tabGroup       = u.tabGroup;
                grpPlots.plotTabs       = u.plotTabs;
                grpPlots.plotLayouts    = u.plotLayouts;
                grpPlots.plotAxes       = u.plotAxes;
                grpPlots.timeLines      = u.timeLines;
                grpPlots.timeMarkers    = u.timeMarkers;
                grpPlots.plotData       = u.plotData;
                grpPlots.xLimListeners  = u.xLimListeners;
                grp.plots = grpPlots;
                
                % 컨트롤 헤더 그룹
                grp.controls = struct( ...
                    'spinner',          u.spinner, ...
                    'currentTimeLabel', u.currentTimeLabel, ...
                    'fileNameLabel',    u.fileNameLabel, ...
                    'btnAtt',           u.btnAtt, ...
                    'btnMap',           u.btnMap, ...
                    'btnVid',           u.btnVid);
                
                % 데이터 테이블 + 컨테이너
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
            ui = flightdash.view.HeaderBar.build(mainLayout);
            app.SyncInput = ui.SyncInput;
            app.SyncBtn   = ui.SyncBtn;
        end

        % [REFACTOR] createGaugePanel는 flightdash.view.AttitudePanel.createGauge로 이동
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
% 워커 path 검색을 위해 본 파일과 동일 폴더에 위치해야 함.
% =========================================================================
