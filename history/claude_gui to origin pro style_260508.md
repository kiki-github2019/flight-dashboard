

콘텐츠로 건너뛰기
스크린 리더로 Gmail 사용하기
2,665개 중 1개
참고
받은편지함

jungsub shin <jungsub99@gmail.com>
첨부파일
오후 6:11 (0분 전)
나에게

 첨부파일 1개
  •  Gmail에서 검사함
먼저 두 문서를 읽어서 검토하겠습니다.

두 문서를 모두 분석했습니다. 계획서의 타당성과 단계별 마이그레이션 로드맵을 검토해서 출력합니다.

---

# FlightDataReviewStudio 전환 계획서 검토 보고서

## 0. 종합 평가: **방향성 타당, 일정·기술 리스크 큼 (B+)**

계획서는 OriginPro의 핵심 GUI 철학(MDI 프로젝트 + 메타데이터 기반 재계산 + 역할별 모드)을 MATLAB 환경에 합리적으로 매핑하고 있습니다. OriginPro 분석보고서의 8가지 핵심 요소(Project Explorer, Object Manager, 상태 표시줄, Analysis Dialog, Recalculate, Mini Toolbar, GUI Mode, Logs)를 빠짐없이 반영했고, 데이터 모델 설계(SourceDataHash·SyncStateHash·DirtyFlag)는 OriginPro의 Recalculate 메커니즘을 정확히 이해한 결과입니다. 다만 MATLAB의 GUI 한계와 동시성 처리에 대한 reality check가 일부 부족하며, 11개 Phase의 작업량이 균등하지 않아 Phase 3·4·10의 일정 폭주 위험이 있습니다.

---

## 1. OriginPro 매핑 적절성 검토

### 1.1 정확하게 반영된 부분

| OriginPro 원리 | 계획서 반영 | 평가 |
|---|---|:---:|
| MDI 프로젝트 (.OPJU) → 다중 워크북 관리 | Project → Sessions[] → Figures[] | ★ 정확 |
| Project Explorer 폴더 트리 | FlightDataDashboard Explorer 12노드 | ★ 정확 |
| Object Manager 미시 객체 제어 | Active Dashboard 내부 객체 트리 | ★ 정확 |
| Plot Details 계층 (페이지·레이어·플롯) | FigureModel.Layers[] | ★ 정확 |
| 분석 대화상자 Input/Settings/Output 노드 | AnalysisDialog 트리 구조 | ★ 정확 |
| Dialog Theme 저장 → 반복 분석 표준화 | AnalysisThemeModel | ★ 정확 |
| 녹색 자물쇠(Recalculate Mode) | Manual/Auto/Frozen 3-state | ★ 정확 |
| 상태표시줄 실시간 요약 통계 | Status Bar Mean/Min/Max/Std/Count/Duration | ★ 정확 |
| 메시지 로그 vs 결과 로그 분리 | Message/Error/Result 3로그 | ★ 정확 — Error Log 추가는 좋은 보완 |
| 2025b Stats Mode (역할 기반) | Review/Analysis/Plot/Report/Compact 5모드 | ★ 정확 — Compact 추가 적절 |

### 1.2 MATLAB 환경 특성을 고려한 합리적 절충

- **Mini Toolbar**: OriginPro의 floating fade-in 구현이 MATLAB uifigure에서 어렵다는 점을 인정하고, 1차 버전은 Inspector 상단 quick action row로 시작 → 합리적 단계화
- **Project file**: `.OPJU` 대응 `.frsproj` 신설 — naming convention 일관성 좋음

### 1.3 매핑이 과욕적인 부분

| 항목 | 우려 |
|---|---|
| **앱 센터 / 앱 갤러리** (origin pro.md §확장성) | 계획서에서 `Apps / Tools` 탭만 언급, 실제 앱 패키지 시스템·OriginLab File Exchange 같은 마켓플레이스 부재 → 1차 범위에서 제외하는 것이 맞음 (계획서 입장 적절) |
| **Code Builder / LabTalk** | 계획서에서 명시 누락. MATLAB은 자체가 IDE이므로 별도 Command Window 불필요 — 누락이 합당 |
| **학습 센터 (F11)** | 누락. 비행 데이터 도메인이 좁아서 100+ 템플릿 갤러리는 과잉 — 누락이 합당 |
| **레이아웃 윈도우** (발표용 패널) | FigureModel에 `Layout` 타입은 있으나 구현 우선순위 미명시 → Phase 7 이후 후순위 권장 |

---

## 2. 데이터 모델 설계 검토

### 2.1 강점

- **계층 분리 명확**: Project → Session → Figure / Result / Theme — OriginPro의 Folder → Workbook → Sheet → Plot 4단 구조와 동등한 깊이
- **무결성 추적 필드**: `SourceDataHash`, `SyncStateHash`, `LastCalculatedAt`, `DirtyFlag`가 모든 결과 모델에 일관되게 부여됨 → Recalculate 메커니즘의 핵심
- **현재 SyncMdl/VideoMdl/PlaybackStateModel과 호환 가능**: SessionModel에 `FlightSyncState`, `VideoSyncState{1,2}`가 채널별로 들어가 기존 채널 분리 구조를 유지

### 2.2 약점 / 보완 필요

| 항목 | 문제 | 권장 보완 |
|---|---|---|
| **SourceDataHash 계산 비용** | 비행 로그가 수십 MB일 때 매번 SHA-256 풀스캔은 부담 | 파일 mtime + size + 첫·중간·끝 1KB 샘플 hash 등 **shallow hash** 전략 필요 |
| **Dirty propagation 그래프 부재** | ROI dirty → 의존 Analysis dirty → 의존 Plot dirty (DAG)인데, 모델에는 `DirtyFlag` 단일 필드만 존재 | `DependsOn[]` 또는 의존 그래프 관리자(`DirtyTracker`) 별도 설계 필요 |
| **AnalysisThemeModel.InputDefaults 직렬화** | Time Range·Variables 같은 동적 필드를 어떻게 저장? | JSON-like 가변 struct 명시 권장 |
| **Sessions[] 메모리 폭증 가능성** | 한 프로젝트에 세션 50+ 시 raw flight table이 모두 메모리 상주 | Session lazy-load (메타만 메모리, 데이터는 활성 세션만) 정책 필수 |
| **WindowId 정의 모호** | FlightDataDashboard 5.1에 WindowId 속성 추가하나 정의 없음 | `(SessionId, FigureType, Index)` 같은 합성키로 명확화 필요 |

---

## 3. 단계별 마이그레이션 로드맵 검토

### Phase 0 — 기존 Dashboard 안정화 ⭐ 최우선

**평가:** ★★★ 매우 적절. Studio 전환 전에 race condition·sync 복원 버그를 잡지 않으면 Embedded 후 디버깅이 두 배 어려워짐.

**보완 권장:**
- `cleanupAsyncDecodeCache` 통합 검증 케이스를 명시 (현재 5초 timeout만 있음)
- Phase 0 작업 6개 모두 회귀 테스트 시나리오 작성 후 통과 확인
- 현재 진행한 wrapper 제거 + 4개 신규 모듈(MarkerDragController/RailSummaryView/RoiAnalyzer/InfoController) 분리 작업도 Phase 0에 포함시켜야 함 → **이미 완료된 작업이므로 Phase 0 일부 충족됨**

**리스크:** 6개 항목 중 video sync anchor 복원과 sequential readFrame 안전화가 가장 위험. 단순 fix가 아니라 디코드 파이프라인 재설계 가능성.

---

### Phase 1 — Studio Shell 신설 ⭐ 비교적 안전

**평가:** ★★★ 신규 파일만 추가하므로 기존 코드 영향 0. UI 골격만 만드는 단계.

**보완 권장:**
- `FlightReviewStudio.m` (entry)와 `FlightReviewStudioApp.m` (구현) 분리 의도 명확히. 현재 root에 entry 둔 이유 명시 필요
- Status Bar의 실시간 요약 통계는 Phase 1에서 placeholder만 만들고 Phase 6에서 실데이터 연결 권장 (Phase 1 작업 폭주 방지)

**MATLAB 한계 reality check:**
- `tabgroup` 안에 다른 `uifigure`를 embed 불가 — Embedded Dashboard는 **uigridlayout 안에 패널을 직접 그려야 함**. Phase 3에서 큰 변경 필요
- OriginPro 같은 docking/floating window는 MATLAB에서 미지원. 우측 Inspector는 고정 dock으로 한정

---

### Phase 2 — Project / Session Model 추가 ⭐ 안전

**평가:** ★★★ 순수 데이터 클래스이므로 위험 낮음.

**보완 권장 (Phase 2 진입 전 결정 필요):**
1. **직렬화 포맷 결정**: `.frsproj`가 MATLAB `.mat` (struct save) vs JSON+에셋폴더 vs 자체 binary. OriginPro `.OPJU`처럼 zip+manifest+assets 구조 권장 (썸네일·외부 리소스 포함 위해)
2. **MAT-File 호환성**: `handle` class 직접 save 불가 — Model 클래스를 `value class`(struct-like) + 별도 controller로 분리하거나, `saveobj`/`loadobj` 메서드 명시 필요
3. **버전 마이그레이션**: `ProjectModel.SchemaVersion` 필드 추가하여 향후 스키마 변경 대응

---

### Phase 3 — FlightDataDashboard Embedded화 ⚠️ 위험도 최상위

**평가:** ★★ 가장 큰 구조 변경. 현재 코드의 figure-level 의존성을 모두 격리해야 함.

**구체적 문제점:**

1. **WindowButton callback의 figure 단위 한계**
   - 현재 `MarkerDragController`, `PannerController`, `DragController`가 `app.UIFigure.WindowButtonMotionFcn`을 직접 잡고 있음
   - Embedded mode에서 한 figure에 두 Dashboard 탭 → 한 탭의 drag가 다른 탭 좌표계로 누수
   - **해결책**: 모든 drag 컨트롤러에 `(SessionId, isActive)` 게이트 추가 + active session 외부 motion ignore

2. **dispose / cleanup 분리 필요**
   - 현재 `delete(app)` → `closeAllAuxFigures` + `parfevalOnAll cleanup`까지 수행
   - Embedded mode에서 tab close 시 어디까지 cleanup? → **tab close = session unload (캐시 evict, future cancel)**, **studio close = 전역 cleanup**으로 명확히 구분 필요

3. **createLayout 분기 부담**
   - 계획서는 `parentContainer 기준으로 UI 생성`이라고만 적시. 현재 5,000줄 메인이 `app.UIFigure` 가정 — 모든 layout 코드(LayoutMgr 포함)에 `RootContainer` 추상화 필요

4. **다중 인스턴스 race**
   - 현재 `flightdash.util.Throttle.instance()`는 싱글톤 — 두 Dashboard가 동시에 throttle key 충돌
   - **해결책**: throttle key에 SessionId 접두 강제 (`'PlotRowResize:S001'`) 또는 per-session throttle instance

**권장 보완:** Phase 3을 **Phase 3a (인터페이스 추상화) + 3b (실제 embed) + 3c (다중 탭 검증)**으로 3분할

---

### Phase 4 — Event Scope / Session Router ⚠️ 작업량 폭주

**평가:** ★★ 작업 분량 과소평가. 모든 `EventBus.publish`/`subscribe` 호출에 SessionId 추가는 수백 곳 변경.

**현실:**
- 현재 `+flightdash`에 `EventBus` 사용 라인이 100+개로 추정
- 모든 listener 시작에 `if ~strcmp(eventData.SessionId, obj.SessionId), return; end` 가드 추가 = 코드 폭증
- AppEventData 시그니처 변경 → 기존 직렬화된 config 호환 깨짐

**권장 보완:**
- `EventBus.publish` 자체에 `Context.SessionId` 자동 주입 메커니즘 (publisher가 자동으로 active session 태깅)
- listener 가드는 `BaseSessionListener` 같은 mixin/베이스로 1회 작성하고 전파
- 기존 single-session 호환을 위해 `SessionId == ''`는 broadcast로 해석하는 fallback

---

### Phase 5 — Project Explorer + Object Manager 완성 ⚠️ UI 구현 부담 큼

**평가:** ★★ MATLAB `uitree` 사용해야 하나, OriginPro 수준의 인터랙션(드래그 reorder, 다중 선택 일괄 스타일)은 어려움.

**MATLAB 한계:**
- `uitree` 노드의 inline checkbox는 R2021b+ 일부만 지원 (NodeIcon 변경 + state 추적 직접 구현 필요)
- 드래그&드롭으로 폴더 이동은 MATLAB 표준 `uitree` 비지원 — 별도 우클릭 컨텍스트 메뉴로 대체 필요
- 다중 선택 일괄 스타일 변경은 가능하나 Plot Details Dialog 자체가 새로 만들어야 함

**권장 보완:**
- Phase 5에서 Object Manager는 **표시·숨김 + 클릭 선택**까지만 구현, **일괄 스타일 변경은 Phase 6 Inspector 확장**으로 미룸

---

### Phase 6 — Toolbar / Menu / Inspector / Mini Toolbar ⚠️ 통합 시점 큰 phase

**평가:** ★★ 4개의 독립 시스템을 한 phase에 묶음. 분할 권장.

**위험:**
- Mini Toolbar의 floating uipanel 구현은 `WindowMousePressedFcn` + `CurrentPoint` 추적 필요 → 기존 marker drag와 mouse event 충돌
- GUI Mode 전환 시 toolbar 재구성은 단순 visibility toggle이 아니라 lazy build 패턴 필요 (모든 모드의 모든 컨트롤을 미리 만들면 메모리 낭비)

**권장 분할:**
- Phase 6a: Toolbar/Menu (active session routing)
- Phase 6b: Inspector + Object Manager 양방향 동기화
- Phase 6c: Mini Toolbar (Inspector 상단 quick action 형태)
- Phase 6d: GUI Mode (Preferences 메뉴)

---

### Phase 7 — Analysis Dialog / Theme / Result Model ⭐ 격리도 좋음

**평가:** ★★★ 신규 시스템이라 외부 파급 적음. 기존 `RoiController.computeAnalysis` 흐름을 흡수하면 됨.

**보완 권장:**
- 현재 `RoiAnalyzer` (이미 분리됨)와 새 `RoiStatisticsAnalyzer`의 관계 명확화. 후자는 dialog UI에서 호출하는 facade이고 실제 계산은 전자에 위임하는 thin layer로 두는 것이 깔끔
- `AnalysisRequest` ↔ `AnalysisResult` ↔ `ReviewResultModel` 변환 책임을 `AnalysisService`(미정의)에 집중

---

### Phase 8 — Auto Update / Recalculate ⚠️ Dirty DAG 복잡도

**평가:** ★★ Recalculate의 의존성 그래프 관리는 간단치 않음.

**구체적 위험:**
- Result A는 ROI 의존, Result B는 Result A 의존 → ROI 변경 시 A 먼저 재계산 후 B 재계산 (위상 정렬 필요)
- Auto mode에서 데이터 변경 폭주 시 디바운싱 안 하면 매 프레임 재계산
- Frozen 결과의 stale warning은 시각적 표시 + 사용자 acknowledge UX 필요

**권장 보완:**
- Phase 8a: 단일 결과 Manual/Auto/Frozen (의존 없는 ROI 통계만)
- Phase 8b: 의존 그래프 + 위상 정렬 (Result→Result 의존 도입 시)
- Phase 8c: Auto debounce + 백그라운드 재계산 큐

---

### Phase 9 — Project Save / Load ⚠️ 직렬화 결정 의존

**평가:** ★★ Phase 2의 직렬화 포맷이 결정되어야 본격 진입 가능.

**핵심 결정 사항:**
1. **External assets 처리**: 비행 로그 / 비디오 파일을 프로젝트에 복사 vs 절대경로 vs 상대경로
2. **`Pack Project` 의미**: zip 통합? 별도 폴더 통합? — 계획서 미정
3. **부분 로드**: 50개 세션 중 활성 세션만 로드 가능해야 — lazy load 인터페이스 필수
4. **호환성 정책**: 향후 스키마 변경 시 forward/backward compatibility — `SchemaVersion` 필드 + 마이그레이션 함수

---

### Phase 10 — SharedDecodeService / SharedCacheService ⚠️ 동시성 최난이도

**평가:** ★★ 가장 복잡. parpool/parfeval 동시성 + cancellation + priority queue 설계.

**현실 점검:**
- 현재 단일 Dashboard에서도 `PendingFrame`/`AsyncFutures`/`AsyncGen` 같은 race 방지 코드가 복잡한데, 다중 세션이 priority queue로 공유하면 더 어려움
- `parfeval` future는 cancel 후에도 worker에서 이미 실행 중이면 즉시 중단 안 됨 → cancel 후 결과 폐기 정책 명확히
- "여러 Dashboard가 열려도 parpool 하나만 사용" 완료 기준은 좋음, 다만 active session priority의 정확한 정의 부재

**권장 보완:**
- Phase 10 진입 전 **prototype**: 2개 세션을 동시에 빠른 scrubbing 시 worker priority/cancel 동작 검증 (Phase 0 또는 Phase 1과 병행)
- `LatestFrameOnlyPolicy` 이미 단일 Dashboard에 있음 — 이걸 service로 격상하는 것이 자연스러움

---

## 4. 누락 항목 / 추가 권장 Phase

### 4.1 명시되지 않은 필수 작업

| 누락 | 권장 위치 |
|---|---|
| **테스트 전략** (단위/통합/회귀) | Phase별 acceptance criteria만 있음 — Phase 0에 test harness 신설 권장 |
| **롤백 전략** | Phase X 실패 시 Phase X-1로 복귀하는 시나리오 부재 — git tag 또는 worktree 활용 |
| **성능 목표** (탭 N개 시 frame rate, 메모리) | 정량 지표 없음 — Phase 1에 baseline 측정 |
| **MATLAB 버전 요구사항** | uitree·uigridlayout 일부 기능은 R2021b+, 명시 필요 |
| **마이그레이션 도구** | 기존 standalone Dashboard 사용자의 config을 Project로 변환하는 importer 부재 — Phase 9 보완 |
| **사용자 시나리오 매핑** | 실제 비행 데이터 리뷰 use case (scrubbing, ROI 분석, 두 비행 비교)가 각 phase에서 어떻게 동작하는지 walkthrough 부재 |

### 4.2 추가 권장 Phase

- **Phase 0.5 (인터페이스 설계)**: Phase 1 진입 전, FlightDataDashboard와 Studio 간 인터페이스 시그니처 확정 (parentContainer 타입, SessionId 형식, EventBus 라우팅 규약)
- **Phase 3.5 (다중 인스턴스 stress test)**: Phase 3 종료 후, Phase 4 진입 전, 2~5개 Dashboard tab 동시 열고 drag/sync/decode 실행하여 race condition 발견
- **Phase 11 (사용자 검증 + 문서)**: 실제 사용자가 Studio에서 비행 리뷰 워크플로우 1회 완수 + 사용자 가이드 작성

---

## 5. 종합 점수 및 권장 조치

### 5.1 점수표

| 영역 | 점수 | 코멘트 |
|---|:---:|---|
| OriginPro 매핑 정확성 | A | 8개 핵심 요소 모두 반영, 합리적 절충 |
| 데이터 모델 설계 | B+ | 계층·필드 우수, dirty DAG·hash 비용 보완 필요 |
| Phase 0 (안정화) | A | 가장 시급한 항목 정확히 식별 |
| Phase 1·2 (Shell·Model) | A- | 안전한 출발 |
| **Phase 3 (Embedded)** | **C+** | **figure-level 의존성·callback 충돌 과소평가** |
| **Phase 4 (Event Scope)** | **C+** | **수정 범위 방대, 자동화 도구 필요** |
| Phase 5·6 (Explorer/Inspector) | B | MATLAB UI 한계 reality check 부족 |
| Phase 7 (Analysis Dialog) | B+ | 격리도 양호 |
| Phase 8 (Auto Update) | B- | dirty 의존성 그래프 미정의 |
| Phase 9 (Save/Load) | B- | 직렬화 포맷 미정 |
| **Phase 10 (Shared Services)** | **C+** | **prototype 선행 권장** |
| 누락 (test/rollback/perf) | C | 추가 보완 필요 |

**종합: B+ (방향 타당, 실행 위험 큼)**

### 5.2 핵심 권장 조치 5가지

