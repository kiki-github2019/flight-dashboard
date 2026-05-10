Below is a **new English implementation/stabilization plan based on the current repository state**. It assumes the current code already contains MVP implementations for Phase 1–6, Phase 8a–8c, and Phase 9, while Phase 7 is only early ROI-result plumbing and Phase 10 has not started. This updates the earlier migration plan in the attached markdown review, which identified Phase 3, Phase 4, Phase 8, Phase 9, and Phase 10 as the highest-risk areas. 

---

# FlightDataReviewStudio Stabilization and Development Plan

## Current-Code-Based English Version

## 0. Executive Summary

The repository has moved beyond a pure planning stage. The current codebase now provides:

* `FlightReviewStudio` as the integrated Studio entry point.
* `FlightDataDashboard` as the legacy standalone compatibility entry point.
* A Studio shell with Project Explorer, workspace tabs, embedded dashboard sessions, right dock, and status bar.
* Project/session/value model classes.
* Embedded dashboard tabs drawn directly inside MATLAB UI containers.
* Session-scoped EventBus routing.
* Project Explorer and Object Manager MVP.
* Toolbar, menu, Inspector, GUI mode, and status bar shell MVP.
* Narrow Phase 8 recalculate/dirty/queue services.
* Linked `.frsproj` save/load support.

The README explicitly states that `FlightReviewStudio.m` is the Studio entry point, its implementation lives in `+flightdash/+studio/FlightReviewStudioApp.m`, and `FlightDataDashboard.m` remains a compatibility wrapper for `+flightdash/FlightDataDashboard.m`. ([GitHub][1])

The current stabilization focus should **not** be “start Phase 10 immediately.” Instead, the next objective should be:

> **Freeze and verify Phase 1–6 and Phase 9, keep Phase 7 narrow, clarify Phase 8 as MVP-only, improve linked-project asset handling, then begin a small Phase 10 prototype.**

---

## 1. Current Phase Status

| Phase                                            |                     Current Status | Updated Interpretation                                                       |
| ------------------------------------------------ | ---------------------------------: | ---------------------------------------------------------------------------- |
| Phase 1 — Studio Shell                           |                        Implemented | Treat as MVP implemented; verify runtime layout and MATLAB Online scaling.   |
| Phase 2 — Project / Session Models               |                        Implemented | Treat as implemented; verify serialization and schema migration assumptions. |
| Phase 3 — Embedded Dashboard Tabs                |             Implemented, high risk | Treat as MVP implemented; must stress-test multi-tab callbacks and cleanup.  |
| Phase 4 — Session-Scoped Events                  | Implemented, needs leakage testing | Treat as implemented; verify listener guards and active-session routing.     |
| Phase 5 — Project Explorer / Object Manager      |                    MVP implemented | Do not claim full OriginPro Object Manager behavior yet.                     |
| Phase 6 — Toolbar / Menu / Inspector / GUI Mode  |                    MVP implemented | Status bar and Inspector are still partly shell/MVP.                         |
| Phase 7 — Analysis Dialog / Theme / Result Model |                Early plumbing only | Freeze until Phase 1–6 and Phase 9 are clean.                                |
| Phase 8 — Recalculate / Dirty / Auto Queue       |             Narrow MVP implemented | Do not treat as full Dirty DAG / Recalculate UX.                             |
| Phase 9 — Project Save / Load                    |            Linked mode implemented | Pack Project and relative-path repair remain future work.                    |
| Phase 10 — Shared Decode / Shared Cache Services |                        Not started | Start only after stabilization gates pass.                                   |

The README defines the active scope as Phase 1–6, Phase 8a/8b/8c, and Phase 9, while also stating that Phase 7 is only ROI result plumbing and broader Analysis Dialog work should wait. ([GitHub][1])

---

# 2. Revised Development Plan

## Phase A — Stabilization Gate Before Further Expansion

### Goal

Create a reliable baseline before adding more features. This phase replaces the previous idea of moving directly from Phase 9 into Phase 10.

### Scope

