# Architecture — Flight Data Dashboard

본 문서는 프로젝트의 아키텍처 결정과 데이터 흐름을 상세히 기술합니다.
빠른 개요는 [README.md](../README.md) 를 참고하세요.

## 목차

1. [설계 원칙](#설계-원칙)
2. [패키지 구조](#패키지-구조)
3. [EventBus + MVC 흐름](#eventbus--mvc-흐름)
4. [모델 계층](#모델-계층)
5. [뷰 계층](#뷰-계층)
6. [컨트롤러 계층](#컨트롤러-계층)
7. [유틸리티 계층](#유틸리티-계층)
8. [비동기 디코딩 파이프라인](#비동기-디코딩-파이프라인)
9. [상태 머신 / 라이프사이클](#상태-머신--라이프사이클)
10. [동시성 / 재진입 방어](#동시성--재진입-방어)
11. [메모리 모델](#메모리-모델)
12. [확장 포인트](#확장-포인트)

## 설계 원칙

| 원칙 | 적용 방식 |
|---|---|
| **단방향 흐름** | View → EventBus → Controller → App → Model. 역방향(Model → View 직접 갱신)은 금지 |
| **View 100% 독립** | 모든 view 빌더는 `app` 객체를 받지 않음. `EventBus.publish` + `AppConstants` 만 사용 |
| **명시적 라이프사이클** | 모든 핸들 자원은 `delete()` 메서드에서 명시 해제 (`onCleanup` + 컨트롤러 `delete`) |
| **재진입 가드** | 모든 비동기/콜백 경로에 `IsUpdating` / `InGoToFrame` / `IsDecoding` 플래그 + `onCleanup` 리셋 |
| **점진 리팩토링** | `app.VideoSyncState` ↔ `app.SyncMdl` 같은 호환 alias 유지하면서 단계적 이동 |
| **High-DPI 1급 지원** | 모든 픽셀 리터럴이 `UIScale.px()` 통과 |

## 패키지 구조

```
+flightdash/
├── FlightDataDashboard.m        본체 (3,100+ 줄)
│
├── +util/
│   ├── EventBus.m               중앙 메시지 브로커 (싱글톤)
│   ├── AppEventData.m           이벤트 페이로드 (ChannelIdx, Payload)
│   ├── AppConstants.m           공유 상수 (MAX_TABS, *_THROTTLE_S)
│   ├── UIScale.m                High-DPI 픽셀 스케일러
│   ├── ErrorLog.m               catch 로깅 헬퍼
│   ├── Throttle.m               시간 기반 hit 게이트
│   └── TimeFormat.m             frame -> HH:MM:SS.mmm
│
├── +model/
│   ├── FrameCacheModel.m        가중 LRU 프레임 캐시
│   ├── VideoModel.m             VideoReader 라이프사이클
│   └── SyncModel.m              Frame <-> Time 변환
│
├── +view/                       정적 build() 메서드만 보유
│   ├── HeaderBar.m
│   ├── ChannelLayout.m
│   ├── AttitudePanel.m
│   ├── MapAltPanel.m
│   ├── InfoPanel.m
│   ├── PlotPanel.m
│   ├── HISplitter.m
│   └── VideoPanel.m
│
└── +controller/                 Listeners cell + delete() 정리
    ├── FileController.m
    ├── VideoSyncController.m
    ├── PlaybackController.m
    ├── PanelToggleController.m
    └── DragController.m
```

## EventBus + MVC 흐름

### 데이터 흐름 (단방향)

```
[사용자 클릭]
    |
    v
[+view/*.m]                  View는 controller를 모름
   EventBus.publish(eventName, AppEventData(fIdx, payload))
    |
    v
[+util/EventBus.m]           중앙 메시지 브로커 (싱글톤)
   notify(inst, eventName, data)
    |
    v
[+controller/*.m]            Controller는 view를 모름
   on<Event>(d) -> obj.App.method(d.ChannelIdx, d.Payload)
    |
    v
[+flightdash/FlightDataDashboard.m]
   비즈니스 로직 + UI 갱신
    |
    v
[+model/*.m] (VideoModel)    Model 변경 시 events 발행
   notify(VideoLoaded / VideoCleared)
    |
    v
[메인의 onVideoLoaded / onVideoCleared 핸들러]
   CacheModel.recomputeLimit / invalidate
```

### 구체적 시나리오: 슬라이더 드래그

```
1. [VideoPanel.m] uislider.ValueChangingFcn 발화
       publishSliderChanging(fIdx, val)
2. [VideoPanel.publishSliderChanging] Throttle.hit('LastSliderPublish', fIdx, 0.03)
       통과 시: EventBus.publish('SliderChanging', AppEventData(fIdx, val))
3. [EventBus] notify(inst, 'SliderChanging', data)
4. [PlaybackController.onSliderChanging]
       app.onVdubSliderChanging(d.ChannelIdx, d.Payload)
5. [FlightDataDashboard.onVdubSliderChanging]
       throttleHit('LastSliderUpdate', fIdx, SLIDER_THROTTLE_S) - 본체 Throttle (이중 안전)
       updateVdubFrameLabel(fIdx, frameNo) - 즉시 라벨 갱신
       updateDragVelocity(fIdx, frameNo) - adaptive prefetch용
       goToFrame(fIdx, value, 'drag')
6. [goToFrame] InGoToFrame 가드 + onCleanup 리셋
       processFrameInternal(fIdx, frameNo, 'drag')
7. [processFrameInternal]
       requestFrame(fIdx, clampedFrame, 'drag')
8. [requestFrame] 캐시 lookup
       hit -> displayFrame (즉시)
       miss -> startAsyncDecode (parfeval) 또는 decodeFrameSync
9. [displayFrame]
       set(ImageHandle, 'CData', img) - 영상 갱신
       cacheStoreFrame - 캐시 저장
       syncFrameMarkersAndLabel - 슬라이더/라벨 동기
```

### 이중 throttle 슬롯 분리

| 슬롯 | 위치 | 목적 |
|---|---|---|
| `LastSliderPublish` | View (`VideoPanel.publishSliderChanging`) | EventBus publish 자체 차단 — `AppEventData` 생성 비용 절감 |
| `LastSliderUpdate` | Controller→App (`onVdubSliderChanging`) | 무거운 `goToFrame` / `updateDashboard` 차단 |
| `LastVideoUpdate` | App (`requestFrame` autoplay 분기) | 자동 재생 시 영상 갱신 빈도 제한 |
| `MapPathDragUpdate` | App (`updateDashboard` map 부분) | 드래그 중 map 전체 path 재그리기 제한 |
| `PlotDragTimelineUpdate` | App (`updateDashboard` plot timeline) | 드래그 중 H 패널 timeline 갱신 제한 |
| `PlotRowResize` | App (`updatePlotRowHeights`) | 리사이즈 다발 호출 차단 |

각 슬롯이 독립 작동하므로 throttle 간 간섭 없음.

## 모델 계층

### `FrameCacheModel` (가중 LRU 캐시)

#### 자료구조

```matlab
Cache       cell      % {img1, img2, ...} (uint8 (H, W, 3))
Keys        double    % [frameNo1, frameNo2, ...]
Hits        double    % [hits1, hits2, ...] - 누적 히트 수
BytesArr    double    % [bytes1, bytes2, ...] - frame 별 바이트
LastUse     uint64    % [useCounter1, ...] - 마지막 접근 시 카운터
BytesUsed   double    % 합계 바이트
UseCounter  uint64    % 단조 증가 카운터
TotalFrames double    % VideoModel과 동기 (clamp 보호용)
BytesPerFrame double  % width * height * 3 캐시 (whos 회피)
```

#### Score 함수

```
score = (hits * recency) / bytes
recency = LastUse / UseCounter   (∈ (0, 1])
```

- **자주 + 최근 + 작은 frame** 우선 보호
- 같은 영상 내에서 bytes 는 거의 상수 → recency 와 hits 에 의해 결정
- `score(1:end-1)` 기반 evict — 가장 최근 store 된 항목은 무조건 보호

#### Evict 로직

```matlab
function evictByScore_(obj, limit, byBytes)
    minKeep = obj.MIN_CACHE_FRAMES;     % 5 (count 모드)
    if byBytes, minKeep = 1; end         % byte 모드는 최신 1개만 보호

    while length(obj.Keys) > minKeep
        if (byBytes && obj.BytesUsed <= limit) || ...
           (~byBytes && length(obj.Keys) <= limit)
            break;
        end
        scores = (Hits .* recency) ./ max(BytesArr, 1);
        [~, evictIdx] = min(scores(1:end-1));   % 최신 보호
        % 모든 배열에서 evictIdx 제거
    end
end
```

`BytesArr` 사전 계산으로 `cellfun(@numel, Cache)` 호출 제거 → O(N) → O(1).

### `VideoModel` (VideoReader 라이프사이클)

```
events
    VideoLoaded      % attachReader 호출 시
    VideoCleared     % cleanup 호출 시
end
```

본체에서 listener 구독:

```matlab
addlistener(app.VideoMdl(i), 'VideoLoaded',  @(src,~) app.onVideoLoaded(i, src));
addlistener(app.VideoMdl(i), 'VideoCleared', @(~,~)   app.onVideoCleared(i));
```

`onVideoLoaded` → `CacheModel(i).recomputeLimit(width, height)`
`onVideoCleared` → `CacheModel(i).invalidate()`

### `SyncModel` (Frame ↔ Time)

#### sub-frame 정밀도

```matlab
% 실효 anchor = AnchorFrame + AnchorOffset (분수 정밀도)
% AnchorOffset ∈ [-0.5, 0.5]

frameNo = round((anchorFrame + anchorOffset) + (timeVal - anchorTime) * videoFps);
```

긴 영상에서 정수 anchor 화로 인한 누적 오차 제거.

#### Jitter guard

```matlab
% [JITTER GUARD] ±0.5 경계 부동소수점 오차로 ±1 frame 점프 방지
rawFrame = round(rawFrame * 1e9) / 1e9;
frameNo = round(rawFrame);
```

`timeVal` 미세 진동 시 `round` 결과가 floor↔ceil 토글되는 현상 차단.

## 뷰 계층

### 정적 빌더 패턴

```matlab
classdef VideoPanel
    methods (Static)
        function ui = build(dataGrid, fIdx)
            % - 인스턴스 없이 호출
            % - app 객체 받지 않음
            % - 모든 콜백은 EventBus.publish 또는 정적 헬퍼
        end

        function publishSliderChanging(fIdx, val)
            % View 단 throttle 선체크 헬퍼
        end
    end
end
```

### View ↔ Controller 결합 제거

**기존 (문제)**:
```matlab
'ButtonPushedFcn', @(~,~) app.handleFlightFile(fIdx)   % app 객체 직접 참조
```

**현재 (해결)**:
```matlab
'ButtonPushedFcn', @(~,~) EventBus.publish('FlightFileRequested', AppEventData(fIdx))
```

View가 `app`/`controller` 객체를 전혀 모름 → 다른 프로젝트 재사용 가능.

### `ancestor()` 활용

```matlab
% Figure 핸들이 필요할 때
hFigure = ancestor(dataGrid, 'figure');
cm = uicontextmenu(hFigure);
```

`app.UIFigure` 참조 없이 부모 트리에서 자동 탐색.

## 컨트롤러 계층

### 표준 구조

```matlab
classdef FileController < handle
    properties (Access = private)
        App
        Listeners cell = {}
    end

    methods
        function obj = FileController(app)
            obj.App = app;
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('FlightFileRequested', @(~,d) obj.onFlightFile(d));
            % ...
        end

        function onFlightFile(obj, d)
            obj.App.handleFlightFile(d.ChannelIdx);
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
```

### Zombie Listener 방어

EventBus 가 `persistent singleton` 이므로:

1. 컨트롤러 생성 시 `addlistener` 가 **EventBus 내부**에 listener 등록
2. listener 가 컨트롤러 메서드 callback 으로 컨트롤러를 참조
3. 메인 앱 종료 시 `app.FileCtrl = []` 만 하면 listener 가 컨트롤러를 계속 보유 → 좀비
4. **해결**: 메인 앱 `delete()` 에서 `delete(app.FileCtrl)` 명시 호출 → 컨트롤러 `delete()` 가 listener 명시 해제

```matlab
% FlightDataDashboard.delete()
try, delete(app.FileCtrl);      catch ME, app.logCaught(ME, 'silent'); end
try, delete(app.VideoSyncCtrl); catch ME, app.logCaught(ME, 'silent'); end
% ...
app.FileCtrl = [];
% ...
```

## 유틸리티 계층

### `EventBus`

- `events { ... }` 블록에 모든 이벤트 사전 정의 → `isKnownEvent()` 검증
- `try-catch + ErrorLog` 로 콜백 실패가 앱 크래시로 번지지 않음
- `notify(inst, eventName, data)` 가 모든 listener 에 전파

### `Throttle`

- `slot (string) × fIdx (int) → tic 핸들` 매핑
- `hit(slotName, fIdx, limitS)` → `true` (차단) / `false` (통과 + 시각 기록)
- 싱글톤 인스턴스로 전역 공유

### `UIScale`

- 96 DPI 를 1.0 기준점
- `factor() = ScreenPixelsPerInch / 96` (persistent 캐싱)
- `px(val) = round(val * factor())`
- 모든 픽셀 리터럴이 디자인 단계에서 96 DPI 기준 → 런타임에 자동 비례

### `AppConstants`

- 외부 view/controller 가 안전하게 참조할 수 있는 public Constant 모음
- 본체 `FlightDataDashboard` private constants 와 의도적 분리 (캡슐화 위반 회피)

## 비동기 디코딩 파이프라인

### 워커 풀 + persistent VR LRU

```matlab
% 메인 스레드:
fut = parfeval(pool, @asyncDecodeFramePersistent, 1, ...
               filePath, frameNo, fIdx, totalFrames);
afterEach(fut, @(img) app.onAsyncDecodeComplete(fIdx, frameNo, myGen, img), 1);
```

```matlab
% 워커 (asyncDecodeFramePersistent.m):
function img = asyncDecodeFramePersistent(filePath, frameNo, fIdx, totalFrames)
    persistent vrCache   % 워커별 persistent VideoReader LRU
    if isempty(vrCache), vrCache = struct('path', {}, 'vr', {}); end

    % 같은 파일 핸들 재사용 (open 비용 절감)
    idx = find(strcmp({vrCache.path}, filePath), 1);
    if isempty(idx)
        % LRU evict if full
        if numel(vrCache) >= WORKER_VR_CACHE_SLOTS
            try, delete(vrCache(1).vr); catch, end
            vrCache(1) = [];
        end
        vr = VideoReader(filePath);
        vrCache(end+1) = struct('path', filePath, 'vr', vr);
    else
        vr = vrCache(idx).vr;
    end

    img = read(vr, frameNo);
end
```

워커가 `WORKER_VR_CACHE_SLOTS = 4` 만큼의 VideoReader 를 보유 → 같은 파일 반복 디코딩 시 open 비용 제거.

### Generation Counter (Race 차단)

```matlab
% 메인:
app.AsyncGen(fIdx) = app.AsyncGen(fIdx) + 1;
myGen = app.AsyncGen(fIdx);
fut = parfeval(...);
afterEach(fut, @(img) app.onAsyncDecodeComplete(fIdx, frameNo, myGen, img), 1);

% 콜백:
function onAsyncDecodeComplete(app, fIdx, frameNo, gen, img)
    if gen ~= app.AsyncGen(fIdx)
        % stale result 폐기
        return;
    end
    % ...
end
```

새 요청이 발생할 때마다 `AsyncGen` 증가 → 이전 future 의 결과가 도착해도 폐기됨.

### Coalescing (PendingFrame)

```matlab
function goToFrame(app, fIdx, frameNo, mode)
    if app.InGoToFrame(fIdx)
        % 처리 중이면 최신 요청만 보존
        app.PendingFrame(fIdx) = frameNo;
        app.PendingMode{fIdx}  = mode;
        return;
    end

    app.InGoToFrame(fIdx) = true;
    cleanup = onCleanup(@() app.clearGoToFrameFlag(fIdx));

    app.processFrameInternal(fIdx, frameNo, mode);

    % Pending 소진 루프 (MAX_PENDING_ITERS 안전망)
    iter = 0;
    while ~isnan(app.PendingFrame(fIdx)) && iter < app.MAX_PENDING_ITERS
        pf = app.PendingFrame(fIdx);
        pm = app.PendingMode{fIdx};
        app.PendingFrame(fIdx) = NaN;
        app.PendingMode{fIdx}  = '';
        iter = iter + 1;
        if pf == app.VideoSyncState(fIdx).CurrentFrame, continue; end
        app.processFrameInternal(fIdx, pf, pm);
    end
end
```

빠른 드래그 중 수많은 요청이 쌓여도 최신 요청만 처리.

## 상태 머신 / 라이프사이클

### App 상태

```
'IDLE'      <-->   'DRAGGING'
   |                   |
   v                   |
'UPDATING'  <----------+
   |
   v
'DECODING'
```

`app.State` 는 디버그/추적용 (실제 분기는 가드 플래그로 처리).

### 가드 플래그

| 플래그 | 용도 | 리셋 시점 |
|---|---|---|
| `IsUpdating(fIdx)` | `applyTimeChange` / `updateDashboard` 재진입 차단 | onCleanup 자동 |
| `InGoToFrame(fIdx)` | `goToFrame` 재진입 차단 (coalescing 진입점) | onCleanup 자동 |
| `IsDecoding(fIdx)` | 동기 디코딩 중복 차단 | onCleanup 자동 |
| `IsDraggingMarker` | 마커 드래그 중 (글로벌) | `stopPlotMarkerDrag` |
| `IsDraggingSplitter` | 스플리터 드래그 중 (글로벌) | `stopHISplitterDrag` |
| `IsProgrammaticXLim(fIdx)` | 책장 넘기기 등 프로그래밍 XLim 변경 시 listener 차단 | 변경 직후 false |
| `InCascade` | `updateMarkersOnly` cascade 중첩 차단 | 외부 호출자만 drawnow 호출 |
| `IsDeleting` | `delete(app)` 중복 진입 차단 | 영구 (앱 종료) |

## 동시성 / 재진입 방어

### 다중 경로 동시 보호

```matlab
function applyTimeChange(app, fIdx, index)
    if app.IsUpdating(fIdx), return; end

    app.IsUpdating(fIdx) = true;
    cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx));   %#ok<NASGU>

    try
        app.updateDashboard(fIdx, index);
    catch e
        app.logCaught(e, 'applyTimeChange');
    end

    if app.SyncState.IsSynced && fIdx == 1 && ~isempty(app.Models(2).rawData)
        idx2 = app.findClosestIndexByTime(...);
        app.applyTimeChange(2, idx2);    % 양 채널 동기 cascade
    end
end
```

`onCleanup` 으로 예외/return/error 시에도 플래그 자동 복원 보장.

### Listener 일시 중단 패턴

```matlab
function startPlotMarkerDrag(app, fIdx, tabIdx, src, event)
    % 드래그 중 XLim listener 일시 중단 → handlePlotXLimChange 무한 재귀 차단
    app.setXLimListenersEnabled(fIdx, false);

    app.UIFigure.WindowButtonMotionFcn = @(~,~) app.plotMarkerDragMotion(fIdx);
    app.UIFigure.WindowButtonUpFcn = @(~,~) app.stopPlotMarkerDrag();
end

function stopPlotMarkerDrag(app)
    % ... 드래그 종료 정리 ...
    app.setXLimListenersEnabled(app.DraggedFIdx, true);   % 복원
end
```

## 메모리 모델

### 명시적 자원 해제 시점

```
앱 종료 (CloseRequestFcn) -> delete(app)
                                |
                                +-- cancel(AsyncFutures{1..2})        // 워커 hang 차단
                                +-- delete(VideoState(*).videoReader) // 파일락 해제
                                +-- CacheModel(*).invalidate()        // 캐시 메모리 해제
                                +-- delete(VideoListeners{*}{*})      // VideoModel listeners
                                +-- delete(FileCtrl/VideoSyncCtrl/   // EventBus listeners
                                          PlaybackCtrl/PanelCtrl/
                                          DragCtrl)
                                +-- parfevalOnAll(@cleanupAsyncCache) // 워커 persistent VR
                                +-- delete(AsyncPool)                  // 풀 해제
                                +-- delete(UIFigure)                   // GUI
```

순서가 중요:
- Future cancel **먼저** → VR delete (워커가 같은 파일 잡고 있을 가능성 차단)
- Listener delete **먼저** → 컨트롤러 nil (좀비 listener 방지)

### 워커 메모리

각 worker process 는:
- `WORKER_VR_CACHE_SLOTS = 4` 개의 VideoReader persistent
- `WORKER_VR_CACHE_SLOTS × 영상_평균_여유 ≈ 수백 MB` 가능

`cleanupAsyncDecodeCache` 가 worker pool 전체에서 persistent 변수 해제.

## 확장 포인트

### 새 이벤트 추가

1. `+util/EventBus.m` 의 `events { ... }` 블록에 사명 추가 (PascalCase)
2. View 빌더에서 `EventBus.publish('NewEvent', AppEventData(fIdx, payload))` 호출
3. 적절한 Controller 의 `subscribeEvents()` 에 listener 추가
4. Controller 메서드에서 본체 메서드 호출

### 새 패널 추가

1. `+view/NewPanel.m` 에 `methods (Static)` 의 `build(dataGrid, fIdx)` 작성
2. `ChannelLayout.build` 에서 호출 + dataGrid column 정의
3. 필요 시 `togglePanel` 에 분기 추가
4. `buildUIGroups` 에 그룹 추가

### 새 모델 추가

1. `+model/NewModel.m` 작성 (`< handle`)
2. 본체 `properties (Access = private)` 에 `NewMdl(1, 2)` 배열 선언
3. `FlightDataDashboard` 생성자에서 인스턴스 할당
4. 필요 시 events 정의 + 메인에서 listener 구독

### 새 컨트롤러 추가

1. `+controller/NewController.m` 표준 구조 복사 (App + Listeners + delete)
2. 본체 `properties` 에 `NewCtrl` 추가
3. `createLayout` 직전에 `app.NewCtrl = flightdash.controller.NewController(app)`
4. `delete(app)` 에 `try, delete(app.NewCtrl); catch ...; end` 추가

## 향후 로드맵

- **Step 5: SyncMdl 단일화** — `app.VideoSyncState(fIdx).{IsSynced, AnchorFrame, AnchorTime, DataFps}` → `app.SyncMdl(fIdx)` 직접 참조 (100+ 호출처)
- **단위 테스트 추가** — `tests/` 디렉토리에 `SyncModel`, `FrameCacheModel`, `Throttle` unit test
- **워커 VR 생명주기 강화** — 메인 cleanup 과 워커 persistent VR 사이 race window 의 retry 횟수 측정 + 보강

자세한 마이그레이션 계획은 [CHANGELOG.md](../CHANGELOG.md) 의 `[Unreleased]` 섹션 참고.
