# Phase 4 Verification Runbook

**문서 버전:** v1.0 | **작성일:** 2026-05-09 | **대상 커밋:** `aa23dcb` 이후

Phase 4 ("Event Scope / Session Router") 변경사항을 실측 검증하는 런북.
자동 가능한 부분과 수동 필요한 부분을 명확히 분리.

---

## 0. 사전 준비

```matlab
% 1) 클래스 캐시 비우기 (이전 캐시가 남아 있으면 옛 시그니처를 참조함)
clear classes
close all force
delete(findall(0, 'Type', 'figure'))

% 2) 작업 디렉토리 확인
pwd            % 'D:\flightdashboard\5. 4th\root' 등 main 코드가 있는 위치
ls +flightdash % 'FlightDataDashboard.m', '+studio', '+util' 등이 보여야 함
```

---

## 1. 자동 검증 (Phase 4 단위 테스트)

```matlab
results = flightdash.studio.diag.verifyPhase4();
```

**기대 출력:** 7개 케이스 모두 PASS.

| ID    | 검증 대상 |
|:-----:|---|
| P4-1  | `AppEventData(fIdx, payload, sessionId)` 3-arg 생성자 + `SessionId` 속성 존재 |
| P4-2  | `SessionScope.set/get/clear/isOwner` 4-state (match/mismatch/broadcast/standalone) |
| P4-3  | `isActiveSession(d)` 우선순위 — payload SessionId > SessionScope > standalone fallback |
| P4-4  | `ProjectModel.newId` 200건 unique + format `<PREFIX>_<17digits>_<6+digits>` |
| P4-5  | `SessionModel.setFlightFile` channelIdx 0/3/-1/1.5/NaN/Inf 거부 + 1/2 + char/string 수용 |
| P4-6  | `SessionModel.setDisplayName` 빈/공백 거부 + trim |
| P4-7  | `ProjectModel.removeSession`이 의존 `ReviewResult` 캐스케이드 삭제 |

**Pass/Fail 결과를 모두 알려주세요** — 자동 검증 통과 후 수동 검증으로 넘어갑니다.

---

## 2. 자동 검증 (이전 단계 회귀 — Phase 3c 기준)

```matlab
results = flightdash.studio.diag.runMultiInstanceTests();
```

**기대 출력:** TC-1, TC-2, TC-3 모두 PASS.

| ID    | 검증 대상 |
|:-----:|---|
| TC-1  | `WindowButtonMotionFcn` 단일 슬롯 (두 번째 등록이 첫 번째 덮어쓰기) |
| TC-2  | Master dispatch + SessionId gate 동작 |
| TC-3  | `Throttle` SessionId 접두 격리 (Phase 0.7 검증) |

---

## 3. 수동 검증 — 표준 시나리오 (필수)

리뷰가 권장한 핵심 시나리오:

> "세션 2개 생성 → 각 탭에서 파일 로드 → 한 탭에서 marker drag 중 탭 전환 → tab close → 다른 탭 playback 유지 → Studio close"

### 3.1 시나리오 A — 다중 세션 격리

```matlab
clear classes; close all force;
FlightReviewStudio
```

| 단계 | 액션 | 기대 결과 |
|:---:|---|---|
| A.1 | `Project > Add Review Session` × 2 | Session 1, Session 2 탭 생성. Project Explorer에 두 노드 |
| A.2 | Session 1 탭의 `Flight 1` 클릭 → 데이터 선택 | 파일 다이얼로그 1번만, 데이터 로드, 풀 패널 표시 |
| A.3 | Session 2 탭으로 전환 | Session 2의 데이터는 비어 있음 (Lat --, Row 0/0). Session 1 데이터 영향 없음 |
| A.4 | Session 2 탭의 `Flight 1` → 다른 데이터 로드 | Session 2만 갱신, Session 1 무관 |
| A.5 | Project Explorer의 Session 1 클릭 | 워크스페이스가 Session 1 탭으로 전환 |
| A.6 | Window > Close Active Tab | Session 1 탭 + Project Explorer 노드 동시 삭제. Session 2 정상 |

### 3.2 시나리오 B — drag 중 탭 전환 (figure-level callback 회복)

| 단계 | 액션 | 기대 결과 |
|:---:|---|---|
| B.1 | 세션 2개 + 양쪽 모두 데이터 로드 | A 시나리오 결과 상태 |
| B.2 | Session 1의 plot marker(빨간 별) drag 시작 후 마우스 누른 채 유지 | marker 따라 X축 시간 갱신 |
| B.3 | drag 유지 중 다른 탭(Session 2) 클릭 | Session 1의 motion fcn은 더 이상 Session 1 모델을 갱신하지 않음 (탭 비활성). Session 2의 marker는 영향 없음 |
| B.4 | 마우스 release | Session 1으로 돌아가 보면 marker가 마지막 active 위치에 있음. drag state 정상 정리됨 |