1. **Phase 0 안정화 작업을 6개에서 9개로 확장**: 현재 sed/grep 기반으로 리팩토링한 4개 신규 모듈(MarkerDragController/RailSummaryView/RoiAnalyzer/InfoController)의 회귀 테스트 추가, throttle SessionId 접두 정책 사전 도입, parfeval cancellation prototype 검증
2. **Phase 0.5 신설 — 인터페이스 설계 phase**: parentContainer/SessionId/AppEventData 시그니처 + 직렬화 포맷(`.frsproj` zip+manifest 구조) + dirty DAG 설계를 문서로 확정한 후 Phase 1 진입
3. **Phase 3 분할 (3a/3b/3c)**: Embedded화는 인터페이스 추상화 → 단일 탭 embed → 다중 탭 stress 순서로 검증. 각 단계마다 회귀 테스트 통과 후 다음 진행
4. **Phase 4 자동화**: EventBus.publish에 active SessionId 자동 주입 + BaseSessionListener mixin 도입으로 100+ 곳 수동 수정 회피
5. **Phase 10 prototype을 Phase 1로 앞당김**: SharedDecodeService의 priority queue + cancellation은 단일 세션에서도 검증 가능 — 늦게 발견할수록 비용 폭증

### 5.3 최종 결론

> **계획서는 "OriginPro 모방 GUI"가 아니라 "비행 데이터 리뷰를 위한 프로젝트 기반 통합 플랫폼"이라는 본질을 정확히 짚었고, MDI/Recalculate/Theme/Logs 같은 OriginPro의 진짜 가치를 MATLAB에 합리적으로 옮기려는 시도다. 다만 실행 단계의 11 Phase 중 Phase 3·4·10이 작업량과 동시성 위험에서 과소평가되어 있으므로, Phase 0.5·3.5 신설과 Phase 3·4·6의 분할을 통해 점진적 위험 관리가 필수적이다. 직렬화 포맷·dirty DAG·MATLAB UI 한계 reality check를 Phase 1 진입 전에 결정하는 것이 성공 여부를 좌우한다.**

https://github.com/kiki-github2019/flight-dashboard.git'

###############################################################################################################
2026 05 09 09 02
chatgpt review
## 종합 결론

현재 `main` 브랜치 기준으로 보면, **Phase 1과 Phase 2는 계획 의도에 맞게 상당 부분 구현되어 있고, Phase 3은 “착수/프로토타입 구현” 수준까지 들어갔지만 아직 안정 완료로 보기 어렵습니다.** 특히 Embedded Dashboard, 다중 세션 EventBus, figure-level callback, cleanup 범위 분리 문제는 일부 보완되어 있으나, 실제 MATLAB에서 다중 탭을 장시간 운용할 때 충돌·누수·잘못된 세션 반응 가능성이 남아 있습니다.

제가 직접 MATLAB에서 실행 검증은 하지 못했고, GitHub 소스 정적 분석 기준입니다.

---

## Phase별 구현 평가

### Phase 1 — Studio Shell 신설

**평가: 대체로 구현됨.**

`FlightReviewStudio.m` entry가 root에 있고, 실제 앱 구현은 `flightdash.studio.FlightReviewStudioApp()`으로 위임되어 있습니다. 즉, 계획서의 “entry와 구현 분리”는 반영되어 있습니다. `FlightReviewStudio.m`은 MATLAB 버전 체크 후 `FlightReviewStudioApp`을 생성하고, 출력 인자가 있으면 app handle을 반환합니다. ([GitHub][1])

`FlightReviewStudioApp`은 `UIFigure`, Header, BodyGrid, ProjectExplorer, Workspace, RightDock, StatusBar를 구성하고 있어 OriginPro식 shell 골격은 구현되어 있습니다. Body는 explorer | workspace | dock 3열 구조이고, status bar도 별도 manager로 분리되어 있습니다. ([GitHub][2])

**좋은 점**

* root entry와 package 구현 분리 방향이 적절합니다.
* menu/toolbar/explorer/workspace/right dock/status bar가 manager class로 나뉘어 있어 Phase 1의 “신규 shell” 의도에 부합합니다.
* status bar는 Phase 1 placeholder임을 명시하고, Phase 6에서 실제 데이터 연결 예정이라고 되어 있어 계획서의 보완 권장과 일치합니다. ([GitHub][3])

**아쉬운 점**

* `README` 빠른 시작은 아직 `FlightDataDashboard` 중심으로 되어 있고, `FlightReviewStudio` 실행 흐름은 주 진입점으로 충분히 강조되어 있지 않습니다. README는 기존 대시보드 구조와 EventBus/MVC 설명에 집중되어 있습니다. ([GitHub][4])

---

### Phase 2 — Project / Session Model 추가

**평가: 잘 구현됨. 단, 아직 저장/로드는 미구현 상태로 보는 것이 맞습니다.**

`+flightdash/+project` 아래에 `ProjectModel`, `SessionModel`, `FigureModel`, `ReviewResultModel`, `AnalysisThemeModel`이 추가되어 있습니다. GitHub 트리에서도 해당 파일들이 확인됩니다. ([GitHub][5])

`ProjectModel`은 `SchemaVersion`, `ProjectId`, `ProjectName`, `Sessions`, `Figures`, `Results`, `AnalysisThemes`, `DirtyFlag`를 갖는 value class 형태이고, `addSession`, `removeSession`, `updateSession`, `sessionCount` 등 기본 CRUD가 구현되어 있습니다. ([GitHub][6])

`SessionModel`도 `SchemaVersion`, `SessionId`, `DisplayName`, 채널별 flight/video path, sync snapshot, plot/ROI snapshot, dirty flag 등을 갖고 있어 Phase 2 목적에는 부합합니다. ([GitHub][7])

직렬화 포맷도 문서로는 명확히 결정되어 있습니다. `.frsproj`는 ZIP + `manifest.json` + assets 구조, 메타는 JSON, raw data는 MAT v7.3, SchemaVersion과 migration chain을 쓰는 설계입니다. ([GitHub][8])

**좋은 점**

* `handle class 직접 save` 문제를 회피하기 위해 project model을 value class로 둔 점은 적절합니다.
* `SchemaVersion` 필드가 model과 문서 양쪽에 있습니다.
* `FigureModel`, `ReviewResultModel`까지 선제적으로 들어가 있어 향후 OriginPro식 project explorer 확장성이 있습니다. ([GitHub][9])

**주의점**

* 문서에는 Phase 9에서 `ProjectSerializer.m`을 신설한다고 되어 있으므로, 현재 상태는 **인메모리 프로젝트 모델만 구현된 상태**입니다. 저장/로드 완료로 판단하면 안 됩니다. ([GitHub][8])
* `SessionModel.setFlightFile(channelIdx, path)` 등은 `channelIdx` 범위 검사가 없습니다. `channelIdx=0`, `3`, `NaN` 입력 시 cell indexing 오류가 날 수 있습니다. Phase 2 순수 모델이라도 `mustBeInteger`, `mustBeInRange(channelIdx,1,2)` 또는 private validator가 필요합니다. ([GitHub][7])

---

### Phase 3 — FlightDataDashboard Embedded화

**평가: 부분 구현됨. 아직 “완료”로 보기 어렵습니다.**

`FlightDataDashboard` 생성자는 `FlightDataDashboard(parentContainer, sessionId)` 형태를 받아 embedded mode를 구분합니다. embedded mode에서는 `IsEmbedded=true`, `ActiveSessionId=sessionId`, `RootContainer=parentContainer`를 설정하고, standalone에서는 `RootContainer=UIFigure`로 둡니다. ([GitHub][10])

`WorkspaceManager.addDashboardTab()`은 `uitab`을 만들고 `flightdash.FlightDataDashboard(tab, sessionId)`를 호출해 dashboard를 tab 안에 생성하려고 합니다. 즉, “tab 안에 다른 uifigure embed”가 아니라, parent tab에 직접 UI를 그리는 방향으로 구현되어 계획서의 MATLAB 한계 회피 방향과 맞습니다. ([GitHub][11])

다중 세션 충돌 방지도 일부 반영되어 있습니다. `SessionScope`가 전역 active session id를 `setappdata`에 저장하고, 각 dashboard는 `isActiveSession()`에서 자기 `ActiveSessionId`와 비교합니다. ([GitHub][12])

또한 `throttleHit()`은 `ActiveSessionId`를 slot name 앞에 붙여 singleton `Throttle`의 key 충돌을 줄이도록 되어 있습니다. ([GitHub][10])

**하지만 Phase 3의 핵심 위험은 아직 남아 있습니다.**

---

## 주요 버그 / 리스크

### 1. Embedded mode에서 resize 처리가 불완전합니다

`FlightDataDashboard`는 embedded mode일 때 `UIFigure.SizeChangedFcn`을 등록하지 않습니다. 주석상으로는 “Phase 3b에서 parent container resize listener를 등록 예정”이라고 되어 있지만, 현재 보이는 구현에서는 tab/panel resize listener가 확인되지 않습니다. ([GitHub][10])

**문제**

* Studio 창 크기 변경
* 좌우 dock 폭 변경
* MATLAB Online 브라우저 resize
* 탭 전환 후 layout 재계산

이 상황에서 embedded dashboard가 즉시 responsive layout을 재적용하지 못할 수 있습니다.

**개선**

* `WorkspaceManager.addDashboardTab()`에서 tab 내부 root panel을 만들고, 그 panel 또는 parent grid의 size-change event를 dashboard에 전달하는 구조가 필요합니다.
* 최소한 `WorkspaceManager.onTabChanged()`에서 선택된 dashboard의 `LayoutMgr.applyLayout(app,'tabChanged')`를 호출해야 합니다.

---

### 2. WindowButtonMotionFcn은 여전히 figure 단일 슬롯입니다

`MarkerDragController`와 `PannerController`는 drag 시작 시 `app.UIFigure.WindowButtonMotionFcn`과 `WindowButtonUpFcn`을 직접 덮어씁니다. ([GitHub][13])

**문제**

* Studio 안에서 모든 dashboard가 같은 host `UIFigure`를 공유합니다.
* 한 세션에서 drag 중 다른 tab으로 전환하거나, 다른 controller가 callback을 설정하면 이전 drag callback이 덮어써질 수 있습니다.
* `startPlotMarkerDrag`, `startVideoFrameDrag`, `PannerController.startHandleDrag` 내부에는 `isActiveSession()` gate가 시작 지점에 명시적으로 없습니다. EventBus entry에는 gate가 있지만, 그래픽 객체 callback에서 직접 호출되는 경로는 별도 보호가 필요합니다.

**개선**

* 모든 figure-level motion callback 내부 첫 줄에 다음 성격의 guard가 필요합니다.

```matlab
if ~app.isActiveSession() || ~isvalid(app.RootContainer) || strcmp(app.RootContainer.Visible,'off')
    return;
end
```

* 더 좋은 구조는 `StudioFigureMotionRouter` 하나만 `WindowButtonMotionFcn`을 소유하고, active dashboard의 drag controller로 dispatch하는 방식입니다. 각 dashboard가 직접 `UIFigure.WindowButtonMotionFcn`을 덮어쓰는 방식은 다중 탭에서 취약합니다.

---

### 3. EventBus singleton + active session gate는 충분조건이 아닙니다

`FileController`, `DragController`, `PlaybackController`, `PannerController` 등은 대부분 EventBus listener 진입점에서 `obj.App.isActiveSession()`을 확인합니다. ([GitHub][14])

이 방향은 좋지만, 현재 구조는 “이벤트가 active tab에만 적용된다”는 전제입니다. 문제는 다음과 같습니다.

* 비활성 tab의 UI 컨트롤이 어떤 이유로 이벤트를 publish하면 active tab이 반응할 수 있습니다.
* `AppEventData` 안에 `SessionId`가 없는 구조라면, 이벤트 자체가 어느 세션에서 발생했는지 검증할 수 없습니다.
* active session global state가 깨지거나 `standalone` fallback이 동작하면 모든 dashboard가 반응할 가능성이 있습니다. `SessionScope.isOwner()`는 active id가 없으면 true를 반환하는 fallback을 갖고 있습니다. ([GitHub][12])

**개선**

* `AppEventData`에 `SessionId` 필드를 추가해야 합니다.
* EventBus publish 시 view가 자기 dashboard/session id를 넣고, controller는 `d.SessionId == app.ActiveSessionId`를 우선 검사해야 합니다.
* `SessionScope` active id는 fallback 용도로만 쓰고, 실제 routing의 주키는 event payload의 session id로 둬야 합니다.

---

### 4. tab close와 studio close cleanup 분리가 아직 완전하지 않습니다

`WorkspaceManager.removeDashboardTab()`은 dashboard를 delete하고 tab도 delete합니다. `FlightDataDashboard.delete()`는 futures cancel, VideoReader delete, cache invalidate, controller delete, aux window close, `parfevalOnAll cleanup`, pool delete까지 수행합니다. ([GitHub][11])

**문제**

* 계획서에서는 “tab close = session unload, studio close = 전역 cleanup”으로 나눌 것을 권장했습니다.
* 현재 dashboard delete가 embedded session close에서도 parallel pool delete까지 수행할 수 있습니다.
* 여러 embedded dashboard가 같은 pool 정책을 공유하거나, 한 tab close가 전체 worker cleanup을 수행하면 다른 세션의 비동기 decode에 영향을 줄 수 있습니다.

**개선**

* `FlightDataDashboard.delete(scope)` 또는 별도 `unloadSession()` / `shutdownGlobalResources()`로 분리해야 합니다.
* embedded tab close에서는 해당 dashboard의 futures cancel, cache evict, VideoReader release까지만 수행하고, pool 전체 delete와 `parfevalOnAll cleanup`은 Studio close에서 한 번만 수행하는 것이 안전합니다.
* `AsyncPool`을 dashboard별로 만들지 말고 `AsyncDecodeService` 같은 Studio-level service로 올리는 편이 낫습니다.

---

### 5. 한글 주석 깨짐이 여전히 존재합니다

`FlightDataDashboard.m`의 GitHub 렌더링에서 `?앹꽦??`, `?몄뒪?댁뒪`, `梨꾨꼸` 같은 깨진 한글 주석이 다수 보입니다. ([GitHub][10])

**문제**

* 실행 자체에는 영향이 없을 수 있지만, 장기 유지보수에는 매우 나쁩니다.
* 주석 깨짐이 문자열 리터럴까지 침범한 경우 UI 문구, 에러 메시지, 파일 파싱 로직에도 영향이 생길 수 있습니다.

**개선**

* 저장소 전체를 UTF-8 with LF로 재정규화해야 합니다.
* `.gitattributes`에 다음을 추가하는 것을 권장합니다.

```text
*.m text eol=lf working-tree-encoding=UTF-8
*.md text eol=lf working-tree-encoding=UTF-8
```

* MATLAB에서 `feature('DefaultCharacterSet','UTF-8')` 같은 런타임 처방보다, 파일 인코딩 자체를 정상화하는 것이 우선입니다.

---

### 6. Project/Session model의 입력 검증이 약합니다

`SessionModel`의 `setFlightFile`, `setVideoFile`, `setRoiRows`, `hasFlightData`, `hasVideo`는 `channelIdx`를 직접 cell index로 사용합니다. ([GitHub][7])

**개선**

* 공통 validator 추가:

```matlab
function validateChannelIdx(~, channelIdx)
    validateattributes(channelIdx, {'numeric'}, ...
        {'scalar','integer','>=',1,'<=',2});
end
```

* `path`는 char/string 모두 받고 `char(path)` 전에 empty/string scalar 검사를 넣는 것이 좋습니다.
* `setDisplayName`도 empty name 방지 필요.

---

### 7. `ProjectModel.newId()` 충돌 가능성

`ProjectModel.newId(prefix)`는 `datestr(now,'yyyymmddHHMMSSFFF') + randi(9999)` 방식입니다. ([GitHub][6])

**문제**

* 빠르게 여러 세션/결과를 생성하면 이론상 충돌 가능성이 있습니다.
* MATLAB random seed 상태에 따라 테스트 재현성이 낮습니다.

**개선**

* `matlab.lang.internal.uuid`는 비공식이므로 피하고, Java 사용 가능 환경이면 `char(java.util.UUID.randomUUID)`를 쓰거나, timestamp + persistent counter 조합으로 바꾸는 것이 낫습니다.
* 예: `SESS_20260509T153012_000001`.

---

## 계획서 대비 구현 충족도

| 항목                                                            |  구현 상태 | 평가                          |
| ------------------------------------------------------------- | -----: | --------------------------- |
| `FlightReviewStudio.m` entry와 `FlightReviewStudioApp.m` 구현 분리 |    구현됨 | 양호                          |
| Status bar placeholder 후 Phase 6 실데이터 연결                      |    구현됨 | 양호                          |
| Project/Session/Figure/Result/Theme model                     |    구현됨 | 양호                          |
| `.frsproj` 포맷 결정                                              |   문서화됨 | 양호, 구현은 Phase 9             |
| SchemaVersion                                                 |    구현됨 | 양호                          |
| handle save 회피용 value class                                   |    구현됨 | 양호                          |
| Dashboard parentContainer embedded 생성자                        |    구현됨 | 부분 양호                       |
| RootContainer 추상화                                             | 일부 구현됨 | 추가 검증 필요                    |
| EventBus active session gate                                  |    구현됨 | payload SessionId 없어서 보완 필요 |
| Throttle SessionId prefix                                     |    구현됨 | 양호                          |
| figure-level drag callback session isolation                  |  일부 구현 | 아직 위험                       |
| tab close vs studio close cleanup 분리                          |  일부 구현 | pool/global cleanup 분리 필요   |
| 다중 탭 검증 기반 코드 안정화                                             |    불충분 | Phase 3c 테스트 필요             |

---

## 우선순위별 수정 권장안

### 최우선 — 실행 안정성

1. `AppEventData`에 `SessionId` 추가
2. 모든 view publish 지점에서 session id 포함
3. 모든 controller listener에서 `d.SessionId`와 `app.ActiveSessionId` 비교
4. figure-level drag callback 내부에도 `app.isActiveSession()` guard 추가
5. embedded tab close 시 parallel pool 전체 삭제 금지

### 2순위 — Embedded layout 안정화

1. embedded tab마다 root panel 생성
2. root panel resize 감지 또는 tab activation 시 layout 재계산
3. Studio 좌우 dock 폭 변경 시 active dashboard layout refresh
4. MATLAB Online, 15인치 노트북, FHD 모니터에서 workspace width threshold 테스트

### 3순위 — 모델/프로젝트 품질

1. `SessionModel` channel index validator 추가
2. `ProjectModel.newId()`를 UUID 또는 counter 기반으로 변경
3. `.frsproj` serializer 전까지 “저장 미지원” UI 안내 명확화
4. `ProjectExplorer`에서 session delete 시 workspace tab과 model 동기화 테스트

### 4순위 — 유지보수성

1. 깨진 한글 주석 복원
2. UTF-8/LF 강제
3. `FlightDataDashboard.m` 4,600줄 규모를 service/controller/view 단위로 계속 분리
4. `WindowButtonMotionFcn` 단일 router 도입

---

## 최종 판단

현재 코드는 **계획서 방향을 잘 따라가고 있으며, 특히 Phase 1/2의 구조 신설은 성공적**입니다. 다만 **Phase 3은 아직 “위험 구간을 통과했다”고 보기 어렵습니다.** Embedded tab 생성, SessionScope, throttle prefix 같은 핵심 장치는 들어갔지만, MATLAB figure-level callback의 단일성, EventBus singleton broadcast, parallel pool cleanup 범위 때문에 다중 세션에서 예외적 충돌이 발생할 가능성이 있습니다.

따라서 다음 작업은 기능 추가보다 **Phase 3c 검증/보강**이 우선입니다. 특히 “세션 2개 생성 → 각 탭에서 파일 로드 → 한 탭에서 marker drag 중 탭 전환 → tab close → 다른 탭 playback 유지 → Studio close” 시나리오를 자동/수동 테스트 케이스로 고정해야 합니다.