1. Run all existing diagnostic scripts.
2. Manually verify embedded multi-session behavior.
3. Confirm standalone dashboard compatibility.
4. Fix documentation contradictions.
5. Add missing runtime stress tests.

### Required MATLAB Verification Commands

```matlab
clear classes
rehash toolboxcache

results05 = flightdash.studio.diag.verifyPhase0_5();
results1  = flightdash.studio.diag.verifyPhase1();
results2  = flightdash.studio.diag.verifyPhase2();
results3  = flightdash.studio.diag.verifyPhase3();
results4  = flightdash.studio.diag.verifyPhase4();
results5  = flightdash.studio.diag.verifyPhase5();
results6  = flightdash.studio.diag.verifyPhase6();
results8  = flightdash.studio.diag.verifyPhase8();
results9  = flightdash.studio.diag.verifyPhase9();
multi     = flightdash.studio.diag.runMultiInstanceTests();
```

The README already recommends clearing cached classes and running these verification commands after pulling updates in MATLAB Online. ([GitHub][1])

### Manual Runtime Scenarios

The following scenarios must pass before Phase 10 begins:

1. Create multiple embedded dashboard tabs.
2. Delete tabs while no operation is active.
3. Delete tabs while marker drag, splitter drag, or playback is active.
4. Switch tabs while dragging markers or splitters.
5. Save `temp.frsproj` and confirm that no unwanted `temp.frsproj.zip` file remains.
6. Load a project with missing external flight/video files.
7. Save/load under a Korean or other non-ASCII Windows path.
8. Confirm that standalone `FlightDataDashboard` still launches.

These manual scenarios are also listed in the repository README as important runtime checks. ([GitHub][1])

### Exit Criteria

* All diagnostic scripts pass.
* Manual multi-tab stress tests pass.
* Standalone dashboard still works.
* `.frsproj` save/load round trip works.
* README and status documentation use the same phase wording.
* No known blocker remains in tab close, project close, or session switch.

---

## Phase B — Phase 1–6 Hardening

## B1. Phase 1 — Studio Shell Hardening

### Current State

The Studio shell exists and includes:

* Project Explorer.
* Central workspace tab group.
* Embedded `flightdash.FlightDataDashboard` sessions.
* Right dock with Inspector, Object Manager, logs, and apps placeholder.
* Status bar.

The README explicitly describes this Studio shell structure. ([GitHub][1])

### Required Work

1. Verify that all shell regions resize correctly in:

   * MATLAB Desktop.
   * MATLAB Online.
   * 15-inch laptop display.
   * 24-inch FHD monitor.
2. Ensure placeholder panels are visibly marked as placeholder/MVP.
3. Add defensive `isvalid` checks around all UI region updates.
4. Confirm that Studio shutdown deletes all region managers safely.
5. Ensure the shell does not assume a fixed pixel size.

### Acceptance Criteria

* `FlightReviewStudio` opens without warnings.
* Resizing does not hide essential controls.
* Closing the Studio produces no invalid-object errors.
* Status bar, right dock, workspace, and explorer remain visually consistent.

---

## B2. Phase 2 — Project / Session Model Hardening

### Current State

The repository contains project/session/value models and uses `.frsproj` for linked project storage. The project archive contains metadata, session JSON, themes, results, and external links. ([GitHub][1])

### Required Work

1. Confirm that all model classes are serializable without saving unstable handle objects.
2. Add or verify:

   * `SchemaVersion`.
   * `ProjectId`.
   * `SessionId`.
   * `CreatedAt`.
   * `ModifiedAt`.
   * `DirtyFlag`.
   * `SourceDataHash`.
   * `SyncStateHash`.
3. Separate persistent state from UI/runtime handles.
4. Add migration stubs even if only one schema version exists.
5. Ensure loaded projects with older or missing fields degrade gracefully.

### Acceptance Criteria

* Project model can round-trip through `ProjectSerializer`.
* Missing optional fields are filled with defaults.
* UI handles are never serialized as project state.
* Model classes can be used in MATLAB R2025a/R2026a.

---

## B3. Phase 3 — Embedded Dashboard Hardening

### Current State

