# MATLAB UI Reality Check: OriginPro 기능별 MATLAB 구현 가능성

**문서 버전:** v1.0 | **작성일:** 2026-05-08 | **Phase:** 0.5 (Phase 1 진입 전 결정사항)

---

## 0. 결론 요약

| 평가 | OriginPro 기능 수 | 비율 |
|---|:---:|:---:|
| ✅ MATLAB에서 동등 구현 가능 | 6 | 38% |
| 🟡 부분 구현 + 합리적 절충 가능 | 7 | 44% |
| 🔴 1차 범위 제외 권장 | 3 | 19% |

**한 줄 요약:** MATLAB uifigure 환경은 OriginPro의 70% 가치를 합리적으로 재현할 수 있으나, **floating dock / 진짜 MDI / 트리 inline checkbox+drag reorder**는 MATLAB의 구조적 한계로 1차 범위에서 제외하거나 대체 UX로 우회해야 한다. **Phase 3 (Embedded화)에서 figure-level WindowButtonMotionFcn 충돌이 가장 큰 기술 부채**이며, 이를 해결하지 못하면 다중 탭 환경에서 drag 동작이 무너진다.

---

## 1. MATLAB 버전 요구사항

### 1.1 현재 코드가 의존하는 최저 버전

| 기능 | 첫 지원 버전 | 사용 위치 |
|---|:---:|---|
| `uifigure` | R2016a | 전반 |
| `uigridlayout` | R2018b | 모든 레이아웃 |
| `axtoolbar` | R2018b | PlotView.m |
| `Axes.Interactions = [panInteraction, zoomInteraction]` | R2018b | PlotView.m, MapAltPanel.m |
| `getpixelposition` (uifigure) | R2018b | ResponsiveLayoutManager |
| `Container.Scrollable = 'on'` | R2020a | InfoPanel.m, plot layout |
| `jsonencode` PrettyPrint | R2020b | ConfigManager.m |
| `parfeval` cancel | R2017a (cancel은 R2020b에서 안정화) | 비디오 디코딩 |
| `WindowState` | R2018a | restoreWindowPosition |

**현재 코드 최저 요구:** **R2020b** (jsonencode PrettyPrint + parfeval cancel 안정화 기준)

### 1.2 Studio 추가 사용 예정 기능

| 기능 | 첫 지원 버전 | 비고 |
|---|:---:|---|
| `uitree` (uifigure context) | R2017b | 노드·아이콘 표시 |
| `uitree` Multi-select | R2020a | Project Explorer 필요 |
| `uistyle` (cell formatting) | R2019b | uitable 강조 표시 |
| `uitable` `RowStriping` | R2017b | 가독성 |
| Toolstrip-like (`uihtml` 기반) | R2021b 권장 | Mini Toolbar 대안 |
| `matfile` (MAT v7.3 부분 로드) | R2009b | 직렬화 |

**Studio 권장 최저 요구:** **R2021b** — uitree Multi-select과 uihtml 안정성 고려

### 1.3 권장 사항

- README 및 ProjectModel 매니페스트에 `MinimumMatlabVersion: "9.11"` (R2021b) 명시
- 주요 함수 진입 시 `verLessThan('matlab', '9.11')` 체크 후 명확한 에러 메시지

---

## 2. OriginPro 기능별 검증

### 2.1 ✅ 동등 구현 가능 (6항목)

#### 2.1.1 MDI 기반 프로젝트 (계획서 §1.1)

**OriginPro:** `.OPJU` 안에 워크북·그래프·이미지 창들

**MATLAB 구현:**
- `uifigure` 1개 + `uitabgroup` 1개 + 각 탭에 panel
- 단점: 진짜 MDI(자유 배치) 불가, **고정 탭 형태**
- 합리적: 비행 리뷰 워크플로우는 보통 1세션 1탭으로 충분

**평가:** 탭 기반으로 충분. 자유 floating은 후순위.

#### 2.1.2 Project Explorer 폴더 트리 (계획서 §1.2)

