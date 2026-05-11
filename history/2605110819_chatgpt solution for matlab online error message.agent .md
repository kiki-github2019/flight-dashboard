검토 결과, 이번 `runAllTestCodesWithCleanup` 실패는 **핵심 구조 붕괴가 아니라 API 노출/테스트 훅 불일치 문제**에 가깝습니다. 전체 26개 entry 중 20개 pass, 5개 fail, 1개 incomplete이며, Phase 0.5/1/2/4/7/8/9는 모두 통과했습니다. 실패는 주로 Phase 3, Phase 10, 그리고 stress test의 close request 접근 문제에 집중되어 있습니다. 

## 1. 전체 판단

현재 상태는 다음처럼 보는 것이 맞습니다.

```text
Phase 0.5: PASS
Phase 1: PASS
Phase 2: PASS
Phase 3: FAIL, 21/23 pass
Phase 4: PASS
Phase 5: 실질 PASS, 1개 manual skip
Phase 6: 실질 PASS, 1개 manual skip
Phase 7: PASS
Phase 8: PASS
Phase 9: PASS
Phase 10: FAIL, 11/13 pass
Overall: FAILED
```

즉, 기능 대부분은 정상입니다. 남은 실패는 아래 5개입니다.

```text
1. testDragAfterStudioCloseRequest
   - onCloseRequest 접근 제한

2. Phase 3 P3-15
   - cleanupAllControllers 메서드 없음

3. Phase 3 P3-23
   - standalone MouseRouter 호환성 불일치

4. Phase 10 P10-10
   - Dashboard shared decode opt-in hooks missing

5. Phase 10 P10-11
   - Session cleanup hooks missing
```

---

# 2. 실패 원인별 분석 및 수정 방향

## A. `testDragAfterStudioCloseRequest` 실패

오류:

```text
'MATLAB:class:MethodRestricted'
'flightdash.studio.FlightReviewStudioApp' 클래스의 메서드 'onCloseRequest'에 액세스할 수 없습니다.
```

테스트가 다음을 호출하고 있습니다.

```matlab
testCase.Studio.onCloseRequest();
```

그런데 `onCloseRequest`가 `Access = private` 또는 `Access = protected`에 들어가 있어 테스트 클래스에서 직접 호출할 수 없습니다.

### 권장 수정

`FlightReviewStudioApp.m`에 **public wrapper**를 추가하는 방식이 가장 안전합니다.

```matlab
methods (Access = public)
    function requestClose(app)
        % Public test-safe wrapper for Studio close request.
        app.onCloseRequest();
    end
end
```

그리고 test 쪽은 가능하면 다음처럼 바꾸는 것이 더 좋습니다.

```matlab
testCase.Studio.requestClose();
```

다만 이미 테스트가 `onCloseRequest()`를 직접 호출하도록 작성되어 있다면, 더 간단하게 `onCloseRequest` 자체를 public methods block으로 이동해도 됩니다.

```matlab
methods (Access = public)
    function onCloseRequest(app)
        % existing close request body
    end
end
```

### 권장 순위

더 좋은 설계는 `requestClose()` public wrapper 추가입니다.
하지만 기존 테스트를 고치기 어렵다면 `onCloseRequest()`를 public으로 바꾸는 것이 빠릅니다.

---

## B. Phase 3 P3-15 실패 — `cleanupAllControllers` 없음

오류:

```text
cleanupAllControllers check failed:
'flightdash.FlightDataDashboard' 클래스에 대한 인식할 수 없는 메서드, 속성 또는 필드 'cleanupAllControllers'입니다.
```

테스트는 embedded dashboard가 session unload 시 controller/listener/timer/future를 정리할 수 있는 public hook을 기대합니다. 그런데 현재 MATLAB 경로에 잡힌 `+flightdash/FlightDataDashboard.m`에는 `cleanupAllControllers`가 없거나 private 메서드로 되어 있는 것으로 보입니다.

### 권장 수정

`+flightdash/FlightDataDashboard.m`의 public methods block에 다음 메서드를 추가하십시오.

