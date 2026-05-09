# Changelog

본 프로젝트의 모든 주요 변경사항을 기록합니다.

형식은 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 을 따르며,
버전은 [Semantic Versioning](https://semver.org/spec/v2.0.0.html) 을 준수합니다.

## [Unreleased] — FlightDataReviewStudio 전환 (Phase 0~4)

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