**OriginPro:** 폴더 트리 + 우클릭 컨텍스트 + 드래그 reorder + 검색

**MATLAB 구현:**
- `uitree` (R2017b+) — 폴더·노드 표시 가능
- `uicontextmenu` — 우클릭 메뉴 가능
- `uitree` 내 검색은 자체 구현 (이름 매칭) 필요
- **드래그 reorder는 미지원 → 우클릭 "Move to..." 다이얼로그로 대체**

**평가:** 검색·생성·삭제·이름변경은 모두 가능. 드래그만 우회 필요.

#### 2.1.3 Object Manager 미시 객체 트리 (계획서 §1.3)

**OriginPro:** 트리 + inline checkbox + 다중 선택 일괄 변경

**MATLAB 구현:**
- `uitree` Multi-select은 R2020a+ 가능
- inline checkbox는 **`uitree`에 직접 미지원** → 노드 아이콘 (`NodeData`로 상태 저장 + 클릭 시 토글) 패턴으로 대체
- 다중 선택 후 "Apply Style" 버튼 → 별도 다이얼로그에서 일괄 변경

**평가:** UX는 다르지만 기능 동등. 사용자 학습 비용 약간.

#### 2.1.4 Plot Details 계층 페이지·레이어·플롯 (계획서 §1.5)

**OriginPro:** 트리 다이얼로그에서 페이지·레이어·플롯 단위 속성 편집

**MATLAB 구현:**
- 자체 다이얼로그 (`uifigure` modal) + 좌측 `uitree` + 우측 `uigridlayout` 속성 패널
- 모든 그래프 객체 (`Axes`, `Line`, `xline`)의 속성을 set/get으로 접근 가능
- 100% 동등 구현 가능

**평가:** 완전 동등. UI 폼 만들기 작업량만 큼.

#### 2.1.5 분석 대화상자 Input/Settings/Output 노드 (계획서 §1.5)

**OriginPro:** 트리 + Theme 저장/로드

**MATLAB 구현:**
- `uifigure` modal + `uitree` (3 루트 노드: Input/Settings/Output)
- Theme는 JSON으로 저장 (이미 ConfigManager 패턴 존재)
- 100% 동등 구현 가능

**평가:** 완전 동등.

#### 2.1.6 자동 재계산 / 녹색 자물쇠 (계획서 §1.6)

**OriginPro:** 결과 노드에 자물쇠 아이콘 + 변경 자동 감지

**MATLAB 구현:**
- 변경 감지: `DirtyTracker` (별도 설계 문서 참조)
- 시각 표시: `uitree` 노드 아이콘 변경 (PNG 16×16) — `Icon` 속성 R2020a+
- 100% 동등 구현 가능

**평가:** 완전 동등. 별도 design-dirty-dag.md 문서로 알고리즘 정의됨.

---

### 2.2 🟡 부분 구현 + 합리적 절충 (7항목)

#### 2.2.1 상태 표시줄 실시간 요약 통계 (계획서 §1.4)

**OriginPro:** 워크시트 셀 선택 시 mean/sum/count 즉시 표시

**MATLAB 구현:**
- `uigridlayout` 하단 행에 `uilabel` 다수 배치
- Active session + ROI 선택 변경 시 listener로 갱신
- **선택 변경 이벤트 부재**: `uitable` `CellSelectionCallback`은 있으나 plot drag로 ROI 갱신은 별도 EventBus
- **합리적 절충:** OriginPro처럼 셀 단위 선택은 없고, ROI/시간 범위 단위 통계만 표시 (계획서도 이 수준)

**평가:** 계획서 범위 100% 가능. OriginPro의 셀 선택 통계는 비행 리뷰에 불필요.

#### 2.2.2 Mini Toolbar (계획서 §1.7)

**OriginPro:** 객체 선택 시 커서 근처 floating fade-in toolbar

**MATLAB 구현:**

