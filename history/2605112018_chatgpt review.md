검토 결과입니다. 단, 이 환경에서는 `git clone`이 DNS 오류로 실패하여 로컬 다운로드/실행 검증은 수행하지 못했습니다. 대신 GitHub 원본 파일을 직접 열람하여 **정적 코드 리뷰**를 수행했습니다. MATLAB 실행 결과는 사용자가 MATLAB Online/2025a+에서 아래 검증 명령으로 확인해야 합니다.

## 1. 현재 저장소 상태 요약

현재 저장소는 단순 `FlightDataDashboard` 단일 앱이 아니라, `FlightReviewStudio` 중심의 통합 Studio 구조로 확장된 상태입니다. README 기준으로 `FlightReviewStudio.m`가 Studio 진입점이고, 실제 구현은 `+flightdash/+studio/FlightReviewStudioApp.m`에 있으며, 기존 `FlightDataDashboard.m`는 호환 wrapper로 유지됩니다. ([GitHub][1])

README는 현재 안정화 범위를 Phase 1–6, Phase 8a/8b/8c, Phase 9, 그리고 Phase 10 prototype까지 포함한다고 설명합니다. 특히 `.frsproj`는 zip 기반 linked project 형식이며 raw flight/video 파일은 포함하지 않는다고 명시되어 있습니다. ([GitHub][1])

업로드된 계획서는 Phase 1–6과 Phase 9를 먼저 안정화하고, Phase 7은 ROI 결과 plumbing 수준으로 동결하며, Phase 10은 안정화 후 prototype으로 시작하자는 방향이었습니다. 현재 저장소 문서와 비교하면 **Phase 10 prototype이 이미 일부 들어간 상태**라는 점이 가장 큰 차이입니다. 

---

## 2. Phase별 구현 상태 판단

| Phase                                     |          현재 판단 | 코멘트                                                       |
| ----------------------------------------- | -------------: | --------------------------------------------------------- |
| Phase 1 — Studio Shell                    |    구현됨, 안정화 필요 | Project Explorer, Workspace, Right Dock, Status Bar 구조 존재 |
| Phase 2 — Project/Session Models          |            구현됨 | serializer와 model round-trip 검증 필요                        |
| Phase 3 — Embedded Dashboard Tabs         |       구현됨, 고위험 | `uitab` 내부에 dashboard를 직접 생성하는 구조. MATLAB 제약을 고려한 방향은 타당  |
| Phase 4 — Session-scoped EventBus         |  구현됨, 누수 위험 존재 | `SessionId` 누락 이벤트 처리 규칙이 아직 위험                           |
| Phase 5 — Explorer/Object Manager         |         MVP 수준 | OriginPro 수준의 object hierarchy는 아직 아님                     |
| Phase 6 — Toolbar/Menu/Inspector/GUI Mode |         MVP 수준 | GUI mode profile 구조는 있으나 소형 화면 UX 검증 필요                   |
| Phase 7 — Analysis/Result                 |    초기 plumbing | 본격 Analysis Dialog로 확장하지 말고 동결 권장                         |
| Phase 8 — Dirty/Recalculate               |        서비스 MVP | `DirtyTracker`, queue, recalculate service 수준. UI 완성 아님   |
| Phase 9 — Save/Load                       | linked mode 구현 | missing asset warning/relink UX는 미흡                       |
| Phase 10 — Shared Decode/Cache            |  prototype 시작됨 | 현재는 production integration이 아니라 service-level prototype   |

---

## 3. 긍정적으로 평가되는 부분

첫째, Studio와 legacy dashboard의 진입점을 분리한 것은 적절합니다. README도 `FlightReviewStudio`와 `FlightDataDashboard`의 역할을 명확히 구분하고 있습니다. ([GitHub][1])

둘째, `WorkspaceManager`가 session별 dashboard를 `containers.Map`으로 관리하고, 탭 삭제 시 dashboard, mouse router, shared decode/cache, undo service를 정리하도록 설계된 점은 좋습니다. 특히 `releaseSessionResources()`에서 mouse router cancel, dashboard unload, shared decode cancel, cache invalidate, undo service 제거를 호출하는 구조는 Phase 3/4/10 안정화 방향과 부합합니다. 

