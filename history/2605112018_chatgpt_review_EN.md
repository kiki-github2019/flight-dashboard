# Review Results

Please note that, in this environment, `git clone` failed due to a DNS error, so I could not download the repository locally or perform runtime execution verification. Instead, I directly inspected the original files on GitHub and performed a **static code review**. MATLAB execution results should be verified by the user in MATLAB Online / R2025a+ using the verification commands below.

## 1. Summary of the Current Repository State

The current repository is no longer just a single `FlightDataDashboard` application. It has been expanded into an integrated Studio structure centered on `FlightReviewStudio`. According to the README, `FlightReviewStudio.m` is the Studio entry point, the actual implementation is located in `+flightdash/+studio/FlightReviewStudioApp.m`, and the existing `FlightDataDashboard.m` is retained as a compatibility wrapper. ([GitHub][1])

The README explains that the current stabilization scope includes Phase 1–6, Phase 8a/8b/8c, Phase 9, and the Phase 10 prototype. It also explicitly states that `.frsproj` is a zip-based linked project format and does not include raw flight/video files. ([GitHub][1])

The uploaded plan proposed stabilizing Phase 1–6 and Phase 9 first, freezing Phase 7 at the ROI result plumbing level, and starting Phase 10 as a prototype only after stabilization. Compared with the current repository documentation, the biggest difference is that **part of the Phase 10 prototype has already been introduced**.

---

## 2. Phase-by-Phase Implementation Assessment

| Phase | Current Assessment | Comment |
|---|---:|---|
| Phase 1 — Studio Shell | Implemented; stabilization required | Project Explorer, Workspace, Right Dock, and Status Bar structures exist |
| Phase 2 — Project/Session Models | Implemented | Serializer and model round-trip verification is required |
| Phase 3 — Embedded Dashboard Tabs | Implemented; high risk | The dashboard is created directly inside a `uitab`. The direction is reasonable given MATLAB limitations |
| Phase 4 — Session-scoped EventBus | Implemented; leakage risk exists | The rule for handling missing `SessionId` events is still risky |
| Phase 5 — Explorer/Object Manager | MVP level | Not yet an OriginPro-level object hierarchy |
| Phase 6 — Toolbar/Menu/Inspector/GUI Mode | MVP level | GUI mode profile structure exists, but small-screen UX verification is required |
| Phase 7 — Analysis/Result | Early plumbing | Recommended to freeze rather than expand into a full Analysis Dialog |
| Phase 8 — Dirty/Recalculate | Service MVP | `DirtyTracker`, queue, and recalculate service level only. UI is not complete |
| Phase 9 — Save/Load | Linked mode implemented | Missing asset warning / relink UX is insufficient |
| Phase 10 — Shared Decode/Cache | Prototype started | Currently a service-level prototype, not production integration |

---

## 3. Positive Findings

First, separating the Studio and legacy dashboard entry points is appropriate. The README also clearly distinguishes the roles of `FlightReviewStudio` and `FlightDataDashboard`. ([GitHub][1])

Second, it is good that `WorkspaceManager` manages dashboards per session using `containers.Map`, and that it is designed to clean up the dashboard, mouse router, shared decode/cache, and undo service when a tab is deleted. In particular, the structure in which `releaseSessionResources()` calls mouse router cancellation, dashboard unload, shared decode cancellation, cache invalidation, and undo service removal is aligned with the stabilization direction for Phase 3/4/10.

Third, the inclusion of `subscribe(eventName, callback, sessionId)`, `subscribeForApp`, and `acceptsSession` in `EventBus` provides the core foundation for session-scoped routing. The direction is also reasonable because it considers both the existing single-dashboard mode and the Studio embedded dashboard mode.

Fourth, `ProjectSerializer` separates project/session/figure/theme/result/external link data into JSON files and includes comments and structure indicating that handle objects should not be serialized. The linked mode direction for `.frsproj` is correct.

