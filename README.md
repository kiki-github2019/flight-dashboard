# Flight Data Dashboard

uicontrol 함수 기반의 비행 데이터 + AVI 영상 동기 리뷰 대시보드.
듀얼 채널(2개의 비행 경로)을 동시에 비교 분석할 수 있으며, EventBus + MVC 아키텍처와 비동기 프레임 디코딩을 통해 대용량 영상에서도 부드러운 스크럽이 가능합니다.

## 주요 기능

- **듀얼 채널 동시 리뷰** — 2개 비행 경로를 한 화면에서 시간 동기 비교
- **AVI ↔ 비행 데이터 동기** — 사용자가 명시적으로 anchor를 지정 (Frame No / Time(s))
- **실시간 스크럽** — 슬라이더 / Frame Navigator / 플롯 별표 마커 모두 양방향 동기
- **자동 페이지 넘김** — 확대된 H 패널에서 마커가 화면 밖으로 벗어나면 줌 비율 유지한 채 X축 자동 이동
- **비동기 프레임 디코딩** — `parfeval` 워커 풀 + persistent VR LRU 캐시
- **가중 LRU 프레임 캐시** — `score = (hits × recency) / bytes` 기반 evict
- **High-DPI 자동 스케일** — 96 DPI 디자인 → 실효 픽셀 자동 변환 (125% / 150% / 200% 모두 지원)
- **다중 플롯 탭** — 한 화면 3개 플롯 + 4개 이상 자동 스크롤, 탭당 최대 12개

## 시스템 요구사항

- **MATLAB R2025a / R2026a 대상** (R2024b 이상에서도 동작 가능하도록 보수적으로 유지)
- **Image Processing Toolbox**
- **Parallel Computing Toolbox** (비동기 디코딩 사용 시)
- Windows 10/11 (Linux/macOS도 동작 가능하나 미검증)

## 빠른 시작

```matlab
% 프로젝트 root에서 (본 README가 있는 디렉토리)
cd <repo-root>
addpath(genpath(pwd))

% Studio shell (Project Explorer / Workspace / Inspector)
FlightReviewStudio

% Legacy standalone dashboard
FlightDataDashboard
```

## 실행 모드

- **Studio 실행**: `FlightReviewStudio`는 Project Explorer, Workspace tab, Inspector/Right Dock, Status Bar를 포함한 통합 shell입니다. MATLAB은 `uifigure`를 `uitab` 안에 직접 embed할 수 없으므로, embedded dashboard는 Studio tab 내부에 panel/grid 기반으로 직접 그립니다.
- **Standalone 실행**: `FlightDataDashboard`는 기존 단일 dashboard 진입점이며, 기존 파일 로드/동기/플롯/영상 리뷰 흐름을 유지합니다.

## `.frsproj` 저장 형식

현재 v1 `.frsproj`는 zip 기반 **linked project** 형식입니다. `manifest.json`, `project.json`, `sessions/<SessionId>/session.json`, `themes/*.json`, `external_links.json`을 포함하며, 비행 로그와 비디오 원본 bytes를 프로젝트 내부로 복사하지 않고 외부 경로를 참조합니다.

알려진 제한: OriginPro식 완전 docking/floating UI와 raw data/video packing은 현재 범위 밖입니다. 프로젝트 로드 시 session metadata와 tab은 복원되지만, 대용량 flight/video 데이터는 사용자가 원본 파일 경로를 유지하는 linked mode 전제로 다룹니다.

### 데이터 로드 흐름

1. 헤더의 **"비행경로 1 선택"** / **"비행경로 2 선택"** 버튼으로 CSV 로드
2. 각 채널의 **"AVI 파일 열기"** 로 영상 로드
3. Frame No / Time(s) 입력 후 **"동기"** 버튼 클릭으로 anchor 설정
4. 이후 슬라이더 / 별표 마커 / 비디오 Frame Navigator가 모두 양방향 동기 동작

## 아키텍처

### 데이터 흐름 (단방향)