[1]: https://github.com/kiki-github2019/flight-dashboard/blob/main/FlightReviewStudio.m "flight-dashboard/FlightReviewStudio.m at main · kiki-github2019/flight-dashboard · GitHub"
[2]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bstudio/FlightReviewStudioApp.m "raw.githubusercontent.com"
[3]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bstudio/StatusBarManager.m "raw.githubusercontent.com"
[4]: https://github.com/kiki-github2019/flight-dashboard "GitHub - kiki-github2019/flight-dashboard: MATLAB Flight Data Dashboard with EventBus + MVC · GitHub"
[5]: https://github.com/kiki-github2019/flight-dashboard/tree/main/%2Bflightdash/%2Bproject "flight-dashboard/+flightdash/+project at main · kiki-github2019/flight-dashboard · GitHub"
[6]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bproject/ProjectModel.m "raw.githubusercontent.com"
[7]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bproject/SessionModel.m "raw.githubusercontent.com"
[8]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/docs/design-serialization.md "raw.githubusercontent.com"
[9]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bproject/FigureModel.m "raw.githubusercontent.com"
[10]: https://github.com/kiki-github2019/flight-dashboard/blob/main/%2Bflightdash/FlightDataDashboard.m "flight-dashboard/+flightdash/FlightDataDashboard.m at main · kiki-github2019/flight-dashboard · GitHub"
[11]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bstudio/WorkspaceManager.m "raw.githubusercontent.com"
[12]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Butil/SessionScope.m "raw.githubusercontent.com"
[13]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bcontroller/MarkerDragController.m "raw.githubusercontent.com"
[14]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bcontroller/FileController.m "raw.githubusercontent.com"





====================================================================================================================
gemini 3.5 제안

Phase 3.5 도입: StudioMouseRouter의 타당성 
기존 구조에서는 마커(MarkerDragController), 화면 이동(PannerController) 등 각 컨트롤러가 app.UIFigure.WindowButtonMotionFcn을 직접 덮어쓰며 경쟁했습니다. 이는 탭이 하나일 때는 문제가 없지만, Embedded 환경(단일 Figure에 여러 탭)에서는 탭 전환 시 이전 탭의 콜백이 남아 다른 탭의 좌표계를 오염시키는 치명적 버그를 유발합니다.

제안하신 StudioMouseRouter를 통한 중앙 통제 방식은 이를 해결하는 완벽한 아키텍처입니다. 이러한 중앙 집중형 이벤트 라우팅은 소프트웨어 설계의 중재자(Mediator) 패턴과 유사합니다.

추가 조언: StudioMouseRouter 구현 시, MATLAB의 hittest(fig) 함수를 활용하면 현재 마우스가 위치한 UI 컴포넌트가 어느 세션(탭)에 속해 있는지 동적으로 판별할 수 있어 라우팅 로직을 더욱 견고하게 짤 수 있습니다.

Phase 3.5의 핵심은 "전역 자원(UIFigure 콜백, Parpool)의 소유권을 개별 대시보드 탭에서 빼앗아 Studio 레벨로 격상시키는 것"입니다.

이를 구현하기 위한 **① `StudioMouseRouter` 뼈대 코드**와 **② Lifecycle(Cleanup) 분리 로직**을 매트랩 R2024a/R2025a 등 최신 환경의 클래스 기반 객체지향 설계에 맞춰 제안해 드립니다.

---

### 1. `flightdash.studio.StudioMouseRouter` (신규 클래스)

이 클래스는 Studio가 구동될 때 단 한 번 생성되며, `UIFigure`의 마우스 이벤트를 독점합니다. 각 대시보드(탭)의 컨트롤러들은 더 이상 Figure에 직접 콜백을 걸지 않고, 이 라우터에게 "나 지금 드래그 시작했어"라고 상태만 알립니다.

```matlab
classdef StudioMouseRouter < handle
    % flightdash.studio.StudioMouseRouter
    % 중앙 집중형 마우스 이벤트 라우터. 단일 UIFigure의 콜백을 독점하고,
    % 현재 활성화된 세션(Active Session)의 컨트롤러에게만 이벤트를 전달합니다.

    properties (Access = private)
        UIFigure          % Studio의 메인 Figure
        WorkspaceMgr      % 현재 활성화된 탭을 알아내기 위한 참조
        
        % 현재 드래그를 소유하고 있는 컨트롤러 참조 (다형성 활용)
        ActiveController = [] 
        ActiveSessionId  char = ''
    end

    methods
        function obj = StudioMouseRouter(uifig, workspaceMgr)
            obj.UIFigure = uifig;
            obj.WorkspaceMgr = workspaceMgr;
            
            % 라우터가 Figure의 콜백을 영구적으로 독점합니다.
            obj.UIFigure.WindowButtonMotionFcn = @(~,~) obj.onMouseMotion();
            obj.UIFigure.WindowButtonUpFcn     = @(~,~) obj.onMouseUp();
        end

        function requestDragLock(obj, sessionId, controller)
            % MarkerDragController나 PannerController가 드래그를 시작할 때 호출
            % 현재 활성화된 탭의 요청만 수락합니다.
            if ~strcmp(sessionId, obj.WorkspaceMgr.ActiveSessionId)
                return; % 백그라운드 탭의 비정상적인 드래그 요청 차단
            end
            
            obj.ActiveSessionId = sessionId;
            obj.ActiveController = controller;
            
            % 커서 변경 (옵션)
            if isprop(obj.UIFigure, 'Pointer')
                obj.UIFigure.Pointer = 'left-right';
            end
        end

        function releaseDragLock(obj)
            % 드래그 종료 시 호출
            obj.ActiveController = [];
            obj.ActiveSessionId = '';
            
            if isprop(obj.UIFigure, 'Pointer')
                obj.UIFigure.Pointer = 'arrow';
            end
        end
    end

    methods (Access = private)
        function onMouseMotion(obj)
            % 활성화된 컨트롤러가 없거나, 세션이 전환되었다면 무시
            if isempty(obj.ActiveController) || ~isvalid(obj.ActiveController)
                return;
            end
            if ~strcmp(obj.ActiveSessionId, obj.WorkspaceMgr.ActiveSessionId)
                return; % 드래그 중 탭이 바뀌면 모션 중단 (누수 방지)
            end
            
            % 실제 컨트롤러의 motion 메서드 호출
            % (각 컨트롤러는 handleDragMotion() 이라는 공통 인터페이스를 가져야 함)
            try
                obj.ActiveController.handleDragMotion();
            catch ME
                flightdash.util.ErrorLog.log(ME, 'MouseRouter:Motion');
            end
        end

        function onMouseUp(obj)
            if isempty(obj.ActiveController) || ~isvalid(obj.ActiveController)
                return;
            end
            
            try
                % 컨트롤러의 드래그 중지 로직 실행
                obj.ActiveController.stopDrag();
            catch ME
                flightdash.util.ErrorLog.log(ME, 'MouseRouter:Up');
            end
            
            % Lock 해제
            obj.releaseDragLock();
        end
    end
end

```

#### 💡 적용 방법 (Controller 수정)

기존 `MarkerDragController.m`의 `startPlotMarkerDrag` 함수 내부를 다음과 같이 바꿉니다.

**[AS-IS] 기존 코드**

```matlab
% 마우스 이벤트 덮어쓰기 (위험)
app.UIFigure.WindowButtonMotionFcn = @(~,~) obj.plotMarkerDragMotion(fIdx);
app.UIFigure.WindowButtonUpFcn = @(~,~) obj.stopDrag();

```

**[TO-BE] 수정된 코드**

```matlab
% Standalone 모드이면 기존처럼 직접 연결, Embedded 모드이면 Router에 위임
if ~app.IsEmbedded
    app.UIFigure.WindowButtonMotionFcn = @(~,~) obj.handleDragMotion(); % 이름 통일
    app.UIFigure.WindowButtonUpFcn = @(~,~) obj.stopDrag();
else
    % Studio가 주입해둔 전역 Router에 Lock 요청
    router = getappdata(app.UIFigure, 'StudioMouseRouter');
    if ~isempty(router)
        router.requestDragLock(app.ActiveSessionId, obj);
    end
end

```

---

### 2. Dispose / Cleanup 격리 분리 로직

메모리 누수와 워커 멈춤(Hang)을 방지하려면 `tab close`(개별 닫기)와 `studio close`(전체 닫기)를 명확히 분리해야 합니다.

#### A. 탭이 닫힐 때 (개별 Dashboard Cleanup)

`FlightDataDashboard.m`의 `delete` 함수는 **자신의 세션에 속한 데이터만** 지워야 합니다. 전역 `AsyncPool`을 지워버리면 안 됩니다.

```matlab
% FlightDataDashboard.m 내부 delete(app) 수정
function delete(app)
    if app.IsDeleting, return; end
    app.IsDeleting = true;
    
    % 1. 현재 세션의 Playback 중지
    try, app.PlaybackCtrl.stopAllFlightPlayback(); catch, end

    % 2. 현재 세션에 할당된 비동기 디코딩 Future만 취소 (Pool은 유지!)
    for fIdx = 1:2
        try
            if ~isempty(app.AsyncFutures{fIdx}) && isvalid(app.AsyncFutures{fIdx})
                cancel(app.AsyncFutures{fIdx});
                % wait는 최대 0.5초만 (UI 프리징 방지)
            end
        catch, end
        
        % 현재 세션의 VideoReader 해제
        try, app.VideoMdl(fIdx).cleanup(); catch, end
    end
    
    % 3. 현재 세션의 캐시 메모리만 해제
    try, app.CacheModel(1).invalidate(); catch, end
    try, app.CacheModel(2).invalidate(); catch, end

    % 4. 컨트롤러 및 UI 컴포넌트 해제 (기존 코드 유지)
    ...

    % 5. ★ [핵심] Embedded 모드에서는 UIFigure와 AsyncPool을 절대 삭제하지 않음
    if ~app.IsEmbedded
        % Standalone 모드일 때만 Parpool과 Figure 삭제
        try, if ~isempty(app.AsyncPool), delete(app.AsyncPool); end, catch, end
        try, if ~isempty(app.UIFigure), delete(app.UIFigure); end, catch, end
    end
end

```

#### B. Studio 전체가 닫힐 때 (Global Cleanup)

`FlightReviewStudioApp.m`의 `delete` 함수에서 전역 리소스를 일괄 정리합니다.

```matlab
% FlightReviewStudioApp.m 내부 delete(app)
function delete(app)
    if app.IsDeleting, return; end
    app.IsDeleting = true;

    % 1. 모든 열려있는 세션(탭)을 명시적으로 먼저 닫음 -> 각 Dashboard의 delete() 트리거
    try
        app.removeAllSessions(); 
    catch ME
        app.logCaught(ME, 'Studio:removeAllSessions'); 
    end

    % 2. UI 매니저들 해제
    try, delete(app.MenuMgr); catch, end
    try, delete(app.ProjectExplorer); catch, end
    ...

    % 3. ★ [핵심] 모든 탭이 안전하게 종료된 후, Parfeval 환경 전역 초기화
    try
        globalPool = gcp('nocreate');
        if ~isempty(globalPool)
            % 워커에 남아있는 캐시/찌꺼기 일괄 청소 명령 하달
            fCleanup = parfevalOnAll(globalPool, @cleanupAsyncDecodeCache, 0);
            try, wait(fCleanup, 'finished', 3); catch, cancel(fCleanup); end
            
            % (선택적) 완전히 Pool을 내리고 싶다면: delete(globalPool);
            % 단, MATLAB 환경을 계속 써야한다면 유지하는 것이 로딩 속도에 유리합니다.
        end
    catch ME
        app.logCaught(ME, 'Studio:GlobalPoolCleanup');
    end

    % 4. 메인 UI Figure 삭제
    try
        if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
            delete(app.UIFigure);
        end
    catch, end
end

```

---

### 🚀 코드 적용 가이드

1. `+flightdash/+studio/` 폴더에 `StudioMouseRouter.m` 파일을 생성하고 위 코드를 넣습니다.
2. `FlightReviewStudioApp.m`의 `buildShell` 함수 끝부분에 라우터를 생성하고 연결합니다.
```matlab
% buildShell(app) 내부 마지막 줄
app.MouseRouter = flightdash.studio.StudioMouseRouter(app.UIFigure, app.Workspace);
setappdata(app.UIFigure, 'StudioMouseRouter', app.MouseRouter);

```


3. `MarkerDragController.m`와 `PannerController.m`가 위에서 제안한 것처럼 `app.IsEmbedded` 분기를 타도록 수정합니다.

이 Phase 3.5 기반 공사가 끝나면, 여러 개의 비디오/비행 데이터를 각기 다른 탭에 띄워놓고 마우스를 마구 드래그해도 **이벤트가 엉키거나 다른 탭의 차트가 움직이는 끔찍한 현상(Event Leak)이 완벽하게 사라집니다.** 위 코드를 바탕으로 로컬에서 바로 테스트 적용을 진행해 보시는 것을 적극 권장합니다!
=========================================================================================================================
26.5.9 17:32
=========================================================================================================================

root/
├── .claude/
│   └── worktrees/
│       └── bold-brown-8651c4/
│           ├── +flightdash/
│           │   ├── +controller/
│           │   │   ├── DragController.m
│           │   │   ├── FileController.m
│           │   │   ├── InfoController.m
│           │   │   ├── MarkerDragController.m
│           │   │   ├── PanelToggleController.m
│           │   │   ├── PannerController.m
│           │   │   ├── PlaybackController.m
│           │   │   ├── PlotController.m
│           │   │   ├── RoiController.m
│           │   │   └── VideoSyncController.m
│           │   ├── +model/
│           │   │   ├── ConfigManager.m
│           │   │   ├── FlightDataLoader.m
│           │   │   ├── FlightModeAnalyzer.m
│           │   │   ├── FrameCacheModel.m
│           │   │   ├── PlaybackStateModel.m
│           │   │   ├── RoiAnalyzer.m
│           │   │   ├── SyncModel.m
│           │   │   └── VideoModel.m
│           │   ├── +project/
│           │   │   ├── AnalysisThemeModel.m
│           │   │   ├── FigureModel.m
│           │   │   ├── ProjectModel.m
│           │   │   ├── ProjectSerializer.m
│           │   │   ├── ReviewResultModel.m
│           │   │   └── SessionModel.m
│           │   ├── +studio/
│           │   │   ├── +diag/
│           │   │   │   ├── runMultiInstanceTests.m
│           │   │   │   └── verifyPhase4.m
│           │   │   ├── FlightReviewStudioApp.m
│           │   │   ├── MenuManager.m
│           │   │   ├── ProjectExplorerPanel.m
│           │   │   ├── RightDockManager.m
│           │   │   ├── StatusBarManager.m
│           │   │   ├── StudioMouseRouter.m
│           │   │   ├── ToolbarManager.m
│           │   │   └── WorkspaceManager.m
│           │   ├── +util/
│           │   │   ├── AppConstants.m
│           │   │   ├── AppEventData.m
│           │   │   ├── ErrorLog.m
│           │   │   ├── EventBus.m
│           │   │   ├── SessionScope.m
│           │   │   ├── Throttle.m
│           │   │   ├── TimeFormat.m
│           │   │   └── UIScale.m
│           │   ├── +view/
│           │   │   ├── AttitudePanel.m
│           │   │   ├── AuxWindowManager.m
│           │   │   ├── ChannelLayout.m
│           │   │   ├── HeaderBar.m
│           │   │   ├── HISplitter.m
│           │   │   ├── InfoPanel.m
│           │   │   ├── MapAltPanel.m
│           │   │   ├── PannerView.m
│           │   │   ├── PlotPanel.m
│           │   │   ├── PlotView.m
│           │   │   ├── RailSummaryView.m
│           │   │   ├── ResponsiveLayoutManager.m
│           │   │   └── VideoPanel.m
│           │   └── FlightDataDashboard.m
│           ├── asyncDecodeFrame.m
│           ├── asyncDecodeFramePersistent.m
│           ├── cleanupAsyncDecodeCache.m
│           ├── FlightReviewStudio.m
│           └── merged_output_2605051834_refactoring.m
├── +flightdash/
│   ├── +controller/
│   │   ├── DragController.m
│   │   ├── FileController.m
│   │   ├── InfoController.m
│   │   ├── MarkerDragController.m
│   │   ├── PanelToggleController.m
│   │   ├── PannerController.m
│   │   ├── PlaybackController.m
│   │   ├── PlotController.m
│   │   ├── RoiController.m
│   │   └── VideoSyncController.m
│   ├── +model/
│   │   ├── ConfigManager.m
│   │   ├── FlightDataLoader.m
│   │   ├── FlightModeAnalyzer.m
│   │   ├── FrameCacheModel.m
│   │   ├── PlaybackStateModel.m
│   │   ├── RoiAnalyzer.m
│   │   ├── SyncModel.m
│   │   └── VideoModel.m
│   ├── +project/
│   │   ├── AnalysisThemeModel.m
│   │   ├── FigureModel.m
│   │   ├── ProjectModel.m
│   │   ├── ProjectSerializer.m
│   │   ├── ReviewResultModel.m
│   │   └── SessionModel.m
│   ├── +studio/
│   │   ├── +diag/
│   │   │   ├── runMultiInstanceTests.m
│   │   │   └── verifyPhase4.m
│   │   ├── FlightReviewStudioApp.m
│   │   ├── MenuManager.m
│   │   ├── ProjectExplorerPanel.m
│   │   ├── RightDockManager.m
│   │   ├── StatusBarManager.m
│   │   ├── StudioMouseRouter.m
│   │   ├── ToolbarManager.m
│   │   └── WorkspaceManager.m
│   ├── +util/
│   │   ├── AppConstants.m
│   │   ├── AppEventData.m
│   │   ├── ErrorLog.m
│   │   ├── EventBus.m
│   │   ├── SessionScope.m
│   │   ├── Throttle.m
│   │   ├── TimeFormat.m
│   │   └── UIScale.m
│   ├── +view/
│   │   ├── AttitudePanel.m
│   │   ├── AuxWindowManager.m
│   │   ├── ChannelLayout.m
│   │   ├── HeaderBar.m
│   │   ├── HISplitter.m
│   │   ├── InfoPanel.m
│   │   ├── MapAltPanel.m
│   │   ├── PannerView.m
│   │   ├── PlotPanel.m
│   │   ├── PlotView.m
│   │   ├── RailSummaryView.m
│   │   ├── ResponsiveLayoutManager.m
│   │   └── VideoPanel.m
│   └── FlightDataDashboard.m
├── asyncDecodeFrame.m
├── asyncDecodeFramePersistent.m
├── cleanupAsyncDecodeCache.m
├── FlightDataDashboard.m
├── FlightReviewStudio.m
└── merged_output_2605051834_refactoring.m

=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase4() 실행 결과 P9-1만 FAIL 발생.
실패 메시지:
P9-1 FAIL save() did not produce the .frsproj file

현재 통과:
P4-1 ~ P4-8 PASS
runMultiInstanceTests() TC-1 ~ TC-3 PASS

수정 대상:
+flightdash/+project/ProjectSerializer.m
+flightdash/+studio/+diag/verifyPhase4.m 필요 시 최소 보완

문제 분석:
ProjectSerializer.save(project, filePath)는 .frsproj 확장자를 가진 filePath로 zip(filePath, entries, tmpDir)를 호출한다.
검증 함수 p91_serializerRoundTrip()는 tmpFile = [tempname() '.frsproj']로 지정하고 save 후 isfile(tmpFile)을 검사한다.
현재 isfile(tmpFile)이 false이므로 zip 결과가 tmpFile 위치에 생성되지 않는 문제가 있다.
MATLAB zip 함수가 .zip 확장자를 자동 부여하거나, 입력 확장자 처리로 인해 tmpFile.frspoj.zip 같은 파일을 만들 가능성을 우선 확인한다.

수정 요구:
1. ProjectSerializer.save()가 호출자가 지정한 filePath 그대로 최종 .frsproj 파일을 반드시 생성하도록 수정한다.
2. 내부 zip 생성은 임시 .zip 파일로 수행한 뒤, 성공 후 filePath로 movefile 또는 rename하는 방식으로 안정화한다.
3. 기존 filePath가 있으면 안전하게 교체하되, 실패 시 기존 파일 손상을 최소화한다.
4. zip 결과 파일 후보를 명확히 처리한다.
   - tempZip
   - tempZip + ".zip"
   - filePath + ".zip"
   등 MATLAB 버전별 zip 확장자 동작 차이를 방어한다.
