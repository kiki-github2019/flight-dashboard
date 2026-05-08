classdef FlightDataDashboard < matlab.apps.AppBase
    % =========================================================================
    % 鍮꾪뻾 ?곗씠??由щ럭 ??쒕낫??- V3.22 (由ы뙥?좊쭅: 紐⑤뱢 遺꾪빐 + 罹먯떆 ?먮즺援ъ“ 媛쒖꽑)
    % ?ㅻ챸:
    %   [V3.22 蹂寃쎌궗??
    %   - #1 ErrorLog ring buffer (silent catch???ы썑 議곗궗 媛??
    %        + dumpErrorLog(n, filterTag) ?ы띁 硫붿꽌??
    %   - #2 cacheGetFrame??lastUse 移댁슫??湲곕컲 O(1) lookup?쇰줈 ?꾪솚
    %        (cell 諛곗뿴 reference shuffle ?쒓굅 ?????꾨젅??lookup ??GC ?뺣젰 媛먯냼)
    %        cacheStoreFrame? in-place 媛깆떊 + lastUse ?숆린 愿由?
    %        evictByScore??lastUse ?몄옄 異붽? ??score = (hits * recency) / bytes
    %   - #3 loadAviFile??6媛??ы띁濡?遺꾪빐:
    %        confirmVideoReplace / invalidateFrameCache / computeStartTimeFromFlightData
    %        cleanupVideoResources / openVideoReader / applyVideoLoadedUI
    %        computeTotalFrames / loadFirstFrame
    %   - #4 留ㅼ쭅 ?섎쾭 ?곸닔?? ASYNC_WORKER_COUNT, WORKER_VR_CACHE_SLOTS,
    %        MAX_SEQ_READ_STEP, MAX_PENDING_ITERS
    %   - #5 UIGroup alias: ?됰㈃ UI struct瑜?attitude/map/video/plots/controls/data
    %        濡?洹몃９?? 湲곗〈 ?됰㈃ ?꾨뱶??洹몃?濡??좎?(100% ?명솚), ?좉퇋 肄붾뱶??洹몃９ ?ъ슜
    %   - #6 Static wrapper: workerDecodeFrame / workerCleanupCache
    %        ???ν썑 +flightdash ?⑦궎吏 留덉씠洹몃젅?댁뀡 ?듭뀡 ?뺣낫
    %   - #7 createLayout 遺꾪빐: buildHeaderBar 異붿텧 + 鍮꾪뻾寃쎈줈 猷⑦봽 ?뱀뀡 媛?대뱶 異붽?
    %
    %   [V3.21 #1-A] Generation counter (AsyncGen): 留?startAsyncDecode ?몄텧 ??
    %     利앷?, future??myGen 罹≪쿂 ??onAsyncDecodeComplete?먯꽌 鍮꾧탳?섏뿬 stale
    %     寃곌낵 ?먭린. 媛숈? frame?대씪??generation mismatch硫?臾댁떆 ??race 李⑤떒.
    %   [V3.21 #3-A] 3怨꾩링 遺꾨━:
    %     Layer 1 requestFrame: 吏꾩엯??+ 罹먯떆 lookup + sync/async ?꾨왂 ?좏깮
    %     Layer 2 decodeFrameSync / startAsyncDecode: ?붿퐫??(?꾨왂 ?⑦꽩)
    %     Layer 3 displayFrame: ?쒖떆 + 罹먯떆 store (write-through ?⑥씪 異쒓뎄)
    %     湲곗〈 updateVideoFrameByFrameNo??requestFrame濡??꾩엫 (?명솚).
    %   [V3.21 #2-A] persistent VideoReader in worker:
    %     asyncDecodeFramePersistent ?몃? ?⑥닔?먯꽌 persistent 蹂?섎줈 VR ?ъ궗??
    %     ???몄텧??~50ms??ms濡??⑥텞. ?뚯씪 蹂寃??쒖뿉留?VR ?ъ깮??
    %   [V3.20 ?좎?] 紐낆떆??由ъ냼???뺣━, ?숆린??濡쒓렇 prefix ?쒖???
    %   [V3.19 ?좎?] 鍮꾨룞湲??붿퐫?? adaptive prefetch, 媛以?LRU.
    %   [V3.18 ?좎?] cache lookup clamp, Pending ?꾩쟾 ?뚯쭊, hard limit 1.0.
    %   [V3.17 ?좎?] InGoToFrame coalescing, IsDecoding 媛??
    % =========================================================================

    % Shared constants live in flightdash.util.AppConstants.

    properties (Access = public)
        UIFigure
        UI
        UIGroup           % [V3.22 #5] UI瑜?attitude/map/video/plots/controls/data濡?洹몃９?뷀븳 alias
        SyncInput
        SyncBtn

        Models
        SyncState
        VideoState
        VideoSyncState    % [V3.12] 鍮꾨뵒??鍮꾪뻾?곗씠???숆린???뺣낫 (諛곗뿴 [1x2])

        CoastlineData
        FixedAreaBounds

        DebugMode         = false   % [V3.14 ??ぉ 6] true ??zoom/pan off ??濡쒓렇 異쒕젰
        State             = 'IDLE'  % [V3.17 (8)] 'IDLE' | 'DRAGGING' | 'UPDATING' | 'DECODING'
        UseAsyncDecode    = false   % [V3.19 (1)] 鍮꾨룞湲??붿퐫???쒖꽦??(Parallel Toolbox ?꾩슂)
    end

    properties (Access = private)
        IsUpdating          = [false, false] % ?ш? 諛⑹? ?뚮옒洹?
        IsProgrammaticXLim  = [false, false] % [V3.11 A] 梨낆옣 ?섍린湲????꾨줈洹몃옒諛?XLim 蹂寃???由ъ뒪??李⑤떒
        IsDraggingPanner    = false         % compact range bar handle drag state
        PannerDragFIdx      = 0             % compact range bar drag channel
        PannerDragSide      = ''            % 'left' or 'right'
        LastDisplayedFrame  = [0, 0]        % [PATCH] ?숈씪 ?꾨젅??議곌린 諛섑솚??
        HISplitterFIdx      = 0             % [PATCH UX-3] H/I 寃쎄퀎 ?쒕옒洹?以묒씤 梨꾨꼸
        IsDraggingSplitter  = false         % [PATCH UX-3b] splitter ?쒕옒洹??곹깭 ?뚮옒洹?
        VideoUserResized    = [false, false] % [FIX] ?ъ슜?먭? splitter濡?議곗옉?덈뒗吏 (?먮룞 由ъ궗?댁쫰 李⑤떒)
        % [REFACTOR Step 1] 罹먯떆??蹂꾨룄 紐⑤뜽 媛앹껜濡??꾩엫. 湲곗〈 8媛??띿꽦 ??1媛쒕줈 ?⑥씪??
        % - flightdash.model.FrameCacheModel 諛곗뿴 [1x2]
        % - 湲곗〈 cacheGetFrame/cacheStoreFrame ?깆? ?명솚???꾪빐 thin wrapper濡??붾쪟
        CacheModel          = []              % [REFACTOR] flightdash.model.FrameCacheModel 諛곗뿴
        VideoMdl            = []              % [REFACTOR Step 2] flightdash.model.VideoModel 諛곗뿴 [1x2]
        SyncMdl             = []              % [REFACTOR Step 2] flightdash.model.SyncModel 諛곗뿴 [1x2]
        PlaybackState       = []              % [REFACTOR] per-channel guard/pending state model [1x2]
        VideoListeners      = {[], []}        % [REFACTOR Step 2-C] event.listener ?몃뱾 蹂닿? (GC 諛⑹?)
        % [REFACTOR Step 4] 肄쒕갚 吏꾩엯??而⑦듃濡ㅻ윭
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
        CacheBudgetMB       = 30              % [V3.14 ??ぉ 3] ?명솚 ?좎?: setCacheBudget 吏꾩엯?먯씠 ?ъ슜
        % --- 鍮?罹먯떆 ?띿꽦 (洹몃?濡??좎?) ---
        InGoToFrame         = [false, false] % [V3.16] goToFrame ?ъ쭊??李⑤떒 ?뚮옒洹?
        PendingFrame        = [NaN, NaN]     % [V3.17 (1)(9)] 泥섎━ 以??ㅼ뼱??理쒖떊 frame ?붿껌
        PendingMode         = {'', ''}        % [V3.17 (1)(9)] 泥섎━ 以??ㅼ뼱??理쒖떊 mode
        InCascade           = false          % [V3.17 (4)(11)] cascade ?ш? 媛??(?몄뒪?댁뒪 ?띿꽦)
        IsDeleting          = false          % [FIX] delete(app) 以묐났 ?몄텧 諛⑹뼱 ?뚮옒洹?
        IsDecoding          = [false, false] % [V3.17 (7)] ?붿퐫??吏꾪뻾 以?媛??
        AsyncPool           = []              % [V3.19 (1)] parallel pool ?몃뱾
        AsyncFutures        = {[], []}        % [V3.19 (1)] 吏꾪뻾 以?parfeval future
        AsyncTargetFrame    = [NaN, NaN]      % [V3.19 (1)] 鍮꾨룞湲??붿퐫??以묒씤 frame No
        AsyncGen            = [0, 0]          % [V3.21 #1-A] generation counter (race 李⑤떒)
        VideoFilePath       = {'', ''}        % [V3.19 (1)] worker媛 ?먯껜 VideoReader ?앹꽦??
        DragVelocity        = [0, 0]          % [V3.19 (2)] frames/sec (遺?? 諛⑺뼢)
        DragVelocitySamples = {[], []}        % [V3.19 (2)] 理쒓렐 ?섑뵆 (?대룞?됯퇏??
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
        % [REFACTOR Step 0] ErrorLog??flightdash.util.ErrorLog ?깃??ㅼ쑝濡??꾩엫
        % - 湲곗〈 ErrorLog/ErrorLogCapacity ?띿꽦? ???댁긽 ?ъ슜?섏? ?딆쑝???명솚???꾪빐 ?좎??섏? ?딄퀬 ?쒓굅
    end

    methods (Access = public)
        % ---------------------------------------------------------------------
        % ?앹꽦??諛?珥덇린??
        % ---------------------------------------------------------------------
        function app = FlightDataDashboard()
            app.Models = [app.createEmptyModel(), app.createEmptyModel()];
            app.SyncState = struct('IsSynced', false, 'SyncT1', 0, 'SyncT2', 0);
            app.VideoState = struct('videoReader', {[], []}, 'videoStartTime', {0, 0}, 'vidImageHandle', {[], []});
            % [V3.12] VideoSyncState 珥덇린?? ??鍮꾪뻾寃쎈줈蹂??숆린???뺣낫
            app.VideoSyncState = struct( ...
                'IsSynced',     {false, false}, ...     % ?숆린 ?ㅼ젙 ?꾨즺 ?щ?
                'AnchorFrame',  {0, 0}, ...             % ?숆린 湲곗? ?꾨젅??踰덊샇 (?뺤닔)
                'AnchorOffset', {0, 0}, ...             % [V3.23] sub-frame 蹂댁젙 [-0.5, 0.5]
                'AnchorTime',   {0, 0}, ...             % ?숆린 湲곗? 鍮꾪뻾?쒓컙(珥?
                'VideoFps',     {70, 70}, ...           % ?곸긽 Hz (湲곕낯 70)
                'DataFps',      {50, 50}, ...           % 鍮꾪뻾?곗씠??Hz (湲곕낯 50)
                'TotalFrames',  {0, 0}, ...             % ?곸긽 珥??꾨젅????
                'CurrentFrame', {1, 1});                % ?꾩옱 ?꾨젅???꾩튂

            % [REFACTOR Step 1] FrameCacheModel ?몄뒪?댁뒪 ?앹꽦 (梨꾨꼸蹂?1媛쒖뵫)
            app.CacheModel = [flightdash.model.FrameCacheModel(app.CacheBudgetMB), ...
                              flightdash.model.FrameCacheModel(app.CacheBudgetMB)];

            % [REFACTOR Step 2] VideoModel/SyncModel ?몄뒪?댁뒪 ?앹꽦 (梨꾨꼸蹂?1媛쒖뵫)
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
                    disp(['option_flight_area.dat 濡쒕뱶 ?ㅽ뙣: ', e.message]);
                end
            end

            close(findobj('Type', 'figure', 'Name', '鍮꾪뻾 ?곗씠??由щ럭 ??쒕낫??(Dual)'));
            % [FIX] AutoResizeChildren='on' ??SizeChangedFcn??臾댁떆?섎뒗 寃쎄퀬 李⑤떒
            % - uigridlayout???먯떇 由ъ궗?댁쫰瑜??대떦?섎?濡?AutoResizeChildren? 遺덊븘??
            initialPos = app.LayoutMgr.initialFigurePosition(app);
            app.UIFigure = uifigure('Name', '鍮꾪뻾 ?곗씠??由щ럭 ??쒕낫??(Dual)', ...
                                    'Units', 'pixels', ...
                                    'Position', app.LayoutMgr.initialFigurePosition(app), ...
                                    'Color', [0.94 0.94 0.96]);
            app.NormalFigurePosition = app.UIFigure.Position;
            try
                app.UIFigure.AutoResizeChildren = 'off';
            catch ME
                app.logCaught(ME, 'UI:AutoResizeChildren');
            end
            app.UIFigure.CloseRequestFcn = @app.UIFigureCloseRequest;
            app.UIFigure.SizeChangedFcn = @(~,~) app.onUIFigureResized();

            % [REFACTOR Step 4] 而⑦듃濡ㅻ윭 ?몄뒪?댁뒪 (createLayout ???꾩닔)
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
                % [REFACTOR Step 2-B] VideoModel?먮룄 ?몃뱾 set
                app.VideoMdl(i).ImageHandle = app.UI(i).vidImageHandle;
                % [REFACTOR Step 2-C] ?대깽??援щ룆: VideoLoaded ??cache recompute, VideoCleared ??invalidate
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
            % [FIX] 以묐났 吏꾩엯 諛⑹뼱 - CloseRequestFcn ??delete ???뚮㈇ 以??ы샇異?李⑤떒
            if app.IsDeleting, return; end
            app.IsDeleting = true;
            try
                if ~isempty(app.PlaybackCtrl) && isvalid(app.PlaybackCtrl)
                    app.PlaybackCtrl.stopAllFlightPlayback();
                end
            catch ME, app.logCaught(ME, 'FlightPlay:delete'); end
            % [V3.20 (5)] 紐낆떆??由ъ냼???뺣━: VideoReader, AsyncPool, futures
            try
                for fIdx = 1:2
                    % [FIX] Future cancel??VR delete蹂대떎 癒쇱? ??worker hang 諛⑹?
                    try
                        if ~isempty(app.AsyncFutures{fIdx}) && isvalid(app.AsyncFutures{fIdx})
                            fut = app.AsyncFutures{fIdx};
                            cancel(fut);
                            try
                                wait(fut, 'finished', 0.5);
                            catch ME_wait
                                app.logCaught(ME_wait, 'Async:cancelWait:delete');
                            end
                            app.AsyncFutures{fIdx} = [];   % post-cancel 紐낆떆 ?대━??
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                    % VideoReader ?뺣━ (worker媛 媛숈? ?뚯씪 ?↔퀬 ?덉쓣 媛?μ꽦 李⑤떒 ??
                    try
                        if ~isempty(app.VideoState(fIdx).videoReader) && ...
                           isvalid(app.VideoState(fIdx).videoReader)
                            delete(app.VideoState(fIdx).videoReader);
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                end
                % 罹먯떆 鍮꾩슦湲?(硫붾え由?利됱떆 ?댁젣) - CacheModel ?꾩엫
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
                app.LastDisplayedFrame = [0, 0];   % [PATCH] 議곌린諛섑솚 ??由ъ뀑
                % [REFACTOR Step 2-C] event listener 紐낆떆 ?댁젣
                for fIdx = 1:numel(app.VideoListeners)
                    try
                        L = app.VideoListeners{fIdx};
                        for k = 1:numel(L)
                            if isvalid(L{k}), delete(L{k}); end
                        end
                    catch ME, app.logCaught(ME, 'silent'); end
                end
                app.VideoListeners = {[], []};

                % [FIX] ?쒗솚 李몄“ 李⑤떒 + EventBus listener 紐낆떆 ?댁젣
                % - EventBus??persistent ?깃??ㅼ씠??listener媛 controller瑜??곴뎄 蹂댁쑀
                % - delete(ctrl) ?몄텧 ??controller.delete() ??Listeners cell ?뺣━
                % - ?⑥닚 [] ??낆? listener leak 諛쒖깮 ???ㅼ쓬 ?ㅽ뻾 ??醫鍮?controller crash
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

            % [PATCH / V3.22 #6 / FIX] ?뚯빱 persistent VR 紐낆떆 ?댁젣 - 2s timeout?쇰줈 hang 李⑤떒
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
                        % [FIX] timeout ??pending future cancel (worker hang 李⑤떒)
                        try, cancel(fCleanup); catch, end
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end

            % [FIX] pool 紐낆떆 ??젣 - ?ㅼ쓬 ?ㅽ뻾?먯꽌 源⑤걮???섍꼍 蹂댁옣
            try
                if ~isempty(app.AsyncPool) && isvalid(app.AsyncPool)
                    delete(app.AsyncPool);
                end
                app.AsyncPool = [];
            catch ME, app.logCaught(ME, 'silent'); end

            try
                app.closeAllAuxFigures();
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
    % ?쒓컙 蹂寃??⑥씪 吏꾩엯??(?숆린???낅뜲?댄듃/?ш?諛⑹?瑜???怨녹뿉??泥섎━)
    % =========================================================================
    methods (Access = public)
        function applyTimeChange(app, fIdx, index)
            if app.stateIsUpdating(fIdx), return; end
            if isempty(app.Models(fIdx).rawData), return; end

            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(index);
            app.Models(fIdx).currentIndex = index;

            % --- ?대떦 寃쎈줈 酉?媛깆떊 ---
            % [FIX] IsUpdating ?뚮옒洹몃? onCleanup?쇰줈 蹂댁옣 - ?덉쇅/return/error 紐⑤몢 ?덉쟾
            app.setStateUpdating(fIdx, true);
            cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
            try
                app.updateDashboard(fIdx, index);
                if abs(app.UI(fIdx).spinner.Value - currTime) > eps
                    app.UI(fIdx).spinner.Value = currTime;
                end
            catch e
                % [FIX] warning ???ErrorLog濡??ы썑 異붿쟻 媛?ν븯寃?
                app.logCaught(e, 'applyTimeChange');
            end
            % cleanup_ 媛 IsUpdating=false 蹂댁옣 ???꾨옒 吏꾪뻾
            clear cleanup_;

            % --- ?숆린?? 寃쎈줈 1 蹂寃???寃쎈줈 2???곕룞 ---
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

    methods (Access = private)
        function resetIsUpdating(app, fIdx)
            % [FIX] applyTimeChange??IsUpdating ?뚮옒洹?由ъ뀑 (onCleanup 肄쒕갚)
            try
                if isvalid(app), app.setStateUpdating(fIdx, false); end
            catch
            end
        end

        function resetInCascade(app)
            % [FIX] updateMarkersOnly??InCascade ?뚮옒洹?由ъ뀑 (onCleanup 肄쒕갚)
            try
                if isvalid(app), app.InCascade = false; end
            catch
            end
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
    % Controller/EventBus 吏꾩엯??諛?硫붿씤 UI 濡쒖쭅
    % =========================================================================
    methods (Access = public)
        function handleFlightFile(app, fIdx)
            [filename, pathname] = uigetfile({'*.dat;*.csv;*.txt', 'Flight data (*.dat, *.csv, *.txt)'}, ...
                sprintf('鍮꾪뻾寃쎈줈 %d ?뚯씪 ?좏깮', fIdx));
            if isequal(filename, 0), return; end

            % [V3.12] 湲곗〈 鍮꾨뵒???숆린 ?ㅼ젙???덉쑝硫??ъ슜???뺤씤 ???댁젣
            if app.VideoSyncState(fIdx).IsSynced
                sel = uiconfirm(app.UIFigure, ...
                    '??鍮꾪뻾?곗씠?곕? 濡쒕뱶?섎㈃ 湲곗〈 鍮꾨뵒??鍮꾪뻾?곗씠???숆린 ?ㅼ젙???댁젣?⑸땲?? 怨꾩냽?섏떆寃좎뒿?덇퉴?', ...
                    '?숆린 ?댁젣 ?뺤씤', ...
                    'Options', {'怨꾩냽', '痍⑥냼'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(sel, '痍⑥냼'), return; end
                app.resetVideoSync(fIdx);
            end

            d = uiprogressdlg(app.UIFigure, 'Title', '?곗씠??濡쒕뵫 以?, ...
                'Message', sprintf('鍮꾪뻾寃쎈줈 %d ?곗씠?곕? ?뚯떛?섍퀬 ?덉뒿?덈떎...', fIdx), ...
                'Indeterminate', 'on');
            try
                fullpath = fullfile(pathname, filename);
                app.parseFlightData(fIdx, fullpath);
                app.FlightFilePath{fIdx} = fullpath;

                timeCol = app.Models(fIdx).mappedCols.Time;
                if ~issorted(app.Models(fIdx).rawData.(timeCol), 'strictascend')
                    errordlg('?쒓컙 ?곗씠?곌? ?쒖감?곸쑝濡?利앷??섏? ?딄굅??以묐났?섏뿀?듬땲??', '?곗씠???ㅻ쪟');
                    close(d);
                    return;
                end

                if ~isempty(app.VideoState(fIdx).videoReader)
                    app.VideoState(fIdx).videoStartTime = app.Models(fIdx).rawData.(timeCol)(1);
                end

                % [V3.12] 鍮꾪뻾?곗씠??Hz ?먮룞 怨꾩궛 ???낅젰? 媛깆떊
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

                % [?섏젙 2] 鍮꾪뻾 ?곗씠???뚯떛 ?? ?대? ?곸긽???대젮?덈떎硫?Video FPS 媛뺤젣 ?ш퀎??
                % [FIX Case 2] ?먮룞 ?숆린(IsSynced=true) ?쒓굅 - "?숆린" 踰꾪듉 ?대┃ ?쒖뿉留??쒖꽦??
                %              FPS ?ш퀎?곕쭔 ?섑뻾?섏뿬 ?쇰꺼/?쒓컙 ?쒖떆???뺤긽 媛깆떊
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
                % [V3.20 (3)] ?곸꽭 ?먮윭 濡쒓렇
                if app.DebugMode
                    fprintf('[Flight] parse failed: %s\n  %s\n  stack: %s\n', ...
                        filename, e.message, e.identifier);
                end
                errordlg(['?ㅻ쪟 諛쒖깮: ', e.message], '?ㅻ쪟');
            end
        end

        function handleCoastFile(app)
            [filename, pathname] = uigetfile('*.csv', '?댁븞???뺣낫 ?뚯씪 ?좏깮');
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
                errordlg(['?ㅻ쪟 諛쒖깮: ', e.message], '?ㅻ쪟');
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
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = '';
                    app.UIFigure.WindowButtonUpFcn = '';
                end
                % [FIX] drag/splitter ?곹깭 紐낆떆 ?대━??(close 以?stale callback 李⑤떒)
                app.IsDraggingSplitter = false;
                app.IsDraggingPanelSplitter = false;
                app.IsDraggingPanner   = false;
                if ~isempty(app.InfoCtrl) && isvalid(app.InfoCtrl), app.InfoCtrl.clearState(); end
                app.MarkerDragCtrl.clearDraggedMarker();
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
            try
                app.autoSaveConfigOnClose();
            catch ME_cfg
                app.logCaught(ME_cfg, 'Config:autoSaveOnClose');
            end
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
            % ?⑤꼸 ?쒖떆/?④? ?좉?. ?ㅼ젣 ??諛곕텇? responsive layout manager媛 ?대떦?쒕떎.
            state = app.UI(fIdx).PanelVisible.(pnlName);
            newState = ~state;
            app.UI(fIdx).PanelVisible.(pnlName) = newState;

            if strcmp(pnlName, 'attitude')
                app.UI(fIdx).panelAttitude.Visible = newState;
                if newState
                    app.UI(fIdx).btnAtt.Text = '?먯꽭 ??;
                else
                    app.UI(fIdx).btnAtt.Text = '?먯꽭 ??;
                end
            elseif strcmp(pnlName, 'map')
                app.UI(fIdx).panelMapAlt.Visible = newState;
                if newState
                    app.UI(fIdx).btnMap.Text = '吏??怨좊룄 ??;
                else
                    app.UI(fIdx).btnMap.Text = '吏??怨좊룄 ??;
                end
            elseif strcmp(pnlName, 'video')
                if newState
                    app.resetVideoWidthPreferences(fIdx);
                end
                app.UI(fIdx).panelVideo.Visible = newState;
                if newState
                    app.UI(fIdx).btnVid.Text = '鍮꾨뵒????;
                else
                    app.UI(fIdx).btnVid.Text = '鍮꾨뵒????;
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
        % 鍮꾨뵒??諛??숆린??
        % ---------------------------------------------------------------------
        function toggleSync(app)
            if app.SyncState.IsSynced
                app.SyncState.IsSynced = false;
                app.SyncBtn.Text = '鍮꾪뻾?쒓컙 ?숆린';
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
                errordlg('?낅젰 ?뺤떇???щ컮瑜댁? ?딆뒿?덈떎. ?? "23.4, 34.4"', '?뺤떇 ?ㅻ쪟');
                return;
            end
            if isempty(app.Models(1).rawData) || isempty(app.Models(2).rawData)
                errordlg('??寃쎈줈 ?곗씠?곌? 紐⑤몢 濡쒕뱶?섏뼱???⑸땲??', '?곗씠??遺議?);
                return;
            end

            t1 = str2double(tokens{1}{1});
            t2 = str2double(tokens{1}{2});
            app.SyncState.SyncT1 = t1;
            app.SyncState.SyncT2 = t2;
            app.SyncState.IsSynced = true;

            app.SyncBtn.Text = '鍮꾪뻾?쒓컙 ?숆린 ?댁젣';
            app.SyncBtn.BackgroundColor = [0.8 0.2 0.2];
            app.SyncInput.Enable = 'off';
            app.UI(2).spinner.Enable = 'off';

            timeCol1 = app.Models(1).mappedCols.Time;
            idx1 = app.findClosestIndexByTime(app.Models(1).rawData.(timeCol1), t1);
            app.applyTimeChange(1, idx1);

            % [V3.20 (2)] ?숆린???붾쾭洹?濡쒓렇 (SyncState - ??鍮꾪뻾?곗씠???쒓컙異?留ㅽ븨)
            if app.DebugMode
                fprintf('[FlightSync] enabled: T1=%.3fs ??T2=%.3fs (offset=%.3fs)\n', ...
                    t1, t2, t2 - t1);
            end
        end

        % [V3.22 #3] loadAviFile 遺꾪빐 - ?ㅼ??ㅽ듃?덉씠??+ 6?④퀎 ?ы띁
        % ?④퀎: 1) ?ъ슜???뺤씤 ??2) 罹먯떆 臾댄슚????3) 湲곗〈 ?먯썝 ?뺣━
        %       4) VR ?앹꽦 ??5) TotalFrames + UI ?숆린????6) 泥??꾨젅??濡쒕뱶
        % 媛??④퀎???ㅽ뙣 ??紐낇솗??醫낅즺 議곌굔??媛吏硫?梨낆엫???쒖젙??
        %
        % [湲곗닠??沅뚯옣?ы빆] ?먰솢???ㅽ겕?щ튃(?щ씪?대뜑 ?꾩쓽 ?대룞) ?깅뒫???꾪빐
        % All-Intra ?щ㎎ ?ъ슜 沅뚯옣:
        %   - 沅뚯옣: AVI (Motion JPEG / Uncompressed), MP4 (All-Intra)
        %   - 鍮꾧텒?? H.264/H.265 Long-GOP MP4
        % Long-GOP ?곸긽? ?꾩쓽 ?꾩튂濡?seek ??媛??媛源뚯슫 ?ㅽ봽?덉엫(I-Frame)遺??
        % ?ㅼ떆 ?붿퐫?⑺빐???섎?濡? ?щ씪?대뜑 ?쒕옒洹???吏?곗씠 ?ы빐吏????덉쓬.
        function loadAviFile(app, fIdx)
            [fname, pname] = uigetfile({'*.avi;*.mp4;*.mkv', 'Video Files (*.avi, *.mp4)'}, sprintf('鍮꾨뵒???좏깮 %d', fIdx));
            if isequal(fname, 0), return; end
            fullPath = fullfile(pname, fname);

            % 1) ?ъ슜???뺤씤 (湲곗〈 ?숆린 ?ㅼ젙 ?댁젣)
            if ~app.confirmVideoReplace(fIdx), return; end

            % 2) ?꾨젅??罹먯떆 臾댄슚??
            app.invalidateFrameCache(fIdx);

            % 3) 湲곗〈 VR/Future ?뺣━ + startTime ?곗텧
            app.invalidateFrameCache(fIdx);
            startTime = app.computeStartTimeFromFlightData(fIdx);
            app.cleanupVideoResources(fIdx);

            % 4) VideoReader ?앹꽦
            vr = app.openVideoReader(fIdx, fullPath, fname);
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

            % 5) TotalFrames ?곗젙 + UI ?꾩젽 ?숆린??
            app.applyVideoLoadedUI(fIdx, vr);

            % 6) 泥??꾨젅??濡쒕뱶 + ?쒖떆 + 罹먯떆 ???
            app.loadFirstFrame(fIdx);
        end

        % --------- loadAviFile ?ы띁??(V3.22 #3) ---------

        % [V3.22 #3-1] 湲곗〈 ?숆린 ?ㅼ젙???덉쓣 ???ъ슜???뺤씤 ?ㅼ씠?쇰줈洹?
        function ok = confirmVideoReplace(app, fIdx)
            ok = true;
            if app.VideoSyncState(fIdx).IsSynced
                sel = uiconfirm(app.UIFigure, ...
                    '???곸긽??濡쒕뱶?섎㈃ 湲곗〈 鍮꾨뵒??鍮꾪뻾?곗씠???숆린 ?ㅼ젙???댁젣?⑸땲?? 怨꾩냽?섏떆寃좎뒿?덇퉴?', ...
                    '?숆린 ?댁젣 ?뺤씤', ...
                    'Options', {'怨꾩냽', '痍⑥냼'}, 'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(sel, '痍⑥냼'), ok = false; return; end
                app.resetVideoSync(fIdx);
            end
        end

        % [V3.22 #3-2 / REFACTOR Step 1] ?꾨젅??罹먯떆 鍮꾩슦湲?- CacheModel濡??꾩엫
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
                            app.UI(fIdx).vidSyncBtn.Text = '?숆린';
                            app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.58 0.0 0.83];
                        end
                        if isfield(app.UI(fIdx), 'vidSyncStatus') && isvalid(app.UI(fIdx).vidSyncStatus)
                            app.UI(fIdx).vidSyncStatus.Text = '?숆린 誘몄꽕??;
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

        % [V3.22 #3-3] 鍮꾪뻾?곗씠??泥??쒓컙 異붿텧 (?쒖옉 ?ㅽ봽?뗭슜)
        function startTime = computeStartTimeFromFlightData(app, fIdx)
            startTime = 0;
            if ~isempty(app.Models(fIdx).rawData) && isfield(app.Models(fIdx).mappedCols, 'Time')
                timeCol = app.Models(fIdx).mappedCols.Time;
                if ~isempty(timeCol) && ismember(timeCol, app.Models(fIdx).rawData.Properties.VariableNames)
                    startTime = app.Models(fIdx).rawData.(timeCol)(1);
                end
            end
        end

        % [V3.22 #3-4] 湲곗〈 VideoReader / 鍮꾨룞湲?future 紐낆떆???뺣━
        function cleanupVideoResources(app, fIdx)
            % Future瑜?癒쇱? 臾댄슚??痍⑥냼????reader瑜??レ븘 ?뚯씪?쎄낵 stale callback??以꾩씤??
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
            % [REFACTOR Step 2-B] VideoModel.cleanup ?꾩엫 + VideoState ?명솚 ?대━??
            try, app.VideoMdl(fIdx).cleanup(); catch ME, app.logCaught(ME, 'silent'); end
            try, app.VideoMdl(fIdx).cleanup(); catch ME, app.logCaught(ME, 'Video:cleanupModel'); end
            app.VideoState(fIdx).videoReader   = [];
            app.VideoState(fIdx).videoStartTime = 0;
            app.VideoFilePath{fIdx} = '';
            app.resetVideoWidthPreferences(fIdx);
        end

        % [V3.22 #3-5] VideoReader ?앹꽦 (?ㅽ뙣 ??errordlg + [] 諛섑솚)
        function vr = openVideoReader(app, fIdx, fullPath, fname)
            vr = [];
            try
                vr = VideoReader(fullPath);
                app.VideoState(fIdx).videoReader = vr;
                app.VideoFilePath{fIdx} = fullPath;
                % [REFACTOR Step 2-C] attachReader ??VideoLoaded notify (cache ?먮룞 recompute)
                app.VideoMdl(fIdx).attachReader(vr, fullPath, app.VideoState(fIdx).vidImageHandle);
                if app.DebugMode
                    fprintf('[Video] loaded: %s (fIdx=%d)\n', fname, fIdx);
                end
            catch e
                if app.DebugMode
                    fprintf('[Video] load failed: %s\n  %s\n', fullPath, e.message);
                end
                app.logCaught(e, 'Video:open');
                errordlg(['?곸긽 濡쒕뱶 ?ㅽ뙣: ', e.message], '?ㅻ쪟');
                app.VideoFilePath{fIdx} = '';
                vr = [];
            end
        end

        % [V3.22 #3-6] TotalFrames ?곗젙 + 愿??UI ?꾩젽/?ㅽ뵾???щ씪?대뜑 ?숆린??
        function applyVideoLoadedUI(app, fIdx, vr)
            % [FIX] TotalFrames 怨꾩궛? ??긽 癒쇱?, UI 媛깆떊 3醫낆? ?낅┰ try濡??꾨떖 蹂댁옣
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
                % [FIX Case 2] ?먮룞 ?숆린(IsSynced=true) ?쒓굅 - "?숆린" 踰꾪듉 ?대┃ ?쒖뿉留??쒖꽦??
                %              FPS ?ш퀎?곗? ?좎? (Case 4 ?붽뎄?ы빆), anchor???ъ슜??紐낆떆 ?숆린 ???ㅼ젙
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

            % [FIX] ?듭떖: ?꾨옒 3媛쒕뒗 ?대뼡 寃쎌슦?먮룄 ?꾨떖?댁빞 ????媛곴컖 ?낅┰ try
            try, app.updateVdubSliderRange(fIdx); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:sliderRange'); end
            try, app.updateVdubFrameLabel(fIdx, 1); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:label'); end
            try, app.adjustVideoPanelWidth(fIdx); catch ME, app.logCaught(ME, 'applyVideoLoadedUI:panelWidth'); end
        end

        % [V3.22 #3-7] TotalFrames 怨꾩궛 (NumFrames ?곗꽑, ?대갚: Duration*FrameRate)
        function totalFrames = computeTotalFrames(app, fIdx, vr)
            % [REFACTOR Step 2] VideoModel ?꾩엫 - vr???명솚??override
            totalFrames = app.VideoMdl(fIdx).computeTotalFrames(app.DebugMode, vr);
        end

        % [V3.22 #3-8] 泥??꾨젅?꾩쓣 ?뺥솗???붿퐫?⑺븯???쒖떆 + 罹먯떆 ???
        function loadFirstFrame(app, fIdx)
            % [REFACTOR Step 2-B] VideoModel ?꾩엫 + axes 蹂댁젙/cache store??硫붿씤 ?붾쪟
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

        % [V3.12 2.1] ?곸긽 媛濡??몃줈 鍮꾩쑉???곕씪 鍮꾨뵒???⑤꼸 ?덈퉬 ?숈쟻 議곗젙
        function adjustVideoPanelWidth(app, fIdx)
            try
                % [FIX] ?ъ슜?먭? splitter濡?議곗옉??寃쎌슦 ?먮룞 由ъ궗?댁쫰 李⑤떒 (異⑸룎 諛⑹?)
                if app.VideoUserResized(fIdx), return; end
                if app.IsDraggingSplitter, return; end
                if isempty(app.VideoState(fIdx).videoReader), return; end
                vr = app.VideoState(fIdx).videoReader;
                if vr.Height <= 0, return; end
                aspectRatio = vr.Width / vr.Height;

                % ?⑤꼸 ?대? ?곸긽 ?곸뿭 ?믪씠 ??280px 媛??(96 DPI 湲곗? ?붿옄??媛?
                % High-DPI ?섍꼍?먯꽌???숈씪 鍮꾩쑉???좎??섎룄濡?UIScale.px ?곸슜
                UIScale = flightdash.util.UIScale;
                targetWidth = UIScale.px(round(280 * aspectRatio) + 100);
                targetWidth = max(UIScale.px(400), min(targetWidth, UIScale.px(900)));  % ?덉쟾 踰붿쐞 ?쒗븳

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

        % [V3.14 ??ぉ 3 / REFACTOR Step 1] ?숈쟻 罹먯떆 ?ш린 怨꾩궛: CacheModel.recomputeLimit?쇰줈 ?꾩엫
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

        % [V3.14 ??ぉ 3 / REFACTOR Step 1] ?ъ슜?먭? GUI?먯꽌 罹먯떆 ?덉궛 蹂寃????몄텧
        function setCacheBudget(app, budgetMB)
            try
                if budgetMB <= 0, return; end
                app.CacheBudgetMB = budgetMB;
                % 媛?CacheModel???덉궛 ?꾪뙆 ???곸긽 濡쒕뱶??寃쎈줈留??쒕룄 ?ш퀎??
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

        % [V3.15 ??ぉ 5-3] DebugMode GUI 泥댄겕諛뺤뒪 肄쒕갚
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

        % [V3.14 ??ぉ 5] VideoReader ?좏슚??寃???ы띁 (?쇨????덈뒗 媛??
        function tf = isVideoReady(app, fIdx)
            % [REFACTOR Step 2-B] VideoModel ?꾩엫
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

        % [REFACTOR Step 2-C] VideoLoaded ?대깽???몃뱾??
        % - cache ?쒕룄 ?ш퀎??(?댁긽??湲곕컲)
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

        % [REFACTOR Step 2-C] VideoCleared ?대깽???몃뱾??- cache 臾댄슚??
        function onVideoCleared(app, fIdx)
            try
                app.resetVideoWidthPreferences(fIdx);
                if ~isempty(app.CacheModel) && fIdx <= numel(app.CacheModel)
                    app.CacheModel(fIdx).invalidate();
                end
                app.LayoutMgr.applyLayout(app, 'videoCleared');
            catch ME, app.logCaught(ME, 'silent'); end
        end

        % [V3.14 VirtualDub UI] Frame ?щ씪?대뜑 踰붿쐞 媛깆떊 (?곸긽 濡쒕뱶 ??
        function updateVdubSliderRange(app, fIdx)
            try
                if isfield(app.UI(fIdx), 'vidVdubSlider') && isvalid(app.UI(fIdx).vidVdubSlider)
                    maxF = max(2, app.VideoSyncState(fIdx).TotalFrames);
                    sld = app.UI(fIdx).vidVdubSlider;
                    sld.Limits = [1, maxF];
                    sld.Value = 1;
                    ticks = round(linspace(1, maxF, 5));
                    sld.MajorTicks = ticks;
                    sld.MajorTickLabels = arrayfun(@num2str, ticks, 'UniformOutput', false); % 吏???쒓린 諛⑹?
                    sld.MinorTicks = [];
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.14 VirtualDub UI] Frame N / Total (HH:MM:SS.mmm) ?쇰꺼 媛깆떊
        % [V3.15 ??ぉ 5-1 / REFACTOR Step 0] ?쒓컙 ?щ㎎?낆쓣 util.TimeFormat?쇰줈 ?꾩엫
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

        % [V3.15 ??ぉ 2 / V3.16 / V3.17 (1)(9)] goToFrame() - ?⑥씪 怨듭떇 吏꾩엯??
        % - V3.16: InGoToFrame ?ъ쭊??媛??+ onCleanup
        % - V3.17 (1)(9): coalescing - 泥섎━ 以????붿껌? PendingFrame???????
        %                 ?꾩옱 泥섎━ ?꾨즺 ???먮룞 ?≪닔 (理쒖떊 frame ?꾨씫 諛⑹?)
        % - V3.17 (8): State = 'UPDATING' ?쒖떆
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
        % [V3.17 (1)(9)] goToFrame???듭떖 泥섎━ 濡쒖쭅 (?ъ쭊??媛???고쉶 - coalescing ?꾩슜)
        function processFrameInternal(app, fIdx, frameNo, mode)
            if isempty(mode), mode = 'final'; end

            % 1. 踰붿쐞 寃利?+ clamp
            totalF = app.VideoSyncState(fIdx).TotalFrames;
            if totalF < 1, return; end
            frameNo = round(frameNo);
            frameNo = max(1, min(frameNo, totalF));

            % 2. 蹂寃??놁쑝硫?醫낅즺
            if app.VideoSyncState(fIdx).CurrentFrame == frameNo, return; end
            app.VideoSyncState(fIdx).CurrentFrame = frameNo;

            % 3. 紐⑤뱺 ?쒖떆 ?붿냼 ?쇨큵 ?숆린??
            app.syncFrameMarkersAndLabel(fIdx, frameNo);

            % 4. ?곸긽 媛깆떊 (mode???곕씪 source ?좏깮)
            app.syncFrameMarkersAndLabel(fIdx, frameNo);
            if strcmp(mode, 'drag')
                app.updateVideoFrameByFrameNo(fIdx, frameNo, 'drag');
            else
                app.updateVideoFrameByFrameNo(fIdx, frameNo, 'sync');
            end

            % 5. ?숆린 紐⑤뱶????鍮꾪뻾?곗씠??痢〓룄 媛깆떊
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
                                % [FIX] IsUpdating onCleanup 蹂댁옣
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

        % [V3.15 ??ぉ 1] ?щ씪?대뜑 ?쒕옒洹?以?肄쒕갚 (ValueChangingFcn)
        % - throttle 0.03s(33fps) ?곸슜?쇰줈 ?붿퐫?????곸껜 諛⑹?
        % - 'drag' 紐⑤뱶濡?goToFrame ?몄텧 ??寃쎈웾 媛깆떊留??섑뻾
        function onVdubSliderChanging(app, fIdx, evtValue)
            % ?щ씪?대뜑 throttle: ?덈Т ?먯＜ ?몄텧?섎㈃ 臾댁떆
            if app.throttleHit('LastSliderUpdate', fIdx, flightdash.util.AppConstants.SLIDER_THROTTLE_S), return; end

            frameNo = round(evtValue);
            % [FIX] ?쒕옒洹?以??쒓컖 ?쇰뱶諛?利됱떆?? goToFrame 吏꾩엯 ???쇰꺼/?щ씪?대뜑 ?쇰꺼留?1??媛깆떊
            try, app.updateVdubFrameLabel(fIdx, frameNo); catch, end

            % [V3.19 (2)] ?쒕옒洹??띾룄 痢≪젙 (adaptive prefetch??
            app.updateDragVelocity(fIdx, frameNo);

            app.goToFrame(fIdx, evtValue, 'drag');
        end

        % [V3.15 ??ぉ 1] ?щ씪?대뜑 ?쒕옒洹?醫낅즺 ??肄쒕갚 (ValueChangedFcn)
        % - 'final' 紐⑤뱶濡?goToFrame ?몄텧 ???꾩껜 ?⑤꼸 1???숆린??蹂댁옣
        % - [V3.16] 媛숈? frame?대씪??drag 紐⑤뱶 醫낅즺 吏곹썑?????덉쑝誘濡?updateDashboard 媛뺤젣
        function onVdubSliderChanged(app, fIdx, src)
            try
                target = round(src.Value);
                if app.VideoSyncState(fIdx).CurrentFrame == target
                    % drag 紐⑤뱶??updateMarkersOnly留??몄텧 ???뚯씠釉?寃뚯씠吏 stale 媛??
                    % final 紐⑤뱶 1??媛뺤젣 ?몄텧濡??꾩껜 ?숆린??蹂댁옣
                    if app.VideoSyncState(fIdx).IsSynced && ~isempty(app.Models(fIdx).rawData)
                        % [FIX] IsUpdating onCleanup 蹂댁옣
                        app.setStateUpdating(fIdx, true);
                        cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx)); %#ok<NASGU>
                        try, app.updateDashboard(fIdx, app.Models(fIdx).currentIndex); catch, end
                        clear cleanup_;
                    end
                    return;
                end
                app.goToFrame(fIdx, src.Value, 'final');
                % [V3.19 (2)] ?щ씪?대뜑 ?쒕옒洹?醫낅즺 ??adaptive prefetch
                app.prefetchAdjacentFrames(fIdx);
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.16 / V3.17 (8)] goToFrame ?ъ쭊???뚮옒洹??댁젣 (onCleanup 肄쒕갚)
        function clearGoToFrameFlag(app, fIdx)
            app.setStateGoToFrame(fIdx, false);
            if ~app.anyStateGoToFrame(), app.State = 'IDLE'; end
        end

        % [V3.17 (7)] ?붿퐫??吏꾪뻾 以??뚮옒洹??댁젣 (onCleanup 肄쒕갚)
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

        % [V3.18 (4) / V3.19 (2)] adaptive prefetch: ?쒕옒洹??띾룄/諛⑺뼢 湲곕컲 prefetch 踰붿쐞
        function prefetchAdjacentFrames(app, fIdx)
            try
                if ~app.isVideoReady(fIdx), return; end
                cur = app.VideoSyncState(fIdx).CurrentFrame;
                total = app.VideoSyncState(fIdx).TotalFrames;

                v = app.DragVelocity(fIdx);   % frames/sec (遺??= 諛⑺뼢)
                speed = abs(v);

                % [V3.19 (2)] ?띾룄 湲곕컲 prefetch 踰붿쐞
                if speed < 30
                    offsets = [-3:-1, 1:3];        % ?먮┝: 洹좊벑 ?묐갑??
                elseif speed < 100
                    if v > 0
                        offsets = [-2, -1, 1:7];   % ?뺣갑???곗꽭
                    else
                        offsets = [-7:-1, 1, 2];   % ??갑???곗꽭
                    end
                else
                    if v > 0
                        offsets = 1:12;            % 鍮좊쫫: 吏꾪뻾諛⑺뼢留?源딄쾶
                    else
                        offsets = -12:-1;
                    end
                end

                if app.DebugMode
                    fprintf('[Prefetch] fIdx=%d, v=%.1f f/s, %d offsets\n', fIdx, v, length(offsets));
                end

                % ?ㅼ쓬 ?쒕옒洹몄슜 reset
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
            % ?붾㈃ ?곹깭? main VideoReader ?꾩튂瑜?嫄대뱶由ъ? ?딄퀬 蹂꾨룄 reader濡?cache留??덉뿴.
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

        % [V3.14 VirtualDub UI] ?꾟뾼 ?????뷜뼷 ?ㅻ퉬寃뚯씠??踰꾪듉 肄쒕갚
        % [V3.15 ??ぉ 2] goToFrame ?⑥씪 吏꾩엯???ъ슜
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

        % [V3.14 VirtualDub UI] Frame 留덉빱/?щ씪?대뜑/?쇰꺼 ?쇨큵 ?숆린???ы띁
        function syncFrameMarkersAndLabel(app, fIdx, frameNo)
            try
                % [?섏젙] ?ъ슜?섏? ?딅뒗 ?쏅궇 留덉빱 媛깆떊 肄붾뱶???꾩쟾????젣?섏뿬 ?먮윭 ?먯쿇 李⑤떒

                % 1. ?щ씪?대뜑 ?꾩튂 媛깆떊
                if isfield(app.UI(fIdx), 'vidVdubSlider') && any(isvalid(app.UI(fIdx).vidVdubSlider))
                    if abs(app.UI(fIdx).vidVdubSlider.Value - frameNo) > 0.5
                        app.UI(fIdx).vidVdubSlider.Value = frameNo;
                    end
                end

                % 2. ?쇰꺼 ?띿뒪??媛깆떊 (?먮윭 ?놁씠 ?덉쟾?섍쾶 ?꾨떖)
                app.updateVdubFrameLabel(fIdx, frameNo);

            catch ME_silent
                app.logCaught(ME_silent, 'silent');
            end
        end

        % [V3.12] 鍮꾨뵒???숆린 ?곹깭 珥덇린??
        function resetVideoSync(app, fIdx)
            % [REFACTOR Step 2-B] SyncModel 癒쇱? clear (model-first; VideoSyncState??compat alias)
            app.SyncMdl(fIdx).clear();
            app.VideoSyncState(fIdx).IsSynced = false;
            app.VideoSyncState(fIdx).AnchorFrame = 0;
            app.VideoSyncState(fIdx).AnchorOffset = 0;
            app.VideoSyncState(fIdx).AnchorTime = 0;
            try
                if isfield(app.UI(fIdx), 'vidSyncBtn') && isvalid(app.UI(fIdx).vidSyncBtn)
                    app.UI(fIdx).vidSyncBtn.Text = '?숆린';
                    app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.58 0.0 0.83];
                end
                if isfield(app.UI(fIdx), 'vidSyncStatus') && isvalid(app.UI(fIdx).vidSyncStatus)
                    app.UI(fIdx).vidSyncStatus.Text = '?숆린 誘몄꽕??;
                    app.UI(fIdx).vidSyncStatus.FontColor = [0.5 0.5 0.5];
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.12 2.2.3] ?숆린 踰꾪듉 肄쒕갚 - ?낅젰媛?寃利?諛??숆린 ?ㅼ젙
        function applyVideoSync(app, fIdx)
            % ?숆린 ?댁젣 紐⑤뱶
            if app.VideoSyncState(fIdx).IsSynced
                app.resetVideoSync(fIdx);
                return;
            end

            % 1. ?곸긽/?곗씠??濡쒕뱶 寃利?
            if isempty(app.VideoState(fIdx).videoReader)
                errordlg('癒쇱? AVI ?뚯씪??濡쒕뱶?섏꽭??', '?숆린 ?ㅻ쪟'); return;
            end
            if isempty(app.Models(fIdx).rawData)
                errordlg('癒쇱? 鍮꾪뻾?곗씠??CSV)瑜?濡쒕뱶?섏꽭??', '?숆린 ?ㅻ쪟'); return;
            end

            % 2. ?낅젰媛?異붿텧
            frameNo = app.UI(fIdx).vidSyncFrameInput.Value;
            timeVal = app.UI(fIdx).vidSyncTimeInput.Value;

            % 3. 踰붿쐞 寃利?
            totalFrames = app.VideoSyncState(fIdx).TotalFrames;
            timeCol = app.Models(fIdx).mappedCols.Time;
            times = app.Models(fIdx).rawData.(timeCol);

            if frameNo < 1 || frameNo > totalFrames
                errordlg(sprintf('Frame No??1 ~ %d 踰붿쐞?ъ빞 ?⑸땲??', totalFrames), '踰붿쐞 ?ㅻ쪟'); return;
            end
            if timeVal < times(1) || timeVal > times(end)
                errordlg(sprintf('Time(s)??%.3f ~ %.3f 踰붿쐞?ъ빞 ?⑸땲??', times(1), times(end)), '踰붿쐞 ?ㅻ쪟'); return;
            end

            % 4. Hz 媛?媛깆떊
            vfpsUI = app.UI(fIdx).vidVideoFpsInput.Value;
            dfps = app.UI(fIdx).vidDataFpsInput.Value;
            if vfpsUI < 1 || dfps < 1
                errordlg('Hz 媛믪? 1 ?댁긽?댁뼱???⑸땲??', '?낅젰 ?ㅻ쪟'); return;
            end

            % [?섏젙 3] ?뚯닔???뺣????좎떎 諛⑹? 濡쒖쭅
            % ?대????뺥솗???뚯닔??FPS瑜?諛섏삱由쇳븳 媛믨낵 ?꾩옱 UI ?ㅽ뵾?덉쓽 媛믪씠 媛숇떎硫?
            % ?ъ슜?먭? ?ㅽ뵾?덈? ?섎룞 議곗옉?섏? ?딆? 寃껋쑝濡?媛꾩＜?섏뿬 ?뺥솗???대? ?뚯닔??FPS瑜??좎???
            if round(app.VideoSyncState(fIdx).VideoFps) == vfpsUI
                % do nothing (?뚯닔???뺣????좎?)
            else
                app.VideoSyncState(fIdx).VideoFps = vfpsUI; % ?ъ슜?먭? ?ㅽ뵾?덈? 諛붽씔 寃쎌슦?먮쭔 媛깆떊
            end

            app.VideoSyncState(fIdx).DataFps = dfps;

            % 5. ?숆린 ?뺣낫 ???
            % [V3.23 sub-frame / FIX] ?섎룞 ?숆린???ъ슜???낅젰???덈?媛믪쑝濡??좊ː ??offset=0 怨좎젙
            % (sub-frame offset? ?먮룞 anchor?먯꽌留??섎?. ?섎룞 ?낅젰?먯꽌??frameNo?봳imeVal??怨?吏꾩떎)
            anchorOffset = 0;

            % [REFACTOR Step 2-B] SyncModel 癒쇱? 媛깆떊 (model-first; VideoSyncState??compat alias)
            app.SyncMdl(fIdx).setAnchor(frameNo, timeVal, anchorOffset);
            app.VideoSyncState(fIdx).IsSynced     = true;
            app.VideoSyncState(fIdx).AnchorFrame  = frameNo;
            app.VideoSyncState(fIdx).AnchorOffset = anchorOffset;
            app.VideoSyncState(fIdx).AnchorTime   = timeVal;

            % 6. UI ?쇰뱶諛?
            app.UI(fIdx).vidSyncBtn.Text = '?숆린 ?댁젣';
            app.UI(fIdx).vidSyncBtn.Text = 'Sync Off';
            app.UI(fIdx).vidSyncBtn.BackgroundColor = [0.8 0.2 0.2];
            app.UI(fIdx).vidSyncStatus.Text = sprintf('?숆린 ?꾨즺 (F%d ??%.3fs)', frameNo, timeVal);
            app.UI(fIdx).vidSyncStatus.FontColor = [0.06 0.65 0.50];

            % [V3.14 ??ぉ 4 / REFACTOR Step 1] ?숆린 ?ъ꽕????罹먯떆 臾댄슚??- ?섑띁 ?ъ슜
            app.invalidateFrameCache(fIdx);
            if app.DebugMode
                fprintf('[VideoSync] fIdx=%d, anchor F%d ??%.3fs, vfps=%d, dfps=%d, cache cleared\n', ...
                    fIdx, frameNo, timeVal, vfpsUI, dfps);
            end
        end

        % [V3.12 2.2.3.1] Hz ?낅젰 짹 ?붿궡??踰꾪듉 肄쒕갚 (1Hz ?⑥쐞)
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

                % 利됱떆 VideoSyncState?먮룄 諛섏쁺 (?숆린 ?ㅼ젙 ?꾩씠?쇰룄)
                if strcmp(target, 'video')
                    app.VideoSyncState(fIdx).VideoFps = newVal;
                else
                    app.VideoSyncState(fIdx).DataFps = newVal;
                end
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        % [V3.12 2.2.3.1] Hz 吏곸젒 ?낅젰 ??肄쒕갚 (?ㅽ뵾??ValueChangedFcn)
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

        % [V3.12 2.2.3] Frame No ??Time 留ㅽ븨 (?듭빱 湲곕컲 ?좏삎)
        function timeVal = frameToTime(app, fIdx, frameNo)
            % [REFACTOR Step 2 / V3.23] SyncModel ?꾩엫 - anchor/fps/offset 紐낆떆 ?꾨떖
            s = app.VideoSyncState(fIdx);
            timeVal = app.SyncMdl(fIdx).frameToTime(frameNo, s.VideoFps, s.AnchorFrame, s.AnchorTime, s.AnchorOffset);
        end

        % [V3.12 2.2.3] Time ??Frame No 留ㅽ븨
        function frameNo = timeToFrame(app, fIdx, timeVal)
            % [REFACTOR Step 2 / V3.23] SyncModel ?꾩엫 - anchor/fps/total/offset 紐낆떆 ?꾨떖
            s = app.VideoSyncState(fIdx);
            frameNo = app.SyncMdl(fIdx).timeToFrame(timeVal, s.VideoFps, s.TotalFrames, s.AnchorFrame, s.AnchorTime, s.AnchorOffset);
        end

        % [V3.13 C-1 / REFACTOR Step 1] ?꾨젅??罹먯떆 議고쉶 - CacheModel ?꾩엫
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

        % [V3.13 C-1 / REFACTOR Step 1] ?꾨젅??罹먯떆 ???- CacheModel ?꾩엫
        % - 媛以?LRU + 硫붾え由??덉궛 evict??紐⑤몢 紐⑤뜽 ?대??먯꽌 泥섎━
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

        % [REFACTOR Step 1] evictByScore??CacheModel ?대? 硫붿꽌?쒕줈 ?댁쟾??
        % ?몃??먯꽌 吏곸젒 ?몄텧?섎뒗 肄붾뱶媛 ?놁쑝誘濡?蹂??대옒?ㅼ뿉???꾩쟾 ?쒓굅.
        % (?꾩슂 ??app.CacheModel(fIdx).stats() 濡?罹먯떆 ?곹깭 ?먭? 媛??

        % =====================================================================
        % [V3.21 #3-A] 3怨꾩링 遺꾨━ 援ъ“ - 梨낆엫 紐낇솗??
        %
        %   Layer 1: requestFrame  - 吏꾩엯??+ 罹먯떆 lookup + ?꾨왂 ?좏깮
        %   Layer 2: decodeFrameSync - ?숆린 ?붿퐫??(read or ?대갚)
        %            startAsyncDecode - 鍮꾨룞湲??붿퐫??(蹂꾨룄 硫붿꽌?? 湲곗〈)
        %   Layer 3: displayFrame  - ?쒖떆 + 罹먯떆 store (?⑥씪 異쒓뎄)
        %
        % 湲곗〈 updateVideoFrameByFrameNo???명솚???꾪빐 requestFrame濡??꾩엫.
        % =====================================================================

        % [V3.21 #3-A Layer 1] Frame ?붿껌 吏꾩엯??
        % source: 'drag' / 'autoplay' / 'sync' / 'force'
        function requestFrame(app, fIdx, frameNo, source)
            if nargin < 4, source = 'force'; end
            if ~app.isVideoReady(fIdx), return; end

            % ?좏슚??寃??

            % autoplay throttle 遺꾧린
            if strcmp(source, 'autoplay')
                if app.throttleHit('LastVideoUpdate', fIdx, flightdash.util.AppConstants.VIDEO_THROTTLE_S), return; end
            end

            % clamp (lookup/store ???쇨???
            totalF = app.VideoSyncState(fIdx).TotalFrames;
            clampedFrame = max(1, min(round(frameNo), max(1, totalF)));

            % [PATCH] ?숈씪 ?꾨젅??議곌린 諛섑솚 - GUI/?붿퐫??遺???숈떆 ?덇컧
            if app.LastDisplayedFrame(fIdx) == clampedFrame, return; end

            % Layer 1: 罹먯떆 lookup
            cached = app.cacheGetFrame(fIdx, clampedFrame);
            if ~isempty(cached)
                app.displayFrame(fIdx, clampedFrame, cached, true);  % cacheHit=true
                return;
            end

            % ?붿퐫??吏꾪뻾 以묒씠硫?理쒖떊 ?붿껌??蹂댁〈?쒕떎.
            if app.stateIsDecoding(fIdx)
                app.queuePendingFrame(fIdx, clampedFrame, source);
                return;
            end

            % ?꾨왂 ?좏깮: async vs sync
            if app.UseAsyncDecode && strcmp(source, 'drag')
                app.startAsyncDecode(fIdx, clampedFrame);
                return;
            end

            % Layer 2: ?숆린 ?붿퐫??
            app.setStateDecoding(fIdx, true);
            cleanup2 = onCleanup(@() app.clearDecodingFlag(fIdx)); %#ok<NASGU>

            img = app.decodeFrameSync(fIdx, clampedFrame);
            if ~isempty(img)
                app.displayFrame(fIdx, clampedFrame, img, false);  % cacheHit=false
            end
        end

        % [V3.21 #3-A Layer 2] ?숆린 ?붿퐫??(read or ?대갚)
        function img = decodeFrameSync(app, fIdx, clampedFrame)
            img = [];
            vr = app.VideoState(fIdx).videoReader;

            try
                img = read(vr, clampedFrame);
            catch
                % ?대갚: CurrentTime + readFrame
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

        % [V3.21 #3-A Layer 3] ?⑥씪 ?쒖떆 異쒓뎄 - 紐⑤뱺 ?붿퐫??寃곌낵???ш린 ?듦낵
        function displayFrame(app, fIdx, frameNo, img, isCacheHit)
            try
                if ~app.isVideoReady(fIdx) || isempty(img), return; end
                set(app.VideoState(fIdx).vidImageHandle, 'CData', img);
                app.LastDisplayedFrame(fIdx) = frameNo;   % [PATCH] 議곌린諛섑솚 ??

                % 罹먯떆 store (?덊듃 ?꾨땺 ?뚮쭔 - cache-first write-through)
                if ~isCacheHit
                    app.cacheStoreFrame(fIdx, frameNo, img);
                end
            catch ME
                app.logCaught(ME, 'displayFrame');
            end
        end

        % [V3.13 / V3.14 / V3.21 ?명솚] 湲곗〈 updateVideoFrameByFrameNo??
        % requestFrame濡??꾩엫 (?몃? ?몄텧泥??명솚 ?좎?)
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
                app.UIFigure.WindowButtonMotionFcn = @(~,~) app.panelSplitterMotion();
                app.UIFigure.WindowButtonUpFcn    = @(~,~) app.stopPanelSplitterDrag();
                if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'left-right'; end
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
                app.UIFigure.WindowButtonMotionFcn = '';
                app.UIFigure.WindowButtonUpFcn    = '';
                if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'arrow'; end
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

                % [FIX] ?ъ슜?먭? splitter 議곗옉 ???먮룞 由ъ궗?댁쫰 李⑤떒 ?뚮옒洹?
                app.VideoUserResized(fIdx) = true;
                app.LayoutMgr.applyResponsiveChannelLayout(app, fIdx, profile);
                drawnow limitrate;
            catch ME, app.logCaught(ME, 'HISplitter:motion'); end
        end

        function stopHISplitterDrag(app)
            try
                app.UIFigure.WindowButtonMotionFcn = '';
                app.UIFigure.WindowButtonUpFcn    = '';
                if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'arrow'; end
                app.IsDraggingSplitter = false;
                app.LayoutMgr.applyLayout(app, 'splitterStop');
                app.HISplitterFIdx = 0;
                drawnow limitrate;
            catch ME, app.logCaught(ME, 'HISplitter:stop'); end
        end


        % ---------------------------------------------------------------------
        % [V3.11 B] XLim 由ъ뒪???쇨큵 ?쒖뼱 (?쒕옒洹?以?以묐떒/蹂듭썝)
        % ---------------------------------------------------------------------
        function setXLimListenersEnabled(app, fIdx, enabled)
            % H ?⑤꼸 ??紐⑤뱺 ??쓽 XLim 由ъ뒪???쒖뼱
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

            % Altitude ?⑤꼸 XLim 由ъ뒪???쒖뼱
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
        % [V3.11 C / V3.12 ?뺤옣] 寃쎈웾 ?낅뜲?댄듃 寃쎈줈 (?쒕옒洹?以??꾩슜)
        % - V3.11: 留덉빱/xline + ?꾩옱?쒓컙 ?쇰꺼 + H ?⑤꼸 梨낆옣 ?섍린湲?
        % - V3.12 1.1: Map 鍮꾪뻾寃쎈줈 + 鍮④컙 ?쇨컖???ㅼ떆媛?媛깆떊 異붽?
        % - V3.12 2.2.3: 鍮꾨뵒???숆린 ?ㅼ젙 ??Frame 留덉빱 媛깆떊 + ?곸긽 ?꾨젅??媛깆떊
        % - ?꾩옱 鍮꾪뻾 ?뺣낫 ?뚯씠釉붽낵 鍮꾪뻾 寃뚯씠吏???쒕옒洹?以묒뿉??利됱떆 媛깆떊
        % ---------------------------------------------------------------------
        function updateMarkersOnly(app, fIdx, idx)
            % [V3.17 (4)(11)] persistent inCascade ??InCascade ?몄뒪?댁뒪 ?띿꽦?쇰줈 ?대룞
            % [V3.17 (5)] drawnow瑜??몃?(goToFrame)?먯꽌 泥섎━?섎?濡??먯껜 ?몄텧? 媛??
            isOuter = ~app.InCascade;

            isOuter = ~app.InCascade;
            app.Models(fIdx).currentIndex = idx;
            timeCol = app.Models(fIdx).mappedCols.Time;
            currTime = app.Models(fIdx).rawData.(timeCol)(idx);

            try
                altCol = app.Models(fIdx).mappedCols.Alt;
                alts = app.Models(fIdx).rawData.(altCol);

                % Altitude ?⑤꼸 留덉빱 + xline 媛깆떊
                if isfield(app.UI(fIdx), 'hAltMarker') && isvalid(app.UI(fIdx).hAltMarker)
                    set(app.UI(fIdx).hAltMarker, 'XData', currTime, 'YData', alts(idx));
                end
                if isfield(app.UI(fIdx), 'timeLine') && isvalid(app.UI(fIdx).timeLine)
                    app.UI(fIdx).timeLine.Value = currTime;
                end

                % ?꾩옱?쒓컙 ?쇰꺼 (留ㅼ슦 媛踰쇱?)
                if isfield(app.UI(fIdx), 'currentTimeLabel') && isvalid(app.UI(fIdx).currentTimeLabel)
                    app.UI(fIdx).currentTimeLabel.Text = sprintf('%.3f s', currTime);
                end

                % ?ㅽ뵾??媛깆떊 (媛踰쇱?)
                if isfield(app.UI(fIdx), 'spinner') && isvalid(app.UI(fIdx).spinner)
                    if abs(app.UI(fIdx).spinner.Value - currTime) > eps
                        app.UI(fIdx).spinner.Value = currTime;
                    end
                end

                app.updateCurrentInfoTable(fIdx, idx);
                app.updateAttitudeGauges(fIdx, idx);
            catch ME, app.logCaught(ME, 'silent'); end

            % [V3.12 1.1] Map 鍮꾪뻾寃쎈줈 + 鍮④컙 ?쇨컖???ㅼ떆媛?媛깆떊 (媛踰쇱?)
            % [PERF] validIdx ?쒓굅 - load ??NaN ?꾩쿂由щ맖, plot??NaN?먯꽌 ?먮룞 ?딄?
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

            % H ?⑤꼸 梨낆옣 ?섍린湲?+ 留덉빱 媛깆떊 (媛쒖꽑??A??IsProgrammaticXLim 媛???묐룞)
            if ~app.MarkerDragCtrl.IsDraggingMarker || ...
                    ~app.throttleHit('PlotDragTimelineUpdate', fIdx, flightdash.util.AppConstants.PLOT_DRAG_THROTTLE_S)
                app.updatePlotTimeLines(fIdx, idx, currTime);
            end

            % [V3.12 2.2.3] 鍮꾨뵒???숆린 ?ㅼ젙 ??Frame 留덉빱 + ?곸긽 ?꾨젅??媛깆떊
            % (?? 鍮꾨뵒??痢≪뿉???쒖옉???쒕옒洹멸? ?꾨땺 ?뚮쭔 - 臾댄븳 猷⑦봽 諛⑹?)
            % [PATCH UX-1] Sync 紐낆떆 ?쒖꽦??+ 鍮꾨뵒??ready ?숈떆 異⑹” ?쒖뿉留?媛깆떊
            if app.VideoSyncState(fIdx).IsSynced && ~app.MarkerDragCtrl.DraggedFromVideo ...
                    && app.isVideoReady(fIdx) && app.VideoSyncState(fIdx).AnchorFrame > 0
                try
                    targetFrame = app.timeToFrame(fIdx, currTime);
                    app.VideoSyncState(fIdx).CurrentFrame = targetFrame;
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);

                    % [V3.14] Frame 留덉빱 + xline + ?щ씪?대뜑 + ?쇰꺼 ?쇨큵 ?숆린??
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);

                    % [V3.13 ?덉땐] 鍮꾪뻾?곗씠???쒕옒洹????곸긽 媛깆떊? throttle ?좎?
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);
                    app.updateVideoFrameByFrameNo(fIdx, targetFrame, 'autoplay');
                catch ME, app.logCaught(ME, 'silent'); end
            end

            % ?숆린??紐⑤뱶: 寃쎈줈 1 ?쒕옒洹???寃쎈줈 2??寃쎈웾 ?낅뜲?댄듃
            if app.SyncState.IsSynced && fIdx == 1 && ~isempty(app.Models(2).rawData)
                targetT2 = app.SyncState.SyncT2 + (currTime - app.SyncState.SyncT1);
                timeCol2 = app.Models(2).mappedCols.Time;
                idx2 = app.findClosestIndexByTime(app.Models(2).rawData.(timeCol2), targetT2);
                if ~isequal(app.Models(2).currentIndex, idx2)
                    % [V3.17 (4)(11) / FIX] InCascade瑜?onCleanup?쇰줈 蹂댁옣 (?덉쇅 ???ㅽ꽦 諛⑹?)
                    app.InCascade = true;
                    cascadeCleanup_ = onCleanup(@() resetInCascade(app)); %#ok<NASGU>
                    app.updateMarkersOnly(2, idx2);
                    clear cascadeCleanup_;
                end
            end

            try, app.LayoutMgr.updatePanelRailSummaries(app, fIdx); catch, end

            % [V3.17 (5)] cascade ?몃? + goToFrame 誘멸꼍???쒖뿉留?drawnow
            % goToFrame? ?먯껜 醫낅즺 ??drawnow ?몄텧?섎?濡?以묐났 諛⑹?
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
        % H ?곸뿭 ??諛??ㅼ쨷 ?뚮’ 愿由?
        % ---------------------------------------------------------------------
        % [FIX] ???붾㈃ 理쒕? 3媛?蹂댁옣: tabGroup 媛???믪씠瑜?3?깅텇??RowHeight ?숈쟻 媛깆떊
        % - throttle 0.05s濡?由ъ궗?댁쫰 以??ㅻ컻 ?몄텧 李⑤떒
        % - 紐⑤뱺 ??쓽 紐⑤뱺 row瑜??숈씪 ?믪씠濡??듭씪 (4媛??댁긽 ???먮룞 ?ㅽ겕濡?
        function updatePlotRowHeights(app, fIdx)
            if app.throttleHit('PlotRowResize', fIdx, 0.05), return; end
            try
                if ~isfield(app.UI(fIdx), 'tabGroup') || ~isvalid(app.UI(fIdx).tabGroup), return; end
                pos = getpixelposition(app.UI(fIdx).tabGroup, true);
                visH = pos(4) - 30;  % ???ㅻ뜑 ~30px 李④컧
                if visH < 90, visH = 90; end
                rowH = max(120, floor(visH / 3));  % 理쒖냼 120px, ???붾㈃ 3媛?
                for t = 1:numel(app.UI(fIdx).plotLayouts)
                    L = app.UI(fIdx).plotLayouts{t};
                    if isempty(L) || ~isvalid(L) || isempty(L.RowHeight), continue; end
                    L.RowHeight = repmat({rowH}, 1, numel(L.RowHeight));
                end
            catch ME, app.logCaught(ME, 'silent'); end
        end

        % [FIX] UIFigure 由ъ궗?댁쫰 ????梨꾨꼸 plot row ?숈떆 媛깆떊
        function onUIFigureResized(app)
            if app.IsDeleting, return; end
            app.LayoutMgr.applyLayout(app, 'resize');
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
            % [V3.11 A] ?꾨줈洹몃옒諛띿쟻 XLim 蹂寃?梨낆옣 ?섍린湲?????寃쎌슦 由ъ뒪??臾댁떆
            %           ???ъ슜?먭? ?쒕옒洹명븳 留덉빱 ?꾩튂媛 以묒븰?쇰줈 媛뺤젣 ?먰봽?섎뒗 ?꾩긽 李⑤떒
            if app.IsProgrammaticXLim(fIdx), return; end

            % =======================================================
            % [V3.8 蹂닿컯] ?대컮??Zoom/Pan 紐⑤뱶瑜??꾨줈洹몃옒諛띿쟻?쇰줈 媛뺤젣 Off
            % - ?뱀떆 ?몃? API???ㅻⅨ 寃쎈줈瑜??듯빐 zoom/pan 紐⑤뱶媛 耳쒖죱??寃쎌슦
            %   WindowButtonUp ?대깽??媛濡쒖콈湲곕줈 ?명븳 留덉빱 ?ㅽ꽦 ?꾩긽 ?먯쿇 李⑤떒
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

            % [踰꾧렇 ?꾨꼍 ?섏젙] 以????깆뿉 ?섑빐 X異?踰붿쐞媛 蹂寃쎈릺?덉쓣 ??
            % ?뱀떆 ?⑥븘?덉쓣吏 紐⑤Ⅴ???쒕옒洹??곹깭瑜??덉쟾?섍쾶 媛뺤젣 珥덇린??
            if app.MarkerDragCtrl.IsDraggingMarker
                app.MarkerDragCtrl.stopDrag();
            end

            % [以??숆린???듭떖] ?뺣?/?대룞 諛쒖깮 ??以묒븰 ?쒓컙 ?띾뱷 ????쒕낫???숆린??
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

            % Y異??먮룞 ?ㅼ??? ?뺣? ??留덉빱媛 Y異?諛뽰쑝濡?踰쀬뼱???щ씪吏??寃껋쓣 ?꾨꼍 諛⑹?
            ax.YLimMode = 'auto';
            app.updatePannerViewport(fIdx);

            if isequal(app.Models(fIdx).currentIndex, idx), return; end
            app.applyTimeChange(fIdx, idx);
        end
    end

    % =========================================================================
    % ?곗씠???뚯꽌 諛??쒓컖???낅뜲?댄듃
    % =========================================================================
    methods (Access = private)
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
            app.UI(fIdx).fileNameLabel.Text = '紐⑥쓽 ?곗씠??(Auto)';
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

            % --- Map ?ㅼ젙 ---
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
            % [PERF] NaN ?꾩쿂由???吏곸젒 plot (NaN?먯꽌 ?먮룞 ?딄?)
            plot(axMap, pathLon, pathLat, 'Color', [0.8 0.8 0.8], 'LineWidth', 1);

            lineColor = [0.23 0.51 0.96];
            if fIdx == 2, lineColor = [0.31 0.27 0.90]; end

            % 泥?NaN ?꾨땶 ?꾩튂
            firstValid = find(~isnan(pathLon) & ~isnan(pathLat), 1);
            if isempty(firstValid), firstValid = 1; end

            app.UI(fIdx).hMapPath = plot(axMap, pathLon(firstValid), pathLat(firstValid), 'Color', lineColor, 'LineWidth', 2);
            app.UI(fIdx).hgMapPlane = hgtransform('Parent', axMap);
            scale = max(bnds.maxLon - bnds.minLon, bnds.maxLat - bnds.minLat) * 0.03;
            if scale <= 0, scale = 0.01; end
            x_base = [0, -0.5, 0.5, 0] * scale; y_base = [1, -1, -1, 1] * scale;
            patch('Parent', app.UI(fIdx).hgMapPlane, 'XData', x_base, 'YData', y_base, 'FaceColor', 'r', 'EdgeColor', [0.5 0 0], 'LineWidth', 1);

            % --- Altitude ?ㅼ젙 諛?Y異??숈쟻 ?ㅼ??쇰쭅 ?쒖꽦??---
            axAlt = app.UI(fIdx).altAxes; cla(axAlt);
            times = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Time);
            alts = app.Models(fIdx).rawData.(app.Models(fIdx).mappedCols.Alt);

            % ?먮윭 諛⑹뼱: altXLimListener媛 ?좏슚?쒖? 泥댄겕
            if isfield(app.UI(fIdx), 'altXLimListener')
                try
                    if ~isempty(app.UI(fIdx).altXLimListener) && isvalid(app.UI(fIdx).altXLimListener)
                        delete(app.UI(fIdx).altXLimListener);
                    end
                catch ME, app.logCaught(ME, 'silent'); end
            end

            % X異뺤쓣 ?곗씠???꾩껜濡??↔퀬, Y異뺤? auto 紐⑤뱶濡??ㅼ젙?섏뿬 GUI 由ъ궗?댁쫰 ???숈쟻?쇰줈 ?곸쓳?섎룄濡?蹂댁옣
            axAlt.XLim = [min(times) max(times)];
            axAlt.YLimMode = 'auto';
            plot(axAlt, times, alts, 'Color', [0.8 0.8 0.8], 'LineWidth', 1, 'HitTest', 'off');

            % [V3.10] Altitude axes???대컮 ?④? (??以??쒕옒洹??щ쭔 ?ъ슜)
            app.UI(fIdx).altAxes.Toolbar.Visible = 'off';
            app.UI(fIdx).altAxes.Interactions = [panInteraction, zoomInteraction];

            % [媛쒖꽑??3] ??꾨씪???먭퍡 利앷? 諛??щ챸??諛섏쁺, 留덉빱 ?ш린 14濡?怨좎젙
            app.UI(fIdx).hAltPath = plot(axAlt, times(1), alts(1), 'Color', [0.06 0.72 0.51], 'LineWidth', 2, 'HitTest', 'off');
            app.UI(fIdx).hAltMarker = plot(axAlt, times(1), alts(1), 'p', 'MarkerFaceColor', [0.98 0.75 0.14], 'MarkerEdgeColor', [0.71 0.33 0.04], 'MarkerSize', 14, 'HitTest', 'on');
            app.UI(fIdx).timeLine = xline(axAlt, times(1), 'r', 'LineWidth', 3.0, 'Alpha', 0.5, 'HitTest', 'on');

            app.UI(fIdx).hAltMarker.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, 0, src, event);
            app.UI(fIdx).timeLine.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, 0, src, event);

            % Altitude ?⑤꼸??Zoom/Pan ???숆린??由ъ뒪??異붽?
            app.UI(fIdx).altXLimListener = addlistener(axAlt, 'XLim', 'PostSet', @(~,~) app.handlePlotXLimChange(fIdx, axAlt));

            % --- 鍮꾪뻾?먯꽭 寃뚯씠吏 ?ㅼ젙 ---
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
                    % FontSize瑜?0.06?쇰줈 ?좎??섏뿬 ?먯븞???レ옄 ?ш린瑜??곸젅?섍쾶 ?ㅼ젙
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

            % [PERF] NaN ?꾩쿂由???吏곸젒 set
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

            % 鍮꾨뵒??諛?H ?곸뿭 媛깆떊
            % [V3.12 2.2.3] 鍮꾨뵒???숆린 ?ㅼ젙 ??Frame No 湲곕컲 媛깆떊 (?뺥솗??留ㅽ븨)
            if app.VideoSyncState(fIdx).IsSynced
                try
                    targetFrame = app.timeToFrame(fIdx, currTime);
                    app.VideoSyncState(fIdx).CurrentFrame = targetFrame;
                    % [V3.14] Frame 留덉빱 + xline + ?щ씪?대뜑 + ?쇰꺼 ?쇨큵 ?숆린??
                    app.syncFrameMarkersAndLabel(fIdx, targetFrame);
                    app.updateVideoFrameByFrameNo(fIdx, targetFrame, 'sync');  % ?뺥솗???숆린??
                catch
                    app.updateVideoFrame(fIdx, currTime);  % ?대갚
                end
            else
                % ?숆린 誘몄꽕?? 湲곗〈 諛⑹떇?濡??쒓컙 湲곕컲 媛깆떊
                % app.updateVideoFrame(fIdx, currTime);  % <--- ??以꾩쓣 二쇱꽍 泥섎━?섏뿬 ?꾩쟾 遺꾨━
            end
            app.updatePlotTimeLines(fIdx, index, currTime);
            app.LayoutMgr.updatePanelRailSummaries(app, fIdx);

            drawnow limitrate;
        end
    end

    % =========================================================================
    % UI ?덉씠?꾩썐 ?앹꽦 ?⑺넗由?(Create Layout)
    % =========================================================================
    methods (Access = private)
        function createLayout(app)
            % [REFACTOR Step 3] 硫붿씤 怨④꺽 + 梨꾨꼸蹂?鍮뚮뱶??view ?⑦궎吏濡??꾩엫
            % - ?ㅻ뜑: buildHeaderBar (湲곗〈 ?좎?)
            % - 梨꾨꼸: flightdash.view.ChannelLayout.build (6而щ읆 ?꾩엫)
            mainLayout = uigridlayout(app.UIFigure, [2 1]);
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

            % [V3.22 #5] UI ?됰㈃ struct瑜?洹몃９?붾맂 view濡?alias (?명솚 ?좎?)
            app.buildUIGroups();
            app.LayoutMgr.applyLayout(app, 'createLayout');
        end

        % [V3.22 #5] ?됰㈃ UI struct瑜?洹몃９?붾맂 view(struct)濡?臾띠뼱 蹂꾨룄 ?띿꽦?????
        % - app.UIGroup(fIdx).attitude.rollAxes = app.UI(fIdx).rollAxes  (alias)
        % - ??肄붾뱶??app.UIGroup(...) 寃쎈줈瑜?沅뚯옣; 湲곗〈 肄붾뱶??app.UI(...) 洹몃?濡?
        % - ?몃뱾 媛앹껜?대?濡?alias媛 ?숈씪 媛앹껜瑜?媛由ъ폒 蹂寃????묒そ 紐⑤몢 ?숆린??
        function buildUIGroups(app)
            % [V3.22 #5] ?됰㈃ UI struct瑜?洹몃９?붾맂 view(struct array, 1x2)濡?臾띠쓬
            % - ?몃뱾 媛앹껜?대?濡?alias媛 ?숈씪 媛앹껜瑜?媛由ъ폒 蹂寃????묒そ 紐⑤몢 ?숆린??
            UIGroup_temp = struct([]);
            for fIdx = 1:2
                u = app.UI(fIdx);
                grp = struct();

                % ?먯꽭(Attitude) 洹몃９
                grp.attitude = struct( ...
                    'panel',      u.panelAttitude, ...
                    'pitchAxes',  u.pitchAxes,  'pitchLabel', u.pitchLabel, 'hgPitch', app.uiFieldOr(u, 'hgPitch', gobjects(0)), ...
                    'rollAxes',   u.rollAxes,   'rollLabel',  u.rollLabel,  'hgRoll',  app.uiFieldOr(u, 'hgRoll',  gobjects(0)), ...
                    'hdgAxes',    u.hdgAxes,    'hdgLabel',   u.hdgLabel,   'hgHdg',   app.uiFieldOr(u, 'hgHdg',   gobjects(0)));

                % 吏??怨좊룄(MapAlt) 洹몃９
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

                % 鍮꾨뵒??+ Frame Navigator 洹몃９
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

                % ?뚮’(H ?곸뿭) 洹몃９ - cell array??struct() ctor ?뚰뵾
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

                % 而⑦듃濡??ㅻ뜑 洹몃９
                grp.controls = struct( ...
                    'spinner',          u.spinner, ...
                    'currentTimeLabel', u.currentTimeLabel, ...
                    'fileNameLabel',    u.fileNameLabel, ...
                    'btnAtt',           u.btnAtt, ...
                    'btnMap',           u.btnMap, ...
                    'btnVid',           u.btnVid);

                % ?곗씠???뚯씠釉?+ 而⑦뀒?대꼫
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

        % [V3.22 #7] 硫붿씤 ?덈룄???곷떒 ?ㅻ뜑 諛?(?뚯씪 ?좏깮 / Debug / Sync ?낅젰)
        % - createLayout?먯꽌 遺꾨━?섏뿬 ?ㅻ뜑 ?곸뿭 蹂寃쎌씠 硫붿씤 鍮뚮뜑???곹뼢 ?녿룄濡???
        function buildHeaderBar(app, mainLayout)
            % [REFACTOR Step 6-1] flightdash.view.HeaderBar濡??꾩엫
            ui = flightdash.view.HeaderBar.build(mainLayout);
            app.LayoutHandles.header = ui;
            app.SyncInput = ui.SyncInput;
            app.SyncBtn   = ui.SyncBtn;
        end

        % [REFACTOR] createGaugePanel??flightdash.view.AttitudePanel.createGauge濡??대룞
        %            (View媛 ?먯껜 寃뚯씠吏 援ъ꽦 - app ?섏〈 ?꾩쟾 ?쒓굅)
    end

    % [REFACTOR Step 5-C] ?댁쟾 Static wrapper(workerDecodeFrame/workerCleanupCache)??
    % ?ъ슜泥?0 ???꾩쟾 ?쒓굅. parfeval? ?댁젣 file-level ?⑥닔瑜?吏곸젒 李몄“:
    %   parfeval(pool, @asyncDecodeFramePersistent, ...)
    %   parfevalOnAll(pool, @cleanupAsyncDecodeCache, 0)
end

% =========================================================================
% [REFACTOR Step 5-B] file-level worker ?⑥닔??蹂꾨룄 .m ?뚯씪濡?遺꾨━??
%   - asyncDecodeFrame.m
%   - asyncDecodeFramePersistent.m  (parfeval worker ?ロ뙣??
%   - cleanupAsyncDecodeCache.m
% ?뚯빱 path 寃?됱쓣 ?꾪빐 蹂??뚯씪怨??숈씪 ?대뜑???꾩튂?댁빞 ??
% =========================================================================