셋째, `EventBus`에 `subscribe(eventName, callback, sessionId)`, `subscribeForApp`, `acceptsSession`이 들어간 것은 session-scoped routing을 위한 핵심 기반입니다. 기존 단일 dashboard와 Studio embedded dashboard를 동시에 고려한 점도 방향은 타당합니다. 

넷째, `ProjectSerializer`는 project/session/figure/theme/result/external link를 JSON으로 분리 저장하고, handle 객체를 저장하지 않겠다는 주석과 구조를 갖고 있습니다. `.frsproj`의 linked mode 구현 방향은 맞습니다. 

다섯째, Phase 10 prototype의 `SharedDecodeService`와 `SharedCacheService`는 아직 단순하지만, session generation, cancel, stale discard, LRU eviction 개념을 갖고 있어 이후 확장 기반으로는 적절합니다.  

---

## 4. 주요 리스크와 버그 가능성

### A. EventBus session 누수 가능성

가장 중요한 위험입니다.

`EventBus.acceptsSession(listenerSessionId, eventSessionId)`는 현재 다음 조건이면 true입니다.

```matlab
isempty(listenerSessionId) || isempty(eventSessionId) || strcmp(listenerSessionId, eventSessionId)
```

이 구조에서는 **eventSessionId가 비어 있으면 session-specific listener도 이벤트를 수신**합니다. 즉, 어떤 callback이 `SessionId`를 누락하면 모든 session controller가 반응할 수 있습니다. `attachSession()`이 `SessionScope.getActive()`로 보정하려 하지만, tab 전환/drag 중/비동기 callback/standalone fallback 상황에서는 `SessionScope`가 항상 정확하다고 보장하기 어렵습니다. 

권장 수정 방향:

```matlab
function tf = acceptsSession(listenerSessionId, eventSessionId)
    listenerSessionId = char(listenerSessionId);
    eventSessionId = char(eventSessionId);

    if isempty(listenerSessionId)
        % broadcast listener
        tf = true;
    elseif strcmp(eventSessionId, '*') || strcmpi(eventSessionId, 'broadcast')
        % explicit broadcast only
        tf = true;
    else
        % session listener must match exactly
        tf = strcmp(listenerSessionId, eventSessionId);
    end
end
```

즉, **빈 SessionId를 broadcast로 취급하지 말고, explicit broadcast 토큰을 도입**하는 것이 안전합니다.

---

### B. Phase 10 shared cache가 “공유 캐시”라기보다 session-isolated cache임

`SharedCacheService.makeKey()`는 key에 `sessionId`를 포함합니다. 따라서 같은 video path, 같은 channel, 같은 frame이어도 session이 다르면 cache hit가 발생하지 않습니다. 

이것은 안전성 면에서는 좋지만, “shared cache”의 성능 이점은 제한됩니다. 현재 구조는 사실상 **Studio-owned session-scoped cache container**에 가깝습니다.

권장 방향:

1. 현재는 session-isolated key 유지.
2. Phase 10b에서 optional two-tier cache 도입:

   * Tier 1: session-local cache key
   * Tier 2: content-addressed shared frame key
     예: `hash(videoPath + fileSize + modifiedTime + frameNo)`

---

### C. SharedDecodeService priority가 동적으로 갱신되지 않음

`requestFrame()` 시점에 `Priority`가 고정됩니다. 이후 사용자가 다른 tab으로 전환해 `ActiveSessionId`가 바뀌어도 기존 queue의 priority는 갱신되지 않습니다. 

권장 수정:

`nextQueueIndex()`에서 저장된 `req.Priority`만 보지 말고, 현재 `ActiveSessionId`를 기준으로 priority를 재계산하십시오.

```matlab
function idx = nextQueueIndex(obj)
    priorities = zeros(1, numel(obj.Queue));
    sequences = [obj.Queue.Sequence];

    for k = 1:numel(obj.Queue)
        priorities(k) = obj.priorityFor(obj.Queue(k).SessionId);
    end

    [~, order] = sortrows([priorities(:), sequences(:)], [1 2]);
    idx = order(1);
end
```

---

### D. ProjectSerializer가 external_links.json을 저장하지만 load 시 검증/경고가 약함

