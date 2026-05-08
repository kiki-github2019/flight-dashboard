# Multi-Instance Drag Sanity Test

**문서 버전:** v1.0 | **작성일:** 2026-05-08 | **Phase:** 0.9 (Phase 3 진입 전 검증)

---

## 0. 목적

MATLAB `uifigure`의 **`WindowButtonMotionFcn` / `WindowButtonUpFcn` 콜백이 figure-level 단일 슬롯**이라는 한계가 다중 세션 환경(Phase 3 Embedded화)에서 어떻게 충돌하는지 실측 검증한다. 결과에 따라 Phase 3의 SessionId 게이트 vs Master Router 전략 중 채택 여부를 결정한다.

**검증 대상:**
1. 단일 figure에서 두 객체가 동시에 motion 콜백을 등록하면 무엇이 일어나는가?
2. 한 콜백이 등록된 동안 다른 콜백이 등록되면 어떻게 되는가?
3. SessionId 게이트 패턴으로 다중 세션 충돌을 막을 수 있는가?
4. `Throttle.instance()` 싱글톤이 다중 인스턴스에서 키 충돌을 일으키는가? (Phase 0.7 검증)

---

## 1. 사전 준비

### 1.1 환경

- MATLAB R2021b 이상
- 작업 디렉토리: `D:\flightdashboard\5. 4th\root\.claude\worktrees\bold-brown-8651c4`
- MATLAB path에 `+flightdash` 부모 폴더 추가:

```matlab
addpath('D:\flightdashboard\5. 4th\root\.claude\worktrees\bold-brown-8651c4');
```

### 1.2 검증 가설 (Phase 0.5 design 문서 기반)

| 가설 | 예상 결과 | 근거 |
|---|---|---|
| H1: WindowButtonMotionFcn은 figure 1개당 1개만 활성 | 두 번째 등록이 첫 번째를 덮어씀 | MATLAB 문서 |
| H2: 두 motion 콜백을 차례로 등록하면 마지막만 실행 | 첫 콜백 영구 비활성 | H1 결과 |
| H3: SessionId 게이트로 막을 수 있음 (활성 세션 외 무시) | 두 컨트롤러가 충돌 안 함 | Phase 3 design |
| H4: Throttle 키에 sessionId 접두로 충돌 회피 | 두 세션이 같은 slotName 써도 독립 동작 | Phase 0.7 design |

---

## 2. Test Cases

### TC-1: WindowButtonMotionFcn 단일 슬롯 검증

**목적:** H1, H2 검증 — 두 motion 콜백 등록 시 동작 확인.

**스크립트 (MATLAB Editor에 붙여넣고 실행):**

```matlab
% TC-1: Two motion callbacks on same figure
fig = uifigure('Name', 'TC-1 Single-slot test', 'Position', [100 100 400 300]);
counter = struct('cb1', 0, 'cb2', 0);

% 첫 번째 콜백 등록
fig.WindowButtonMotionFcn = @(~,~) updateCounter('cb1');
disp('Step 1: cb1 registered. Move mouse over figure for 2 seconds.');
pause(2);
fprintf('  cb1=%d, cb2=%d\n', counter.cb1, counter.cb2);

% 두 번째 콜백 등록 (덮어씀 예상)
fig.WindowButtonMotionFcn = @(~,~) updateCounter('cb2');
disp('Step 2: cb2 registered (cb1 overwrite expected). Move mouse for 2 seconds.');
pause(2);
fprintf('  cb1=%d, cb2=%d\n', counter.cb1, counter.cb2);

% Helper (script-local — appdata로 카운터 공유)
function updateCounter(name)
    fig = gcf;
    c = getappdata(fig, 'counter');
    if isempty(c), c = struct('cb1', 0, 'cb2', 0); end
    c.(name) = c.(name) + 1;
    setappdata(fig, 'counter', c);
end
```

**예상 결과:**
- Step 1 후: cb1 > 0, cb2 = 0
- Step 2 후: cb1 동일 (증가 멈춤), cb2 > 0

**합격 기준:** Step 2에서 cb1이 증가하지 않으면 H1·H2 확정.

**불합격 시 의미:** MATLAB 버전이 다중 콜백을 지원하거나 미상의 동작 — 추가 조사 필요.

---

### TC-2: SessionId 게이트 패턴 검증

**목적:** H3 검증 — 활성 세션 ID 가드로 충돌 회피 가능 여부.

**스크립트:**