Fifth, although the Phase 10 prototype’s `SharedDecodeService` and `SharedCacheService` are still simple, they include concepts such as session generation, cancellation, stale discard, and LRU eviction, which makes them suitable as a foundation for later expansion.

---

## 4. Major Risks and Possible Bugs

### A. EventBus Session Leakage Risk

This is the most important risk.

`EventBus.acceptsSession(listenerSessionId, eventSessionId)` currently returns true under the following condition:

```matlab
isempty(listenerSessionId) || isempty(eventSessionId) || strcmp(listenerSessionId, eventSessionId)
```

With this structure, **if `eventSessionId` is empty, even session-specific listeners receive the event**. In other words, if any callback omits `SessionId`, all session controllers may react. Although `attachSession()` tries to compensate using `SessionScope.getActive()`, it is difficult to guarantee that `SessionScope` is always accurate during tab switching, dragging, asynchronous callbacks, or standalone fallback situations.

Recommended modification:

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

In short, it is safer **not to treat an empty SessionId as a broadcast**, and instead introduce an explicit broadcast token.

---

### B. The Phase 10 Shared Cache Is Closer to a Session-Isolated Cache Than a “Shared Cache”

`SharedCacheService.makeKey()` includes `sessionId` in the key. Therefore, even if the video path, channel, and frame are the same, a cache hit will not occur when the session differs.

This is good for safety, but it limits the performance benefits of a “shared cache.” The current structure is effectively closer to a **Studio-owned session-scoped cache container**.

Recommended direction:

1. Keep the session-isolated key for now.
2. Introduce an optional two-tier cache in Phase 10b:

   * Tier 1: session-local cache key
   * Tier 2: content-addressed shared frame key  
     Example: `hash(videoPath + fileSize + modifiedTime + frameNo)`

---

### C. SharedDecodeService Priority Is Not Dynamically Updated

`Priority` is fixed at the time `requestFrame()` is called. If the user later switches to another tab and `ActiveSessionId` changes, the priority of existing queued requests is not updated.

Recommended modification:

In `nextQueueIndex()`, do not rely only on the stored `req.Priority`; instead, recalculate priority based on the current `ActiveSessionId`.

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

### D. ProjectSerializer Saves `external_links.json`, but Load-Time Validation/Warnings Are Weak

`ProjectSerializer.save()` creates `external_links.json`. However, the current load flow appears focused on restoring manifest/project/session/figure/theme/result data and validating counts. The design for checking the existence of external assets and returning structured warnings to the user still appears insufficient.

The README and status document state that missing external files should be handled as linked asset warnings, not project corruption. ([GitHub][1])

Recommended addition:

```matlab
project.LinkedAssetWarnings = flightdash.project.ExternalLinkValidator.validate(project);
```

Alternatively, extend the load result as follows:

```matlab
[project, report] = ProjectSerializer.load(filePath);
```

The `report` should include:

```matlab
report.MissingFlightFiles
report.MissingVideoFiles
report.MissingConfigFiles
report.SchemaWarnings
report.RelinkCandidates
```

---

### E. `cleanupHandleProperty` May Fail for Handle Arrays

`FlightDataDashboard.cleanupHandleProperty()` uses the following pattern:

```matlab
if isobject(h) && isvalid(h)
```

However, if `h` is a handle array, `isvalid(h)` may return a logical array, which can cause an error in the `&&` condition. Although this function is wrapped in a catch block, if the error is caught, the corresponding handle array cleanup may not be performed properly. This is risky when `PlotView`, controller arrays, or listener arrays are involved.

Recommended modification:

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

### F. MVC/Component Separation Is Not Yet “Complete Separation”

Many states in `FlightDataDashboard` are still maintained as public properties, and controllers/managers directly reference the `app` object. The code comments also state that properties have been left public because of MATLAB Online private access restrictions.

Therefore, the current structure should be described not as complete MVC, but rather as:

> A strangler-pattern refactoring stage that gradually separates the existing monolithic app into controllers, views, models, and services.

The recommended future refactoring direction is as follows:

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