| 옵션 | 가능성 | 평가 |
|---|---|---|
| 진짜 floating + cursor follow | 🔴 어려움 — `uifigure` 내 `uipanel`은 pixel 위치 가능하나 커서 추적은 `WindowMousePressedFcn`으로 가능, 단 fade-in/out 애니메이션 없음 | 비권장 |
| Inspector 상단 quick action row | 🟢 쉬움 | **권장 (계획서도 1차 안)** |
| `uihtml` + HTML toolbar | 🟡 가능하나 R2021b+ 필요 + JS bridge 비용 | 후순위 |

**합리적 절충:** 계획서 §1.7의 1차 안 그대로 채택 — Inspector 상단 quick action row.

**평가:** OriginPro의 floating UX는 1차에서 포기. 사용자에게 "선택 객체 작업은 우측 Inspector"로 안내.

#### 2.2.3 GUI Mode (Stats Mode 등) (계획서 §1.8)

**OriginPro:** 메뉴/Toolbar/창을 역할별로 통째 재구성

**MATLAB 구현:**
- `uimenu`/`uitoolbar` 컴포넌트의 `Visible` 토글 — 가능
- **단, 모든 모드의 모든 컨트롤을 미리 만들면 메모리 낭비** → lazy build 패턴 필요
- 모드 전환 시 panel visibility + grid column width 동시 변경 → 기존 `ResponsiveLayoutManager` 확장으로 가능

**합리적 절충:** lazy build로 첫 진입 시에만 모드별 컨트롤 생성, 이후 cache.

**평가:** 가능하나 lazy build 설계 추가 필요 (Phase 6d 작업량 증가).

#### 2.2.4 도킹 패널 (Right Dock: Inspector/Object Manager/Logs) (계획서 §2.2)

**OriginPro:** 진짜 도킹 + 사용자가 떼어내서 floating 가능

**MATLAB 구현:**
- `uigridlayout`의 우측 칼럼에 고정 (현재 `ResponsiveLayoutManager`와 동일 방식)
- **떼어내서 floating 불가** — uifigure는 단일 컨테이너만 가능
- 다른 모니터로 분리도 불가

**합리적 절충:**
- 우측 칼럼을 splitter로 폭 조정 가능 (현재 `DragController` 패턴 재사용)
- 탭 형태로 Inspector / Object Manager / Logs / Apps 전환
- 진짜 floating은 **별도 `uifigure` 창**으로 띄우는 옵션 (Phase 6 후순위)

**평가:** 80% UX 충족. 듀얼 모니터 활용은 별도 figure로 우회.

#### 2.2.5 Title Bar (프로젝트명 + 폴더경로) (계획서 §2.1)

**OriginPro:** 제목 표시줄에 프로젝트명·폴더경로·Pro 여부

**MATLAB 구현:**
- `uifigure.Name` 동적 변경 가능
- 단점: Windows OS 제목 표시줄에만 표시, `Name` 길이 제한 없음
- 폴더 경로는 길어서 `app.UIFigure.Name = sprintf('FlightDataReviewStudio - %s [%s]', projName, folderPath)` 형태

**합리적 절충:** 폴더 경로는 너무 길면 `...` 절단. 마우스 hover 시 tooltip은 미지원 → Status Bar에 풀 경로 표시 추가.

**평가:** 80% 가능.

#### 2.2.6 학습 센터 (F11) (계획서에서 누락)

**OriginPro:** 100+ 그래프 템플릿 갤러리 + 더블클릭으로 프로젝트 열기

**MATLAB 구현:**
- 비행 리뷰 도메인이 좁아서 100+ 템플릿 비현실
- **합리적 절충:** Help 메뉴 > "Sample Projects" → 5~10개 예시 프로젝트 번들

**평가:** 1차 범위 제외 (계획서 입장 합당). Phase 11 (사용자 검증 + 문서)에서 sample 프로젝트 5개 작성 권장.

#### 2.2.7 Toolstrip / Ribbon (OriginPro 2025b 신규)

**OriginPro:** Office 스타일 ribbon