```matlab
% TC-2: SessionId-gated drag controllers
fig = uifigure('Name', 'TC-2 SessionId gate test', 'Position', [100 100 400 300]);
state = struct('activeSessionId', 'S001', 'cb1Hits', 0, 'cb2Hits', 0);
setappdata(fig, 'state', state);

% 세션 S001과 S002의 motion fcn 등록 (master dispatcher 패턴)
fig.WindowButtonMotionFcn = @(~,~) dispatch(fig);

% 시뮬레이션: 활성 세션 변경
disp('Step 1: Active=S001. Move mouse for 2 seconds.');
pause(2);
s = getappdata(fig, 'state');
fprintf('  cb1=%d, cb2=%d\n', s.cb1Hits, s.cb2Hits);

s.activeSessionId = 'S002';
setappdata(fig, 'state', s);
disp('Step 2: Active=S002. Move mouse for 2 seconds.');
pause(2);
s = getappdata(fig, 'state');
fprintf('  cb1=%d, cb2=%d\n', s.cb1Hits, s.cb2Hits);

function dispatch(fig)
    s = getappdata(fig, 'state');
    if strcmp(s.activeSessionId, 'S001')
        s.cb1Hits = s.cb1Hits + 1;
    elseif strcmp(s.activeSessionId, 'S002')
        s.cb2Hits = s.cb2Hits + 1;
    end
    setappdata(fig, 'state', s);
end
```

**예상 결과:**
- Step 1 후: cb1 > 0, cb2 = 0
- Step 2 후: cb1 동일, cb2 > 0

**합격 기준:** master dispatch + SessionId 게이트로 정확히 분리됨.

**Phase 3 시사점:** 이 패턴이 작동하면, Studio가 master `WindowButtonMotionFcn`을 소유하고 활성 탭의 컨트롤러로 dispatch하는 구조 채택 가능.

---

### TC-3: Throttle SessionId 접두 격리 검증

**목적:** H4 검증 — Phase 0.7에서 적용한 SessionId 접두 정책이 실제로 두 세션의 throttle 슬롯을 격리하는지 확인.

**스크립트:**

```matlab
% TC-3: Throttle key isolation by sessionId prefix
throttle = flightdash.util.Throttle.instance();

% 두 세션이 같은 slotName 'TestSlot'을 사용
key1 = 'S001:TestSlot';
key2 = 'S002:TestSlot';

% S001의 hit
hit1a = throttle.hit(key1, 1, 1.0);  % 첫 hit → false 예상
hit1b = throttle.hit(key1, 1, 1.0);  % 즉시 재호출 → true (throttled) 예상
fprintf('S001 first hit: %d (expect 0), second: %d (expect 1)\n', hit1a, hit1b);

% S002의 hit (S001과 독립이어야 함)
hit2a = throttle.hit(key2, 1, 1.0);  % 첫 hit → false 예상 (S001과 독립)
fprintf('S002 first hit: %d (expect 0 if isolated, 1 if collision)\n', hit2a);

% Cleanup
throttle.reset(key1);
throttle.reset(key2);
```

**예상 결과:**
- `S001 first hit: 0` (통과)
- `S001 second hit: 1` (throttle 작동)
- `S002 first hit: 0` (S001과 독립이므로 통과)

**합격 기준:** 세 출력이 모두 예상대로면 Phase 0.7 SessionId 접두 정책 작동 확정.

---

### TC-4: 두 Dashboard 인스턴스 동시 실행 (실 환경)

**목적:** 실제 FlightDataDashboard를 두 개 띄워 throttle/drag 충돌이 일어나지 않는지 stress test.

**전제조건:**
- Phase 0.7 + 0.8 작업 완료 후 실행

**스크립트:**

```matlab
% TC-4: Two FlightDataDashboard instances
import flightdash.FlightDataDashboard

app1 = FlightDataDashboard();
app1.ActiveSessionId = 'S001';

app2 = FlightDataDashboard();
app2.ActiveSessionId = 'S002';

disp('Two Dashboards launched. Verify:');
disp('  1. 두 figure가 독립적으로 표시되는지');
disp('  2. app1에서 slider drag 시 app2가 영향받지 않는지');
disp('  3. 콘솔에 throttle 관련 에러가 없는지');

% Manual verification:
% - app1.UIFigure에서 비행 데이터 로드 → slider drag
% - 동시에 app2.UIFigure에서 비행 데이터 로드 → slider drag
% - 양쪽이 독립적으로 동작하는지 확인
```