Controllers should gradually stop holding the entire app object and instead receive only the required service/state interfaces.

---

## 5. Compatibility Check from the MATLAB R2025a+ Perspective

The current code direction appears generally compatible with R2025a or later. However, the following must be verified in MATLAB Online / R2025a:

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

Manual verification is even more important:

```text
1. Launch FlightReviewStudio
2. Create two or more Review Sessions
3. Perform marker drag in each tab
4. Switch tabs during drag
5. Close a tab during drag
6. Close a tab during playback
7. Save temp.frsproj
8. Confirm that temp.frsproj.zip does not remain
9. Save/load under a Korean path, for example: D:\테스트\비행리뷰\temp.frsproj
10. Delete external flight/video files and then load the project
11. Launch standalone FlightDataDashboard
```

---

## 6. Improvement Priorities

### Top Priority 1 — Modify the EventBus Session Rule

The biggest current risk is session leakage. The current structure, which permits `SessionId == ''` as broadcast, is unfavorable for embedded multi-session stability.

Modification policy:

```text
- Empty listenerSessionId: global listener
- Exact eventSessionId match: session listener
- Explicit '*' or 'broadcast': broadcast event
- Empty eventSessionId: session listener must not receive the event
```

---

### Top Priority 2 — Strengthen Close/Unload Stress Tests

The direction of `WorkspaceManager` and `FlightDataDashboard.prepareForSessionUnload()` is good. However, in actual MATLAB UI behavior, invalid handles, timers, futures, and listeners can easily become entangled. The following tests should be added without fail:

```matlab
testCloseTabDuringMarkerDrag
testCloseTabDuringSplitterDrag
testCloseTabDuringPlayback
testAsyncDecodeReturnsAfterSessionClose
testSessionScopeClearedAfterTabClose
testUndoServiceRemovedAfterTabClose
```

---

### Top Priority 3 — Structure `.frsproj` Missing Asset Warnings

Currently, Phase 9 appears to implement linked save/load itself, but the UX for clearly informing the user that “files are missing” is insufficient.

The minimum structure to add is:

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

### Priority 4 — Clearly Limit Phase 10 to a Prototype

Because Phase 10 service files have already been added, it is safer to describe the documentation as follows:

```text
Phase 10: service-level prototype exists.
It does not replace the dashboard decode path by default.
Production shared decode/cache scheduling remains pending.
```

The README is already close to this direction. However, relative to the user’s plan, the wording should be updated from “Phase 10 not started” to “prototype started; before production transition.”

---

### Priority 5 — Verify GUI Scaling

The README requires verification for MATLAB Online, a 15-inch laptop, and non-ASCII Windows paths. ([GitHub][1])

In particular, the `BodyGrid.ColumnWidth = {leftW, '1x', rightW}` structure is simple and stable, but on a 15-inch laptop or in MATLAB Online, the left/right dock should be hidden when needed. Since `Compact`, `Review`, and `Analysis` profiles already exist, the following automatic switching is recommended:

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

## 7. Final Assessment

The current code substantially reflects the direction of the uploaded plan. However, to describe it accurately:

```text
Phase 1–6: MVP implemented. Multi-tab / cleanup / runtime stabilization required.
Phase 7: ROI result plumbing level. Expansion freeze recommended.
Phase 8: service-level MVP implemented. Full Recalculate UX is incomplete.
Phase 9: linked .frsproj save/load implemented. Missing asset / relink UX is incomplete.
Phase 10: service-level prototype has started. Before production decode path replacement.
```

The first items to fix are **EventBus session leakage risk**, **tab close/unload stress tests**, **missing linked asset warnings**, **SharedDecode priority recalculation**, and **handle array cleanup stabilization**. Addressing these five items first should significantly improve stability in MATLAB R2025a+ and MATLAB Online.

[1]: https://github.com/kiki-github2019/flight-dashboard "GitHub - kiki-github2019/flight-dashboard: MATLAB Flight Data Dashboard with EventBus + MVC · GitHub"