```
[사용자 클릭]
    |
    v
[+view/*.m]                  View는 controller를 모름
   EventBus.publish(eventName, AppEventData)
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

### 디렉토리 구조

```
root/
├── FlightDataDashboard.m              호환 wrapper, flightdash.FlightDataDashboard() 위임
├── asyncDecodeFrame.m                 parfeval worker, 단발성 fallback
├── asyncDecodeFramePersistent.m       parfeval worker hot path, persistent VideoReader LRU
├── cleanupAsyncDecodeCache.m          parfeval worker cache cleanup
├── option1.dat                        Flight 1 option 기본 파일
├── option2.dat                        Flight 2 option 기본 파일
├── README.md / CHANGELOG.md / CONTRIBUTING.md / LICENSE
├── docs/
└── +flightdash/
    ├── FlightDataDashboard.m          본체 클래스, 약 6,268줄, function 선언 약 246개
    │                                  레이아웃, 데이터 로드, video sync, drag,
    │                                  plot/ROI/range/statistics, config 저장/복원,
    │                                  responsive layout, 보조 figure 관리 포함
    │
    ├── +util/
    │   ├── ErrorLog.m                 catch 로깅 ring buffer/helper
    │   ├── Throttle.m                 시간 기반 hit gate singleton
    │   ├── TimeFormat.m               frame/time 표시 포맷팅
    │   ├── AppConstants.m             공유 상수, throttle/layout/cache 제한값
    │   ├── UIScale.m                  High-DPI 및 responsive 픽셀 스케일러
    │   ├── EventBus.m                 중앙 이벤트 브로커, view-controller 연결
    │   └── AppEventData.m             EventBus payload wrapper
    │
    ├── +model/
    │   ├── FrameCacheModel.m          가중 LRU frame cache, byte budget 관리
    │   ├── VideoModel.m               VideoReader lifecycle, total frame/meta 계산
    │   └── SyncModel.m                frame-time 변환, sub-frame offset 지원
    │
    ├── +view/
    │   ├── HeaderBar.m                파일/Coast, Max, Debug, Sync,
    │   │                              Export/Import CFG, flight view selector
    │   ├── ChannelLayout.m            채널 패널, control header, 6-column dataGrid
    │   ├── AttitudePanel.m            Pitch/Roll/Heading gauge UI
    │   ├── MapAltPanel.m              Map + Altitude axes UI
    │   ├── InfoPanel.m                현재 비행 정보 table,
    │   │                              plot 추가/순서/표시형식 context menu
    │   ├── PlotPanel.m                H data view, tabs, plots, manager/details,
    │   │                              ROI, Analyze, compact Range bar
    │   ├── HISplitter.m               H/I video splitter
    │   └── VideoPanel.m               AVI video player, frame navigator, sync controls
    │
    └── +controller/
        ├── FileController.m           flight/video/coast/config import/export 이벤트 처리
        ├── VideoSyncController.m      video sync, Hz 입력, cache budget 이벤트 처리
        ├── PlaybackController.m       slider/nav/spinner/table/plot/tab,
        │                              info format/order, ROI, panner, analysis 이벤트 처리
        ├── PanelToggleController.m    panel toggle, debug, sync, maximize,
        │                              channel view mode 이벤트 처리
        └── DragController.m           H/I splitter drag 이벤트 처리

root/
├── FlightDataDashboard.m                  7 lines
│   └─ 호환 wrapper, flightdash.FlightDataDashboard() 호출
│
├── asyncDecodeFrame.m                     20 lines
├── asyncDecodeFramePersistent.m           87 lines
├── cleanupAsyncDecodeCache.m              13 lines
│
├── option1.dat
├── option2.dat
│
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── .gitignore
│
├── docs/
│   └── architecture.md
│
└── +flightdash/FlightDataDashboard.m
    ├── FlightDataDashboard.m              6,267 lines
    │   └─ 본체 클래스
    │      - 앱 생성/삭제, 레이아웃, config 저장/복원
    │      - 파일 로드, option 적용, 데이터 파싱
    │      - 지도/고도/게이지/현재정보/H plot/video 갱신
    │      - Plot Manager / Details / ROI / Stats 보조 figure
    │      - Play/Stop timer
    │      - splitter, panner, drag, responsive layout
    │
    ├── +util/
    │   ├── AppConstants.m                 80 lines
    │   ├── AppEventData.m                 20 lines
    │   ├── ErrorLog.m                     124 lines
    │   ├── EventBus.m                     121 lines
    │   ├── Throttle.m                     75 lines
    │   ├── TimeFormat.m                   46 lines
    │   └── UIScale.m                      123 lines
    │
    ├── +model/
    │   ├── FrameCacheModel.m              264 lines
    │   ├── SyncModel.m                    71 lines
    │   └── VideoModel.m                   132 lines
    │
    ├── +view/
    │   ├── AttitudePanel.m                67 lines
    │   ├── ChannelLayout.m                123 lines
    │   │   └─ 9-column responsive layout + panel splitters
    │   ├── HeaderBar.m                    71 lines
    │   ├── HISplitter.m                   18 lines
    │   ├── InfoPanel.m                    68 lines
    │   ├── MapAltPanel.m                  73 lines
    │   ├── PlotPanel.m                    226 lines
    │   │   └─ Manager / Details / ROI / Range / axis controls
    │   └── VideoPanel.m                   172 lines
    │
    └── +controller/
        ├── DragController.m               35 lines
        ├── FileController.m               42 lines
        ├── PanelToggleController.m        51 lines
        ├── PlaybackController.m           97 lines
        └── VideoSyncController.m          52 lines


## 핵심 컴포넌트