**MATLAB 구현:**
- `uitoolbar`만 존재 — flat 1줄
- `uihtml` + Bootstrap toolbar로 ribbon 흉내 가능 (R2021b+)
- **합리적 절충:** flat toolbar 채택 (계획서 §6.2 그대로)

**평가:** 1차 범위 적정.

---

### 2.3 🔴 1차 범위 제외 권장 (3항목)

#### 2.3.1 진짜 MDI (창 자유 배치, 분리 가능)

**OriginPro:** 자식 창 자유 floating, 다른 모니터 이동, drag-to-arrange

**MATLAB 구현:**
- `uifigure` 안에서 자식 창 분리 **불가능** — uifigure는 단일 figure 단위 리소스
- 별도 `uifigure`를 spawn하면 가능하나, 이는 **다중 figure 관리** 패턴이며 OriginPro의 MDI와 다름

**판단:** 1차에서 포기. Workspace를 `uitabgroup` 탭으로만 제공. 사용자가 동시에 두 화면 보고 싶으면 두 Studio 인스턴스 실행 (현재 single-Dashboard와 동일).

**향후 옵션:** Phase 11 이후 별도 figure spawn 기능 (예: "Detach this tab to new window")

#### 2.3.2 uitree 드래그 reorder

**OriginPro:** 폴더 간 창 드래그로 이동

**MATLAB 구현:**
- `uitree` 드래그&드롭 표준 미지원
- `WindowMousePressedFcn` + 좌표 추적으로 흉내는 가능하나 매우 fragile

**판단:** 우클릭 "Move to..." 컨텍스트 메뉴 → 폴더 선택 다이얼로그로 대체 (Phase 5).

#### 2.3.3 Toolbar 사용자 정의 (Alt+드래그)

**OriginPro:** Alt+드래그로 toolbar 버튼 위치 자유 변경

**MATLAB 구현:**
- `uitoolbar` 버튼 순서 변경은 코드로만 가능 — 사용자 인터랙션 미지원
- Toolbar Customize 다이얼로그 자체 구현 가능하나 작업량 큼

**판단:** Phase 6 이후로 미룸. 1차는 fixed toolbar.

---

## 3. Phase별 MATLAB UI 영향 분석

### 3.1 Phase 1 (Studio Shell 신설) — 안전

**우려:** 없음. uifigure + uitabgroup + uigridlayout만으로 골격 구축 가능.

**확인 필요:**
- 우측 dock panel을 `uitabgroup` (Inspector/Object Manager/Logs/Apps 탭)으로 구성 — 가능 ✅
- Status Bar는 하단 row에 `uigridlayout` — 가능 ✅
- Title Bar는 `uifigure.Name` 동적 갱신 — 가능 ✅

### 3.2 Phase 3 (Embedded화) — **위험도 최고**

**핵심 문제:** `WindowButtonMotionFcn` / `WindowButtonUpFcn`은 **figure-level 단일 콜백**.

**현재 코드:**

| 컨트롤러 | 사용 콜백 | 충돌 가능성 |
|---|---|:---:|
| `MarkerDragController` | WindowButtonMotionFcn, WindowButtonUpFcn | 🔴 |
| `PannerController` | 동일 | 🔴 |
| `DragController` (HISplitter) | 동일 | 🔴 |
| `InfoController` | WindowButtonUpFcn | 🟡 |

**다중 탭 시나리오:**
- 탭 A에서 marker drag 시작 → `WindowButtonMotionFcn = @plotMarkerDragMotion`
- 탭 B 클릭 → 탭 A의 motion fcn이 **여전히 활성** → 탭 B 좌표를 탭 A로 전달

**해결 전략 3가지:**

**전략 1: SessionId 게이트 (권장)**

각 컨트롤러의 모션 콜백 진입부에 `if obj.SessionId ~= activeSession.Id, return; end` 가드. 이미 `MarkerDragCtrl` 등은 인스턴스 단위라 `obj.IsDraggingMarker` 체크로 일부 자연 차단되나, **두 세션이 동시에 drag**하는 경우 (예: 한 손은 탭 A의 slider, 다른 손은 탭 B의 panner) 충돌 가능. → SessionId 명시 가드 필수.