The embedded dashboard is drawn directly into MATLAB tab containers because MATLAB cannot embed a separate `uifigure` inside a `uitab`. The README correctly documents this limitation and the chosen workaround. ([GitHub][1])

### Main Risk

MATLAB has only one figure-level mouse callback slot per figure. Multiple embedded dashboard sessions may compete for drag, pan, zoom, or splitter callbacks.

### Required Work

1. Verify all figure-level mouse routing through the Studio-level mouse router.
2. Ensure every drag/pan/splitter operation is gated by:

   * `SessionId`.
   * active tab.
   * valid UI object.
   * current operation generation/token.
3. Separate cleanup into:

   * session unload cleanup;
   * project close cleanup;
   * global Studio shutdown cleanup.
4. Cancel or ignore async work from closed sessions.
5. Add stress tests for:

   * tab switch during drag;
   * tab close during drag;
   * playback during tab switch;
   * async decode result returning after tab close.

### Acceptance Criteria

* Two or more dashboard tabs can be used without event leakage.
* Dragging in one tab never moves markers in another tab.
* Closing a tab does not break other sessions.
* Async results from deleted sessions are discarded safely.

---

## B4. Phase 4 — Session-Scoped EventBus Hardening

### Current State

The codebase uses session-scoped EventBus routing. The current `FlightReviewStudioApp` code comments describe active-session tracking and future callback gating, while EventBus comments indicate older callbacks may omit `SessionId` in Studio mode. ([GitHub][2])

### Required Work

1. Audit every `EventBus.publish` call.
2. Audit every listener callback.
3. Define the exact rule:

   * `SessionId == ''` means broadcast/system event.
   * non-empty `SessionId` means session-local event.
4. Add a helper guard such as:

```matlab
function tf = acceptsSession(obj, eventData)
    tf = isempty(eventData.SessionId) || strcmp(eventData.SessionId, obj.SessionId);
end
```

5. Add diagnostics for event leakage:

   * publish from Session A;
   * assert Session B does not react;
   * publish broadcast;
   * assert both sessions react only when intended.

### Acceptance Criteria

* Event routing does not depend on accidental active tab state after dispatch.
* Legacy single-dashboard mode remains compatible.
* Session-local events do not leak across tabs.
* Broadcast events are explicit and documented.

---

## B5. Phase 5 — Project Explorer / Object Manager MVP Hardening

### Current State

Project Explorer and Object Manager are implemented as MVP features. The README states that Object Manager currently covers MVP handles and does not yet expose a full plot/ROI hierarchy. ([GitHub][1])

### Required Work

1. Keep Phase 5 scope intentionally limited:

   * project nodes;
   * session nodes;
   * figure/result/theme nodes;
   * active object selection;
   * basic visibility/refresh behavior.
2. Do not attempt OriginPro-level drag-and-drop object management yet.
3. Add right-click context menus only for stable operations:

   * rename;
   * activate;
   * close session;
   * remove result;
   * show properties.
4. Add refresh debouncing to avoid expensive tree rebuilds.
5. Add missing-node recovery after project load.

### Acceptance Criteria

* Project Explorer reflects the current project model.
* Selecting a session activates the correct workspace tab.
* Object Manager updates for the active dashboard only.
* Full plot/ROI hierarchy is documented as future work.

---

## B6. Phase 6 — Toolbar / Menu / Inspector / GUI Mode Hardening

### Current State

The repository treats toolbar/menu/Inspector/GUI mode as MVP. The status bar shell exists, but README says status bar values are partly placeholders. ([GitHub][1])

### Required Work

1. Route all toolbar/menu actions through `CommandRouter`.
2. Avoid direct calls from toolbar buttons into dashboard internals.
3. Ensure GUI mode switching uses visibility/layout profiles instead of reconstructing the entire UI.
4. Mark placeholder status values explicitly.
5. Add a small-screen mode:

   * collapse right dock;
   * reduce toolbar density;
   * allow Object Manager/Inspector as toggleable panels.
6. Ensure mode switching does not reset loaded data, ROI selections, playback state, or plot zoom.