**실패 신호:**
- B.3에서 Session 1 marker가 Session 2의 마우스 위치 따라 움직임 → motion guard 미작동
- B.4 후 콘솔 에러 / 응답 없음 → stopDrag 미정상

### 3.3 시나리오 C — tab close 시 다른 세션의 비동기 디코딩 보존

| 단계 | 액션 | 기대 결과 |
|:---:|---|---|
| C.1 | 세션 2개 + 양쪽 모두 비행 데이터 + AVI 로드 | 양쪽 비디오 재생 가능 상태 |
| C.2 | Session 2의 `Play` 클릭 → 자동 재생 시작 | Session 2 시간이 진행 |
| C.3 | Session 1 탭으로 전환 → `Window > Close Active Tab` | Session 1만 닫히고, Session 2의 재생은 중단 없이 계속 |
| C.4 | Session 2의 비디오 frame이 정상 디코딩되어 표시 | parpool / async decode 워커가 살아있음 |

**실패 신호:**
- C.4에서 Session 2 비디오가 멈추거나 "Decoding..." 상태로 영구 정지 → parpool 공유 위반

### 3.4 시나리오 D — Studio resize → 활성 dashboard 레이아웃 재계산

| 단계 | 액션 | 기대 결과 |
|:---:|---|---|
| D.1 | Studio 실행 + 세션 1개 + 데이터 로드 | 풀 패널 표시 |
| D.2 | Studio 창 크기를 마우스로 작게 줄이기 | 활성 dashboard의 column 폭 자동 재계산. rail이 활성화되지 않음 (embedded mode 강제 disable) |
| D.3 | Studio 창을 크게 키우기 | 패널 폭 재확장 |
| D.4 | 세션 추가 후 Session 1 → Session 2 → Session 1 탭 왕복 전환 | 매 전환 시 활성 dashboard `LayoutMgr.applyLayout('tabActivated')` 호출 — 레이아웃 즉시 재계산 |

### 3.5 시나리오 E — Project Explorer 작업 (Phase 5)

| 단계 | 액션 | 기대 결과 |
|:---:|---|---|
| E.1 | Project Explorer의 Session 우클릭 → `Rename...` | 입력창. 새 이름 → 탭 제목 + 트리 라벨 동시 변경 |
| E.2 | Session 우클릭 → `Duplicate` | "(copy)" 새 탭 생성 + 트리 노드 추가 |
| E.3 | Session 우클릭 → `Delete` → Confirm | 탭 + 모델 + 트리 노드 삭제 |
| E.4 | `Project > Rename Session / Duplicate Session / Delete Session` | 활성 탭 기준 동작. Welcome 탭에서는 "No active session" 안내 |

---

## 4. 결과 보고 양식

각 시나리오별로 다음 정보를 알려주세요:

```text
[자동] verifyPhase4()      : (PASS/FAIL 개수)
[자동] runMultiInstanceTests(): (PASS/FAIL 개수)

[수동 A] 다중 세션 격리      : (PASS/FAIL — 어느 단계에서 실패했는지)
[수동 B] drag 중 탭 전환     : ...
[수동 C] async decode 보존   : ...
[수동 D] Studio resize       : ...
[수동 E] Project Explorer    : ...

MATLAB 버전: ___________
```

자동 검증이 통과하면 Phase 4의 API 계약이 모두 충족됨을 의미합니다.
수동 검증은 figure-level callback / parpool / responsive layout 같은 **runtime
상호작용**을 확인하므로 실제 MATLAB Online에서만 가능합니다.

---

## 5. 알려진 제약 (검증에서 제외)

리뷰의 priority-4 미반영 항목 — Phase 4 검증 범위 아님:

- **`WindowButtonMotionFcn` master router 미도입**: 현재는 `isActiveSession()` guard로 보호 중. master router는 이후 별도 phase 작업.
- **`FlightDataDashboard.m` 추가 분해**: 4,481줄 유지. Phase 6+ 작업 중 자연스럽게 분리.
- **한글 주석 잔존 mojibake (109건)**: 컴파일/동작 무관. 점진 정리.

이 세 항목 때문에 위 5개 시나리오가 실패하면 안 됩니다. 실패 시 Phase 4 자체의
회귀로 분석.

---

## 6. 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| `MATLAB:TooManyInputs` 에러 | 클래스 캐시. `clear classes` 실행 |
| Studio 창이 안 열림 | `clear all; close all force; delete(findall(0,'Type','figure'))` |
| `verifyPhase4` 가 P4-2 FAIL | `flightdash.util.SessionScope` 파일 누락 또는 옛 버전. `+util/` 디렉토리 확인 |
| `runMultiInstanceTests` 의 TC-3 FAIL | `flightdash.util.Throttle` 인스턴스 캐시. `clear classes` |
| 닫히지 않는 GUI | `delete(findall(0, 'HandleVisibility', 'off'))` + `clear all` |
| 유지보수: 깨끗히 시작하려면 | MATLAB Online > Home > Restart MATLAB |