**전략 2: Per-tab callback router**

Studio가 마스터 `WindowButtonMotionFcn`을 소유하고, 활성 탭의 컨트롤러로 dispatch. 이 패턴은 깔끔하나 **모든 컨트롤러를 router 등록 방식으로 재작성**해야 함.

**전략 3: 한 시점에 1개 drag만 허용 (제한적)**

mutex 패턴 — 어떤 컨트롤러가 drag 시작 시 다른 모든 drag 차단. 사용자 경험 저하 우려.

**권장 채택:** 전략 1 (SessionId 게이트) — 기존 코드 변경 최소.

**Phase 3 추가 필수 작업:**
- 모든 drag 컨트롤러에 `BoundSessionId` 속성 추가
- `MarkerDragCtrl.startPlotMarkerDrag()` 진입부에 `if obj.BoundSessionId ~= obj.App.ActiveSessionId, return; end` 게이트
- `obj.App.ActiveSessionId` 속성 신설 (탭 전환 시 갱신)

### 3.3 Phase 5 (Project Explorer + Object Manager)

**Risk Items:**

| 기능 | MATLAB 가능성 | 작업량 |
|---|:---:|:---:|
| 폴더 트리 표시 | 🟢 `uitree` | 소 |
| 노드 우클릭 컨텍스트 메뉴 | 🟢 `uicontextmenu` | 소 |
| 노드 아이콘 (Dirty/Frozen) | 🟢 `Icon` 속성 (R2020a+) | 중 |
| 키워드 검색 | 🟢 자체 구현 (재귀 + ChildNodes) | 중 |
| 드래그 reorder | 🔴 미지원 → 우클릭 "Move" | 회피 |
| Multi-select + 일괄 작업 | 🟡 R2020a+ Multi-select, 작업 적용은 자체 다이얼로그 | 중 |
| Inline checkbox (Object Manager) | 🔴 미지원 → 아이콘 토글 | 회피 |

**완료 기준 보완:** "드래그 reorder 미지원 — 우클릭 Move 메뉴로 대체" 명시.

### 3.4 Phase 6c (Mini Toolbar)

**계획서 1차 안:** Inspector 상단 quick action row → 구현 무난.

**OriginPro 식 floating은 Phase 11+ 후순위.**

### 3.5 Phase 6d (GUI Mode)

**Risk:** lazy build 패턴 필수.

**구현 패턴:**

```text
ModeManager.activate(modeName):
    if not modeBuilt[modeName]:
        ModeBuilder.build(modeName)  // 메뉴/툴바/패널 생성
        modeBuilt[modeName] = true
    setVisibility(modeName, true)
    setVisibility(otherModes, false)
```

**메모리 절약:** 사용자가 한 번도 안 쓴 모드는 메모리에 없음.

---

## 4. 구체적 한계 사항 및 우회

### 4.1 우회 불가 한계

| 한계 | 영향 |
|---|---|
| uifigure 안의 자식 figure 불가 | 진짜 MDI 불가 — 탭으로 대체 |
| Alt+드래그 toolbar 사용자 정의 미지원 | Phase 6 이후 자체 다이얼로그로 |
| uitree 드래그 reorder | 우클릭 메뉴로 대체 |
| uipanel 떼어내서 floating 불가 | 별도 uifigure로 대체 (Phase 6 옵션) |
| Toolstrip/Ribbon 표준 미지원 | uihtml 또는 flat toolbar |
| 다중 모니터 자유 배치 (hot zone) | uifigure 1개 단위로 한정 |

### 4.2 우회 가능한 한계 (워크어라운드 명시)

| 한계 | 워크어라운드 |
|---|---|
| `WindowButtonMotionFcn` figure-level | SessionId 게이트 + 활성 탭 dispatch |
| uitree inline checkbox | `Icon` 토글 (체크/언체크 PNG) |
| Multi-row uitable formatting | `uistyle` (R2019b+) |
| Plot 실시간 통계 표시 | 별도 status bar listener |
| Settings persistence | JSON config (이미 ConfigManager 패턴) |
| Undo/Redo | 직접 구현 — Phase 11+ |