### Acceptance Criteria

* GUI mode switching is reversible.
* Active session actions are routed correctly.
* Status bar placeholder values are not mistaken for real statistics.
* MATLAB Online layout remains usable on a 15-inch laptop.

---

# 3. Phase C — Phase 7 Scope Freeze and Minimal Completion

## Phase 7 — Analysis Dialog / Theme / Result Model

### Current State

Phase 7 is **not full Analysis Dialog completion**. The status document states that ROI result plumbing exists through `AnalysisService`, `RoiStatisticsAnalyzer`, and `verifyPhase7`, but it should remain frozen until Phase 1–6 and Phase 9 are clean. ([GitHub][3])

### Updated Goal

Do **not** expand Phase 7 into a full Analysis Dialog yet. Instead, define Phase 7 as:

> A minimal ROI statistics result pipeline that can create, store, serialize, and refresh one ROI-based `ReviewResultModel`.

### Required Work

1. Confirm `AnalysisService` is a thin orchestration layer.
2. Confirm `RoiStatisticsAnalyzer` performs actual computation or delegates cleanly.
3. Confirm `ReviewResultModel` stores:

   * result type;
   * source session;
   * ROI/time range;
   * source hash;
   * sync hash;
   * calculated values;
   * timestamp;
   * error state.
4. Confirm `AnalysisThemeModel` stores input defaults without depending on UI handles.
5. Add one minimal UI entry point:

   * “Compute ROI Statistics”
   * “Save as Result”
   * “Show Result Metadata”

### Out of Scope

* Full Analysis Dialog tree.
* Batch analysis.
* Theme gallery.
* Complex result UI.
* Cross-result workflows.
* Report generation.

### Acceptance Criteria

* One ROI statistics result can be created.
* The result survives `.frsproj` save/load.
* The result can become dirty/stale when its source changes.
* No broader Analysis Dialog expansion is started before stabilization completes.

---

# 4. Phase D — Phase 8 MVP Clarification and Controlled Integration

## Phase 8 — Recalculate / Dirty / Auto Queue

### Current State

The status document says Phase 8a/8b/8c have small services:

* `RecalculateService`
* `RecalculateQueue`
* `DirtyTracker`
* `verifyPhase8`

It also states that the supported scope is intentionally narrow: one ROI result can be marked Manual/Auto/Frozen, hash changes can mark results dirty/stale, dependencies can be marked in topological order, cycles are rejected, and Auto results can be queued with debounce/latest-request coalescing. ([GitHub][3])

### Documentation Conflict

README also says “Dirty DAG, dependency propagation, and automatic recalculation are deferred,” while the status document says a narrow MVP exists. This must be corrected. ([GitHub][1])

### Updated Goal

Treat Phase 8 as:

> Narrow service-level MVP implemented; full UI and production-grade recalculation workflow pending.

### Required Work

1. Update README wording to remove ambiguity.
2. Add a result status badge:

   * Clean
   * Dirty
   * Stale
   * Frozen
   * Error
3. Add minimal stale warning for Frozen results.
4. Ensure dependency cycles fail safely with a clear error.
5. Add logging for recalculation decisions.
6. Add debounce configuration as a constant or preference.
7. Keep all recalculation sequential for now.

### Do Not Implement Yet

The status document explicitly says not to assume these features exist before a later shared-worker phase:

* `parfeval` priority scheduling.
* Cross-session shared recalculation workers.
* Frozen stale-result acknowledgement UI. ([GitHub][3])

### Acceptance Criteria

* `verifyPhase8()` passes.
* One ROI result can be dirty/clean/stale.
* Auto mode does not recalculate on every frame.
* Dependency order is deterministic.
* README accurately describes Phase 8 as MVP-only.

---

# 5. Phase E — Phase 9 Linked Project Save/Load Stabilization

## Phase 9 — Project Save / Load

### Current State

`.frsproj` v1 is a zip-based linked project format. It stores metadata and references external assets by path; it does not pack raw flight data or video bytes. The archive currently includes `manifest.json`, `project.json`, session JSON, themes, results, and `external_links.json`. ([GitHub][1])