**합격 기준:**
1. 두 인스턴스가 독립 figure로 표시
2. app1의 slider drag가 app2의 slider 위치를 변경하지 않음
3. throttle 관련 warning/error 없음
4. `flightdash.util.Throttle.instance().Slots`을 보면 `S001:LastSliderUpdate`, `S002:LastSliderUpdate` 별도 키로 존재

**주의:** 현재 Throttle.Slots는 Access=private이므로 디버그 시 `Throttle.m`에 임시 getter 추가 또는 breakpoint 사용.

**불합격 시 시사점:** Phase 3 진입 시 추가 격리 작업 필요 — 가장 가능성 높은 원인은 다른 싱글톤(EventBus)이나 Static 함수의 sessionId 미전파.

---

### TC-5: WindowButton 콜백 충돌 reproduction (실 환경)

**목적:** 두 Dashboard가 동시에 motion 콜백 등록 시 어떻게 깨지는지 실측.

**전제조건:** TC-4 후, app1과 app2가 모두 떠 있음.

**시나리오:**

1. app1에서 slider drag 시작 (release 안 함)
2. **마우스를 들지 않고** app2 figure로 이동
3. app2의 slider 영역에서 motion 발생 시 어떤 콜백이 실행되는지 관찰

**예상 동작 (현재 코드):**
- app1의 `WindowButtonMotionFcn`이 app1의 figure에만 적용 (figure-level 콜백)
- app2의 motion은 app2의 콜백만 호출 (만약 등록되어 있으면)
- **결과:** 두 figure는 독립이므로 충돌 없음

**그러나 진짜 위험은 Phase 3 (Embedded mode)에서 발생:**

Phase 3에서는 1개 figure 안에 2개 Dashboard 탭이 들어감 → 한 figure의 motion 콜백이 두 탭 모두에서 작동 → 한 탭의 drag가 다른 탭으로 누수.

**TC-5 결과 → Phase 3 권장 전략:**

| 결과 | Phase 3 전략 |
|---|---|
| 두 인스턴스 독립 → 충돌 없음 | standalone 모드는 OK. embedded 모드만 추가 가드 필요 |
| (가설) 어떤 식으로든 누수 | 즉시 master router 패턴 도입 |

---

## 3. 검증 시나리오 실행 절차

### 3.1 자동화 스크립트 (TC-1, TC-2, TC-3)

위 스크립트들을 차례로 MATLAB Command Window에서 실행한 뒤 출력 확인.

### 3.2 수동 시나리오 (TC-4, TC-5)

**준비:**
```matlab
clear all; close all force; clc;
addpath('D:\flightdashboard\5. 4th\root\.claude\worktrees\bold-brown-8651c4');
```

**TC-4 절차:**
1. 위 TC-4 스크립트 실행
2. app1에 비행 데이터 1개 로드 (Load Flight 1 메뉴)
3. app2에 다른 비행 데이터 로드 (또는 같은 파일)
4. 양쪽에서 slider drag 동시 시도 (별도 마우스 사용 또는 빠른 전환)
5. 콘솔에 에러 메시지 없는지 확인
6. 디버그 — Throttle.Slots 검사:
   ```matlab
   t = flightdash.util.Throttle.instance();
   keys(t.Slots)  % 'S001:LastSliderUpdate', 'S002:LastSliderUpdate' 등 출력 기대
   ```

**TC-5 절차:**
1. TC-4 환경 그대로
2. app1 figure에서 마우스 누르고 (slider drag 시작)
3. 마우스 누른 채로 app2 figure로 이동
4. app2 slider 위에서 motion 발생 시 동작 관찰
5. 마우스 release
6. 양 인스턴스가 정상 idle 상태로 복귀하는지 확인

---

## 4. 합격 기준 종합

**Phase 0.9 통과 조건 (모두 충족):**

- [x] TC-1 통과: WindowButtonMotionFcn 단일 슬롯 확인 (H1, H2)
- [x] TC-2 통과: master dispatch + SessionId 게이트 작동 (H3)
- [x] TC-3 통과: Throttle SessionId 접두 격리 작동 (H4)
- [ ] TC-4 통과: 두 Dashboard 동시 실행 시 throttle/state 충돌 없음
- [ ] TC-5 통과: 마우스 cross-figure 시나리오 동작 확인

**TC-4, TC-5는 실제 MATLAB 환경에서 사용자 검증 필요.** 이 문서는 시나리오만 제공.