---

## 5. Phase 0 검증 작업 (Reality Check 결과 반영)

### 5.1 즉시 추가 권장 작업

**A. Throttle SessionId 접두 — Phase 3 진입 전 수정**

```text
현재: flightdash.util.Throttle.instance().hit('PlotRowResize', fIdx, 0.05)
변경: flightdash.util.Throttle.instance().hit(['PlotRowResize:' sessionId], fIdx, 0.05)
```

**B. WindowButton callback 다중 인스턴스 sanity test (Phase 0.5)**

테스트 시나리오:
1. 단일 figure에 2개 patch 객체 생성
2. 각각 ButtonDownFcn으로 다른 motion fcn 등록
3. 동시 drag 시도 → 두 번째 motion이 첫 번째를 덮어쓰는지 확인
4. **결과 확인 후 Phase 3 게이트 전략 확정**

**C. Active session 추적 메커니즘 신설 (Phase 1)**

- `Studio.ActiveSessionId` 속성
- `uitabgroup.SelectionChangedFcn` listener에서 갱신
- 모든 컨트롤러가 이 값을 읽어 자기 세션이 활성인지 판단

### 5.2 Phase 1 진입 전 결정 항목

| 항목 | 결정 |
|---|---|
| **MATLAB 최저 요구 버전** | R2021b (uitree multi-select + uihtml) |
| **MDI 방식** | 단일 uifigure + uitabgroup (자유 floating 미지원) |
| **Right Dock 방식** | uitabgroup (Inspector/Object Manager/Logs/Apps) |
| **드래그 reorder** | 미지원 — 우클릭 "Move" 메뉴 |
| **Object Manager checkbox** | 노드 아이콘 토글 |
| **Mini Toolbar** | Inspector 상단 quick action row (1차) |
| **Toolstrip/Ribbon** | flat uitoolbar |
| **Toolbar 사용자 정의** | 1차 범위 제외 |
| **다중 모니터** | 별도 Studio 인스턴스 실행 (uifigure spawn은 Phase 11+) |

---

## 6. 수정된 Phase 우선순위 권고

### 6.1 Phase 0 → 0.1로 추가 작업

기존 Phase 0의 6개 항목에 다음 추가:
- **0.7 Throttle SessionId 접두 정책**: 모든 throttle key에 접두 추가
- **0.8 ActiveSessionId 속성 prototype**: Studio가 없는 단일 Dashboard에서도 `app.ActiveSessionId = 'standalone'` 기본값
- **0.9 Multi-instance drag sanity test**: 위 §5.1.B 테스트 후 결과 문서화

### 6.2 Phase 3a (인터페이스 추상화) 강화

기존 §5.2 권장에 다음 추가:
- 모든 drag 컨트롤러에 `BoundSessionId` 도입 (계획서 §5.2 EventBus Session Scope와 통일)
- `WindowButtonMotionFcn` master router 패턴 검토 (전략 2 비교)

### 6.3 Phase 5 완료 기준 보강

- "드래그 reorder는 우클릭 Move로 대체"
- "Object Manager checkbox는 아이콘 토글"
- "Multi-select 일괄 작업은 별도 다이얼로그"

명시.

### 6.4 Phase 6 d 완료 기준 보강

- "lazy build 적용 — 첫 진입 모드만 컨트롤 생성"

---

## 7. 정량 지표 (Performance baseline)

### 7.1 현재 단일 Dashboard

| 지표 | 측정값 (예상) | 권장 목표 |
|---|---|---|
| 시작 → 첫 화면 표시 | ~3초 | < 5초 (Studio 후) |
| Tab 전환 | < 100ms | < 200ms |
| Slider drag (60fps 시도) | ~25fps | > 20fps |
| ROI 통계 1개 계산 | ~30ms | < 100ms |
| 메모리 (50MB flight + 1GB video) | ~600MB | < 1GB (Studio 단일 세션) |

