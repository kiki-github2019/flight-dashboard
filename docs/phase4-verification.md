# Phase 4 + Undo/Redo Verification Runbook

Document version: v2.0
Scope: session-scoped EventBus routing, Studio mouse-router safety checks, and per-session Undo/Redo stabilization.

## 0. Preparation

Run from the repository root in MATLAB R2025a or newer:

```matlab
clear classes
close all force
delete(findall(0, 'Type', 'figure'))
rehash toolboxcache
addpath(genpath(pwd))
```

## 1. Automated API Verification

```matlab
results = flightdash.studio.diag.verifyPhase4();
```

Expected: every case reports `PASS`.

| ID | Coverage |
|---|---|
| P4-1 | `AppEventData(fIdx, payload, sessionId)` stores `SessionId` |
| P4-2 | `SessionScope` set/get/clear/isOwner and EventBus auto-tagging |
| P4-3 | `isActiveSession(d)` payload priority and standalone fallback |
| P4-4 | `ProjectModel.newId` uniqueness and format |
| P4-5 | `SessionModel.setFlightFile` channel validation |
| P4-6 | `SessionModel.setDisplayName` empty rejection and trim |
| P4-7 | `ProjectModel.removeSession` cascades dependent results |
| P4-8 | `StudioMouseRouter` lock/refusal/detach semantics |
| P4-9 | EventBus session filters, `subscribeForApp`, target publish, broadcast |
| P4-10 | `SessionScopedListener` and `ControllerBase` cleanup API presence |
| P4-11 | `UndoService` stack transitions and `UndoStateChanged` routing |
| P4-12 | `MaxHistory` alias, max-depth trimming, missing-target command no-op |
| P9-1 | Serializer save/load smoke round-trip |

## 2. Automated Suite Verification

```matlab
suiteResults = runtests('FlightReviewStudioTestSuite');
table(suiteResults)
```

Phase 4 + Undo/Redo-specific expectations:

- session-scoped events do not leak across sessions
- `UndoService` accepts only commands for its own session
- `MaxHistory` / `MaxDepth` limits are enforced
- missing ROI/marker graphics targets are safe no-ops
- toolbar, Edit menu, and History dock reflect active-session undo state
- closing a session removes its undo service
- multi-session undo/redo stress remains isolated per tab

## 3. Multi-Instance Mouse Verification

```matlab
multi = flightdash.studio.diag.runMultiInstanceTests();
```

Expected: all cases pass. These checks cover MATLAB's single figure-level
`WindowButtonMotionFcn` limitation and the master dispatch pattern.

## 4. Manual Runtime Scenarios

### A. Session event isolation

1. Open `FlightReviewStudio`.
2. Add two review sessions.
3. Load data only in Session 1.
4. Switch to Session 2.
5. Confirm Session 2 remains empty and Session 1 data does not update.

### B. Mouse routing during drag

1. Add two sessions with visible plots.
2. Start marker or splitter drag in Session 1.
3. While holding the mouse, switch to Session 2.
4. Release the mouse.
5. Confirm Session 2 is not modified and Session 1 drag state is released.

### C. Undo/Redo isolation

1. Add at least three sessions.
2. Create or move an ROI/marker in each session.
3. Switch among tabs and run Undo/Redo from toolbar, Edit menu, and Ctrl+Z/Ctrl+Y.
4. Confirm only the active session changes and History dock contents follow the active tab.

### D. Close during interaction

1. Start a marker, splitter, panner, or ROI interaction.
2. Close the active session tab.
3. Confirm no "Invalid or deleted object" error appears.
4. Confirm remaining sessions keep their own undo/redo state.

### E. Async/runtime interaction

1. Start playback or video decode in one session.
2. Switch tabs and perform Undo/Redo in another session.
3. Close one inactive session.
4. Confirm playback/decode in the remaining session continues or cancels only when that session is closed.

## 5. Pass Criteria

Phase 4 + Undo/Redo can be considered stabilized when:

- `verifyPhase4()` passes
- `FlightReviewStudioTestSuite` passes
- manual multi-tab mouse and undo/redo scenarios pass
- standalone `FlightDataDashboard` still launches
- no unresolved "Invalid or deleted object" errors appear during tab close/switch

## 6. Notes

- `ControllerBase` is the preferred base for new controllers, but current legacy controllers are not required to inherit from it.
- `MaxDepth` is the canonical undo stack limit; `MaxHistory` remains a compatibility alias.
- `EventBus.subscribeForApp(app, ...)` should be preferred for dashboard-owned controllers because it keeps standalone mode as broadcast while filtering embedded sessions.