`ProjectSerializer.save()`는 `external_links.json`을 생성합니다. 그러나 현재 load 흐름은 manifest/project/session/figure/theme/result를 복원하고 count를 검증하는 데 집중되어 있으며, external asset 존재 여부를 사용자에게 warning으로 구조화해 반환하는 설계는 아직 부족해 보입니다. 

README와 상태 문서에서는 missing external file을 project corruption이 아니라 linked asset warning으로 처리해야 한다고 되어 있습니다. ([GitHub][1])

권장 추가:

```matlab
project.LinkedAssetWarnings = flightdash.project.ExternalLinkValidator.validate(project);
```

또는 load 결과를 다음처럼 확장:

```matlab
[project, report] = ProjectSerializer.load(filePath);
```

`report`에는 다음을 포함합니다.

```matlab
report.MissingFlightFiles
report.MissingVideoFiles
report.MissingConfigFiles
report.SchemaWarnings
report.RelinkCandidates
```

---

### E. cleanupHandleProperty가 handle array에서 실패할 가능성

`FlightDataDashboard.cleanupHandleProperty()`는 다음 패턴을 사용합니다.

```matlab
if isobject(h) && isvalid(h)
```

그런데 `h`가 handle array이면 `isvalid(h)`가 logical array를 반환할 수 있고, `&&` 조건에서 오류가 납니다. 이 함수는 catch로 감싸져 있지만, catch되면 해당 handle array cleanup이 제대로 되지 않을 수 있습니다. `PlotView`, controller array, listener array가 포함될 경우 위험합니다. 

권장 수정:

```matlab
if isobject(h)
    for n = 1:numel(h)
        try
            if isa(h(n), 'handle') && isvalid(h(n))
                if ismethod(h(n), 'cleanup')
                    h(n).cleanup();
                end
                delete(h(n));
            end
        catch ME
            app.logCaught(ME, ['ControllerCleanup:' propName ':item']);
        end
    end
end
app.(propName) = [];
```

---

### F. MVC/Component 분리는 아직 “완전 분리”가 아님

`FlightDataDashboard`의 많은 상태가 public property로 유지되고 있고, controller/manager가 app 객체를 직접 참조합니다. 코드 주석에서도 MATLAB Online private access 제약 때문에 public으로 열어둔 상태라고 설명합니다. 

따라서 현재 구조는 완전한 MVC라기보다:

> 기존 monolithic app을 유지하면서 controller/view/model/service로 점진 분리하는 strangler-pattern 리팩토링 단계

로 보는 것이 정확합니다.

향후 리팩토링 방향은 다음이 좋습니다.

```text
FlightDataDashboard
 ├─ AppState / SessionState
 ├─ VideoPlaybackService
 ├─ FrameDecodeService
 ├─ RoiTableService
 ├─ PlotStateService
 ├─ LayoutProfileService
 └─ UI Adapter Layer
```

controller가 app 전체를 들고 있는 구조를 줄이고, 필요한 service/state interface만 주입해야 합니다.

---

## 5. MATLAB R2025a+ 관점의 호환성 체크

현재 코드 방향은 R2025a 이상에서 대체로 가능해 보입니다. 다만 다음은 MATLAB Online/2025a에서 반드시 검증해야 합니다.

```matlab
clear classes
rehash toolboxcache

results05 = flightdash.studio.diag.verifyPhase0_5();
results1  = flightdash.studio.diag.verifyPhase1();
results2  = flightdash.studio.diag.verifyPhase2();
results3  = flightdash.studio.diag.verifyPhase3();
results4  = flightdash.studio.diag.verifyPhase4();
results37 = flightdash.studio.diag.verifyPhase3_Phase7(false);
results5  = flightdash.studio.diag.verifyPhase5();
results6  = flightdash.studio.diag.verifyPhase6();
results8  = flightdash.studio.diag.verifyPhase8();
results9  = flightdash.studio.diag.verifyPhase9();
results10 = flightdash.studio.diag.verifyPhase10();
multi     = flightdash.studio.diag.runMultiInstanceTests();
full      = runFullStabilizationTests();
isolated  = runAllTestCodesWithCleanup();
```

추가로 수동 검증이 더 중요합니다.

```text
1. FlightReviewStudio 실행
2. Review Session 2개 이상 생성
3. 각 tab에서 marker drag 수행
4. drag 중 tab 전환
5. drag 중 tab close
6. playback 중 tab close
7. save temp.frsproj
8. temp.frsproj.zip가 남지 않는지 확인
9. Korean path 예: D:\테스트\비행리뷰\temp.frsproj 저장/로드
10. 외부 flight/video 파일 삭제 후 project load
11. standalone FlightDataDashboard 실행
```