```matlab
methods (Access = public)

    function prepareForSessionUnload(app)
        % Idempotent cleanup hook for embedded Studio tab removal.
        try
            app.cleanupAllControllers();
        catch ME
            app.logCaught(ME, 'SessionUnload:cleanupAllControllers');
        end

        try
            if isprop(app, 'SharedDecodeService') && ...
                    ~isempty(app.SharedDecodeService) && isvalid(app.SharedDecodeService)
                app.SharedDecodeService.cancelSession(app.ActiveSessionId);
            end
        catch ME
            app.logCaught(ME, 'SessionUnload:sharedDecode');
        end

        try
            if isprop(app, 'SharedCacheService') && ...
                    ~isempty(app.SharedCacheService) && isvalid(app.SharedCacheService)
                app.SharedCacheService.invalidateSession(app.ActiveSessionId);
            end
        catch ME
            app.logCaught(ME, 'SessionUnload:sharedCache');
        end

        try
            if isprop(app, 'UndoService') && ...
                    ~isempty(app.UndoService) && isvalid(app.UndoService)
                app.UndoService.clear();
            end
        catch ME
            app.logCaught(ME, 'SessionUnload:undo');
        end
    end


    function cleanupAllControllers(app)
        % Public idempotent cleanup hook used by Studio and diagnostics.
        try
            app.releaseEmbeddedDragLock();
        catch
        end

        try
            if isprop(app, 'PlaybackCtrl') && ~isempty(app.PlaybackCtrl)
                for k = 1:numel(app.PlaybackCtrl)
                    if isvalid(app.PlaybackCtrl(k)) && ...
                            ismethod(app.PlaybackCtrl(k), 'stopAllFlightPlayback')
                        app.PlaybackCtrl(k).stopAllFlightPlayback();
                    end
                end
            end
        catch ME
            app.logCaught(ME, 'ControllerCleanup:playback');
        end

        try
            if isprop(app, 'MarkerDragCtrl') && ~isempty(app.MarkerDragCtrl)
                for k = 1:numel(app.MarkerDragCtrl)
                    if isvalid(app.MarkerDragCtrl(k))
                        if ismethod(app.MarkerDragCtrl(k), 'stopDrag')
                            app.MarkerDragCtrl(k).stopDrag();
                        end
                        if ismethod(app.MarkerDragCtrl(k), 'clearDraggedMarker')
                            app.MarkerDragCtrl(k).clearDraggedMarker();
                        end
                    end
                end
            end
        catch ME
            app.logCaught(ME, 'ControllerCleanup:marker');
        end

        try
            if ismethod(app, 'cleanupAsyncOperations')
                app.cleanupAsyncOperations();
            end
        catch ME
            app.logCaught(ME, 'ControllerCleanup:async');
        end

        try
            if ismethod(app, 'cleanupListeners')
                app.cleanupListeners();
            end
        catch ME
            app.logCaught(ME, 'ControllerCleanup:listeners');
        end

        try
            if ismethod(app, 'cleanupVideoResources')
                app.cleanupVideoResources();
            end
        catch ME
            app.logCaught(ME, 'ControllerCleanup:video');
        end
    end

end
```

중요한 점은 `cleanupAllControllers`가 **public**이어야 한다는 것입니다.
`WorkspaceManager.releaseSessionResources()`와 diagnostic test가 외부에서 호출할 수 있어야 합니다.

---

## C. Phase 3 P3-23 실패 — Standalone MouseRouter mismatch

오류:

```text
Standalone MouseRouter mismatch: hasProp=0 empty=0 standalone=1
```

이 메시지는 standalone `FlightDataDashboard`에 대해 테스트가 다음 조건을 기대한다는 뜻으로 보입니다.

```text
- MouseRouter 속성이 존재해야 함
- standalone에서는 MouseRouter가 비어 있어야 함
- IsEmbedded == false 또는 ActiveSessionId == 'standalone'이어야 함
```

그런데 `hasProp=0`이므로 현재 로드된 `flightdash.FlightDataDashboard`에는 `MouseRouter` property가 없는 상태입니다.

### 권장 수정

`+flightdash/FlightDataDashboard.m`의 public properties에 다음을 반드시 추가하십시오.

```matlab
properties (Access = public)
    MouseRouter = []
    SharedCacheService = []
    SharedDecodeService = []
    UseSharedDecodeService logical = false
    UndoService = []
end
```

그리고 constructor에서 standalone일 때는 다음 상태가 유지되어야 합니다.

```matlab
if app.IsEmbedded
    app.ActiveSessionId = char(sessionId);
    app.RootContainer = parentContainer;
else
    app.ActiveSessionId = 'standalone';
    app.MouseRouter = [];
end
```

또한 `setMouseRouter` public method도 필요합니다.

```matlab
methods (Access = public)
    function setMouseRouter(app, router)
        app.MouseRouter = [];
        try
            if ~isempty(router) && isa(router, 'handle') && isvalid(router)
                app.MouseRouter = router;
                if ismethod(app, 'injectRouterToControllers')
                    app.injectRouterToControllers();
                end
            end
        catch ME
            app.logCaught(ME, 'Studio:mouseRouter');
        end
    end
end
```