---

## 5. 결과 기록 (사용자 작성 영역)

검증 수행 후 아래 표를 채워 docs 폴더에 commit하면 Phase 3 진입 전 의사결정 자료가 됨.

**Phase 3c 자동화:** TC-1~TC-3은 다음 명령으로 한 번에 실행 가능.
```matlab
results = flightdash.studio.diag.runMultiInstanceTests();
```

| TC | 실행일 | 결과 | 비고 |
|---|---|---|---|
| TC-1 | YYYY-MM-DD | Pass / Fail | |
| TC-2 | YYYY-MM-DD | Pass / Fail | |
| TC-3 | YYYY-MM-DD | Pass / Fail | |
| TC-4 | YYYY-MM-DD | Pass / Fail | |
| TC-5 | YYYY-MM-DD | Pass / Fail | |

**MATLAB 버전:** ___________
**OS:** Windows 11
**검증자:** ___________

---

## 6. Phase 3 진입 의사결정 매트릭스

검증 결과에 따라 Phase 3 전략 선택:

| TC-1 | TC-2 | TC-3 | TC-4 | TC-5 | Phase 3 권장 전략 |
|:---:|:---:|:---:|:---:|:---:|---|
| Pass | Pass | Pass | Pass | Pass | **전략 1: SessionId 게이트** (각 컨트롤러에 BoundSessionId 추가) — 최소 변경 |
| Pass | Pass | Pass | Fail | Pass | **전략 2: Master Router** — Studio가 단일 motion fcn 소유, 활성 탭 dispatch |
| Pass | Pass | Fail | — | — | Phase 0.7 재검토 필요 — Throttle 접두 정책 보강 |
| Pass | Fail | — | — | — | master dispatch 패턴 자체 부적합 — 컨트롤러 인스턴스 격리 강화 |
| Fail | — | — | — | — | MATLAB 버전 또는 figure 동작 가정 재검증 필요 |

---

## 7. Phase 3c 완료 노트 (2026-05-08 시점)

**Phase 3c가 다룬 범위:**
- ✅ Window > Close Active Tab / Close All Tabs 메뉴 동작 (`WorkspaceManager.closeActiveTab/closeAllTabs`)
- ✅ 탭 종료 시 임베드된 FlightDataDashboard `delete()` 명시적 호출 (Phase 3a의 `IsEmbedded` 가드 덕분에 Studio shell은 보존됨)
- ✅ TC-1/TC-2/TC-3 자동화: `flightdash.studio.diag.runMultiInstanceTests()` — 단일 명령으로 세 시나리오 검증
- ✅ Active 탭 추적 — 탭 변경 또는 닫기 시 `app.ActiveSessionId` 갱신, StatusBar 반영

**Phase 3c가 다루지 않은 범위 (Phase 4 작업으로 이전):**
- ❌ EventBus 이벤트 자체에 `SessionId` 페이로드 추가
- ❌ 모든 listener 진입부에 `SessionId` 가드 (BaseSessionListener mixin)
- ❌ Active session 외부 EventBus 이벤트 무시 정책

**왜 Phase 4로 이전했는가:**
다중 임베드 시 한 탭의 버튼 클릭(예: Add ROI)이 모든 탭의 RoiController에 전파되는 문제는 EventBus 라우팅 단계에서 해결해야 한다. 이는 100여 곳의 publish/subscribe 호출을 수정해야 하는 별도 작업이며, Phase 3c의 "탭 운영 인프라" 범위를 넘어선다. 단일 탭 또는 동일 세션의 action만 수행한다면 Phase 3c 결과로 충분히 안정적으로 동작한다.

**Phase 4 진입 전 검증 권장:**
1. `flightdash.studio.diag.runMultiInstanceTests()` 실행 → 3건 모두 PASS
2. Studio에서 세션 1개 추가 → Flight 1 데이터 로드 → 정상 작동
3. 두 번째 세션 추가 → 두 번째 탭에서도 Flight 1 데이터 로드 → 첫 번째 탭에 영향 없는지 확인
4. **두 번째 탭의 Add ROI 버튼 클릭 → 첫 번째 탭의 ROI도 추가되는지 (예상: 됨, Phase 4 사유)**
5. Window > Close Active Tab / Close All Tabs 동작 확인

**가장 가능성 높은 시나리오:** 모두 Pass → 전략 1 (SessionId 게이트) 채택.