The README also states that `ProjectSerializer.save(project, filePath)` should create the requested `.frsproj` path exactly and normalize the final filename to avoid MATLAB `zip()` producing `*.frsproj.zip`. ([GitHub][1])

### Updated Goal

Treat Phase 9 as:

> Linked-project save/load implemented. Pack Project is not implemented.

### Required Work

1. Confirm `.frsproj` path creation:

   * no accidental `.frsproj.zip`;
   * no temp archive left behind;
   * safe overwrite behavior.
2. Confirm round-trip persistence for:

   * project metadata;
   * sessions;
   * figures;
   * results;
   * themes;
   * external links.
3. Add missing external asset warnings:

   * missing flight log;
   * missing video;
   * missing config/coastline file.
4. Add a Relink UX design:

   * locate missing file;
   * update `external_links.json`;
   * revalidate source hash.
5. Add non-ASCII path tests.
6. Add schema migration stub:

   * `SchemaVersion == 1`;
   * future `migrateProjectSchema(projectStruct)` entry point.

### Out of Scope

* Packing raw flight logs.
* Packing video bytes.
* Relative path repair.
* Cloud sync.
* Project asset deduplication.

The README already lists `.frsproj` linked mode only, Pack Project not implemented, and relative path repair not implemented. ([GitHub][1])

### Acceptance Criteria

* Save/load works with Korean Windows paths.
* Missing external files are warnings, not project corruption.
* Results and themes survive round trip.
* The project can be opened even when external assets are temporarily unavailable.

---

# 6. Phase F — Documentation Alignment

## Required Documentation Changes

### README Current Phase Scope

Replace ambiguous Phase 8 wording with:

```text
Phase 8a/8b/8c are implemented only as narrow service-level MVPs.
They support ROI-result dirty/stale marking, simple dependency ordering,
cycle rejection, and debounced sequential Auto recalculation. Full Dirty DAG UX,
Frozen acknowledgement UI, and shared worker scheduling are not implemented.
```

### README Known Limitations

Replace:

```text
Dirty DAG, dependency propagation, and automatic recalculation are deferred.
```

with:

```text
Full Dirty DAG UX and production-grade automatic recalculation are deferred.
A narrow Phase 8 service MVP exists for ROI results only.
```

### Phase 7 Wording

Use:

```text
Phase 7 currently contains early ROI result plumbing only.
Full Analysis Dialog, batch analysis, theme gallery, and result UI workflows
must remain frozen until Phase 1–6 and Phase 9 verification is clean.
```

### Phase 9 Wording

Use:

```text
Phase 9 implements linked `.frsproj` save/load only.
Raw flight logs and video files are not packed into the project archive.
Missing external files must be shown as linked-asset warnings.
```

---

# 7. Phase G — Test Plan Expansion

## Automated Tests to Add

### G1. Project Serializer Tests

```matlab
function testProjectSerializerExactExtension()
    p = flightdash.project.ProjectModel();
    tmp = [tempname, '.frsproj'];
    flightdash.project.ProjectSerializer.save(p, tmp);
    assert(isfile(tmp));
    assert(~isfile([tmp, '.zip']));
end
```

### G2. Missing External Asset Test

```matlab
function testMissingExternalAssetIsWarning()
    % Create project with external_links.json pointing to a deleted file.
    % Load project.
    % Assert project loads and reports warning instead of throwing corruption error.
end
```

### G3. Session Event Leakage Test

```matlab
function testSessionScopedEventsDoNotLeak()
    % Create two sessions.
    % Publish a session-local event for Session A.
    % Assert Session B listener is not triggered.
end
```

### G4. Tab Close During Drag Test

```matlab
function testCloseTabDuringDragDoesNotCrash()
    % Start drag operation in Session A.
    % Close Session A tab.
    % Assert no invalid UI handle error.
    % Assert Session B remains usable.
end
```

### G5. Recalculate Cycle Rejection Test

```matlab
function testDirtyTrackerRejectsCycles()
    % Create A -> B -> A dependency.
    % Assert DirtyTracker rejects cycle with controlled error.
end
```

