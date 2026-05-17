# Changelog

본 프로젝트의 모든 주요 변경사항을 기록합니다.

형식은 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 을 따르며,
버전은 [Semantic Versioning](https://semver.org/spec/v2.0.0.html) 을 준수합니다.

## [Unreleased]

### 2026-05-17 묶음 — Ownership / Ribbon / Controller stabilization

- **R1 ~ R8 ownership inversion** — `FlightDataDashboard`의 35개 storage
  속성을 4개 state 클래스로 이동: `SessionContext` 9개, `AsyncDecodeState`
  10개, `DashboardLayoutState` 11개, `VideoSessionState` 3개,
  `ChannelState` (per-channel paths) 2개. 호출 측 `app.*` syntax 무변경
  (모두 Dependent forward). `Models` 인버전은 의도적 보류 (77 read site +
  hot path).
- **Ribbon UI 전면 교체** — 12 menus + 21 toolbar buttons → 6-탭 ribbon
  (Home / Data / Sync / Playback / Review / Plot) + QuickAccess
  (편집 가능 프로젝트명, Mode dropdown, Theme, Settings(⚙), Help(?)).
  legacy `MenuManager` + `ToolbarManager`는 더 이상 생성되지 않으나
  파일은 회귀 대응을 위해 보존. `RibbonIconFactory`가 24×24 RGB 아이콘
  코드 생성 (text + symbol 스타일, 카테고리 색상).
- **Controller 10/10 → `ControllerBase` 상속** — 자체 `Listeners` /
  `delete` 제거, 베이스의 `cleanup()` 단일 경로 사용. EventBus
  subscriptions은 모두 `obj.subscribeEvent(name, cb)` 한 줄 호출.
  Adapter 입력 검증은 `ControllerBase.normalizeAdapterInput` 정적
  헬퍼로 통합.
- **CommandRouter 핸들러 21개 추가** — `Video:Clear`/`Snapshot`/
  `DecodeSettings`/`Metadata`, `Data:Validate`/`EstimateFps`/`Summary`,
  `Sync:VideoData`/`ResetVideo`/`OffsetEditor`/`QualityCheck`,
  `Plot:NewComparison`/`Axis`/`LinkAxes`/`Export`/`Copy`,
  `Review:Compare`/`ExportTable`/`Report`, `Analysis:EventDetect`/`Filter`/
  `Smooth`/`FFT`/`Compare`/`Recalculate`,
  `Pref:Experimental:SharedDecode` (opt-in 토글). `knownCommands()` 정적
  메서드 + 리본 cmdId 매핑 테스트로 회귀 가드.
- **EventBus.subscriberCount** — 구독자 라이브 카운트 노출 (registry 기반
  prune). `verifyCallbackSafety` 런타임 leak probe가 이제 실제 누수 감지.
- **Perf** — `FlightDataLoader.generateMockFlightData` rand 사전 배치 +
  time 벡터화, `FlightModeAnalyzer.computeBands` 변화점 벡터화 +
  `compose()` 배치 라벨 생성.
- **Path validation** — `ProjectSerializer.validatePath` text-scalar
  validator 추가 + `save/load` 진입점에 wire.
- **MATLAB 버전 정책 통일** — README + 진입점이 2-티어 (R2021b 최소 /
  R2025a+R2026a 검증) 정책으로 동기화, R2024a 미만 launch 시 1회성
  warning.
- **External links** — `ProjectSerializer.collectExternalLinks`에
  `kind='option_file'` 루프 추가 (legacy session 안전 isfield 가드).
- **WorkspaceManager.openSampleProject** — repo root `..\..\..` →
  `..\..` 수정 + `isfolder` 사전 검증.
- **logCaught 강화** — Studio + Workspace의 9개 고위험 silent catch 사이트가
  `app.logCaught` / `obj.logIfPossible` 호출로 전환.
- **Phase 4 stabilization 회귀 가드** — `verifyPhase4`에 P4-13
  (migrated controller leak-free) + `verifyCallbackSafety`에
  `EventBus.publish` raw numeric payload 스캔 추가.

### 다음 사이클 작업 영역 후보

- Phase 8d / Auto Update 마무리 (Frozen 결과 stale-warning UI)
- DashboardPanel / VideoPlayerPanel / InstrumentsPanel / DataViewPanel
  `ComponentContainer` 분리 (기존 `FlightDataDashboard` 와 functional parity
  확인 후 진행)
- 사용자 직접 입력 ROI 영역 분석 다중 표시
- Phase 9 Pack Project + 상대경로 복구 옵션
- 단독 `FlightDataDashboard` 표준화 정리
- `Models` ownership inversion (R2 brief 잔여; 77 read site → 점진
  `app.channel(fIdx)` 마이그레이션 필요)

---

## [0.13.0] — 2026-05-16 Modern Responsive GUI

Phase 11 묶음 (커밋 b3b87d9..현재) — 리뷰 보고서 7건을 단계적으로 흡수한
프론트엔드 현대화 + 분석 다이얼로그 신설 + 메모리/타이머 회귀 보호 +
Project.GuiTheme persistence + 5개 추가 smoke test + 슬라이더 hot-path
gauge needle 경량화.

(상세 변경사항은 아래 "Phase 11 — Modern Responsive GUI and Real-Time
Review UX" 절 참조; 이 절은 0.13.0 으로 동결.)

0.13.0-rc1 (커밋 b3b87d9..c95491b) 이후 추가:
- Patch 4 medium-term — `ProjectModel.GuiTheme` + `ProjectSerializer`
  round-trip + `buildShell` 읽기 + `toggleTheme` write-back (8f3b09d).
- Patch 5 — 5개 smoke test 추가: VideoReader 참조 해제, 옵션 자세
  컬럼 누락 가드, 슬라이더 scrub 마커 프리뷰, Theme 토글이 plot data
  색상을 건드리지 않음, Dock 토글 후 Workspace width 회복 (8f3b09d).
- 슬라이더 hot path 경량 게이지 — `updateAttitudeNeedlesOnly` (HGtransform
  matrix 만 갱신, sprintf 라벨 생략) 추가 + `previewSyncedMarkersOnly`
  에서 우선 사용; 라벨은 슬라이더 릴리즈 시 final commit 경로가 갱신.

---

## [Legacy Unreleased] — FlightDataReviewStudio 전환 (Phase 0~4)

OriginPro 식 통합 GUI(`FlightDataReviewStudio`)로의 전환 작업 중. 기존
`FlightDataDashboard`는 **standalone + embedded(Studio 내부 탭)** 양쪽으로
동작 가능.

### Phase 0 — 기존 dashboard 안정화 (완료)
- 67개 wrapper 메서드 삭제, 4개 신규 모듈 분리
  (`MarkerDragController`, `RailSummaryView`, `RoiAnalyzer`, `InfoController`)
- `PlaybackStateModel` 도입(채널별 가드/pending 상태)
- `Throttle` 키에 `ActiveSessionId` 접두 정책
- 4 design 문서 추가 (`design-serialization.md`, `design-dirty-dag.md`,
  `design-matlab-ui-reality-check.md`, `test-multi-instance-drag.md`)

### Phase 1 — Studio shell 신설 (완료)
- `FlightReviewStudio.m` entry + `flightdash.studio.FlightReviewStudioApp`
- 좌측 Project Explorer(`uitree`) + 중앙 Workspace tabgroup +
  우측 Inspector/Object Manager/Logs/Apps 탭 + 하단 Status Bar
- Menu (File/Project/Data/Video/Sync/Review/Analysis/Plot/Window/Preferences/Help)

### Phase 2 — Project / Session model (완료)
- `+flightdash/+project/`: `ProjectModel`, `SessionModel`, `FigureModel`,
  `ReviewResultModel`(DAG 메타 포함), `AnalysisThemeModel`
- 모두 value class + `SchemaVersion` + `DirtyFlag`
- `.frsproj` ZIP+JSON+MAT v7.3 포맷 결정 (구현은 Phase 9)

### Phase 3 — Embedded dashboard (완료)
- 3a: `FlightDataDashboard(parentContainer, sessionId)` 시그니처
- 3b: workspace 탭 안에 dashboard 임베드, `RootContainer` 추상화
- 3c: 탭 라이프사이클(close active/all), 자동 진단(`runMultiInstanceTests`),
  embedded mode rail 강제 disable, 파일 다이얼로그 setappdata 가드,
  Explorer↔workspace 양방향 동기화

### Phase 4 — Event Scope / Session Router (완료)
- `flightdash.util.SessionScope` (전역 active session id registry)
- `app.isActiveSession(eventData)` 2-layer 체크
- `AppEventData.SessionId` 필드 (default `''` = broadcast)
- 8개 controller listener에 session gate 적용
- `MarkerDragController` / `PannerController` motion fcn 직접 guard
- `FlightDataDashboard.delete()` embedded는 parpool/parfevalOnAll **건드리지 않음**
- Studio resize / 탭 변경 시 active dashboard `LayoutMgr.applyLayout` 자동 호출

### Round B — 모델 hardening (완료)
- `SessionModel` channel index validator + path/name coercion
- `ProjectModel.newId()` persistent counter (random 충돌 제거)

### Repository hygiene
- `.gitattributes` 추가: `*.m`/`*.md` UTF-8 + LF 강제 (CP949 mojibake 재발 방지)

### 진행 중 (deferred)
- Phase 5 (Project Explorer rename/duplicate, Object Manager wiring)
- Phase 6 (Toolbar/Menu/Inspector/Mini Toolbar/GUI Mode)
- Phase 7 (Analysis Dialog System)
- Phase 8 (Auto Update / Recalculate, DirtyTracker)
- Phase 9 (`.frsproj` Save/Load via ZIP)
- Phase 10 (SharedDecodeService / SharedCacheService)
- 우선 Phase 4까지 실측 검증 통과를 권장

### Deprecated
- `app.VideoSyncState(fIdx)` 직접 참조 — 향후 `app.SyncMdl(fIdx)` 로 마이그레이션 예정

### Phase 11 — Modern Responsive GUI and Real-Time Review UX (in progress)

리뷰 보고서 7건을 단계적으로 흡수한 프론트엔드 현대화 묶음.

#### Data loading / Studio 초기화
- `AppConstants.columnAliases()` static + `REQ_KEYS_CRITICAL`/`REQ_KEYS_OPTIONAL`
  분리 — Roll/Pitch/Heading 누락 시 critical=error, optional=warning
- `FlightDataLoader.inferRequiredColumn(reqKey, csvHeaders, optTargetValue)` —
  alias 머지 + 정규화 + ≥4-char 부분일치 fallback (e.g. `Roll(deg)`, `RollAngle`, `BankAngle`)
- `option*.dat` block-1 매핑 실패 시 alias 기반 재시도, `validateRequiredColumnData`
  의 다운스트림 가드와 일치
- `FlightReviewStudio.m` entry-point 래퍼에서 Untitled 프로젝트 진입 시
  "Session 1" 자동 생성 (테스트/diag 는 클래스 직접 인스턴스 → clean baseline)
- `ProjectExplorerPanel.refreshFromProject` `drawnow limitrate` + ActiveSessionId-first
  selection + tagged warning
- `WorkspaceManager.addDashboardTab` WelcomeTab 안전망 + `onTabChanged` tagged warning

#### Drag / cleanup / UI safety
- `forceEndAllDrag(reason)` 도우미 — 모든 드래그/커서 상태 복구; `cleanupAllControllers`
  진입 시 자동 호출
- `cleanupHandleProperty` 핸들-배열 안전화 (per-element iterate)
- `StudioMouseRouter.releaseDragLock` / `onMouseUp` `isvalid(obj)` 가드
- `MarkerDragController.safeClearUpdating` static + `setStateUpdating` `isvalid(app)` 가드
  — 모달 파일 다이얼로그 중 드래그-up 이벤트가 invalid handle 으로 폭주하는 문제 해소
- Roll/Pitch/Heading 다운스트림 가드: `mappedColAvailable(fIdx, key)` +
  `setAttitudeGaugeVisible(fIdx, tf)` — 자세 데이터 미매핑 시 게이지 자동 숨김

#### Layout / Theme / Toolbar
- 표준이용 figure 초기 사이즈 `FIGURE_INITIAL_W`/`H` = 1700×900, `FIGURE_MIN_W`/`H`
  = 1120×640 (NARROW 프로파일 자동 진입 방지)
- `BodyGrid` 3-column `[220 1x 300]`, Studio 기본 GUI 모드 = `Studio`
- 신규 `DockedFigure` GUI 모드 (Studio 레이아웃 + `WindowStyle='docked'`) +
  `applyWindowStyle` 안전 헬퍼 (MATLAB Online 비대응 시 silent fallback)
- 신규 `+flightdash/+ui/StudioTheme` — `light()`/`dark()` 정적 팔레트 + `apply(fig, theme)`
  헬퍼 (uipanel / uitab / uigridlayout / uilabel / uibutton / Axes 만 스타일링,
  plot data line/patch/image 색상은 절대 건드리지 않음)
- `Pref:Theme:Toggle` 명령 + 메뉴 + 툴바 `Theme` 버튼
- `RightDockManager` `AnalysisTab` placeholder + `Toolbar:ToggleRightDock` /
  `Window:ToggleRightDock` 대칭 토글
- 툴바 trailing 영역 28-column: `Expl` / `Dock` / `Theme` 고정 픽셀 버튼 3개
- 리사이즈 throttle 80 ms (`LastResizeTic` + `ResizeThrottleMs`) — Studio + 단독
  Dashboard 양쪽

#### Video slider / shared decode
- `requestFrame` drag/slider-preview 소스에서 절대 sync-decode 차단 (UI 스레드 보호) —
  async 사용 시 dispatch, 아니면 pending 큐로 enqueue
- `SliderScrubTimer` (fixedSpacing, Period 1/30, BusyMode='drop') — `ValueChangingFcn`
  은 PendingFrame 만 기록, 타이머가 cache→sync decode 순으로 ~30 fps 드레인
- `logTimerError(evt, tag)` — timer ErrorFcn 이 MException 가 아닐 때도 안전하게 unpack
- `WorkspaceManager.onTabChanged` → `SharedDecodeService.setActiveSession(newId)` —
  활성 세션 priority 0, 백그라운드 priority 10
- `onVdubSliderChanged` → `SharedDecodeService.advanceSessionGeneration(sid)` —
  슬라이더 릴리즈 시 진행 중인 stale decode discard
- `VideoPanel.publishSliderChanging` 가 `SessionScope.getActive()` 로부터 sessionId 를
  resolve → multi-session throttle 슬롯 충돌 제거 + `AppEventData(fIdx, value, sessionId)`
  3-arg form 사용

#### Gauges
- Pitch/Roll/Heading 게이지 니들 ~50% 확대, 고대비 fill (Pitch=blue, Roll=red,
  Heading=green) + 흰색 edge, panel resize 시 uigridlayout 통해 자동 스케일

#### Phase 7 — Analysis Dialog (신설)
- `+flightdash/+analysis/AnalysisDialog` 공통 base (handle) — 세션/채널 컨텍스트
  라벨, Body 영역 + OK/Apply/Cancel + Save Theme; Apply 시 subclass `compute()` →
  `ReviewResultModel` → `Project.addResult` → Explorer refresh → EventBus
  `AnalysisResultCreated` publish (sessionId 첨부)
- `RoiStatisticsDialog` — Mean/Std/Min/Max/N over `[T0,T1]`, 변수 드롭다운
- `SyncQualityDialog` — IsSynced/VideoFps/DataFps/FpsResidual/AnchorOffset/Verdict
- `CommandRouter.openAnalysisDialog` — 활성 세션 + 우측 dock Analysis 탭 전환 +
  dialog 표시; `Toolbar:Analyze` → ROI dialog, `Analysis:SyncQuality` → Sync dialog
- 기존 `RoiStatisticsAnalyzer` 값 클래스(AnalysisService 가 사용)와 충돌 방지 위해
  dialog 는 `*Dialog` 접미사로 분리

#### Project Explorer
- `onSearch` 실제 구현 — 트리 DFS 로 첫 일치 노드 찾기, 조상 expand, select+scroll;
  매치 실패/공백 시 상태 표시줄 갱신

#### 미반영 (의도적 deferred)
- `DashboardPanel` / `VideoPlayerPanel` / `InstrumentsPanel` / `DataViewPanel`
  ComponentContainer 분리 — 기존 `FlightDataDashboard` 와 functional parity
  확인 전까지 보류
- 사용자 직접 입력 ROI 영역 분석 다중 표시
- GUI Layout Toolbox / 미문서화 ToolGroup — 의도적으로 사용하지 않음

---

## [0.12.0] — 2026-05-03 EventBus + High-DPI

### Added
- **EventBus 아키텍처** — `flightdash.util.EventBus` 싱글톤 + `AppEventData` 페이로드 래퍼로 View↔Controller 결합 제거
- **5개 Controller 클래스** — `FileController`, `VideoSyncController`, `PlaybackController`, `PanelToggleController`, `DragController`
- **3개 Model 클래스** — `FrameCacheModel`, `VideoModel`, `SyncModel` (가중 LRU + Frame↔Time 변환 + sub-frame 정밀도)
- **`AppConstants`** — 공유 상수 중앙화 (`MAX_TABS`, `*_THROTTLE_S` 등)
- **`UIScale`** — High-DPI 픽셀 스케일러 (96 DPI 기준 → 실효 픽셀 자동 변환)
- **`ErrorLog`** — DebugMode 게이팅 catch 로깅 헬퍼
- **`Throttle`** — 시간 기반 hit 게이트 싱글톤 (슬롯 + 채널별)
- **`TimeFormat`** — frame → HH:MM:SS.mmm 포맷팅
- **자동 페이지 넘김** — H 패널에서 마커가 화면 밖 이탈 시 줌 비율 유지한 채 X축 자동 이동 (`IsProgrammaticXLim` 가드)
- **비동기 프레임 디코딩** — `parfeval` 워커 풀 + persistent VR LRU (`asyncDecodeFramePersistent.m`)
- **Generation counter (`AsyncGen`)** — stale future 결과 자동 폐기
- **PendingFrame coalescing** — latest 요청만 처리, `MAX_PENDING_ITERS` 안전망

### Fixed
- **좀비 컨트롤러 메모리 누수** — `delete(app)` 시 모든 Controller에 명시적 `delete()` 호출 → EventBus listener 누수 차단
- **자동 동기 회귀** — AVI + flight data 로드만으로 자동 동기되던 동작 제거. "동기" 버튼 명시 클릭 시에만 활성화
- **Inf 값 처리** — `markInvalidGpsAsNaN` 이 (0,0) 좌표 외 Inf 값도 NaN 처리 → fillmissing/plot 멈춤 방어
- **H 패널 보호 우선화** — 스플리터 드래그 시 H 최소폭(320px) 절대 보장, 비디오는 잔여 한도 내에서만 양보
- **`uifigure` SizeChangedFcn 경고** — `AutoResizeChildren='off'` 설정으로 콜백 정상 발화
- **`hgPitch` 등 미초기화 필드** — `AttitudePanel`/`MapAltPanel` 에서 `gobjects(0)` placeholder 사전 생성 → `buildUIGroups` 단계에서 안전 alias

### Performance
- **`whos` 호출 제거** — `FrameCacheModel.BytesPerFrame` 캐시 (영상 해상도 기반 1회 산정)
- **`cellfun` 핫패스 제거** — `BytesArr` 사전 계산으로 매 evict O(N) → O(1)
- **View-단 Throttle 선체크** — 슬라이더 드래그 시 33fps 초과 모션은 EventBus publish 자체 생략 → AppEventData 생성/notify 오버헤드 절감
- **SyncModel jitter guard** — 1e-9 사전 절삭으로 부동소수점 boundary ±1 frame 토글 차단

### Compatibility
- **High-DPI 자동 스케일** — 모든 `ColumnWidth` / `RowHeight` 가 `UIScale.px()` 통과 (96 DPI 디자인 → 125%/150%/200% 자동 비례 확장)
- **App 의존 제거** — 모든 view 빌더가 `EventBus + AppConstants` 만 사용 (View 100% 독립)
- **`createGaugePanel`** → `AttitudePanel.createGauge` 정적 헬퍼로 이동

---

## [0.11.x] — V3.x 시리즈 (이전)

### V3.23 — Sub-frame Precision
- `SyncModel.AnchorOffset [-0.5, 0.5]` 도입 — 긴 영상 누적 오차 제거

### V3.22 — Refactor #1~5
- `FlightDataDashboard` private constants 정의
- `applyVideoLoadedUI` TotalFrames 산정 + UI 위젯 동기화 흐름 재구성
- `UIGroup` alias 도입 — 평면 UI struct → 그룹화된 view 구조

### V3.21 — Async Race Mitigation
- Generation counter 도입
- Async future + sync decode 경로 분리

### V3.19~V3.20 — 비동기 디코딩 + Adaptive Prefetch
- `UseAsyncDecode` 옵션 + 드래그 속도/방향 기반 prefetch 범위

### V3.17~V3.18 — Coalescing
- `PendingFrame` / `PendingMode` + `MAX_PENDING_ITERS` 안전망

### V3.15~V3.16 — Slider/Frame Navigator
- `goToFrame` 단일 진입점 + drag/final 모드
- VirtualDub-style Frame Navigator UI

### V3.14 — 동적 Cache 한도
- 영상 해상도 + 메모리 예산 기반 `FrameLimit` 계산

### V3.11~V3.13 — Drag/Sync 안정화
- `IsProgrammaticXLim` 가드, 동적 throttle, 동기 anchor

### V3.8~V3.10 — Toolbar / Plot 인터랙션
- 커스텀 `axtoolbar`, zoom/pan-off 강제 호출 패턴

---

## 버전 정책

- **MAJOR** (1.0.0 → 2.0.0): 호환되지 않는 API 변경 (예: 외부 호출 메서드 시그니처 변경)
- **MINOR** (0.12.0 → 0.13.0): 하위 호환 기능 추가 (예: 새 컨트롤러, 새 이벤트)
- **PATCH** (0.12.0 → 0.12.1): 하위 호환 버그 수정

`v0.x.x` 동안은 내부 API가 자유롭게 변경될 수 있으며, `v1.0.0` 도달 시점에 안정화됩니다.