5. save 완료 직후 isfile(filePath)를 내부에서도 검증하고, 없으면 명확한 ProjectSerializer:WriteFailed 오류를 발생시킨다.
6. load(filePath)는 기존 .frsproj 파일을 그대로 unzip할 수 있어야 한다.
7. verifyPhase4()의 P9-1이 PASS 되도록 한다.
8. 기존 P4-1 ~ P4-8 결과가 깨지면 안 된다.

검증:
1. results = flightdash.studio.diag.verifyPhase4();
2. 모든 항목 9 / 9 PASS 확인
3. multi = flightdash.studio.diag.runMultiInstanceTests();
4. TC-1 ~ TC-3 PASS 유지 확인
5. tempname 기반 .frsproj 저장 후 isfile(tmpFile) true 확인
6. 저장된 .frsproj를 ProjectSerializer.load(tmpFile)로 load 가능 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “P9-1 serializer 저장 파일 생성 수정 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행

#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
아래 내용을 **ChatGPT Cowork 입력 프롬프트**로 그대로 사용하면 됩니다.


재현 조건상 원인은 **Flight Play 정지 후 H 패널 별표 marker의 drag 시작 조건 또는 figure mouse callback이 복구되지 않는 문제**입니다.

현재 코드에서 관련 위험 지점은 명확합니다.

1. `MarkerDragController.startPlotMarkerDrag()`는 drag 시작 시 `src.HitTest='off'`, `ax.Interactions=[]`, `setXLimListenersEnabled(false)`를 수행하고, `stopDrag()`에서 다시 복구합니다. 따라서 play/stop 이후 `stopDrag()`가 아닌 다른 경로로 UI 상태가 바뀌면 별표가 클릭되지 않을 수 있습니다. ([GitHub][1])
2. `PlaybackController.stopFlightPlayback()`은 timer만 stop/delete하고, H 패널 marker의 `HitTest`, `PickableParts`, `ButtonDownFcn`, `Interactions`, `WindowButtonMotionFcn` 복구는 수행하지 않습니다. ([GitHub][2])
3. `applyTimeChange()`는 playback tick에서 계속 호출되며, 내부에서 `updateDashboard()`를 호출합니다. 이 과정에서 H 패널 plot/marker가 재생성되거나 callback이 누락되면 play 전에는 정상이고 stop 후에는 drag가 안 되는 현상이 생길 수 있습니다. ([GitHub][3])
4. `setXLimListenersEnabled()`와 `updateMarkersOnly()`가 H 패널 marker/xline 갱신에 관여하므로, play/stop 후 listener 또는 marker handle 유효성도 함께 점검해야 합니다. ([GitHub][3])

아래 프롬프트를 ChatGPT Cowork에 입력해서 바로 수정 작업을 시키는 것을 권장합니다.

```text id="hj8hq0"
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
Flight 1에서 현재 비행 정보 항목을 선택해 "H: Data View Panel"에 plot을 추가한 뒤, 별표 marker drag는 정상 동작한다.
하지만 Flight Play 버튼을 눌렀다가 Stop 버튼을 누른 후에는 "H: Data View Panel"의 별표 marker를 마우스로 드래그해도 반응하지 않는 버그를 수정한다.

재현 절차:
1. FlightDataDashboard 또는 FlightReviewStudio 실행
2. Flight 1 데이터 로드
3. 현재 비행 정보 테이블에서 항목 선택
4. "H: Data View Panel"에 plot 추가
5. H 패널의 별표 marker를 드래그 → 정상 반응 확인
6. Play 버튼 클릭
7. Stop 버튼 클릭
8. H 패널의 별표 marker를 다시 드래그
9. 현재 문제: marker drag 반응 없음

우선 분석 대상:
- +flightdash/+controller/MarkerDragController.m
- +flightdash/+controller/PlaybackController.m
- +flightdash/FlightDataDashboard.m
- H 패널 plot/marker 생성부
- updateDashboard()
- updateMarkersOnly()
- applyTimeChange()
- setXLimListenersEnabled()
- play/stop 버튼 EventBus publish 경로

수정 방향:
1. PlaybackController.stopFlightPlayback() 이후 H 패널 plot marker의 drag 가능 상태를 복구한다.
2. stop 이후 모든 H 패널 marker에 대해 다음 상태를 보장한다.
   - HitTest = 'on'
   - PickableParts = 'visible' 또는 적절한 클릭 가능 값
   - ButtonDownFcn이 MarkerDragController.startPlotMarkerDrag로 연결되어 있음
   - marker handle이 유효함
   - axes Interactions가 drag 불능 상태로 남아 있지 않음
3. updateDashboard() 또는 plot 재생성 경로에서 marker ButtonDownFcn이 누락되는지 확인하고, 누락 시 재바인딩한다.
4. Playback stop 시 timer만 삭제하지 말고, UI interaction 복구 helper를 호출한다.
5. 단, 재생 중 성능 저하가 생기지 않도록 매 tick마다 무거운 전체 plot 재생성은 피한다.
6. 기존 drag, slider, spinner, video sync, H panel auto paging 기능은 유지한다.
7. Embedded Studio mode와 standalone mode 모두 고려한다.
8. 예외 발생 시 ErrorLog에 기록하되 UI가 멈추지 않게 한다.

권장 구현:
- FlightDataDashboard에 restorePlotMarkerInteractions(fIdx) 또는 rebindPlotMarkerDragCallbacks(fIdx) 같은 경량 helper 추가
- PlaybackController.stopFlightPlayback(fIdx) 끝에서 해당 helper 호출
- updateDashboard()가 H 패널 marker를 새로 만들 경우 동일 helper를 호출하거나 marker 생성 직후 ButtonDownFcn을 확실히 설정
- embedded mode에서는 StudioMouseRouter 원칙을 깨지 않도록 직접 WindowButtonMotionFcn을 건드리지 않는다

검증:
1. play 전 marker drag 정상
2. play 중 marker drag 동작 정책 확인
3. stop 후 marker drag 정상 복구
4. H 패널에 여러 plot이 있을 때 모든 별표 marker drag 정상
5. Flight 1/Flight 2 각각 확인
6. standalone FlightDataDashboard 확인
7. Studio embedded tab 환경 확인
8. tab 전환 후에도 drag 정상
9. stop 반복 클릭 후에도 예외 없음
10. ErrorLog에 관련 예외 없음

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “H 패널 marker drag stop 후 복구 수정 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 고려
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

[1]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bcontroller/MarkerDragController.m "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/%2Bcontroller/PlaybackController.m "raw.githubusercontent.com"
[3]: https://raw.githubusercontent.com/kiki-github2019/flight-dashboard/main/%2Bflightdash/FlightDataDashboard.m "raw.githubusercontent.com"
#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================

결과 해석:

`P0.5-7 FAIL`은 **2가지가 섞인 상태**입니다.

1. `verifyPhase0_5.m contains "�"`
   → 검증 코드 자체의 `patterns` 목록에 `"�"` 문자가 들어 있어서 **자기 자신을 mojibake로 오탐지**한 것입니다.

2. 아래 3개 파일은 실제 깨진 한글 주석/문자 가능성이 큽니다.

   * `+flightdash/+view/FlightDataDashboard.m`
   * `+flightdash/FlightDataDashboard.m`
   * `merged_output_2605051834_refactoring.m`

우선 `verifyPhase0_5.m`의 오탐지를 제거하고, 실제 코드 파일의 깨진 한글만 잡도록 수정하는 것이 좋습니다.

ChatGPT Cowork 입력용 프롬프트:

```text
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase0_5() 실행 결과 P0.5-7만 FAIL 발생.
mojibake 검출 로직이 verifyPhase0_5.m 자기 자신을 오탐지하고 있으며, 일부 실제 코드 파일에도 깨진 한글 주석이 남아 있다.
P0.5-7을 정확하게 동작하도록 수정하고 실제 mojibake를 정리한다.

현재 결과:
P0.5-1 PASS
P0.5-2 PASS
P0.5-3 PASS
P0.5-4 PASS
P0.5-5 PASS
P0.5-6 PASS
P0.5-7 FAIL
P0.5-8 PASS

실패 메시지:
Potential mojibake markers:
+flightdash/+studio/+diag/verifyPhase0_5.m contains "�";
+flightdash/+view/FlightDataDashboard.m contains "?앹";
+flightdash/FlightDataDashboard.m contains "?앹";
merged_output_2605051834_refactoring.m contains "?앹"

수정 대상:
1. +flightdash/+studio/+diag/verifyPhase0_5.m
2. +flightdash/+view/FlightDataDashboard.m
3. +flightdash/FlightDataDashboard.m
4. merged_output_2605051834_refactoring.m 처리 여부 확인

수정 요구:
1. verifyPhase0_5.m의 mojibake 검출 로직이 자기 자신을 오탐지하지 않도록 수정한다.
2. pattern 목록에 실제 "�" 문자를 직접 넣어 자기 파일이 검출되는 문제를 제거한다.
   - 예: char(65533) 또는 sprintf 기반으로 생성하거나,
   - verifyPhase0_5.m 자기 파일은 검사 대상에서 제외한다.
3. 단, 다른 파일에 실제 replacement character가 있으면 계속 검출해야 한다.
4. +flightdash/FlightDataDashboard.m 및 +flightdash/+view/FlightDataDashboard.m의 깨진 한글 주석/문자열을 점검한다.
5. 깨진 부분이 주석이면 의미 보존 가능한 한글 또는 영어 주석으로 복구한다.
6. 깨진 부분이 UI 문자열, 에러 메시지, 파일명, key, event name 등 실행에 영향을 줄 수 있는 문자열이면 임의 삭제하지 말고 의미를 확인해 안전하게 복구한다.
7. merged_output_2605051834_refactoring.m이 단순 병합 산출물/백업 파일이면 실제 배포 코드에서 제외하거나 archive/test artifact로 이동할지 판단한다.
8. MATLAB 실행 경로에 불필요한 merged_output 파일이 잡히지 않게 한다.
9. 수정 후 verifyPhase0_5()가 전체 PASS 되도록 한다.

검증:
1. results = flightdash.studio.diag.verifyPhase0_5();
2. P0.5-1 ~ P0.5-8 전체 PASS 확인
3. checkcode 주요 파일 실행
4. FlightReviewStudio, FlightDataDashboard entry resolution 유지 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 0.5 mojibake 검증/복구 수정 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

핵심은 **`verifyPhase0_5.m`의 `"�"` 자기검출은 오탐**, 나머지 `FlightDataDashboard.m` 계열의 `?앹` 검출은 **실제 인코딩 깨짐 가능성이 높아 복구 대상**이라는 점입니다.
#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================

결과상 Phase 1 기능 자체는 대부분 정상이고, 실패 2개는 **검증 코드가 실제 구현명/메뉴 구조와 안 맞는 문제**일 가능성이 큽니다.

ChatGPT Cowork 입력용 프롬프트:

```text
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase1() 실행 결과 P1-3, P1-5만 FAIL 발생.
Phase 1 Studio Shell 구현 상태를 실제 코드 기준으로 정확히 검증하도록 verifyPhase1.m을 보완하고, 실제 구현 누락이면 최소 수정한다.

현재 결과:
P1-1 PASS
P1-2 PASS
P1-3 FAIL Missing: [MainGrid, HeaderGrid, StatusBarGrid], invalid: []
P1-4 PASS
P1-5 FAIL Too few root menus detected:
P1-6 PASS
P1-7 PASS
P1-8 PASS
P1-9 PASS
P1-10 PASS
P1-11 PASS
P1-12 PASS

우선 확인 대상:
- +flightdash/+studio/FlightReviewStudioApp.m
- +flightdash/+studio/MenuManager.m
- +flightdash/+studio/ToolbarManager.m
- +flightdash/+studio/StatusBarManager.m
- +flightdash/+studio/+diag/verifyPhase1.m

수정 요구:
1. P1-3:
   - verifyPhase1.m이 MainGrid, HeaderGrid, StatusBarGrid라는 property명을 고정 가정하고 있다.
   - 실제 FlightReviewStudioApp의 property명을 확인한다.
   - 실제 shell top-level grid/container가 다른 이름이면 검증 코드를 실제 구현명에 맞게 수정한다.
   - 단, 실제로 UIFigure, BodyGrid 또는 Header/Status 영역 container가 누락된 경우에는 구현을 최소 보완한다.
   - 검증은 특정 property명만 강제하지 말고, 다음 중 하나를 만족하면 PASS하도록 유연화한다.
     a) MainGrid/HeaderGrid/StatusBarGrid property 존재
     b) 실제 구현명으로 된 root/header/body/status container 존재
     c) UIFigure 하위에 uigridlayout/uipanel/uilabel 구조로 shell이 구성되어 있음

2. P1-5:
   - verifyPhase1.m이 root menu property명을 고정 가정하고 있어 MenuManager 구현과 불일치할 수 있다.
   - MATLAB uimenu의 Text/Label property 차이도 고려한다.
   - findall(app.UIFigure,'Type','uimenu') 방식으로 실제 메뉴를 탐색한다.
   - uimenu.Text가 비어 있으면 Label 또는 다른 표시 속성을 확인한다.
   - MenuManager가 메뉴를 생성하지 않는 실제 버그라면 File/Project/Data/Video/Review/Analysis/Plot/Window/Preferences/Help 중 MVP root menu를 최소 생성한다.
   - 검증은 최소 4개 이상의 root menu 또는 의도된 메뉴 manager structure가 있으면 PASS하도록 한다.

3. 기존 PASS 항목은 깨지지 않게 한다.
4. verifyPhase1() 결과가 12 / 12 PASS가 되도록 한다.
5. 실제 구현 누락이 아니라 검증 코드 불일치라면 구현 코드는 건드리지 말고 verifyPhase1.m만 수정한다.

검증:
1. results = flightdash.studio.diag.verifyPhase1();
2. 12 / 12 PASS 확인
3. results = flightdash.studio.diag.verifyPhase0_5();
4. Phase 0.5 기존 PASS 항목 유지 확인
5. Studio app 생성/삭제 정상 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 1 검증 코드 보완 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

요약하면 **P1-3은 property명 고정 가정 문제**, **P1-5는 메뉴 탐색 방식 문제**일 가능성이 높습니다.
#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================

결과상 실제 Phase 2 구현이 전부 실패한 것이 아니라, **`verifyPhase2.m`가 현재 모델 API를 잘못 가정한 상태**입니다.

핵심 원인:

```text
1. SessionModel 생성자가 (SessionId, DisplayName) 2개 인자를 받지 않음
2. SessionModel 속성명이 FlightFiles / VideoFiles가 아닐 가능성 높음
3. ProjectModel에 addAnalysisTheme()가 없고 다른 메서드명일 가능성 있음
4. verifyPhase2.m가 실제 API 확인 없이 고정 생성자/속성/메서드를 호출함
```

ChatGPT Cowork 입력용 프롬프트:

```text
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase2() 실행 결과 다수 FAIL 발생.
실패 대부분은 verifyPhase2.m이 현재 ProjectModel / SessionModel / AnalysisThemeModel의 실제 API와 맞지 않아서 발생한 것으로 보인다.
실제 모델 구현을 기준으로 verifyPhase2.m을 보완하고, 실제 구현 누락이 확인되는 경우에만 최소 수정한다.

현재 결과:
P2-1 PASS
P2-2 PASS
P2-3 FAIL SessionModel missing/invalid props: FlightFiles, VideoFiles
P2-4 FAIL MATLAB:TooManyInputs
P2-5 FAIL MATLAB:TooManyInputs
P2-6 FAIL MATLAB:TooManyInputs
P2-7 PASS
P2-8 PASS
P2-9 FAIL MATLAB:TooManyInputs
P2-10 FAIL ProjectModel에 addAnalysisTheme 없음
P2-11 FAIL MATLAB:TooManyInputs
P2-12 PASS

우선 분석 대상:
- +flightdash/+project/ProjectModel.m
- +flightdash/+project/SessionModel.m
- +flightdash/+project/FigureModel.m
- +flightdash/+project/ReviewResultModel.m
- +flightdash/+project/AnalysisThemeModel.m
- +flightdash/+studio/+diag/verifyPhase2.m

수정 원칙:
1. 먼저 실제 모델 클래스의 constructor 시그니처, public property, public method를 확인한다.
2. verifyPhase2.m이 실제 구현과 다른 이름을 고정 가정하고 있으면 verifyPhase2.m을 수정한다.
3. 실제 모델에 반드시 있어야 할 기능이 누락된 경우에만 모델 코드를 최소 수정한다.
4. 기존 모델 API를 불필요하게 깨지 않는다.
5. Phase 2 검증은 value model, session CRUD, id uniqueness, validation, cascade delete, schema version 중심으로 유지한다.

구체 수정 요구:

1. SessionModel 생성 방식 보완
- verifyPhase2.m에서 flightdash.project.SessionModel('S001','Session 1')처럼 2개 인자를 고정 호출하지 않는다.
- 실제 생성자가 무인자이면 무인자로 생성 후 SessionId / DisplayName 또는 해당 setter로 설정한다.
- helper 함수를 만든다.
  예:
  makeSession(sessionId, displayName)
  setSessionIdSafe(session, sessionId)
  setDisplayNameSafe(session, displayName)

2. SessionModel 파일 속성명 보완
- verifyPhase2.m에서 FlightFiles / VideoFiles를 고정 요구하지 않는다.
- 실제 속성명이 FlightFilePaths, VideoFilePaths, ChannelFiles, FlightFile, VideoFile 등인지 확인한다.
- setFlightFile / setVideoFile 메서드가 있으면 그것을 우선 사용한다.
- 속성 직접 검증은 실제 존재하는 속성 기준으로 한다.
- Phase 2 필수 조건은 “채널별 flight/video path 저장 가능”이지 특정 속성명 강제가 아니다.

3. TooManyInputs 오류 제거
- 모든 테스트에서 모델 생성자에 인자를 직접 넣는 부분을 helper 기반으로 교체한다.
- ReviewResultModel, FigureModel, AnalysisThemeModel도 무인자 생성 후 property 설정 방식으로 통일한다.

4. ProjectModel 메서드명 보완
- addAnalysisTheme()가 실제로 없으면 실제 메서드명을 확인한다.
  후보:
  addTheme
  addAnalysisThemeModel
  addThemePreset
  updateAnalysisTheme
  직접 AnalysisThemes 배열 append
- verifyPhase2.m은 실제 API가 있으면 사용하고, 없으면 안전 helper로 append한다.
- 단, ProjectModel 설계상 theme CRUD가 필수인데 메서드가 아예 없으면 최소 addAnalysisTheme 호환 메서드를 추가해도 된다.

5. P2-3 보완
- SessionModel 필수 속성 검증 목록을 실제 모델에 맞게 조정한다.
- 반드시 확인할 항목:
  SchemaVersion
  SessionId 또는 동등 id 필드
  DisplayName 또는 동등 name 필드
  DirtyFlag 또는 동등 dirty 상태 필드
  flight/video path 저장 수단

6. P2-4 보완
- Project session CRUD는 실제 addSession/updateSession/removeSession/getSession/hasSession/sessionCount 메서드 또는 Sessions 배열 직접 확인을 통해 검증한다.
- 생성자 인자 오류가 없어야 한다.

7. P2-5 보완
- channelIdx validation 검증은 setFlightFile/setVideoFile/setRoiRows 메서드가 있을 때만 수행한다.
- 해당 메서드가 없으면 SKIP_NOT_IMPLEMENTED가 아니라, 실제 대체 API가 있는지 확인 후 그 API로 검증한다.
- invalid channel index는 {0,3,-1,1.5,NaN,Inf}를 거부해야 한다.

8. P2-6 보완
- display name validation은 setDisplayName 메서드가 있으면 사용한다.
- 없으면 property 직접 설정 정책인지 확인한다.
- empty/whitespace reject가 설계 요구라면 모델에 setDisplayName 또는 validator를 추가한다.

9. P2-9 보완
- ReviewResultModel 생성도 무인자 + property 설정 방식으로 변경한다.
- Result의 SessionId 필드명이 실제와 다르면 helper로 처리한다.
- removeSession 시 해당 session 결과 cascade delete가 실제 구현됐는지 검증한다.

10. P2-10 보완
- AnalysisThemeModel 추가는 실제 ProjectModel API 또는 helper append 방식으로 검증한다.
- addAnalysisTheme가 설계상 필요한 public API라면 ProjectModel에 최소 구현한다.

