# FlightDataDashboard 리팩토링 보고서 v2 (rev. 2026-05-17b)

> **갱신일**: 2026-05-17 (minor revision b)
> **변경 내역 (rev. b)**: §1-1 메트릭 보강 / §3 책임 경계 핵심 원칙 명시 / §8 hot-path indirection 위험 추가 / 부록 B 첫 액션 구체화
> **이전 버전**: v1 (R1~R8 + Ribbon + ControllerBase 작업을 인지하지 못한 상태로 작성됨)
> **v2 변경 의도**: 기 완료 작업 8건 인정 → Presenter/View 레이어를 **기존 어댑터/컨트롤러 위에 얹는 형태**로 재정의 + `Models` 반전을 별도 RFC로 분리 + 실측 수치 반영

---

## 목차

1. [현재 상태 (실측 기반)](#1-현재-상태-실측-기반)
2. [이 보고서의 범위](#2-이-보고서의-범위)
3. [목표 책임 경계](#3-목표-책임-경계)
4. [신규 도입 컴포넌트 2종](#4-신규-도입-컴포넌트-2종)
5. [Phase별 실행 계획](#5-phase별-실행-계획)
6. [Models 반전 — 별도 RFC](#6-models-반전--별도-rfc)
7. [테스트 전략 (v1에서 채택)](#7-테스트-전략-v1에서-채택)
8. [위험 및 대응](#8-위험-및-대응)
9. [성공 기준](#9-성공-기준)

---

## 1. 현재 상태 (실측 기반)

### 1-1. FlightDataDashboard.m 메트릭

| 항목 | 값 | v1 보고서 주장 | 차이 |
|------|-----|---------------|-----|
| 파일 크기 | 308 KB | 1.6 MB+ | 5× 과장 |
| 행 수 | 6,221 | "수만 줄" | ~4× 과장 |
| public 속성 (storage 잔존) | ~45 | (미측정) | — |
| public 속성 (Dependent forward) | 35 | (미측정) | R6~R8 결과 |
| public 메서드 | ~180 | (미측정) | — |
| `app.Models(fIdx)` 직접 접근 | 77 read | "수백 군데" | 일부 과장 |
| `app.UI(fIdx)` 직접 접근 수 | 측정 중 (예: 142 read / 87 write) | "수백 군데" | 정밀 측정 진행 |

### 1-2. 기 완료된 리팩토링 자산

```
StateStore 레이어 (이미 존재)
├── flightdash.runtime.SessionContext        (9/9 필드 storage, R7)
├── flightdash.state.AsyncDecodeState        (10/10 필드 storage + 4 helper verbs, R6)
├── flightdash.state.DashboardLayoutState    (11/11 필드 storage + 편의 writer, R6)
├── flightdash.state.VideoSessionState       (3/3 필드 storage, R8)
├── flightdash.state.ChannelState            (per-channel paths storage, R8)
└── flightdash.state.DashboardStateStore     (channel 집계 + 비디오 집계, R2)

서비스 경계 (이미 존재)
├── flightdash.runtime.DashboardAppAdapter   (R5 — session/channel/store/asyncDecode/layout 라우팅 + dispatchCommand/logCaught)
└── flightdash.runtime.DashboardRuntime      (StateStore + Adapter + Session 집계, R2)

컨트롤러 레이어 (이미 존재 — 10/10 ControllerBase 상속)
├── ControllerBase.subscribeEvent / trackListener / normalizeAdapterInput
├── Drag / Marker / Panner / Roi / Playback (drag-aware controllers)
└── File / VideoSync / PanelToggle / Plot   (pure event-relay)

진단 가드
├── flightdash.diag.verifyDashboardRefactorBaseline  (35개 inversion 잠금)
├── static_test/verifyPhase4.m                       (P4-1~P4-13 — 컨트롤러 leak guard 포함)
├── static_test/verifyCallbackSafety.m               (정적 + 런타임 EventBus leak probe)
└── FlightReviewStudioTestSuite.m                    (runner — static_test/*.m 순회 + .log 작성)
```

### 1-3. 의도적으로 보류된 작업

- **`Models` 반전** — 77 read site, hot path (`updateDashboard`/`applyTimeChange`/plot 렌더링). Prior 세션에서 "대안 3"으로 deferred.

---

## 2. 이 보고서의 범위

### 2-1. 포함 (v2가 새로 제안)

1. **`DashboardPresenter` (신규)** — state 변화 → View 갱신 / user input 라우팅을 한 곳에 모음
2. **`ChannelView` (신규)** — 현재 `ChannelLayout.build()`가 반환하는 struct를 handle class로 격상, callback wiring 캡슐화
3. **v1 테스트 전략 채택** — `matlab.mock` + constraints 가이드를 즉시 자산화 (value-struct mock 버그는 handle wrapper로 교체)

### 2-2. 제외 (별도 트랙)

- `Models` 반전 — §6 RFC 별도 분리
- 기 완료된 StateStore/Layout/Async/Session 인프라 재작업 — 0건
- Controller 재구성 — 0건 (현재 10/10 ControllerBase 기반 안정 운영 중)
- Ribbon UI 변경 — 0건

---

## 3. 목표 책임 경계

```
┌──────────────────────────────────────────────────────────────────┐
│                  사용자 입력 (uitable / button / drag)              │
└─────────────────┬────────────────────────────────────────────────┘
                  │ EventBus.publish(...) 또는 직접 콜백
                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  10 Controllers (ControllerBase 상속)                              │
│  · EventBus 구독 (subscribeEvent)                                  │
│  · session/active 가드 + drag lock                                 │
│  · 변경 의도를 Presenter.applyXxx() / dispatchCommand 로 위임            │
└─────────────────┬────────────────────────────────────────────────┘
                  │ Presenter API 호출
                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  DashboardPresenter (NEW)                                         │
│  · StateStore mutation (currentIndex/playback/sync 상태)            │
│  · Throttle (markers @60fps)                                      │
│  · UndoService.push(MoveMarkerCommand 등)                          │
│  · ChannelView.updateXxx() 호출                                    │
│  · Sync cascade (fIdx=1 → fIdx=2)                                 │
└─────────────────┬────────────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┐
        ▼                    ▼
┌──────────────────┐  ┌───────────────────────────────────────────┐
│  StateStore       │  │  ChannelView (NEW)                        │
│  (기존, 사용)     │  │  · UI handle 보유 (struct → handle wrap)   │
│  · ChannelState   │  │  · updateMarkersOnly(idx)                 │
│  · LayoutState    │  │  · updateAttitudeGauges(idx)              │
│  · AsyncDecode    │  │  · updateCurrentInfoTable(idx)            │
│  · Session/Video  │  │  · refresh()                              │
└──────────────────┘  └───────────────────────────────────────────┘
                  ▲
                  │
┌──────────────────────────────────────────────────────────────────┐
│  DashboardAppAdapter (기존, 유지)                                  │
│  · session() / channel(fIdx) / store() / asyncDecode() / layout() │
│  · dispatchCommand / logCaught                                    │
│  · controllers 가 이미 의존 중 — Presenter 가 추가 의존자가 됨        │
└──────────────────────────────────────────────────────────────────┘
                  ▲
                  │
┌──────────────────────────────────────────────────────────────────┐
│  FlightDataDashboard (얇은 Orchestrator로 축소 진행 중)              │
│  · 35개 Dependent forward 유지 (R6~R8 결과)                        │
│  · Models / UI는 잔존 storage (Models 반전은 §6 RFC)                │
└──────────────────────────────────────────────────────────────────┘
```

> **🔑 중요 원칙**: Controllers는 절대 StateStore를 직접 수정하지 않고, 반드시 `Presenter.applyXXX()` 또는 `dispatchCommand`를 통해 요청한다. (단방향 흐름 보존)

### 3-1. 책임 매트릭스

| 역할 | 담당 |
|------|------|
| 상태 저장 (Layout/Async/Session/Video/Channel paths) | **이미: StateStore + 4 state classes** |
| 상태 저장 (Models = rawData/mappedCols/displayMeta/...) | **잔존: FlightDataDashboard** (RFC 대상) |
| 서비스 접근 추상 (Undo/Cache/Decode/UI fig/session) | **이미: DashboardAppAdapter** |
| 사용자 입력 수신 | **이미: 10 Controllers** |
| 상태 → View 갱신 조율 | **신규: DashboardPresenter** |
| 채널 UI handle 보유/wiring | **신규: ChannelView** |
| Throttle / Sync cascade | **신규: DashboardPresenter** |
| Cmd dispatch (메뉴/리본) | **이미: CommandRouter (Adapter.dispatchCommand 경유)** |

---

## 4. 신규 도입 컴포넌트 2종

### 4-1. `flightdash.presenter.DashboardPresenter`

**위치**: `+flightdash/+presenter/DashboardPresenter.m`

**의존성** (생성자에서 주입):
- `flightdash.runtime.DashboardAppAdapter` (기존)
- `flightdash.state.DashboardStateStore`  (기존, adapter.store() 통해 접근)
- (선택) `flightdash.studio.UndoService` (이미 SessionContext.UndoService에 storage)

**공개 API (1차):**
| 메서드 | 호출처 | 비고 |
|--------|--------|------|
| `updateDashboard(fIdx, index)` | Controllers + 내부 cascade | Models 잔존 동안 `app.Models(fIdx).rawData` 읽기는 Adapter.app() 경유 |
| `updateMarkersOnly(fIdx, index)` | MarkerDragController 드래그 motion | 60fps throttle |
| `onSpinnerChanged(fIdx, time)` | PlaybackController | time→index 변환 후 updateDashboard |
| `onPlotXLimChanged(fIdx, xlim)` | PannerController | center→index 변환 후 updateDashboard |
| `pushMarkerMoveCommand(fIdx, old, new)` | stopMarkerDrag 종료 | UndoService.push |
| `handleSyncCascade(sourceFIdx, index)` | 내부 | fIdx=1 → fIdx=2 자동 동기 |

**비공개 헬퍼:**
- `throttleHit(key, fIdx, intervalSec)` — 단일 throttle 매니저 (기존 `app.throttleHit` 위임 가능)

**미포함** (RFC §6 도착 전):
- `app.Models(fIdx)` 쓰기 경로 직접 소유 — 아직 app에 의존
- `app.UI(fIdx)` 직접 접근 — 아직 일부 잔존 (ChannelView로 점진 이동)

### 4-2. `flightdash.view.ChannelView`

**위치**: `+flightdash/+view/ChannelView.m`

**역할 한정**:
- 기존 `ChannelLayout.build()`가 반환하던 struct(`app.UI(fIdx)`)를 owning handle class로 감쌈
- Callback wiring (`ButtonDownFcn`, `ValueChangedFcn`)을 한 곳에 모음
- View 갱신 API (`updateMarkersOnly`, `updateAttitudeGauges`, `updateCurrentInfoTable`) 노출
- **상태 보관 금지** — 상태는 StateStore가 소유

**점진 도입 전략**:
- `app.View(fIdx)` 신규 Dependent 속성 추가 → 내부적으로 `app.Models(fIdx).View` 또는 신규 ChannelView 인스턴스 반환
- 기존 `app.UI(fIdx).hAltMarker` 같은 직접 접근은 1차 phase에서 그대로 둠 (소유권 이동만 먼저, 사용처는 phase 2-3에서 마이그레이션)

---

## 5. Phase별 실행 계획

### Phase A — Scaffolding (1~2일)

| 단계 | 결과물 | 회귀 가드 |
|------|--------|----------|
| A-1 | `+flightdash/+presenter/DashboardPresenter.m` skeleton (no logic, just constructor + property block) | metaclass 확인 테스트 |
| A-2 | `+flightdash/+view/ChannelView.m` skeleton (wraps `ChannelLayout.build` output) | 인스턴스 생성 smoke test |
| A-3 | `FlightDataDashboard` 생성자 끝부분에 Presenter/View 인스턴스 lazy-init 훅 추가 (standalone + embedded 모두 동작 확인) | 기존 `static_test/old_FlightReviewStudioCoreTestSuite` 전체 PASS 유지 |

### Phase B — Presenter Pilot: `updateMarkersOnly` (3~5일)

| 단계 | 결과물 | 가드 |
|------|--------|------|
| B-1 | Presenter에 `updateMarkersOnly(fIdx, idx)` 구현 — 기존 `app.updateMarkersOnly` 로직을 그대로 호출 (delegation 단계) | 시각 회귀 없음 확인 |
| B-2 | MarkerDragController가 `obj.Adapter.app().updateMarkersOnly(...)` 대신 `obj.Adapter.presenter().updateMarkersOnly(...)` 사용 | Phase4 P4-13 leak guard 유지 |
| B-3 | Throttle 통합 (현재 `app.throttleHit('MapPathDragUpdate', ...)` 등) | drag 성능 동등성 측정 |

### Phase C — ChannelView 1개 채널 시범 (1주)

| 단계 | 결과물 | 가드 |
|------|--------|------|
| C-1 | `ChannelView(fIdx=1, parent, presenter)` 생성 — 기존 `ChannelLayout.build` 호출 결과를 `obj.UI`로 보관 | standalone 시각 동일성 |
| C-2 | `wireInteractions()` — `hAltMarker.ButtonDownFcn` 등 5~10개 callback을 ChannelView에서 등록 | 기존 직접 등록 코드와 충돌 방지 (한 곳만 등록) |
| C-3 | `updateMarkersOnly(idx)` / `updateAttitudeGauges(idx)` 메서드 추가 — Presenter가 ChannelView를 호출 | embedded 모드 회귀 없음 |

### Phase D — fIdx=2 확장 + Adapter API 추가 (3~5일)

| 단계 | 결과물 | 가드 |
|------|--------|------|
| D-1 | Adapter에 `presenter()` / `channelView(fIdx)` accessor 추가 (이미 있는 `channel(fIdx)`와 별도) | 컨트롤러 dispatch 변경 없음 |
| D-2 | fIdx=2 ChannelView 활성화 | Sync cascade 정상 동작 검증 |

### Phase E — 나머지 update 메서드 점진 이동 (1~2주)

`updateDashboard`, `updateCurrentInfoTable`, `applyTimeChange` 등 약 5~7개 update 함수를 `app` 메서드에서 Presenter로 1개씩 이동. 각 이동은 단독 commit.

### Phase F — UI 직접 접근 정리 (선택, 1~2주)

`app.UI(fIdx).*` 직접 read/write 사이트를 `obj.Adapter.channelView(fIdx).*`로 점진 라우팅. 핫패스(`updateDashboard` 내부)는 보류 — RFC §6 Models 반전과 함께 처리.

---

### 총 예상 기간

| 시나리오 | 기간 |
|---------|------|
| Phase A~C만 (Presenter 도입 + ChannelView 1채널 시범) | **1.5~2주** |
| Phase A~E (Presenter 메서드 전체 이동 + ChannelView 2채널) | **3~4주** |
| Phase A~F (UI 직접 접근 정리 포함, Models 반전은 제외) | **5~7주** |

v1 보고서의 10~12주 추정은 (중복 작업 8건 제거 + Models 반전 분리) 후 **50~70% 축소**됨.

---

## 6. Models 반전 — 별도 RFC

> **이 보고서의 범위 밖. 별도 설계 문서 작성 후 진행 결정.**

### 6-1. 왜 분리하는가

- `app.Models(fIdx).rawData.column(idx)` deep struct-array access가 ~77 read site + 핫패스(`updateDashboard`/`applyTimeChange`/plot 렌더링) 다수 포함
- Dependent forward로 단순 ownership 반전 시 매 `app.Models(fIdx)` 호출이 getter 디스패치 + struct 합성 → 측정되지 않은 성능 회귀 위험
- 다른 35개 inversion (LayoutState/AsyncDecodeState/SessionContext/VideoSessionState/ChannelState paths)와 risk profile이 다름

### 6-2. RFC가 다뤄야 할 항목

1. **현 read site 정밀 카운트 + 핫패스 분류** (cold/warm/hot)
2. **두 가지 후보 설계**:
   - 후보 A: `app.Models` → Dependent forward (단순, 검증 가능, 성능 측정 후 결정)
   - 후보 B: 읽기 사이트를 `app.channel(fIdx).RawData` 등으로 점진 마이그레이션 후 storage 이동 (다중 커밋, 안전)
3. **성능 벤치마크 기준** (`updateDashboard` 평균 시간, marker drag fps)
4. **R6/R7/R8 회귀 가드와의 통합** (`verifyDashboardRefactorBaseline`에 Models 잠금 추가 시점)

### 6-3. v2 보고서와의 관계

- v2 (Phase A~F)는 Models 잔존 상태에서 완료 가능 — Presenter/ChannelView는 `obj.Adapter.app().Models(fIdx)` 경유로 읽기/쓰기
- RFC 결정 이전에는 Presenter/ChannelView가 Models 인터페이스 자체를 가정하지 않도록 코딩 (어댑터 통과 패턴 일관성 유지)

---

## 7. 테스트 전략 (v1에서 채택)

v1의 `matlab.mock` 가이드는 핵심 자산으로 즉시 채택. 단, value-struct mock 버그는 handle class wrapper로 교체.

### 7-1. Mock 헬퍼 (handle class 교체본)

```matlab
% +flightdash/+test/MockChannelView.m
classdef MockChannelView < handle
    properties
        fIdx                double  = 1
        LastUpdatedIndex    double  = 0
        UpdateCount         double  = 0
        LastAttitudeIdx     double  = 0
        ErrorOnUpdate       MException = MException.empty
    end
    methods
        function obj = MockChannelView(fIdx), obj.fIdx = fIdx; end
        function updateMarkersOnly(obj, idx)
            if ~isempty(obj.ErrorOnUpdate), throw(obj.ErrorOnUpdate); end
            obj.LastUpdatedIndex = idx;
            obj.UpdateCount = obj.UpdateCount + 1;
        end
        function updateAttitudeGauges(obj, idx),    obj.LastAttitudeIdx = idx; end
        function updateCurrentInfoTable(~, ~), end
        function refresh(~), end
    end
end
```

### 7-2. Presenter 기본 테스트 패턴

```matlab
classdef DashboardPresenterTest < matlab.unittest.TestCase
    properties
        Presenter   flightdash.presenter.DashboardPresenter
        StateStore  flightdash.state.DashboardStateStore
        MockView1   flightdash.test.MockChannelView
        MockView2   flightdash.test.MockChannelView
    end
    methods (TestMethodSetup)
        function setupTest(tc)
            tc.StateStore = flightdash.state.DashboardStateStore(2);
            tc.MockView1 = flightdash.test.MockChannelView(1);
            tc.MockView2 = flightdash.test.MockChannelView(2);
            tc.Presenter = flightdash.presenter.DashboardPresenter.forUnitTest( ...
                tc.StateStore, {tc.MockView1, tc.MockView2});
        end
    end
    methods (Test)
        function viewReceivesIndex(tc)
            tc.Presenter.updateMarkersOnly(1, 150);
            tc.verifyEqual(tc.MockView1.LastUpdatedIndex, 150);
            tc.verifyEqual(tc.MockView1.UpdateCount, 1);
        end
        function throttleLimitsCalls(tc)
            for i = 1:30, tc.Presenter.updateMarkersOnly(1, i); end
            tc.verifyLessThan(tc.MockView1.UpdateCount, 30);
        end
        function syncCascadeUpdatesBoth(tc)
            tc.StateStore.Video.SyncState.IsSynced = true;
            tc.Presenter.updateDashboard(1, 100);
            tc.verifyGreaterThan(tc.MockView2.LastUpdatedIndex, 0);
        end
    end
end
```

### 7-3. `matlab.mock` 고급 검증 (v1에서 채택)

v1의 `verifyCalled` / constraints (`IsGreaterThan`/`IsEqualTo`/`WasCalled`) 패턴은 그대로 사용 가능 — 단, Presenter API가 안정화된 phase D 이후 도입 권장.

### 7-4. 기존 회귀 가드와의 통합

- `static_test/old_FlightReviewStudioCoreTestSuite.m` 의 T15_* 시리즈 — 변경 0건
- `static_test/verifyPhase4.m` P4-13 (controller leak) — 변경 0건
- `flightdash.diag.verifyDashboardRefactorBaseline` — Presenter/ChannelView가 새로 잠글 storage가 있으면 step 추가
- `FlightReviewStudioTestSuite.m` runner — 새 `+flightdash/+test/DashboardPresenterTest.m` 자동 발견되도록 `static_test/` 또는 `+flightdash/+test/` 두 경로 모두 스캔 검토

---

## 8. 위험 및 대응

| 위험 | 심각도 | 대응 |
|------|-------|------|
| Presenter와 ControllerBase의 책임 경계 모호 | ★★★ | Controller = "EventBus 수신 + active 가드 + Presenter 호출" 1줄 규칙 명문화. Controller는 상태 변경 직접 안 함. |
| `DashboardAppAdapter`와 Presenter의 메서드 중복 | ★★★ | Adapter = **read accessor + dispatchCommand**, Presenter = **update orchestration**. 둘이 같은 verb 갖지 않도록 PR 리뷰 체크리스트. |
| ChannelView 도입 시 callback 이중 등록 | ★★ | `ChannelLayout.build` 가 등록하던 callback 슬롯은 1차 phase에서 비워두고 `ChannelView.wireInteractions`만 등록. |
| MouseRouter drag lock과 Presenter dispatch 경합 | ★★ | drag motion은 여전히 MarkerDragController가 router lock 잡음. Presenter는 lock 검사 후에만 호출되는 구조 유지. |
| **Hot-path indirection 오버헤드** | **★★** | **`updateMarkersOnly`가 Presenter → ChannelView → UI handle로 이어지는 호출 체인으로 인한 latency 증가 가능성. Phase B에서 성능 베이스라인 측정 필수** (drag fps + `updateMarkersOnly` 평균 시간 ≤ 기준선 +5%). 회귀 시 Presenter→ChannelView 단계의 inline hot-path 경로 또는 dispatch 캐싱 검토. |
| v1처럼 일정 과대 추정 | ★ | Phase A~C 마일스톤 (1.5~2주) 도달 후 v3 일정 재산정. |
| MATLAB R2025a/R2026a + Online 호환 | ★ | Presenter/ChannelView는 모두 `handle` 클래스 + 일반 `uifigure`/`uigridlayout` 사용. R2021b까지 동작. |

---

## 9. 성공 기준

### 9-1. Phase A~C 완료 기준 (필수)

- [ ] `flightdash.presenter.DashboardPresenter` 생성 가능, smoke test PASS
- [ ] `flightdash.view.ChannelView` (fIdx=1) 생성 가능, smoke test PASS
- [ ] MarkerDragController가 Presenter 경유로 동작 (시각/성능 회귀 없음)
- [ ] `static_test/*.m` 전체 PASS (변경 0건)
- [ ] 기존 35개 ownership inversion baseline (`verifyDashboardRefactorBaseline`) PASS 유지

### 9-2. Phase D~E 완료 기준 (목표)

- [ ] fIdx=1, fIdx=2 모두 ChannelView 사용
- [ ] `updateDashboard`, `updateMarkersOnly`, `updateAttitudeGauges`, `updateCurrentInfoTable`, `applyTimeChange`가 Presenter에 위치
- [ ] `FlightDataDashboard.m` 행수 ≤ 5,500 (현재 6,221)
- [ ] `DashboardPresenterTest` 최소 10개 테스트 PASS

### 9-3. 명시적 비-목표

- `FlightDataDashboard.m` 행수 < 1,500 (v1의 슬림화 목표) — Models 반전 RFC 완료 전까지는 불가
- `Models` ownership 반전 — §6 RFC가 결정할 사항
- Throttle 시스템 전면 재설계 — Presenter 도입과 분리

---

## 부록 A — v1 대비 변경 요약

| 항목 | v1 | v2 |
|------|-----|----|
| 파일 크기 위기감 | 1.6 MB / 수만 줄 | 308 KB / 6,221 줄 |
| `app.UI(fIdx)` 접근 수 | "수백 군데" (추정) | 측정 중 (예: 142 read / 87 write) |
| StateStore/ChannelState 생성 | "이제 만들자" | "이미 R2에 존재 — 재사용" |
| LayoutState/VideoSessionState/AsyncDecodeState | (없음) | "이미 R6/R8 완료 — 인지" |
| DashboardAppAdapter | 미언급 | Presenter와 책임 분리 명시 |
| Controllers | "Presenter가 startMarkerDrag 처리" | "기존 10 컨트롤러 유지 — Presenter 호출자 역할" |
| Models 반전 | Phase 1 (1주) | §6 별도 RFC |
| 총 기간 | 10~12주 | Phase A~C 1.5~2주, A~E 3~4주, A~F 5~7주 |
| 슬림화 목표 | "300 KB 이하" | "행수 5,500 이하 (Phase E)" — 현실적 재설정 |
| Unit Test 가이드 | value-struct mock (버그) | handle class mock + v1 `matlab.mock` 가이드 채택 |
| 단방향 흐름 명시 | 암시적 | §3 다이어그램 직하단에 "🔑 중요 원칙" 명문화 |
| Hot-path indirection 위험 | 미언급 | §8에 ★★ 위험 + Phase B 베이스라인 측정 요구 |

---

## 부록 B — 다음 액션

1. **결정 대기**: v2 보고서 채택 여부 — ✅ **채택됨 (rev. b)**
2. **채택 시 즉시 작업**:
   - **Phase A-1 skeleton PR 생성 및 리뷰**
     - `+flightdash/+presenter/DashboardPresenter.m` skeleton (생성자 + 속성 블록 + smoke test target)
     - `+flightdash/+view/ChannelView.m` skeleton (ChannelLayout.build 결과 wrap, no logic 이동)
     - PR 설명에 책임 경계 다이어그램 + 단방향 흐름 원칙 첨부
   - **`MockChannelView.m` + `DashboardPresenterTest.m` 동시 작성** (skeleton과 같은 PR 또는 직후)
     - `+flightdash/+test/MockChannelView.m` (§7-1 코드)
     - `+flightdash/+test/DashboardPresenterTest.m` (§7-2 코드, smoke 단계 3개 테스트만 먼저)
     - `FlightReviewStudioTestSuite.m` 러너가 `+flightdash/+test/` 폴더도 스캔하도록 path 확장 검토
   - Phase A-3: `FlightDataDashboard` 생성자에 Presenter/View lazy-init 훅 + `verifyDashboardRefactorBaseline` PASS 확인
3. **RFC 트리거**: Models 반전 RFC를 별도 문서로 시작 (관련자 합의 후)
4. **Phase B 진입 전 측정**:
   - drag fps 베이스라인 (현재 `updateMarkersOnly` 경로)
   - `updateMarkersOnly` 평균 호출 시간 (tic/toc N=100 샘플)
   - 두 수치를 §8 hot-path indirection 위험의 회귀 판정 기준으로 사용