---

## D. Phase 10 P10-10 실패 — Shared decode opt-in hook 누락

오류:

```text
Dashboard shared decode opt-in hooks are missing
```

Phase 10은 아직 production decode path를 교체하는 단계가 아니라 **opt-in prototype**이어야 합니다. 따라서 dashboard에는 최소한 다음 hook이 있어야 합니다.

```matlab
setSharedServices
hasSharedServices
setSharedDecodeEnabled
```

### 권장 수정

`+flightdash/FlightDataDashboard.m` public methods block에 다음을 추가하십시오.

```matlab
methods (Access = public)

    function setSharedServices(app, cacheService, decodeService)
        app.SharedCacheService = cacheService;
        app.SharedDecodeService = decodeService;
    end

    function tf = hasSharedServices(app)
        tf = false;
        try
            tf = isprop(app, 'SharedCacheService') && ...
                 isprop(app, 'SharedDecodeService') && ...
                 ~isempty(app.SharedCacheService) && ...
                 ~isempty(app.SharedDecodeService) && ...
                 isvalid(app.SharedCacheService) && ...
                 isvalid(app.SharedDecodeService);
        catch
            tf = false;
        end
    end

    function setSharedDecodeEnabled(app, tf)
        app.UseSharedDecodeService = logical(tf);
    end

end
```

추가로 diagnostic이 “opt-in only”를 검사한다면 constructor 기본값은 반드시 false여야 합니다.

```matlab
UseSharedDecodeService logical = false
```

---

## E. Phase 10 P10-11 실패 — Session cleanup hook 누락

오류:

```text
Session cleanup hooks are missing
```

이것은 B 항목과 연결됩니다. 보통 테스트는 dashboard에 다음 중 일부가 있는지 확인할 가능성이 큽니다.

```matlab
ismethod(dash, 'prepareForSessionUnload')
ismethod(dash, 'cleanupAllControllers')
```

따라서 B에서 제시한 public method 2개를 추가하면 P3-15와 P10-11이 동시에 해결될 가능성이 큽니다.

필수 public hook:

```matlab
prepareForSessionUnload
cleanupAllControllers
```

---

# 3. 수정 후 기대 결과

위 수정이 적용되면 다음 실패가 해소될 가능성이 높습니다.

```text
testDragAfterStudioCloseRequest
  -> onCloseRequest public 또는 requestClose wrapper로 해결

P3-15 cleanupAllControllers
  -> public cleanupAllControllers 추가로 해결

P3-23 Standalone MouseRouter mismatch
  -> MouseRouter property 추가 + standalone empty 유지로 해결

P10-10 shared decode opt-in hooks
  -> setSharedServices / hasSharedServices / setSharedDecodeEnabled 추가로 해결

P10-11 session cleanup hooks
  -> prepareForSessionUnload / cleanupAllControllers 추가로 해결
```

---

# 4. 수정 후 실행 순서

수정 후 MATLAB Online에서 반드시 cache를 초기화한 뒤 재실행하십시오.

```matlab
clear classes
rehash toolboxcache
```

먼저 실패 항목만 빠르게 확인하십시오.

```matlab
results3  = flightdash.studio.diag.verifyPhase3();
results10 = flightdash.studio.diag.verifyPhase10();
```

그 다음 stress test와 전체 suite를 실행하십시오.

```matlab
runMultiInstanceTests();
runAllTestCodesWithCleanup();
```

---

# 5. 현재 상태에 대한 최종 평가

이번 로그 기준으로 프로젝트는 상당히 안정화되었습니다. 특히 다음 항목이 모두 통과한 것은 긍정적입니다.

```text
Phase 0.5 encoding/formatting
Phase 1 Studio shell
Phase 2 model layer
Phase 4 EventBus + Undo/Redo
Phase 7 ROI result plumbing
Phase 8 Dirty/Recalculate MVP
Phase 9 Project Save/Load
```

남은 실패는 대부분 다음 성격입니다.

```text
- public API 노출 누락
- 테스트가 기대하는 hook 이름과 실제 구현 이름 불일치
- standalone/embedded 공통 property 선언 누락
- Phase 10 prototype opt-in interface 누락
```

따라서 대규모 재설계보다 **FlightDataDashboard.m과 FlightReviewStudioApp.m에 public compatibility hook을 보강하는 방식**으로 해결하는 것이 가장 안전합니다.