### EventBus (`flightdash.util.EventBus`)
- `persistent singleton` 으로 1개 인스턴스만 존재
- 20개의 이벤트 정의 (PascalCase 명명 규칙)
- `isKnownEvent()` 검증으로 오타 이벤트명 즉시 차단
- `try-catch + ErrorLog` 로 콜백 실패가 앱 크래시로 번지지 않음

### FrameCacheModel (`flightdash.model.FrameCacheModel`)
- 가중 LRU 캐시: `score = (hits × recency) / bytes`
- `BytesArr` 사전 계산으로 매 evict O(N) → O(1)
- `BytesPerFrame` 캐시로 `whos` 호출 회피 (recomputeLimit 시 1회 산정)
- `MIN_CACHE_FRAMES = 5` 절대 하한 보호 + `1:end-1` 최신 store 보호

### SyncModel (`flightdash.model.SyncModel`)
- `frameToTime` / `timeToFrame` 양방향 변환
- `AnchorOffset [-0.5, 0.5]` sub-frame 정밀도로 긴 영상 누적 오차 제거
- 1e-9 jitter guard 로 부동소수점 boundary ±1 frame 토글 차단

### Async 디코딩 (`asyncDecodeFramePersistent`)
- `parfeval` 프로세스 풀 워커마다 persistent VideoReader LRU (`WORKER_VR_CACHE_SLOTS = 4`)
- Generation counter (`AsyncGen`) 로 stale future 결과 자동 폐기
- `PendingFrame` coalescing 으로 latest 요청만 처리

## 최근 개선사항

### 안정성
- **좀비 컨트롤러 방지** — `delete(app)` 시 모든 Controller에 명시적 `delete()` 호출 → EventBus listener 누수 차단
- **자동 동기 제거** — AVI + flight data 로드만으로 자동 동기되던 동작을 제거. 사용자가 "동기" 버튼을 명시적으로 클릭해야 활성화
- **Inf NaN 처리** — `markInvalidGpsAsNaN`이 (0,0)에 더해 Inf 값도 NaN 처리 → fillmissing/plot 멈춤 방어
- **H 패널 보호 우선화** — 스플리터 드래그 시 H 패널 최소 폭(320px) 절대 보장, 비디오 패널이 잔여 한도 내에서만 양보

### 성능
- **whos 호출 제거** — FrameCacheModel이 영상 해상도 기반 BytesPerFrame 캐시 사용 → 핫패스 CPU 부담 절감
- **View 단 Throttle 선체크** — 슬라이더 드래그 시 33fps 초과 모션은 EventBus publish 자체를 생략

### 호환성
- **High-DPI 자동 스케일** — 모든 ColumnWidth/RowHeight 가 `UIScale.px()`로 통일. 96 DPI 디자인이 125%/150%/200% 환경에서 자동 비례 확장
- **app 의존 제거** — 모든 view 빌더가 EventBus + AppConstants 만 사용 (View 100% 독립)

## 디버그 모드

헤더의 **"Debug"** 체크박스로 활성화. 다음이 콘솔에 출력됨:

- XLim 변경 / zoom-pan-off 강제 호출
- 캐시 store/evict 동작
- VFR/MP4 mismatch 경고
- 비동기 future stale 폐기

또는 코드에서:
```matlab
app.DebugMode = true;
app.dumpErrorLog(20);          % 최근 20건
app.dumpErrorLog(20, 'Async'); % 'Async' 태그 필터
```

## 알려진 제약사항

- **VideoSyncState vs SyncMdl 이중 보유** — 점진 리팩토링 흔적. 본체 100+ 호출처가 `app.VideoSyncState(fIdx)` 직접 참조 중. 향후 SyncMdl로 단일화 예정 (Step 5)
- **VFR (Variable Frame Rate) 영상** — `vr.NumFrames`와 `vr.Duration × vr.FrameRate` 가 10% 이상 차이 시 동기 정확도 저하 가능. 디버그 모드에서 경고 출력
- **process pool 워커 persistent VR** — 메인 스레드의 `VideoModel.cleanup()`과 워커의 persistent VR 사이에 미세한 race window 존재 (`isvalid` 체크 + retry로 방어 중)

## 디렉토리 / 파일 명명 규칙

- 패키지 네임스페이스: `+flightdash.+util` / `+flightdash.+model` / `+flightdash.+view` / `+flightdash.+controller`
- 이벤트 이름: PascalCase, "동작Target" 또는 "TargetVerbed" (예: `TableRowSelected`, `PlotTabAddRequested`)
- 채널 인덱스: `fIdx ∈ {1, 2}`, 비채널 이벤트는 `fIdx = 0`
- 메서드 prefix: `on<Event>` (콜백), `apply<Action>` (변경), `update<Target>` (UI 갱신)

## 라이선스

(TBD — 사내 사용 / 오픈소스 결정 후 추가)

## 기여 가이드

(TBD — 추후 작성)

## 변경 이력

상세 변경 이력은 [project_info.md](project_info.md) 참고.