11. P2-11 보완
- value class copy semantics 검증도 무인자 생성 + helper 기반으로 수정한다.
- p1.addSession(s) 호출 후 p1은 변경되지 않고 p2만 변경되는지 확인한다.

검증:
1. results = flightdash.studio.diag.verifyPhase2();
2. 12 / 12 PASS 확인
3. results = flightdash.studio.diag.verifyPhase0_5();
4. results = flightdash.studio.diag.verifyPhase1();
5. 기존 PASS 항목 유지 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 2 검증 코드/API 정합성 보완 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

요약하면, **P2 실패는 모델 전체 문제라기보다 검증 코드가 실제 API와 불일치한 문제**가 큽니다. 먼저 `verifyPhase2.m`을 실제 `SessionModel` / `ProjectModel` 구조에 맞게 유연화해야 합니다.

#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================

결과 해석:

`Phase 3` 핵심 Embedded 생성/SessionScope는 정상입니다. 실패는 2개입니다.

1. **P3-8 FAIL**

   * `afterAdd=4`인데 `hasAdd=0`이므로, 실제 tab은 추가됐지만 `verifyPhase3.m`의 `workspaceHasSession()`이 현재 `WorkspaceManager`의 session 저장 방식과 맞지 않습니다.
   * 즉, **구현 버그일 수도 있지만 우선 검증 코드의 key 탐색 방식 불일치 가능성이 큽니다.**

2. **P3-10 SKIP_NOT_IMPLEMENTED**

   * `refreshLayout()` public method가 아직 없음.
   * 이건 실제 미구현입니다. Phase 3.5d에서 반드시 구현해야 합니다.

ChatGPT Cowork 입력용 프롬프트:

```text
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase3() 실행 결과 P3-8 FAIL, P3-10 SKIP_NOT_IMPLEMENTED 발생.
Phase 3 Embedded Dashboard 검증을 실제 WorkspaceManager 구현과 정합시키고, refreshLayout(reason) public method를 추가/보완한다.

현재 결과:
P3-1 PASS
P3-2 PASS
P3-3 PASS
P3-4 PASS
P3-5 PASS
P3-6 PASS
P3-7 PASS
P3-8 FAIL Workspace add/remove mismatch: before=1 afterAdd=4 afterRemove=1 hasAdd=0 hasRemove=0
P3-9 PASS
P3-10 SKIP_NOT_IMPLEMENTED refreshLayout method not implemented yet
P3-11 PASS
P3-12 PASS

우선 분석 대상:
- +flightdash/+studio/WorkspaceManager.m
- +flightdash/FlightDataDashboard.m
- +flightdash/+studio/+diag/verifyPhase3.m

수정 요구:

1. P3-8 원인 분석
- WorkspaceManager.addDashboardTab(sessionId, displayName)의 실제 동작을 확인한다.
- DashboardMap / TabMap / SessionId 저장 방식 / tab.UserData / appdata 사용 여부를 확인한다.
- verifyPhase3.m의 workspaceHasSession(), countWorkspaceDashboards(), callWorkspaceAdd(), callWorkspaceRemove()가 실제 구현과 맞지 않으면 검증 코드를 수정한다.
- 실제 add/remove 구현이 잘못되어 sessionId 기준으로 dashboard/tab을 추적하지 못한다면 WorkspaceManager를 최소 수정한다.
- addDashboardTab 후 sessionId로 dashboard/tab을 조회할 수 있어야 한다.
- removeDashboardTab 후 해당 sessionId의 dashboard/tab이 제거되어야 한다.
- 초기 workspace에 welcome tab 또는 placeholder tab이 있을 수 있으므로, count 검증은 placeholder tab을 고려해 session dashboard count 기준으로 판단한다.

2. P3-8 검증 기준 보완
- 단순 uitab 개수 증가량으로 PASS/FAIL하지 않는다.
- session dashboard tab만 세도록 보완한다.
- 다음 중 실제 구현에 맞는 방식을 사용한다.
  a) DashboardMap key 확인
  b) TabMap key 확인
  c) tab.UserData.SessionId 확인
  d) tab.UserData가 char/string sessionId인지 확인
  e) appdata(tab,'SessionId') 확인
  f) dashboard.ActiveSessionId 확인
- add 후 hasAdd=true가 되어야 한다.
- remove 후 hasRemove=false가 되어야 한다.

3. P3-10 refreshLayout 구현
- FlightDataDashboard에 public method refreshLayout(reason)를 추가한다.
- standalone/embedded 모두 안전하게 호출 가능해야 한다.
- reason은 char/string을 허용한다.
- 내부에서는 기존 layout manager 또는 size changed 처리 경로를 재사용한다.
- LayoutMgr가 있으면 LayoutMgr.applyLayout 또는 동등한 메서드를 호출한다.
- LayoutMgr가 없거나 UI가 아직 초기화되지 않았으면 no-op 처리한다.
- 삭제 중/닫힌 app/invalid RootContainer 상태에서는 조용히 return한다.
- 예외는 ErrorLog에 기록하되 호출자가 죽지 않게 한다.
- refreshLayout은 무거운 전체 재생성 없이 layout recalculation만 수행한다.

4. WorkspaceManager 연동
- tab selection 시 active dashboard.refreshLayout("TabActivated") 호출 가능하면 추가한다.
- Studio resize/dock 변경 연동은 Phase 3.5d에서 확장 예정이므로 이번에는 최소한 public method smoke test가 PASS 되도록 한다.

검증:
1. results = flightdash.studio.diag.verifyPhase3();
2. P3-1 ~ P3-12 전체 PASS 확인
3. results = flightdash.studio.diag.verifyPhase1();
4. 기존 Studio shell 검증 PASS 유지 확인
5. results = flightdash.studio.diag.verifyPhase4();
6. SessionScope/EventBus 관련 기존 PASS 유지 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 3 workspace 검증/refreshLayout 보완 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

요약하면 **P3-8은 검증 코드와 WorkspaceManager 구현의 session 추적 방식 불일치 가능성이 높고**, **P3-10은 실제로 `refreshLayout()`을 추가해야 하는 미구현 항목**입니다.

#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================

GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase5() 실행 결과 다수 FAIL 발생.
대부분 "입력 인수가 너무 많습니다" 오류이므로 verifyPhase5.m이 현재 Studio/Project/Workspace API의 실제 시그니처와 맞지 않는 상태로 판단된다.
실제 구현을 기준으로 verifyPhase5.m을 보완하고, 실제 구현 누락이 있으면 최소 수정한다.

현재 결과:
P5-1 PASS
P5-2 PASS
P5-3 PASS
P5-4 FAIL Session add/tree refresh check failed: 입력 인수가 너무 많습니다.
P5-5 FAIL Session rename check failed: 입력 인수가 너무 많습니다.
P5-6 FAIL Session duplicate check failed: 입력 인수가 너무 많습니다.
P5-7 FAIL Session delete check failed: 입력 인수가 너무 많습니다.
P5-8 FAIL Tree/workspace activation check failed: 입력 인수가 너무 많습니다.
P5-9 PASS
P5-10 SKIP_NOT_IMPLEMENTED No Object Manager refresh method exposed
P5-11 FAIL Object Manager dashboard refresh failed: 입력 인수가 너무 많습니다.
P5-12 SKIP_NOT_IMPLEMENTED No public Inspector invalid-selection method exposed
P5-13 SKIP_MANUAL

우선 분석 대상:
- +flightdash/+studio/+diag/verifyPhase5.m
- +flightdash/+studio/FlightReviewStudioApp.m
- +flightdash/+studio/ProjectExplorerPanel.m
- +flightdash/+studio/WorkspaceManager.m
- +flightdash/+studio/RightDockManager.m
- +flightdash/+project/SessionModel.m
- +flightdash/+project/ProjectModel.m

수정 원칙:
1. 먼저 실제 public method 시그니처와 property명을 확인한다.
2. verifyPhase5.m이 실제 API와 다르게 인자를 넣고 있으면 verifyPhase5.m을 수정한다.
3. 구현 누락이 명확한 경우에만 구현 코드를 최소 수정한다.
4. 기존 Phase 1~4 PASS 항목을 깨지 않는다.
5. Phase 5 목표는 Project Explorer / Object Manager MVP 검증이며, OriginPro급 drag/drop, inline checkbox, multi-style edit는 범위 밖이다.

구체 수정 요구:

1. SessionModel 생성 helper 수정
- verifyPhase5.m에서 flightdash.project.SessionModel(sessionId, displayName)처럼 2개 인자 생성자를 직접 호출하지 않는다.
- 실제 SessionModel이 무인자 생성자라면 무인자로 생성 후 helper로 SessionId/DisplayName을 설정한다.
- helper 예:
  makeSession(sessionId, displayName)
  setSessionIdSafe(session, sessionId)
  setDisplayNameSafe(session, displayName)
- setDisplayName 메서드가 있으면 우선 사용하고, 없으면 property 직접 설정한다.

2. Studio session command helper 수정
- app.addSession(sessionId, displayName)처럼 고정 호출하지 않는다.
- 실제 app.addSession 시그니처가 무인자/UI-dialog 기반이면 자동 검증에서 호출하지 않는다.
- 검증에서는 ProjectModel에 SessionModel을 직접 추가하고 WorkspaceManager.addDashboardTab 또는 실제 add tab API를 호출하는 방식으로 우회한다.
- 실제 app에 addSessionWithModel 또는 addSessionFromModel 같은 비UI 메서드가 있으면 우선 사용한다.

3. renameSession helper 수정
- app.renameSession(sessionId, newName) 고정 호출 금지.
- 실제 renameSession이 UI prompt 기반이면 검증에서는 ProjectModel session update + ProjectExplorer refresh + Workspace tab title update 경로로 처리한다.
- WorkspaceManager에 rename/update title API가 있으면 사용하고, 없으면 TabMap을 통해 title만 갱신한다.

4. duplicateSession helper 수정
- app.duplicateSession(sourceId) 고정 호출 금지.
- 실제 API가 UI selection 기반이면 검증에서는 source session을 직접 복사해 새 SessionModel 생성 후 ProjectModel/Workspace에 추가한다.
- 새 session id는 ProjectModel.newId('SESS') 사용.

5. removeSession helper 수정
- app.removeSession(sessionId) 고정 호출 금지.
- 실제 API가 현재 선택 기반이면 검증에서는 WorkspaceManager.removeDashboardTab(sessionId) 또는 실제 remove API를 사용하고, ProjectModel.removeSession(sessionId)를 호출한다.

6. Workspace selection helper 수정
- selectWorkspaceSession(ws, sessionId)가 실제 WorkspaceManager API와 맞지 않으면 수정한다.
- 후보:
  selectSession
  selectDashboardTab
  activateSession
  switchToSession
  TabMap(sessionId) 기반 SelectedTab 설정
  tab.UserData / appdata 기반 탐색
- onTabChanged가 인자를 요구하지 않는지/요구하는지 확인 후 안전 호출한다.

7. P5-4 ~ P5-8 검증 기준 보완
- 단순 uitab 전체 개수 대신 session dashboard tab 기준으로 검증한다.
- welcome/placeholder tab은 제외한다.
- treeContainsText는 ProjectExplorer의 실제 tree node Text/NodeData/UserData 구조를 탐색한다.
- ProjectExplorer refresh method가 없으면 실제 method명을 확인해 사용한다.
- tree refresh가 비동기 drawnow 이후 반영될 수 있으므로 drawnow limitrate를 적절히 사용한다.

8. P5-10 Object Manager refresh
- RightDockManager에 Object Manager refresh public method가 실제로 없으면 MVP용 public wrapper를 추가한다.
- 권장 public method:
  refreshObjectManager(activeDashboard)
  refreshInspectorForObject(graphicsHandle)
- 내부 기존 private 메서드가 있으면 public wrapper만 얇게 추가한다.
- 기능은 표시/숨김, 단일 선택, Inspector 연동 수준만 유지한다.

9. P5-11 Object Manager dashboard refresh
- verifyPhase5.m은 RightDockManager의 실제 refresh API에 맞게 호출한다.
- refreshObjectManager(dashboard)가 추가되면 해당 메서드 사용.
- dashboard가 유효하지 않거나 UI가 아직 비어 있으면 예외 없이 빈 object tree로 처리한다.

10. P5-12 Inspector invalid selection
- RightDockManager에 public invalid selection 테스트용 method가 없으면 SKIP_NOT_IMPLEMENTED 유지 가능.
- 단, 이미 내부에 selected object 처리 로직이 있으면 public wrapper를 추가한다.
- 삭제된 graphics handle이 들어와도 예외 없이 clear 상태가 되어야 한다.

검증:
1. results = flightdash.studio.diag.verifyPhase5();
2. 최소 목표:
   - P5-1 ~ P5-9 PASS
   - P5-10 PASS 또는 SKIP_NOT_IMPLEMENTED 허용은 이번 수정에서 가급적 PASS로 전환
   - P5-11 PASS
   - P5-12 PASS 또는 SKIP_NOT_IMPLEMENTED 허용
   - P5-13 SKIP_MANUAL 유지
3. results = flightdash.studio.diag.verifyPhase1();
4. results = flightdash.studio.diag.verifyPhase2();
5. results = flightdash.studio.diag.verifyPhase3();
6. 기존 PASS 항목 유지 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 5 검증/API 정합성 보완 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================
결과상 Phase 6도 실제 구현 전체 실패라기보다 **검증 코드가 현재 API 시그니처와 맞지 않는 문제 + Inspector public wrapper 부족**입니다.

핵심 원인:

```text
P6-6, P6-7: verifyPhase6.m의 addSession/selectWorkspaceSession helper가 실제 API에 인자를 잘못 전달
P6-9: RightDockManager에 public selection method 없음
P6-10: selection 실패(selected=0) 상태에서 visible toggle만 시도됨
P6-11: GUI Mode apply method 미구현
```

ChatGPT Cowork 입력용 프롬프트:

```text
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase6() 실행 결과 P6-6, P6-7, P6-10 FAIL 및 P6-9/P6-11 SKIP 발생.
Toolbar/Menu/Inspector MVP 검증 코드와 실제 API를 정합시키고, 필요한 public wrapper를 최소 추가한다.

현재 결과:
P6-1 PASS
P6-2 PASS
P6-3 PASS
P6-4 PASS
P6-5 PASS
P6-6 FAIL Session command check failed: 입력 인수가 너무 많습니다.
P6-7 FAIL Tab switch routing check failed: 입력 인수가 너무 많습니다.
P6-8 PASS
P6-9 SKIP_NOT_IMPLEMENTED No public Inspector selection method exposed
P6-10 FAIL Inspector visible toggle path exercised; selected=0 visible=on
P6-11 SKIP_NOT_IMPLEMENTED Project.GuiMode exists; GUI mode apply method not implemented yet
P6-12 SKIP_MANUAL

우선 분석 대상:
- +flightdash/+studio/+diag/verifyPhase6.m
- +flightdash/+studio/FlightReviewStudioApp.m
- +flightdash/+studio/WorkspaceManager.m
- +flightdash/+studio/RightDockManager.m
- +flightdash/+studio/ToolbarManager.m
- +flightdash/+studio/MenuManager.m
- +flightdash/+project/SessionModel.m
- +flightdash/+project/ProjectModel.m

수정 원칙:
1. 실제 public API 시그니처를 먼저 확인한다.
2. verifyPhase6.m이 실제 API와 다르게 인자를 넣고 있으면 verifyPhase6.m을 수정한다.
3. 실제 MVP 기능에 필요한 public wrapper가 없으면 얇은 wrapper만 추가한다.
4. 기존 Phase 1~5 PASS 항목을 깨지 않는다.
5. Mini Toolbar floating 구현은 하지 않는다.

구체 수정 요구:

1. P6-6 / P6-7 입력 인수 오류 수정
- verifyPhase6.m의 addSessionToStudio(), selectWorkspaceSession(), getActiveDashboard() helper를 실제 API 기준으로 수정한다.
- app.addSession(sessionId, displayName)처럼 고정 호출하지 않는다.
- 실제 addSession이 UI-dialog 기반/무인자라면 검증에서는 직접 호출하지 않는다.
- 검증용 세션 생성은 다음 순서로 처리한다.
  a) SessionModel 무인자 생성
  b) 실제 property/setter로 SessionId, DisplayName 설정
  c) ProjectModel.addSession 또는 Sessions 배열에 안전 추가
  d) WorkspaceManager.addDashboardTab 또는 실제 tab add API 호출
- Workspace selection도 실제 API에 맞게 처리한다.
  후보:
  selectSession
  selectDashboardTab
  activateSession
  switchToSession
  TabMap(sessionId) 기반 SelectedTab 설정
  tab.UserData 또는 appdata 기반 탐색
- onTabChanged 호출 시 실제 시그니처를 확인하고, 인자 오류가 나지 않게 safe call한다.

2. P6-9 Inspector public selection wrapper 추가
- RightDockManager에 public method가 없다면 다음 중 최소 1개를 추가한다.
  selectObject(graphicsHandle)
  refreshInspector(graphicsHandle)
  setSelectedObject(graphicsHandle)
- 내부 기존 private 로직이 있으면 재사용한다.
- invalid/deleted graphics handle 입력 시 예외 없이 selection clear 처리한다.

3. P6-10 visible toggle 수정
- 현재 selected=0이므로 Inspector가 graphics handle을 선택하지 못하고 있다.
- RightDockManager public selection wrapper를 통해 selected object가 저장되도록 한다.
- visible toggle public method도 없으면 최소 1개를 추가한다.
  toggleSelectedVisible()
  setSelectedVisible(value)
- 선택된 graphics handle이 유효하고 Visible 속성이 있으면 on/off 변경한다.
- Visible 속성이 없는 객체는 예외 없이 no-op 또는 status message 처리한다.
- 삭제된 handle이면 no-op 처리한다.
- verifyPhase6.m의 P6-10은 실제 selection 성공 후 visible이 off로 바뀌는지 확인하도록 수정한다.

4. P6-11 GUI Mode MVP 처리
- Project.GuiMode 필드는 이미 존재하므로 최소 apply method를 추가한다.
- FlightReviewStudioApp에 다음 중 하나를 public으로 구현한다.
  setGuiMode(modeName)
  applyGuiMode(modeName)
- MVP 범위:
  Classic / Studio / Review / Analysis 문자열 허용
  Project.GuiMode 갱신
  필요한 경우 Explorer/RightDock/Toolbar visible profile만 최소 반영
  layout refresh 호출
- 아직 완성된 GUI mode가 아니면 visibility 조정은 최소화해도 된다.
- verifyPhase6.m은 setGuiMode/applyGuiMode 중 실제 구현된 메서드를 호출한다.

5. Toolbar/Menu active session routing 보존
- P6-3/P6-4/P6-5는 이미 PASS이므로 관련 구현은 불필요하게 건드리지 않는다.
- command routing 검증은 active dashboard가 바뀌는지만 확인하고 실제 heavy command 실행은 피한다.

6. 검증 코드 보완
- verifyPhase6.m은 현재 모델/워크스페이스 API에 유연하게 대응하도록 helper 기반으로 수정한다.
- TooManyInputs가 발생하면 다른 fallback으로 시도하거나 명확한 FAIL 메시지를 남긴다.
- UI-dialog 기반 method는 자동검증에서 직접 호출하지 않는다.

검증:
1. results = flightdash.studio.diag.verifyPhase6();
2. 목표:
   - P6-1 ~ P6-8 PASS
   - P6-9 PASS
   - P6-10 PASS
   - P6-11 PASS 또는 최소 SKIP_NOT_IMPLEMENTED가 아닌 PASS
   - P6-12 SKIP_MANUAL 유지
3. results = flightdash.studio.diag.verifyPhase1();
4. results = flightdash.studio.diag.verifyPhase3();
5. results = flightdash.studio.diag.verifyPhase5();
6. 기존 PASS 항목 유지 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 6 검증/API 정합성 및 Inspector MVP 보완 후 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

우선순위는 **P6-6/P6-7의 helper API 정합성 수정 → RightDockManager selection/toggle wrapper 추가 → GUI mode 최소 method 추가** 순서가 안전합니다.

#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================
결과상 Phase 9의 핵심 실패는 두 종류입니다.