---

## 6. 개선 우선순위

### 최우선 1 — EventBus session 규칙 수정

현재 가장 큰 리스크는 session leakage입니다. `SessionId == ''`를 broadcast로 허용하는 현재 구조는 embedded multi-session 안정성에 불리합니다.

수정 정책:

```text
- listenerSessionId empty: global listener
- eventSessionId exact match: session listener
- explicit '*' 또는 'broadcast': broadcast event
- empty eventSessionId: session listener는 수신 금지
```

---

### 최우선 2 — close/unload stress test 강화

`WorkspaceManager`와 `FlightDataDashboard.prepareForSessionUnload()`는 방향은 좋지만, 실제 MATLAB UI에서는 invalid handle/timer/future/listener가 얽히기 쉽습니다. 다음 test를 반드시 추가해야 합니다.

```matlab
testCloseTabDuringMarkerDrag
testCloseTabDuringSplitterDrag
testCloseTabDuringPlayback
testAsyncDecodeReturnsAfterSessionClose
testSessionScopeClearedAfterTabClose
testUndoServiceRemovedAfterTabClose
```

---

### 최우선 3 — `.frsproj` missing asset warning 구조화

현재 Phase 9는 linked save/load 자체는 구현된 것으로 보이지만, “파일이 없음”을 사용자에게 친절하게 보여주는 UX가 부족합니다.

추가해야 할 최소 구조:

```matlab
classdef LinkedAssetReport
    properties
        MissingFlightFiles
        MissingVideoFiles
        MissingConfigFiles
        ExistingFiles
        RelinkNeeded logical
    end
end
```

---

### 우선 4 — Phase 10은 prototype으로 명확히 제한

현재 Phase 10 서비스 파일이 이미 들어왔으므로, 문서 표현은 다음처럼 바꾸는 것이 안전합니다.

```text
Phase 10: service-level prototype exists.
It does not replace the dashboard decode path by default.
Production shared decode/cache scheduling remains pending.
```

README도 이미 이 방향에 가깝지만, 사용자 계획서 기준으로는 “Phase 10 미착수”가 아니라 “prototype 착수됨, production 전환 전”으로 업데이트해야 합니다.

---

### 우선 5 — GUI scaling 검증

README는 MATLAB Online, 15-inch laptop, non-ASCII Windows path 검증을 요구합니다. ([GitHub][1])

특히 `BodyGrid.ColumnWidth = {leftW, '1x', rightW}` 구조는 단순하고 안정적이지만, 15인치 노트북/MATLAB Online에서는 left/right dock이 숨겨져야 합니다. 이미 `Compact`, `Review`, `Analysis` profile이 있으므로 다음 자동 전환을 권장합니다.

```matlab
if width < 1100
    mode = 'Compact';
elseif width < 1400
    mode = 'Review';
else
    mode = 'Studio';
end
```

---

## 7. 최종 판단

현재 코드는 업로드 계획서의 방향을 상당 부분 반영하고 있습니다. 다만 표현을 정확히 하면 다음과 같습니다.

```text
Phase 1–6: MVP 구현됨. 다중 tab/cleanup/runtime 안정화 필요.
Phase 7: ROI result plumbing 수준. 확장 동결 권장.
Phase 8: service-level MVP 구현됨. full Recalculate UX는 미완성.
Phase 9: linked .frsproj save/load 구현됨. missing asset/relink UX는 미완성.
Phase 10: service-level prototype이 시작됨. production decode path 대체 전 단계.
```

가장 먼저 고칠 부분은 **EventBus session leakage 가능성**, **tab close/unload stress test**, **missing linked asset warning**, **SharedDecode priority 재계산**, **handle array cleanup 안정화**입니다. 이 5개를 먼저 정리하면 MATLAB R2025a+와 MATLAB Online에서의 안정성이 크게 올라갈 것으로 판단됩니다.

[1]: https://github.com/kiki-github2019/flight-dashboard "GitHub - kiki-github2019/flight-dashboard: MATLAB Flight Data Dashboard with EventBus + MVC · GitHub"