### 7.2 Studio 다중 세션 목표

| 지표 | 목표 |
|---|---|
| 5개 세션 동시 로드 (메타만) | < 10초 |
| 활성 세션 외 메모리 | 세션당 < 50MB (메타만) |
| 활성 세션 메모리 | < 1GB |
| 5개 세션 simultaneous scrub | 활성 탭만 60fps 시도, 나머지 freeze 허용 |

---

## 8. 결론

**핵심 결론:**
1. MATLAB R2021b+ 환경에서 OriginPro의 70% UX 가치를 합리적으로 재현 가능
2. **Phase 3 Embedded화의 figure-level callback 충돌이 가장 큰 기술 부채** — SessionId 게이트 전략으로 해결
3. 진짜 MDI / floating dock / drag reorder 3가지는 1차 범위 제외 — 우클릭 메뉴, 별도 figure spawn, fixed toolbar로 대체
4. uitree 기반 Project Explorer / Object Manager는 OriginPro 80% 수준 구현 가능
5. Mini Toolbar는 Inspector 상단 quick action row로 1차 시작

**Phase 1 진입 전 결정 완료:** ✅ 본 문서 전체

**Phase 0 추가 작업 필요:**
- 0.7 Throttle SessionId 접두
- 0.8 ActiveSessionId prototype
- 0.9 Multi-instance drag sanity test (실제 MATLAB에서 검증)

**Phase 3 진입 전 추가 검증 필요:**
- WindowButtonMotionFcn router vs SessionId 게이트 비교 결과
- MATLAB 실제 환경에서 다중 탭 drag 충돌 케이스 reproduction

---

## 부록: OriginPro 기능 → MATLAB 매핑 종합 표

| OriginPro 기능 | MATLAB 컴포넌트 | 가능성 | Phase |
|---|---|:---:|:---:|
| MDI 프로젝트 | uitabgroup | 🟡 | 1 |
| 제목 표시줄 (프로젝트·폴더) | uifigure.Name | 🟡 | 1 |
| 메뉴 (File/Project/Data/...) | uimenu | 🟢 | 1 |
| Toolbar | uitoolbar | 🟢 | 1 |
| Project Explorer | uitree | 🟢 | 5 |
| Object Manager | uitree (Multi-select R2020a+) | 🟡 | 5 |
| Inspector / Property Editor | uigridlayout + 컨트롤들 | 🟢 | 6b |
| Mini Toolbar (floating) | Inspector quick action row | 🟡 | 6c |
| GUI Mode (Stats Mode 등) | uimenu/toolbar Visible 토글 + lazy build | 🟡 | 6d |
| Status Bar 실시간 통계 | uigridlayout 하단 + uilabel | 🟢 | 6 |
| Analysis Dialog 트리 | uifigure modal + uitree | 🟢 | 7 |
| Dialog Theme | JSON 직렬화 | 🟢 | 7 |
| Recalculate 자물쇠 표시 | uitree 노드 Icon | 🟢 | 8 |
| Auto Update 자동 갱신 | DirtyTracker + listener | 🟢 | 8 |
| Message/Error/Result Log | uitable + uipanel | 🟢 | 6 |
| Save/Load Project | ZIP + JSON + MAT v7.3 | 🟢 | 9 |
| 드래그 reorder | 우클릭 "Move" | 🔴→🟡 | 5 |
| Floating dock (떼어내기) | 별도 uifigure spawn | 🔴→🟡 | 11+ |
| Toolbar 사용자 정의 | 자체 다이얼로그 | 🔴→🟡 | 11+ |
| 다중 모니터 자유 배치 | 다중 Studio 인스턴스 | 🔴 | 제외 |
| Code Builder / LabTalk | MATLAB 자체 IDE | 🔴 | 제외 |
| Apps Gallery / 앱 센터 | 미적용 (도메인 좁음) | 🔴 | 제외 |
| 학습 센터 (F11) | Help > Sample Projects | 🔴→🟡 | 11+ |