```text id="hhvyrt"
1. ProjectSerializer.save()가 .frsproj 대신 .frsproj.zip을 생성함
2. verifyPhase9.m이 현재 ProjectModel/SessionModel/AnalysisThemeModel API와 맞지 않게 인자를 전달함
```

ChatGPT Cowork 입력용 프롬프트:

```text id="yce7me"
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

작업 목표:
flightdash.studio.diag.verifyPhase9() 실행 결과 다수 FAIL 발생.
핵심 문제는 ProjectSerializer.save()가 지정된 .frsproj 파일 대신 .frsproj.zip 파일을 생성하는 문제와, verifyPhase9.m이 현재 모델 API와 맞지 않는 문제다.
ProjectSerializer 저장 경로를 안정화하고 verifyPhase9.m을 실제 API 기준으로 수정한다.

현재 결과:
P9-1 PASS
P9-2 FAIL save() did not produce requested file. Candidates: /tmp/...frsproj.zip
P9-3 FAIL Round-trip failed: File not found: /tmp/...frsproj
P9-4 FAIL Session metadata round-trip failed: 입력 인수가 너무 많습니다.
P9-5 FAIL AnalysisTheme round-trip failed: ProjectModel에 addAnalysisTheme 없음
P9-6 FAIL External links round-trip failed: 입력 인수가 너무 많습니다.
P9-7 FAIL Manifest/archive content check failed: 입력 인수가 너무 많습니다.
P9-8 FAIL Overwrite check failed: File not found: /tmp/...frsproj
P9-9 PASS
P9-10 PASS
P9-11 PASS
P9-12 FAIL Open project restore smoke failed: 입력 인수가 너무 많습니다.

우선 분석 대상:
- +flightdash/+project/ProjectSerializer.m
- +flightdash/+project/ProjectModel.m
- +flightdash/+project/SessionModel.m
- +flightdash/+project/AnalysisThemeModel.m
- +flightdash/+studio/FlightReviewStudioApp.m
- +flightdash/+studio/WorkspaceManager.m
- +flightdash/+studio/+diag/verifyPhase9.m

수정 요구:

1. ProjectSerializer.save() 파일 생성 문제 수정
- save(project, filePath)는 호출자가 지정한 filePath 그대로 최종 파일을 생성해야 한다.
- filePath가 /tmp/test.frsproj이면 최종 결과는 반드시 /tmp/test.frsproj여야 한다.
- MATLAB zip 함수가 .zip 확장자를 자동 부여하여 .frsproj.zip을 만드는 문제를 방어한다.
- 권장 구현:
  a) tempZipBase 또는 tempZipFile을 별도 임시 경로로 생성
  b) zip은 임시 .zip 경로로 생성
  c) zip 결과 후보를 탐색
     - tempZipFile
     - tempZipFile + ".zip"
     - filePath + ".zip"
  d) 성공한 zip 결과를 filePath로 movefile/copyfile
  e) 저장 완료 후 isfile(filePath)와 파일 크기 > 0 검증
  f) 실패 시 ProjectSerializer:WriteFailed 오류 발생
- 기존 filePath가 있으면 안전하게 교체한다.
- 실패 시 기존 파일 손상을 최소화한다.
- load(filePath)는 .frsproj를 그대로 unzip할 수 있어야 한다.

2. verifyPhase9.m SessionModel 생성 오류 수정
- flightdash.project.SessionModel('ID','Name')처럼 2개 인자 생성자를 고정 호출하지 않는다.
- 실제 SessionModel이 무인자 생성자라면 무인자로 생성 후 helper로 SessionId/DisplayName 설정한다.
- helper 추가:
  makeSession(sessionId, displayName)
  setSessionIdSafe(session, sessionId)
  setDisplayNameSafe(session, displayName)
  safeSetFlightFile(session, channelIdx, path)
  safeSetVideoFile(session, channelIdx, path)
- setFlightFile/setVideoFile 메서드가 있으면 우선 사용하고, 없으면 실제 파일 경로 속성을 찾아 설정한다.

3. verifyPhase9.m AnalysisTheme 추가 오류 수정
- ProjectModel.addAnalysisTheme가 없으면 실제 method명을 확인한다.
- 후보:
  addTheme
  addAnalysisThemeModel
  addThemePreset
  updateAnalysisTheme
  직접 AnalysisThemes 배열 append
- verifyPhase9.m에서는 helper addThemeToProject(project, theme)를 만들어 실제 API에 맞게 처리한다.
- 설계상 addAnalysisTheme public API가 필요하면 ProjectModel에 호환 메서드를 최소 추가해도 된다.

4. verifyPhase9.m ProjectModel/SessionModel API 정합성 보완
- ProjectModel.addSession, removeSession, getSession, sessionCount 등은 실제 구현을 확인하고 helper로 감싼다.
- 생성자 인자 직접 호출 금지.
- property 직접 접근도 실제 존재 여부를 확인한다.
- FlightFiles/VideoFiles 같은 고정 속성명만 가정하지 않는다.

5. P9-7 manifest/archive content 검증 보완
- save()가 .frsproj 파일을 정확히 만들도록 수정 후 unzip(tmpFile)으로 검사한다.
- manifest.json, project.json, sessions/*/session.json 존재 확인.
- 실제 archive 내부 경로가 다르면 verifyPhase9.m을 실제 serializer 포맷에 맞게 수정한다.

6. P9-8 overwrite 검증
- 동일 .frsproj 경로에 두 번 저장해도 최종 filePath가 존재해야 한다.
- 두 번째 project name이 load 결과에 반영되어야 한다.
- .frsproj.zip 임시 잔여물이 남지 않게 정리한다.

7. P9-12 open project restore smoke 수정
- app.openProject가 UI dialog 기반이면 자동 검증에서 직접 호출하지 않는다.
- 직접 파일 경로를 받는 public method가 없으면 SKIP_MANUAL 유지가 가능하다.
- 가능하면 FlightReviewStudioApp에 loadProjectFromFile(filePath) 또는 openProjectFile(filePath) public helper를 추가한다.
- 이 helper는 ProjectSerializer.load(filePath)를 호출하고 ProjectExplorer 갱신 및 session tab metadata 복원을 수행한다.
- 대용량 data/video lazy load는 하지 않는다.
- session tab 복원은 metadata 기반으로만 수행한다.

8. 기존 PASS 유지
- P9-1, P9-9, P9-10, P9-11은 깨지지 않아야 한다.
- verifyPhase2, verifyPhase5에서 이미 동일한 API helper 문제가 있으므로 가능하면 공통 helper 패턴을 맞춘다.

검증:
1. results = flightdash.studio.diag.verifyPhase9();
2. 목표: P9-1 ~ P9-11 PASS, P9-12 PASS 또는 SKIP_MANUAL 허용
3. 특히 P9-2는 반드시 PASS:
   - save() produced .frsproj file
   - .frsproj.zip 후보가 최종 결과로 남으면 안 됨
4. results = flightdash.studio.diag.verifyPhase4();
5. 기존 serializer smoke 관련 PASS 유지 확인
6. results = flightdash.studio.diag.verifyPhase2();
7. 모델 helper 수정으로 인한 회귀 없음 확인

응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- git 명령어 출력 금지
- 성공 시 “Phase 9 serializer 저장 경로/API 정합성 보완 및 push 완료” 한 줄만 출력
- 실패 시 실패 원인만 한 줄 출력

코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 여러 개선안이 있으면 2개만 내부 검토 후 가장 안전한 안 적용
- 작업 완료 시 테스트 후 git commit 및 git push 자동 실행
```

우선순위는 **`ProjectSerializer.save()`가 지정된 `.frsproj` 파일을 실제로 만들도록 고치는 것**입니다. 이 하나가 해결되면 P9-2, P9-3, P9-8의 핵심 실패가 같이 풀립니다.

#######################################################################################################################
# ok
#######################################################################################################################
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
=========================================================================================================================
========================================================================================================================
```text
GitHub 저장소:
https://github.com/kiki-github2019/flight-dashboard

목표:
현재 저장소의 Flight Review Studio / FlightDataDashboard Embedded 구조를 안정화하고, 아래 Phase 순서대로 작업한다.
각 Phase는 독립적으로 완료 가능한 단위로 진행하고, Phase 완료 시 반드시 테스트 후 git commit 및 git push를 자동 실행한다.

공통 응답 규칙:
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 기존 코드 반복 출력 금지
- 불필요한 설명 금지
- 불필요한 과정 출력 금지
- git 명령어 출력 금지
- 응답은 최대 1줄 요약만 출력
- 결과 출력에는 토큰을 최소 사용
- 코드 작업과 검증에는 토큰을 최대 사용

공통 코드 작업 규칙:
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 강화
- 기존 기능 보존
- MATLAB 2025a/2026a 호환성 고려
- MATLAB Online 및 15인치 노트북/FHD 모니터 환경 고려
- 여러 개선안이 있으면 최대 2개만 내부 검토 후 가장 안전한 안 적용
- 대규모 리팩토링보다 안정적인 점진 수정 우선
- Phase 완료 시 git push 자동 실행

절대 규칙:
- 작업 결과 설명은 최소화
- 코드 출력 금지
- 현재 Phase 작업 종료 시 반드시 git push 실행
- 실패 시 원인만 1줄 출력
- 성공 시 “Phase X 완료 및 push 완료” 형식으로만 출력


============================================================
Phase 0.5 — Encoding / Formatting Stabilization
============================================================

목표:
저장소의 MATLAB 파일 인코딩, 줄바꿈, 주석 깨짐, 문법 파싱 위험을 먼저 안정화한다.

작업:
1. 모든 .m 파일의 줄바꿈 상태 확인
2. GitHub raw에서 한 줄로 보이는 파일이 실제 MATLAB 실행에 문제가 없는지 확인
3. UTF-8 / LF 기준으로 정규화
4. 깨진 한글 주석이 있으면 가능한 범위에서 복구하거나 의미 보존 영어/한글 주석으로 교체
5. 문자열 리터럴 내부의 한글 깨짐 여부 확인
6. .gitattributes 추가 또는 보완
7. MATLAB checkcode 기준 치명 오류 제거
8. FlightReviewStudio.m entry가 정상 실행 가능한지 확인

검증:
- checkcode 주요 파일 실행
- FlightReviewStudio entry 파싱 확인
- FlightDataDashboard entry 파싱 확인
- 기존 기능 영향 최소 확인

완료 조건:
- MATLAB에서 주요 entry 파일이 파싱 가능
- 인코딩/줄바꿈 위험 제거
- git commit 후 git push 완료


============================================================
Phase 3.5a — Embedded Session Lifecycle Stabilization
============================================================

목표:
Embedded Dashboard의 session lifecycle을 명확히 하고, active/inactive/closing/disposed 상태를 안전하게 관리한다.

작업:
1. FlightDataDashboard에 session lifecycle 상태를 명확히 정리
2. IsEmbedded, ActiveSessionId, RootContainer, closing/disposed 상태 검사 강화
3. isActiveSession()이 standalone/embedded에서 일관되게 동작하는지 검증
4. tab 전환 시 SessionScope active id 갱신 안정화
5. 닫힌 dashboard가 event/callback에 반응하지 않도록 guard 추가
6. WorkspaceManager의 add/remove/select tab 흐름 점검
7. removeDashboardTab 후 DashboardMap, TabMap, ProjectModel 상태 동기화 확인

검증:
- Studio 실행
- Session 2개 생성
- 탭 전환
- 탭 삭제
- 삭제된 session callback 미동작 확인

완료 조건:
- session lifecycle 누수 방지
- git commit 후 git push 완료


============================================================
Phase 3.5b — StudioMouseRouter Stabilization
============================================================

목표:
Embedded mode에서 UIFigure의 WindowButtonMotionFcn / WindowButtonUpFcn 소유자를 StudioMouseRouter 하나로 고정한다.

작업:
1. MarkerDragController, PannerController, DragController의 embedded mode 직접 figure callback fallback 제거
2. embedded mode에서 router lock 실패 시 drag 시작 취소
3. standalone mode에서는 기존 direct callback 유지
4. StudioMouseRouter의 drag lock / release / tab mismatch 처리 검증
5. drag 중 tab 전환 시 motion suppress 확인
6. mouse up 누락 상황에서도 lock release 되도록 예외 처리 강화

검증:
- Session A marker drag
- drag 중 Session B 탭 전환
- Session B에서 marker/pan 정상 동작
- Session A 삭제 후 callback 누수 없음

완료 조건:
- Embedded mode figure-level callback 단일 소유 보장
- git commit 후 git push 완료


============================================================
Phase 3.5c — Cleanup Scope Separation
============================================================

목표:
tab close와 studio close의 cleanup 범위를 분리한다.

작업:
1. tab close에서는 해당 session 리소스만 정리
2. tab close에서 parpool 전체 delete 금지
3. studio close에서만 global worker cleanup 수행
4. AsyncFutures cancel 범위를 session 단위로 제한
5. VideoReader/cache/frame buffer/session UI 리소스 해제 순서 정리
6. delete 중 예외가 발생해도 나머지 cleanup이 계속 진행되도록 보호

검증:
- Session 2개 생성
- Session A 비디오 작업 후 탭 닫기
- Session B playback/plot 동작 유지 확인
- Studio close 시 global cleanup 확인

완료 조건:
- tab close가 다른 session에 영향 없음
- git commit 후 git push 완료


============================================================
Phase 3.5d — Embedded Resize / Layout Refresh
============================================================

목표:
Studio resize, tab activation, dock width 변경 시 active dashboard layout이 안정적으로 갱신되도록 한다.

작업:
1. FlightDataDashboard에 refreshLayout(reason) public method 추가 또는 보완
2. WorkspaceManager tab activation 시 active dashboard refreshLayout 호출
3. Studio UIFigure resize 시 active dashboard refreshLayout 호출
4. RightDock/Explorer show-hide 또는 width 변경 시 refreshLayout 호출
5. MATLAB Online / 작은 화면에서 layout 예외 방지
6. refreshLayout 호출 과다 방지를 위해 throttle 적용

검증:
- Studio 창 크기 변경
- tab 전환
- Explorer/RightDock 표시 변경
- FHD 및 작은 화면 기준 UI 깨짐 최소화 확인

완료 조건:
- Embedded layout refresh 경로 확정
- git commit 후 git push 완료


============================================================
Phase 4a — EventBus Compatibility Layer
============================================================

목표:
기존 EventBus API를 깨지 않으면서 session-aware event envelope를 도입한다.

작업:
1. AppEventData SessionId 사용 흐름 점검
2. EventBus에 publishSession 또는 동등한 helper 추가
3. EventBus에 publishGlobal 또는 명시적 broadcast helper 추가
4. legacy publish는 유지하되 내부적으로 안전한 default 처리
5. SessionId 빈 값이 무분별한 broadcast가 되지 않도록 정책 정리
6. 기존 subscribe 동작은 유지

검증:
- 기존 single-session FlightDataDashboard 동작 유지
- Studio embedded session event 충돌 없음
- legacy event가 치명 오류 없이 동작

완료 조건:
- backward compatibility 유지
- session-aware publish 경로 추가
- git commit 후 git push 완료


============================================================
Phase 4b — Scoped Subscribe Migration
============================================================

목표:
모든 listener에 수동 guard를 반복하지 않고 session scoped subscribe 구조로 점진 전환한다.

작업:
1. EventBus에 subscribeSession wrapper 추가
2. EventBus에 subscribeGlobal wrapper 추가
3. 주요 controller부터 subscribeSession으로 전환
4. listener delete/dispose 시 등록 해제 또는 handle cleanup 확인
5. closed dashboard listener가 호출되지 않도록 검증
6. 수동 guard 중복은 필요한 곳만 유지

검증:
- Session 2개 생성
- 각 session에서 다른 이벤트 발생
- active session만 반응
- tab close 후 listener 누수 없음

완료 조건:
- 주요 controller scoped subscribe 전환
- git commit 후 git push 완료


============================================================
Phase 5 — Project Explorer / Object Manager MVP Stabilization
============================================================

목표:
Project Explorer와 Object Manager를 OriginPro식 완성형이 아니라 MVP 수준으로 안정화한다.

작업:
1. Project Explorer tree refresh 안정화
2. session add/rename/duplicate/delete 동작 검증
3. openProject 후 session tree와 workspace tab 복원 흐름 보완
4. Object Manager는 표시/숨김, 단일 선택, Inspector 연동까지만 구현
5. drag/drop reorder, inline checkbox, 다중 스타일 편집은 구현하지 않음
6. 선택 객체가 삭제된 경우 Inspector/Object Manager 예외 방지

검증:
- session 생성/삭제/복제/이름변경
- tree selection → workspace activation
- graphics object selection → inspector 표시
- object visible toggle

완료 조건:
- Project Explorer / Object Manager MVP 안정화
- git commit 후 git push 완료


============================================================
Phase 6a — Toolbar / Menu Active Session Routing
============================================================

목표:
Toolbar와 Menu 명령이 항상 active session 또는 global command로 정확히 라우팅되도록 한다.

작업:
1. command를 GlobalCommand와 SessionCommand로 구분
2. Toolbar 버튼이 active dashboard command를 호출하도록 정리
3. Menu 항목도 동일 routing 사용
4. active session이 없을 때 비활성화 또는 안내 처리
5. placeholder command는 명확히 no-op 처리
6. command 실행 중 예외는 status bar에 짧게 표시

검증:
- session 없는 상태 command
- session 2개 상태 command
- tab 전환 후 toolbar/menu command 대상 확인

완료 조건:
- Toolbar/Menu active session routing 안정화
- git commit 후 git push 완료

추가작업 : 
- verifyPhase6.m 업데이트 검토 및 필요시 코드 수정
############################################################
done
############################################################
============================================================
Phase 6b — Inspector MVP
============================================================

목표:
Inspector에서 선택된 객체의 주요 속성을 안전하게 표시/수정한다.

작업:
1. selected object handle 유효성 검사
2. Visible, DisplayName, LineWidth, Color 등 안전 속성만 MVP로 처리
3. 속성이 없는 객체는 읽기 전용 또는 미지원 표시
4. Object Manager 선택과 Inspector 표시 동기화
5. 잘못된 handle, 삭제된 객체, 빈 선택 예외 방지
6. 대량 객체 스타일 편집은 제외

검증:
- plot line 선택
- axes 선택
- panel/video/info object 선택
- visible toggle
- 삭제된 객체 선택 시 예외 없음

완료 조건:
- Inspector MVP 안정화
- git commit 후 git push 완료

추가작업 : 
- verifyPhase6.m 업데이트 검토 및 필요시 코드 수정
############################################################
done
############################################################
============================================================
Phase 6c — GUI Mode / Preferences MVP
============================================================

목표:
GUI mode를 전체 재구성이 아닌 visibility profile 중심으로 최소 구현한다.

작업:
1. ProjectModel.GuiMode 필드와 UI 상태 연결
2. Classic / Studio / Review / Analysis mode의 visibility profile 정의
3. mode 변경 시 toolbar/dock/explorer visibility만 안전하게 조정
4. 모든 mode에서 active dashboard 동작 유지
5. Preferences 메뉴와 상태 저장 흐름 최소 연결

검증:
- mode 전환
- session 유지
- layout refresh 정상
- 저장/로드 후 mode 복원 가능 여부 확인

완료 조건:
- GUI Mode MVP 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase6.m 업데이트 검토 및 필요시 코드 수정
############################################################
done
############################################################
============================================================
Phase 7 — Analysis Service / Result Model Integration
============================================================

목표:
AnalysisDialog를 무리하게 확장하지 않고, AnalysisService 중심으로 ROI 분석 결과를 ReviewResultModel에 연결한다.

작업:
1. AnalysisService 신설
2. RoiAnalyzer 기존 계산 엔진 재사용
3. RoiStatisticsAnalyzer가 필요하면 thin facade로만 구현
4. AnalysisRequest / AnalysisResult 구조 최소 정의
5. AnalysisResult를 ReviewResultModel로 변환
6. ProjectModel.Results에 등록
7. AnalysisThemeModel과 기본 preset 연결

검증:
- ROI 하나 선택
- 수동 분석 실행
- ReviewResultModel 생성
- Project Explorer results에 반영
- 저장/로드 metadata 유지

완료 조건:
- ROI 분석 결과가 ResultModel로 저장됨
- git commit 후 git push 완료

추가작업 : 
- verifyPhase7.m 코드 신규 작성
############################################################
done
############################################################
============================================================
Phase 8a — Dirty Flag / Stale Warning
============================================================

목표:
자동 재계산 전에 dirty/stale 표시만 안정적으로 구현한다.

작업:
1. DirtyTracker 최소 skeleton 추가
2. ROI 변경 시 관련 ReviewResultModel DirtyState=Stale 처리
3. Inspector 또는 Object Manager에 stale 상태 표시
4. 자동 재계산은 하지 않음
5. Frozen 결과는 stale warning만 표시
6. dirty propagation은 단순 1-depth만 우선 처리

검증:
- ROI 변경
- result stale 표시
- frozen result stale 표시
- 저장/로드 후 dirty state 유지

완료 조건:
- stale warning MVP 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase8.m 코드 신규 작성

============================================================
Phase 8b — Manual Recalculate
============================================================

목표:
사용자 명령으로 stale result를 수동 재계산한다.

작업:
1. Recalculate Selected 구현
2. Recalculate All Stale 구현
3. AnalysisService를 통해 재계산
4. 성공 시 DirtyState=Clean
5. 실패 시 DirtyState=Error 및 LastError 저장
6. 자동 재계산은 아직 제외

검증:
- stale result 선택 재계산
- stale result 전체 재계산
- 실패 케이스 error state 처리

완료 조건:
- manual recalculate 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase8.m 업데이트 검토 및 필요시 코드 수정

============================================================
Phase 8c — Auto Recalculate MVP
============================================================

목표:
의존성 없는 ROI 통계 result에 한해 auto recalculate를 구현한다.

작업:
1. Auto mode result만 대상
2. ROI 변경 이벤트 debounce 적용
3. background queue 또는 timer 기반으로 재계산
4. Result dependency DAG는 아직 제외
5. active session 우선 처리
6. 비활성 session 과도한 재계산 방지

검증:
- ROI 연속 변경
- debounce 동작
- auto result만 재계산
- manual/frozen result는 자동 제외

완료 조건:
- auto recalculate MVP 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase8.m 업데이트 검토 및 필요시 코드 수정

============================================================
Phase 9a — Project Save / Load Metadata Stabilization
============================================================

목표:
현재 ProjectSerializer v1 metadata save/load를 안정화한다.

작업:
1. saveProject / saveProjectAs / openProject 흐름 점검
2. openProject 후 Project Explorer 갱신
3. openProject 후 session tab metadata 복원
4. external link missing file 처리
5. schema version 검사 강화
6. serializer round-trip test 보완

검증:
- 새 프로젝트 저장
- 열기
- session metadata 복원
- missing external file warning
- 다시 저장

완료 조건:
- metadata save/load 안정화
- git commit 후 git push 완료

추가작업 : 
- verifyPhase9.m 업데이트 검토 및 필요시 코드 수정

============================================================
Phase 9b — Lazy Load Session
============================================================

목표:
프로젝트 로드 시 모든 비디오/로그를 즉시 로드하지 않고 metadata만 먼저 복원한다.

작업:
1. SessionModel.LoadState 추가 또는 보완
2. MetadataLoaded / DataLoaded / Active 상태 구분
3. workspace tab 생성은 metadata 기반
4. tab activation 시 필요한 데이터만 로드
5. missing file이면 session 유지하되 warning 표시
6. 대량 session 프로젝트에서 초기 로드 비용 최소화

검증:
- session 여러 개 포함 project load
- active tab만 data load
- missing file session 유지
- 저장/로드 반복

완료 조건:
- lazy load MVP 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase9.m 업데이트 검토 및 필요시 코드 수정

============================================================
Phase 9c — Pack Project Policy
============================================================

목표:
external assets 처리 정책을 명확히 하고 Pack Project MVP를 설계/부분 구현한다.

작업:
1. Reference / Relative / Packed mode 정책 확정
2. 대용량 video는 기본 reference 유지
3. log file은 packed copy 옵션 제공
4. manifest에 asset mode 기록
5. Pack Project 메뉴는 MVP 범위만 구현
6. 실패 시 원본 project 손상 방지

검증:
- reference mode 저장
- relative path 저장
- log asset packed copy
- load 시 path resolve

완료 조건:
- asset policy MVP 반영
- git commit 후 git push 완료

추가작업 : 
- verifyPhase9.m 업데이트 검토 및 필요시 코드 수정


============================================================
Phase 10a — SharedDecodeService Prototype
============================================================

목표:
기존 per-dashboard async decode를 즉시 전면 교체하지 말고 service prototype을 만든다.

작업:
1. SharedDecodeService skeleton 추가
2. requestFrame(sessionId, videoId, frameNo, priority, generation) 인터페이스 정의
3. cancelSession(sessionId) 구현
4. setActiveSession(sessionId) 구현
5. 완료 future 결과가 session/generation/latest 조건 불일치 시 폐기되도록 구현
6. 기존 LatestFrameOnlyPolicy 개념을 service로 이동 가능한 구조 검토

검증:
- 2개 session 빠른 scrubbing prototype
- cancel 후 늦게 도착한 frame 폐기
- active session priority 기본 동작

완료 조건:
- SharedDecodeService prototype 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase10.m 신규 코드 작성

============================================================
Phase 10b — SharedCacheService Prototype
============================================================

목표:
session-aware frame cache service prototype을 만든다.

작업:
1. SharedCacheService skeleton 추가
2. key = sessionId + videoId + frameNo 구조 사용
3. LRU eviction 구현
4. active session cache 우선 유지
5. session close 시 해당 session cache만 evict
6. memory limit 설정 가능하게 구성

검증:
- session별 cache 분리
- session close cache evict
- active session frame 유지
- memory limit 초과 시 LRU 동작

완료 조건:
- SharedCacheService prototype 구현
- git commit 후 git push 완료

추가작업 : 
- verifyPhase10.m 업데이트 검토 및 필요시 코드 수정

============================================================
Phase 10c — Shared Decode / Cache Integration
============================================================

목표:
prototype을 기존 dashboard async decode 경로에 점진 통합한다.

작업:
1. 기존 per-dashboard decode 경로 유지하며 feature flag 추가
2. SharedDecodeService 사용 경로 추가
3. SharedCacheService 사용 경로 추가
4. fallback 경로 유지
5. parpool one-owner policy 정리
6. Studio close에서만 shared service shutdown
7. tab close에서는 해당 session cancel/evict만 수행

검증:
- feature flag off 기존 동작
- feature flag on shared service 동작
- session 2개 동시 scrubbing
- tab close 후 다른 session 유지
- studio close cleanup

완료 조건:
- shared decode/cache 선택적 통합
- git commit 후 git push 완료


최종 작업 방식:
1. 한 번에 하나의 Phase만 수행
2. Phase 시작 전 현재 상태를 짧게 점검
3. 코드 수정은 직접 수행
4. 검증 수행
5. git commit
6. git push
7. 응답은 “Phase X 완료 및 push 완료” 또는 실패 원인 1줄만 출력
```