---

# 8. Phase H — Phase 10 Preparation Only

## Phase 10 — SharedDecodeService / SharedCacheService

### Status

Not started.

### Do Not Begin Full Implementation Yet

Phase 10 should not begin until:

1. Phase 1–6 diagnostics pass.
2. Phase 9 linked save/load passes.
3. Multi-instance tab stress tests pass.
4. Event leakage tests pass.
5. Async cancellation behavior is understood.
6. Phase 8 remains clearly MVP-scoped.

### Prototype Scope Only

The first Phase 10 step should be a prototype, not production integration.

### Prototype Goals

1. Two embedded sessions request video frames concurrently.
2. One shared decode service receives requests.
3. Active session receives higher priority.
4. Old frame requests are coalesced by latest-frame-only policy.
5. Cancelled or stale results are discarded safely.
6. Closed-session results are ignored.

### Prototype Non-Goals

* Full shared cache service.
* GPU scheduling.
* Multi-video prefetch policy.
* Cross-session memory budgeting.
* Production UI integration.

### Acceptance Criteria

* Prototype can demonstrate correct priority behavior.
* No stale decode result updates a closed or inactive session.
* Existing single-dashboard async decode path remains functional.
* Prototype can be disabled with a feature flag.

---

# 9. Updated Roadmap

## Immediate Next Step: Stabilization Sprint

1. Run all diagnostics.
2. Fix Phase 8 documentation conflict.
3. Add missing external asset warning behavior.
4. Add multi-tab event leakage tests.
5. Add tab-close-during-drag stress tests.
6. Verify Korean/non-ASCII path save/load.
7. Confirm standalone dashboard still launches.

## Next Sprint: Phase 7 Minimal Result Completion

1. Freeze full Analysis Dialog expansion.
2. Stabilize ROI result creation.
3. Persist ROI result through `.frsproj`.
4. Show result dirty/stale status.
5. Add minimal result metadata view.

## Next Sprint: Phase 8 UI-Minimal Integration

1. Add result status badges.
2. Add stale/frozen warning.
3. Add Auto debounce diagnostics.
4. Keep recalculation sequential.
5. Avoid shared workers.

## Later Sprint: Phase 9b Linked Asset UX

1. Add missing asset banner.
2. Add Relink command.
3. Add external link validator.
4. Add relative path design document.
5. Defer Pack Project.

## Final Pre-Phase-10 Gate

1. Multi-session stress tests pass.
2. Event leakage tests pass.
3. Save/load tests pass.
4. Standalone dashboard works.
5. README/status docs are consistent.
6. No unresolved blocker in cleanup, async, or UI callbacks.

---

# 10. Final Implementation Policy

The project should now follow this rule:

> **A phase is not complete because files exist. A phase is complete only when the implementation, runtime behavior, diagnostics, exception handling, and documentation all agree.**

Therefore, the current status should be documented as:

```text
Phase 1–6: MVP implemented; stabilization and runtime verification required.
Phase 7: early ROI result plumbing only; full Analysis Dialog deferred.
Phase 8: narrow service-level MVP; full Dirty DAG/Recalculate UX deferred.
Phase 9: linked `.frsproj` save/load implemented; Pack Project and relink UX pending.
Phase 10: not started; prototype only after stabilization gates pass.
```

This wording best matches the current repository state and avoids overclaiming readiness before the high-risk multi-session, serialization, and async paths have been fully verified.

[1]: https://github.com/kiki-github2019/flight-dashboard "GitHub - kiki-github2019/flight-dashboard: MATLAB Flight Data Dashboard with EventBus + MVC · GitHub"
[2]: https://github.com/kiki-github2019/flight-dashboard/raw/refs/heads/main/%2Bflightdash/%2Bstudio/FlightReviewStudioApp.m "raw.githubusercontent.com"
[3]: https://github.com/kiki-github2019/flight-dashboard/blob/main/docs/phase-stabilization-status.md "flight-dashboard/docs/phase-stabilization-status.md at main · kiki-github2019/flight-dashboard · GitHub"