추가작업 : 
- verifyPhase10.m 업데이트 검토 및 필요시 코드 수정
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================

results = flightdash.studio.diag.verifyPhase7();

=== Phase 7 verification: Analysis Service / ROI Results ===

Progress is printed before and after each check.

[P7-1] START 1/8 - Phase7Classes
[P7-1] PASS            0.06s - Analysis service, ROI facade, and result/theme models resolved
[P7-2] START 2/8 - Default Theme
[P7-2] PASS            0.10s - Default ROI statistics AnalysisThemeModel is created once
[P7-3] START 3/8 - Single Roi Analysis
[P7-3] PASS            0.19s - Single ROI analyzed: Roll=4, RMSE=RMSE 1.2247
[P7-4] START 4/8 - Review Result Conversion
[P7-4] PASS            0.04s - ReviewResultModel created: R_20260509232006996_000005
[P7-5] START 5/8 - Project Registration
[P7-5] PASS            0.05s - ProjectModel registers ROI ReviewResultModel and default theme
[P7-6] START 6/8 - Serializer Round Trip
[P7-6] PASS            0.39s - ProjectSerializer round-trips ROI ReviewResultModel metadata
[P7-7] START 7/8 - Project Explorer Result Node
[P7-7] PASS            4.83s - Project Explorer shows ROI ReviewResultModel under results
[P7-8] START 8/8 - Dashboard Wiring Methods
[P7-8] FAIL            0.18s - Missing Dashboard or ROI controller registration hook

TC      Result          Message
------  --------------  -------
P7-1    PASS            Analysis service, ROI facade, and result/theme models resolved
P7-2    PASS            Default ROI statistics AnalysisThemeModel is created once
P7-3    PASS            Single ROI analyzed: Roll=4, RMSE=RMSE 1.2247
P7-4    PASS            ReviewResultModel created: R_20260509232006996_000005
P7-5    PASS            ProjectModel registers ROI ReviewResultModel and default theme
P7-6    PASS            ProjectSerializer round-trips ROI ReviewResultModel metadata
P7-7    PASS            Project Explorer shows ROI ReviewResultModel under results
P7-8    FAIL            Missing Dashboard or ROI controller registration hook

7 / 8 Phase 7 checks passed.
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
아래는 **ChatGPT/Codex/Cowork에 그대로 붙여넣기 좋은 영어 프롬프트**입니다. 이전 검토 기준과 업로드된 전환 계획서의 리스크 항목을 반영했습니다. 

```text
You are acting as a senior MATLAB application architect and code reviewer.

Repository:
https://github.com/kiki-github2019/flight-dashboard

Task:
Please access and analyze the current repository state. Review whether the implementation of Phase 1 through Phase 6 and Phase 9 has been completed correctly according to the FlightDataReviewStudio transition plan. Phase 7 and Phase 8 are not supposed to be started yet, so only check whether there are premature or partial implementations that may affect future work.

Important context:
The project is a MATLAB-based FlightDataDashboard application being migrated into an OriginPro-like integrated review studio called FlightDataReviewStudio. The goal is to support a project-based multi-session GUI with embedded dashboards, project/session models, explorer/object manager, toolbar/menu/inspector, and project save/load.

Please perform a careful static code review. If possible, also identify likely runtime risks, MATLAB UI limitations, race conditions, serialization issues, and missing tests.

Review scope:

1. Phase 1 — Studio Shell
Check whether:
- `FlightReviewStudio.m` exists as the root entry point.
- The actual implementation is separated into something like `+flightdash/+studio/FlightReviewStudioApp.m`.
- The shell creates a main `uifigure`, header, project explorer area, workspace area, right dock/inspector area, and status bar.
- The entry/implementation separation is clearly documented.
- Phase 1 remains mostly a shell and does not overreach into heavy real-time status wiring.

2. Phase 2 — Project / Session Model
Check whether:
- Project/session/result/theme/figure models exist under `+flightdash/+project`.
- `ProjectModel` has fields such as `SchemaVersion`, `ProjectId`, `Sessions`, `Figures`, `Results`, `AnalysisThemes`, `GuiMode`, `AutoUpdateMode`, and `DirtyFlag`.
- `SessionModel` has fields such as `SessionId`, file paths, sync states, plot/ROI state, hashes, auto-update mode, and dirty flags.
- The model classes are safe for serialization, preferably value-style or with explicit `saveobj/loadobj`.
- Schema versioning and migration readiness are present.
- Any missing dirty dependency graph / hash strategy / lazy-load strategy is identified.

3. Phase 3 — Embedded FlightDataDashboard
Check whether:
- `FlightDataDashboard` can be constructed with a parent container and session id, e.g. `FlightDataDashboard(parentContainer, sessionId)`.
- Standalone mode and embedded mode are clearly separated.
- The code avoids assuming that `app.UIFigure` is always the root layout parent.
- `RootContainer` or equivalent abstraction is used.
- `WorkspaceManager` or equivalent can create dashboard tabs and embed dashboard instances.
- Deleting a tab/session does not incorrectly trigger global cleanup such as deleting the parpool or closing all unrelated resources.
- Figure-level callbacks such as `WindowButtonMotionFcn`, `WindowButtonDownFcn`, marker drag, panner, splitter drag, and controller callbacks are safely gated by active session.
- Multi-instance risks are identified.

4. Phase 4 — Event Scope / Session Router
Check whether:
- EventBus messages include or can infer `SessionId`.
- Embedded dashboards ignore events for non-active or non-owned sessions.
- There is a helper such as `isActiveSession`, `SessionScope`, or equivalent.
- Legacy events without `SessionId` are handled safely.
- Throttle keys are session-scoped, for example by prefixing with `SessionId`.
- There are no obvious cross-tab event leaks, zombie listeners, or stale callbacks.
- Recommend stronger listener/session guard patterns if needed.

5. Phase 5 — Project Explorer / Object Manager
Check whether:
- A project explorer panel exists and can show project/session/theme/result structure.
- It is wired to the project model and active workspace/session.
- It supports or plans for context menu actions such as create, rename, delete, select, or open.
- MATLAB `uitree` limitations are acknowledged.
- Object Manager functionality is actually implemented or only partially present.
- Clearly separate Project Explorer responsibilities from Object Manager responsibilities.
- Identify missing support for active dashboard internal objects such as axes, plots, ROIs, markers, video panels, and result objects.

6. Phase 6 — Toolbar / Menu / Inspector / Mini Toolbar / GUI Mode / Status Bar
Check whether:
- Toolbar and menu managers exist and route commands to the active session.
- GUI modes such as Studio, Review, Analysis, Plot, Report, Compact, or Classic exist.
- The right dock or inspector exists.
- Mini Toolbar is implemented or intentionally deferred/simplified.
- Status bar is wired to real data or still mostly placeholder.
- Active session changes update toolbar, inspector, explorer, workspace, and status bar consistently.
- Identify incomplete wiring, selection-model gaps, or overly broad Phase 6 responsibilities.

7. Phase 7 & Phase 8(Not Yet Started)
7.1 Phase 7
- If fields already exist for future use, check whether they are harmless placeholders or partially wired logic that may cause bugs.
7.2 phase 8(Not Yet Started)
Verify that:
- Analysis Dialog, Analysis Theme, Result Model, Auto Update, Recalculate, Dirty DAG, and dependency graph features are not prematurely implemented in a fragile way.


8. Phase 9 — Project Save / Load
Check whether:
- `.frsproj` save/load exists.
- The project file format is zip + manifest + JSON/assets or similar.
- `ProjectSerializer` or equivalent exists.
- Save/load round-trip can preserve project metadata, sessions, file paths, sync state, themes, GUI mode, and active sessions.
- It avoids the common MATLAB `zip()` issue where the file becomes `.frsproj.zip` instead of `.frsproj`.
- It handles Windows paths, Korean/non-ASCII paths, missing external files, and temp folder cleanup.
- It clearly distinguishes linked project mode from packed project mode.
- Identify whether raw flight data/video files are copied into the project or only referenced externally.
- Recommend improvements for Pack Project, relative path repair, lazy loading, and schema migration.

Please produce the review in the following structure:

A. Executive Summary
- Overall implementation status.
- Phase-by-phase completion table.
- Main conclusion: what is safe, what is risky, and whether Phase 7/8 should be delayed.

B. Phase-by-Phase Findings
For each phase, include:
- Implementation evidence: files/classes/functions found.
- What is implemented well.
- What is incomplete or risky.
- Specific bugs or edge cases.
- Recommended fixes.

C. High-Risk Technical Areas
Please deeply review:
- Embedded MATLAB UI architecture.
- Figure-level callback conflicts.
- Session routing and EventBus scoping.
- Multi-dashboard race conditions.
- Async decode cleanup and parfeval cancellation.
- Singleton/shared services such as throttle/cache.
- Save/load serialization reliability.
- Status bar and inspector active-session synchronization.

D. Bug and Exception Handling Review
Identify:
- Likely runtime errors.
- Missing `try/catch` or overly broad `try/catch`.
- Resource leaks.
- Invalid handle risks.
- Deleted tab/session access risks.
- Missing file/path handling.
- Non-ASCII path issues.
- MATLAB version compatibility issues.

E. Test Recommendations
Provide concrete tests, preferably named test cases, for:
- Phase 1 shell creation.
- Phase 2 model round-trip.
- Phase 3 embedded dashboard tab creation/deletion.
- Phase 4 cross-session event isolation.
- Phase 5 explorer refresh and selection.
- Phase 6 GUI mode/status bar/inspector routing.
- Phase 9 save/load round-trip.
- Multi-session stress test.
- Missing external file recovery.
- `.frsproj` vs `.frsproj.zip` save behavior.

F. Prioritized Fix Plan
Provide:
- P0 critical fixes before Phase 7/8.
- P1 important architectural cleanup.
- P2 usability and maintainability improvements.
- Recommended split of Phase 5/6/9 if needed.

Important constraints:
- Do not modify the repository unless explicitly asked.
- Do not assume Phase 7/8 are complete.
- Do not only check file existence; inspect whether the implementation is actually robust.
- Be strict about MATLAB UI limitations.
- Be strict about multi-session embedded mode.
- Be strict about project serialization.
- If something cannot be verified statically, clearly mark it as “requires MATLAB runtime verification.”
- Include concrete file names, class names, and function names whenever possible.
```
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================

---

**주요 결론:** Phase 1-3 및 Phase 9는 추가적인 안정화 작업을 진행하기에 충분히 안전하지만, 이미 시작된 Phase 7은 Phase 1-6 및 Phase 9의 검증이 깔끔하게 완료될 때까지 동결(freeze)되어야 합니다. Phase 8은 계속 보류 상태를 유지해야 합니다.

**B. 단계별(Phase) 확인 사항**

* **Phase 1 증거:** `FlightReviewStudio.m`(1번째 줄)이 `FlightReviewStudioApp.m`(1번째 줄)을 실행합니다. `buildShell()`은 uifigure, 헤더, 본문, 탐색기(explorer), 작업 공간(workspace), 우측 도크(right dock), 상태 표시줄을 생성합니다. 분리가 잘 되어 있습니다. **위험 요소:** 진입부 주석에 아직 Phase 2/3 연결이 없다고 되어 있으나, 현재는 사실이 아닙니다.
* **Phase 2 증거:** `ProjectModel.m`(15번째 줄), `SessionModel.m`(9번째 줄), `FigureModel`, `ReviewResultModel`, `AnalysisThemeModel`. **긍정적 요소:** 값(value) 클래스, `SchemaVersion`, CRUD, `FlightFiles`와 같은 호환성 별칭(alias)이 존재합니다. **미완성 요소:** 스키마 마이그레이션 함수 부재, 지연 로드(lazy-load) 관리자 부재, 해시가 임시값(placeholder)으로 설정됨(`LastDataHash`, `LastSyncHash`), 의존성 그래프 부재.
* **Phase 3 증거:** `FlightDataDashboard.m`(137번째 줄)이 `(parentContainer, sessionId)`를 허용하고 `RootContainer`를 사용하며, `WorkspaceManager.m`(44번째 줄)이 대시보드를 `uitab`에 임베드합니다. **긍정적 요소:** 임베디드 삭제 시 UIFigure/parpool이 삭제되는 것을 방지합니다. **위험 요소:** 임베디드 UI가 여전히 호스트의 `UIFigure.CurrentPoint`를 사용합니다. 이는 MATLAB에서 예상된 동작이긴 하지만, 활성 탭(active-tab)에 대한 스트레스 테스트가 필요합니다.
* **Phase 4 증거:** `AppEventData.m`(19번째 줄)에 `SessionId`가 포함되어 있습니다; `FlightDataDashboard.isActiveSession()`이 이벤트를 제어합니다; `SessionScope.m`(21번째 줄)이 활성 탭을 추적합니다. **긍정적 요소:** 컨트롤러들이 대부분 `isActiveSession`을 호출합니다. **위험 요소:** 많은 뷰 퍼블리셔(view publishers)가 여전히 `SessionId` 없이 `AppEventData(fIdx, payload)`를 생성하고 있어, 전역 활성 세션에 정확성을 의존하고 있습니다.
* **Phase 5 증거:** `ProjectExplorerPanel.m`(27번째 줄)이 세션/테마/결과를 재구성합니다; 컨텍스트 메뉴에 추가/이름 변경/복제/삭제 임시 로직 및 핸들러가 있습니다. `RightDockManager.m`(266번째 줄)이 선택된 대시보드 UI로부터 Object Manager를 빌드합니다. 훌륭한 MVP(최소 기능 제품)입니다. **미완성 요소:** 객체 트리(object tree)가 전체 플롯/ROI/마커/결과 계층구조가 아닌 선택된 정적 핸들(static handles)만 커버합니다.
* **Phase 6 증거:** `CommandRouter.m`(17번째 줄)이 전역/세션 명령을 라우팅합니다; `ToolbarManager.m`(1번째 줄)과 `MenuManager.m`(1번째 줄)이 라우터를 공유합니다. Inspector가 `Visible`, `DisplayName`, `LineWidth`, `Color`를 안전하게 편집합니다. `applyGuiMode` 내에 GUI 모드들이 존재합니다. 미니 툴바는 Inspector의 퀵 로우(quick row) 형태로 단순화되었습니다. 상태 표시줄은 여전히 대부분 정적 라벨(static labels)입니다.
* **Phase 7/8 증거:** Phase 7은 단순한 임시 로직이 아닙니다. `+flightdash/+analysis/AnalysisService.m`, `RoiStatisticsAnalyzer.m`, ROI 컨트롤러 등록, 프로젝트 결과 직렬화, `verifyPhase7.m` 등이 존재합니다. 이는 기능적으로 작동하는 초기 작업물이므로 동결(freeze)해야 합니다. Phase 8은 `DependsOn`, `DirtyState`, `RecalculateMode` 등의 필드를 가지고 있으나, 실제 `DirtyTracker` 구현체는 없습니다.
* **Phase 9 증거:** `ProjectSerializer.m`(30번째 줄)이 `project.json`, `sessions/*`, `themes/*`, `results/*`, `external_links.json`, `manifest.json`을 작성합니다. `writeZipToTarget()`은 임시 zip/스테이징/백업을 사용하고 최종 `.frsproj`를 확인합니다. 좋습니다. **미완성 요소:** 링크 모드(linked mode)만 지원됩니다; Pack Project(프로젝트 패키징), 상대 경로 복구, 파일 재배치 또는 마이그레이션 기능이 없습니다.

**C. 고위험 영역 (High-Risk Areas)**

* 가장 위험이 큰 부분은 임베디드 마우스 처리입니다. `StudioMouseRouter.m`(41번째 줄)이 `WindowButtonMotionFcn/UpFcn`을 소유하고 있으며, 마커/패너(panner)/스플리터(splitter) 경로는 이제 드래그 락(drag locks)을 요청합니다. 이는 올바른 MATLAB 아키텍처입니다. 단, 드래그 도중에 탭을 전환하거나 닫을 때 런타임 위험이 남아 있습니다.
* 두 번째 위험 요소는 이벤트 스코핑(Event scoping)입니다. `CommandRouter`는 `SessionId`를 주입하지만, 뷰(view) 레벨의 UI 콜백들은 종종 이를 주입하지 않습니다. 이는 모든 리스너가 `isActiveSession()` 가드(guards)를 유지한다는 전제하에서만 MVP 수준에서 허용될 수 있습니다.
* 비동기 디코드(Async decode) 정리 로직이 개선되었지만 여전히 경쟁 상태(race condition)에 취약합니다. 임베디드 삭제 시 세션의 future들을 취소하며, Studio 종료 시 전역 정리가 실행됩니다. `parfeval` 취소 시 여전히 지연된 결과(late results)가 반환될 수 있으므로 생성 확인(generation checks) 로직은 필수적으로 유지되어야 합니다.
* 직렬화기(Serializer)는 훨씬 안전해졌지만, 비-ASCII Windows 경로 및 MATLAB의 zip/unzip 동작에 대해 MATLAB Online 및 Windows 환경에서의 검증이 필요합니다.

**D. 버그 / 예외 발생 위험**

발생 가능성이 높은 런타임 위험 요소들:

* 대시보드 새로고침/삭제 후 Object Manager에 남은 만료된 그래픽 핸들(stale graphics handles).
* 전역 `SessionScope`를 통해 동작하는 숨겨진 탭 콜백이나 타이머.
* 깨진 UI 상태를 은폐하는 광범위하고 빈 `catch` 블록들.
* `VideoPanel.publishSliderChanging()`이 선택적인(optional) sessionId로 스로틀링(throttle)을 수행하지만, 실제 이벤트 발행(publish) 시에는 이를 누락함.
* Phase 6 및 Phase 9의 안정화가 완전히 검증되기 전에, ROI 분석 중에 Phase 7의 결과 등록이 프로젝트 변경을 유발할 수 있음.
* 소스 주석/문서에서 셸 출력 시 글깨짐(mojibake) 가능성이 보임. `verifyPhase0_5()` 및 MATLAB 에디터에서 인코딩 확인이 필요함.

**E. 테스트 권장 사항**

다음 이름의 테스트들을 실행하고 유지할 것:

* `T1_Shell_CreateDelete`: FlightReviewStudio, 매니저 검증, 깔끔한 삭제.
* `T2_Model_RoundTrip`: 2개의 세션, 테마, 피규어(figure), 결과를 직렬화기를 통해 왕복 처리하는 프로젝트.
* `T3_Embedded_AddRemove`: 3개의 대시보드 탭을 반복적으로 추가/제거 (추가적인 uifigure 없음).
* `T4_Event_Isolation`: 2개의 탭에서 세션 범위(session-scoped) 및 레거시 브로드캐스트를 발행.
* `T5_Explorer_Selection`: 트리 세션 선택 시 작업 공간 및 상태 표시줄 활성화 확인.
* `T6_Inspector_InvalidHandles`: 선/축/패널/삭제된 핸들 선택 및 표시(visible) 토글 검증.
* `T6_GuiMode_Persist`: 모드 전환, 저장/불러오기, GuiMode 및 레이아웃 새로고침 검증.
* `T9_Save_Extension`: `temp.frsproj`를 저장하고, `temp.frsproj.zip` 파일이 생기지 않는지 확인(assert).
* `T9_NonAscii_Path`: 한국어 경로 환경에서 저장 및 불러오기.
* `T9_Missing_External`: 비디오/데이터 파일이 누락된 프로젝트를 충돌(crash) 없이 불러오기.
* `TStress_MultiSession_Scrub`: 2개의 세션 동시 실행, 재생/스크러빙/드래그, 비동기 디코드 도중 탭 닫기.

**F. 우선순위 기반 수정 계획 (Prioritized Fix Plan)**

* **P0 (Phase 7/8 진행 전 필수):** `verifyPhase1/2/3/4/5/6/9`에 대한 MATLAB 검증, 다중 인스턴스 테스트, 비-ASCII 환경 저장/불러오기, 드래그 중 탭 닫기, 그리고 만료된 핸들(stale-handle) Inspector 테스트 실행.
* **P1:** `EventBus`의 세션 태깅(tagging)을 특히 뷰 퍼블리셔(view publishers) 수준에서 더 엄격하게 강제; 공유 리스너 가드 헬퍼(shared listener guard helper) 추가; 임베디드 모드에서 `WindowButton*Fcn`에 대한 모든 직접적인 수정(writes)을 계속 금지.
* **P2:** 오래된 문서 및 주석 업데이트, `.frsproj`를 링크 모드로 문서화, Pack Project(프로젝트 압축 패키징) 및 상대 경로 복구 기능은 추후 추가로 미루고, Phase 8이 깔끔하게 시작될 때까지 `DirtyTracker` 작업 보류.
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
아래는 **ChatGPT Cowork에 바로 붙여넣기 좋은 영문 프롬프트**입니다.

```text
You are acting as a senior MATLAB application architect and code reviewer.

Please access and review the following GitHub repository:

https://github.com/kiki-github2019/flight-dashboard

The project is a MATLAB-based FlightDataDashboard / FlightDataReviewStudio application. It is being migrated from a standalone dashboard into a project-based integrated GUI inspired by OriginPro-style workflows.

Your task is to perform a rigorous code review against the attached migration plan and verify whether Phase 1 through Phase 9 have been implemented correctly. Phase 10 has not started yet and should only be considered as a future risk area.

Important context:
- The current target is MATLAB R2025a / R2026a compatibility.
- The application is transitioning toward `FlightReviewStudio`.
- The intended architecture includes:
  - Studio shell
  - Project/session models
  - Embedded dashboard sessions
  - Session-scoped events
  - Project Explorer / Object Manager
  - Toolbar / menu / inspector / GUI modes
  - Analysis result plumbing
  - Dirty / recalculation services
  - Project save/load using `.frsproj`
- Phase 10 SharedDecodeService / SharedCacheService is not yet in scope.

Please review the implementation in detail and produce a structured technical assessment.

Review requirements:

1. Repository structure review
   - Identify the main entry points.
   - Identify the current package/module structure.
   - Explain how `FlightReviewStudio.m`, `FlightReviewStudioApp.m`, `FlightDataDashboard.m`, and related studio/project/service classes are organized.
   - Check whether the entry-point separation is clean and maintainable.

2. Phase-by-phase implementation verification
   Review Phase 1 through Phase 9 individually.

   For each phase, provide:
   - Implementation status:
     - Implemented
     - Partially implemented
     - MVP only
     - Not implemented
     - Unclear / needs runtime verification
   - Relevant files/classes/functions
   - Evidence from the code
   - Missing pieces
   - Runtime risks
   - Recommended fixes

   The phases are:

   Phase 1 — Studio Shell
   - Verify whether the Studio shell exists.
   - Check Project Explorer, workspace tabs, right dock / inspector, status bar, toolbar/menu placeholders.
   - Confirm that embedded dashboard sessions can be created from the shell.
   - Check whether placeholder UI and real-data UI are clearly separated.

   Phase 2 — Project / Session Model
   - Review `ProjectModel`, `SessionModel`, `FigureModel`, `ReviewResultModel`, `AnalysisThemeModel`, and related model classes.
   - Check whether the data model supports project/session/figure/result/theme hierarchy.
   - Check whether schema versioning, dirty flags, timestamps, hashes, and model serialization assumptions are reasonable.
   - Identify any handle-class serialization risks.

   Phase 3 — Embedded FlightDataDashboard
   - Verify whether `FlightDataDashboard` can be hosted inside a parent container or tab.
   - Check whether the code avoids hard dependency on a standalone `uifigure`.
   - Identify any remaining figure-level callback risks such as `WindowButtonMotionFcn`, drag/pan/zoom callback leakage, or tab-close race conditions.
   - Check whether cleanup/dispose behavior is correctly separated between session unload and global studio shutdown.
   - Inspect multi-instance risks.

   Phase 4 — Event Scope / Session Router
   - Review `EventBus`, `SessionScope`, router/listener logic, and session tagging.
   - Confirm whether event publishing automatically injects active `SessionId`.
   - Check whether single-session compatibility is preserved.
   - Identify any event leakage between multiple dashboard instances.
   - Identify places where listeners still need session guards.

   Phase 5 — Project Explorer / Object Manager
   - Review Project Explorer and Object Manager MVP implementation.
   - Check whether session/figure/result/theme nodes are represented correctly.
   - Check whether object selection, visibility toggling, refresh behavior, and active-dashboard routing work.
   - Clearly distinguish MVP implementation from full OriginPro-style Object Manager behavior.
   - Identify limitations in MATLAB `uitree` behavior.

   Phase 6 — Toolbar / Menu / Inspector / GUI Mode
   - Review menu manager, toolbar manager, right dock / inspector manager, status bar manager, and GUI mode logic.
   - Check whether mode switching works without destroying state.
   - Verify whether toolbar/menu actions are routed to the active session.
   - Check whether status bar values are real data or placeholders.
   - Identify UI scaling risks, especially for MATLAB Online and small laptop screens.

   Phase 7 — Analysis Dialog / Theme / Result Model
   - Determine whether Phase 7 is truly implemented or only partially implemented.
   - Review any `AnalysisService`, ROI statistics analyzer, result model, theme model, and diagnostic tests.
   - Check whether this is full Analysis Dialog support or only ROI result plumbing.
   - Identify missing dialog UI, theme reuse, input/default serialization, and result persistence issues.

   Phase 8 — Auto Update / Recalculate / Dirty DAG
   - Review `DirtyTracker`, `RecalculateService`, `RecalculateQueue`, or equivalent classes.
   - Determine whether Phase 8 is implemented only as a narrow MVP.
   - Check whether dependency propagation, stale marking, manual/auto/frozen modes, debounce, topological ordering, and error handling are actually implemented.
   - Compare README/status documentation against code and identify any contradictions.
   - Clearly state whether full Dirty DAG / Recalculate UX is still pending.

   Phase 9 — Project Save / Load
   - Review `ProjectSerializer` and `.frsproj` save/load behavior.
   - Verify whether the serializer creates the requested project file correctly and avoids unwanted `.zip` suffix issues.
   - Check round-trip save/load behavior for:
     - Project metadata
     - Sessions
     - Figures
     - Results
     - Analysis themes
     - External links
   - Determine whether the current implementation is linked-project only or packed-project capable.
   - Identify missing asset handling, relink UX, schema migration, and backward/forward compatibility risks.

3. Bug and exception-handling review
   Please look for:
   - Broken constructors
   - Missing arguments
   - Incorrect package paths
   - Invalid MATLAB class references
   - Handle/value class serialization bugs
   - File extension bugs such as `.frsproj.zip`
   - Cleanup errors
   - Async/parfeval cancellation issues
   - UI callback conflicts
   - Missing `isvalid` checks
   - Missing try/catch around UI deletion
   - Race conditions during tab close, project close, and active session switch
   - MATLAB Online compatibility risks
   - MATLAB R2025a/R2026a compatibility risks

4. Diagnostic test review
   Search for and review diagnostic functions such as:
   - `verifyPhase1`
   - `verifyPhase2`
   - `verifyPhase3`
   - `verifyPhase4`
   - `verifyPhase5`
   - `verifyPhase6`
   - `verifyPhase7`
   - `verifyPhase8`
   - `verifyPhase9`
   - `runMultiInstanceTests`

   For each diagnostic test:
   - Explain what it verifies.
   - Identify what it does not verify.
   - Recommend additional test cases.
   - Check whether runtime verification is still required.

5. Documentation consistency review
   Compare the README, phase status documents, and actual code.
   Identify mismatches such as:
   - README says something is deferred, while code has MVP implementation.
   - Status document says implemented, while runtime behavior is not guaranteed.
   - Phase 7/8 scope ambiguity.
   - Phase 9 linked-save/load vs packed-project ambiguity.

6. Output format
   Please produce the review in the following structure:

   A. Executive Summary
   - Overall implementation status
   - Overall risk level
   - Whether Phase 1–9 can be considered complete or only MVP-level

   B. Phase-by-Phase Verdict Table
   Columns:
   - Phase
   - Status
   - Evidence
   - Main risks
   - Required next action

   C. Detailed Findings
   Organize by phase.
   Include file/class names and function names where possible.

   D. Critical Bugs / High-Risk Issues
   Rank by severity:
   - Blocker
   - High
   - Medium
   - Low

   E. Exception Handling / Robustness Issues
   Include UI, file I/O, async, serialization, and cleanup issues.

   F. Test Coverage Gaps
   Include specific MATLAB commands or test scenarios that should be run.

   G. Documentation Corrections
   Suggest exact README/status wording where useful.

   H. Recommended Next Development Plan
   Provide a practical plan before Phase 10:
   - Stabilize Phase 1–6/9
   - Freeze Phase 7 scope
   - Clarify Phase 8 MVP vs full implementation
   - Add missing runtime stress tests
   - Improve linked project save/load warning and relink UX
   - Only then start Phase 10 prototype

7. Important judgment rule
   Do not mark a phase as fully complete just because files exist.
   Judge based on actual integration, runtime behavior, exception handling, and diagnostic coverage.

8. Final expected conclusion
   Please explicitly answer:
   - Are Phase 1–9 implemented?
   - Which phases are MVP only?
   - Which phases require runtime verification?
   - What should be fixed before Phase 10 begins?
```

권장 사용 방식: 위 프롬프트와 함께 **현재 수정계획서 파일**도 ChatGPT Cowork에 첨부하면 됩니다.



=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================

[응답 규칙]
- 전체 코드 출력 금지
- 수정된 코드 출력 금지
- 불필요한 설명 금지 (최대 1줄)
- 기존 코드 반복 출력 금지
- 불필요한 과정 출력 금지
  ex. git push 명령어 출력 등

[코드 작업 규칙]
- 성능 개선 우선
- 메모리 효율 고려
- 예외 처리 고려
- 여러 개선안이 있으면 2개만 제시

[절대 규칙]
- 결과 출력에 토큰사용 최소화
- 코드 작업에 토큰사용 최대화
- 코드 작업 현재 phase 작업 종료시 git push 자동 실행

[Response Rules]
- Do not print the entire code
- Do not print modified code
- Do not provide unnecessary explanations (maximum 1 line)
- Do not repeat existing code
- Do not print unnecessary steps

[Code Work Rules]
- Prioritize performance improvement
- Consider memory efficiency
- Consider exception handling
- If multiple improvement suggestions exist, present only two
- after complete modifying codes, show me message that do git push

[Absolute Rules]
- Minimize token usage for result output
- Maximize token usage for code work

[When creating any Git commit message, always append the current local timestamp at the end of the commit subject line.]

Required timestamp format:
@yyyy-mm-dd HH:MM:SS

Examples:
fix(ui): improve video slider scrubbing @2026-05-15 23:42:10
feat(studio): add default session initialization @2026-05-15 23:42:10
chore(test): update MATLAB verification scripts @2026-05-15 23:42:10

Rules:
1. Every git commit subject must end with the timestamp.
2. Use the current local system time at the moment the commit is created.
3. Keep the timestamp at the very end of the first commit message line.
4. Do not place extra text after the timestamp.
5. Use 24-hour time.
6. Use zero padding for month, day, hour, minute, and second.
7. If creating a multi-line commit message, only the first subject line needs the timestamp.

Before running git commit, generate the timestamp automatically.

For Linux/macOS/Termux/Git Bash:
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
git commit -m "fix(ui): improve video slider scrubbing @$TIMESTAMP"


=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================
=================================================================================================================

https://github.com/kiki-github2019/flight-dashboard


push 전에 원격 저장소가 맞는지 확인하려면:
git remote -v

origin  https://github.com/kiki-github2019/flight-dashboard.git (fetch)
origin  https://github.com/kiki-github2019/flight-dashboard.git (push)


git branch --show-current

main

---------------------------------------------------------------------------------------------------------
cd "D:\flightdashboard\5. 4th\root"

git status

git add .

# "Update phase verification and stabilization fixes"는 할때마다 수정
git commit -m "Update phase verification and stabilization fixes"

git push                                                          # claude/bold-brown-8651c4
git -C 'D:\flightdashboard\5. 4th\root' push origin main          # main


============================================================================================
git clone https://github.com/kiki-github2019/flight-dashboard.git

wget https://github.com/kiki-github2019/flight-dashboard/archive/refs/heads/main.zip

git config --global user.name "kiki-github2019"
git config --global user.email "본인_이메일@주소.com"

git config --global --add safe.directory /storage/emulated/0/Download/flight-dashboard

# 1. 변경된 파일 상태 확인 (수정된 파일이 빨간색으로 표시됨)
git status

# 2. 변경된 모든 파일을 커밋할 준비(Staging) 상태로 올리기
git add .

# 3. 변경 사항 커밋하기
git commit -m "안드로이드 폰에서 코드 수정 및 테스트"

# 4. git update
git push
============================================================================================
# 1. 폰에서 프로젝트 폴더로 이동 (이전 경로 기준)
cd /storage/emulated/0/Download/flight-dashboard

# 2. GitHub 서버에서 최신 코드 당겨오기
git pull
============================================================================================
https://github.dev/kiki-github2019/flight-dashboard.git

=================================================================================================================
=================================================================================================================
================================================================================================================== echo "alias go-codex='proot-distro login ubuntu --bind /storage/emulated/0:/sdcard --shared-tmp -- bash -c "cd /sdcard/Download/flight-dashboard && exec bash"'" >> ~/.bashrc source ~/.bashrc

go-codex

dex-codex-260511

스마트폰이나 PC 브라우저에서 👉 https://github.com/settings/tokens 에 접속합니다.



스마트폰이나 PC 브라우저에서 👉 https://github.com/settings/tokens 에 접속합니다.

다음의 검토결과를 claude code에서 검토하기 적합한 영문 보고서로 변경해서 md 파일로 출력요청합니다.