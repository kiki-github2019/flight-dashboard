# Flight Dashboard / FlightDataReviewStudio

MATLAB GUI tools for reviewing flight log data with synchronized video, plots,
ROI review, and project-based Studio sessions.

## Entry Points

Run from the repository root:

```matlab
cd <repo-root>
addpath(genpath(pwd))

% Integrated Studio shell (recommended — multi-session project,
% Project Explorer, Workspace tabs, Inspector / Object Manager,
% Light/Dark theme, .frsproj save/load)
FlightReviewStudio

% Legacy standalone dashboard (single-channel/dual-channel review
% only, no project model, kept for backward compatibility)
FlightDataDashboard
```

Quick smoke test after addpath:

```matlab
results = runtests('FlightReviewStudioTestSuite');
table(results)
```

Full sweep:

```matlab
runAllTestCodesWithCleanup
```

`FlightReviewStudio.m` is the Studio entry point. The implementation lives in
`+flightdash/+studio/FlightReviewStudioApp.m`.

`FlightDataDashboard.m` is a compatibility wrapper. The implementation lives in
`+flightdash/FlightDataDashboard.m`.

## Execution Modes

### Studio Mode

`FlightReviewStudio` opens an integrated review shell with:

- Project Explorer
- central Workspace tab group
- embedded `flightdash.FlightDataDashboard` sessions
- right dock with Inspector, Object Manager, logs, and apps placeholder
- status bar

MATLAB cannot embed a separate `uifigure` inside a `uitab`. The embedded
dashboard is therefore drawn directly into the tab using panels and grid
layouts.

### Standalone Mode

`FlightDataDashboard` launches the legacy single-dashboard workflow. Existing
flight/video loading, sync, playback, plot, ROI, and config workflows should
continue to work.

## Project Format

`.frsproj` v1 is a zip-based linked project format. It stores project metadata
and references external assets by path. It does not pack raw flight data or
video bytes into the project archive.

Current archive contents include:

- `manifest.json`
- `project.json`
- `sessions/<SessionId>/session.json`
- `figures/*.json`
- `themes/*.json`
- `results/*.json`
- `external_links.json`

`ProjectSerializer.save(project, filePath)` is expected to create the requested
`.frsproj` path exactly. It uses a temporary zip archive and then normalizes the
final filename to avoid MATLAB `zip()` producing `*.frsproj.zip`.

## Current Phase Scope

The active stabilization focus is Phase 1 through Phase 6, Phase 8a/8b/8c,
Phase 9, and the Phase 4 per-session Undo/Redo stabilization gate:

- Phase 1: Studio shell
- Phase 2: Project/session/value models
- Phase 3: embedded dashboard tabs
- Phase 4: session-scoped EventBus routing and per-session Undo/Redo
- Phase 5: Project Explorer and Object Manager MVP
- Phase 6: toolbar, menu, Inspector MVP, GUI mode MVP, status bar shell
- Phase 8a: single ROI result Manual/Auto/Frozen recalculate MVP
- Phase 8b: dirty dependency propagation and topological result ordering
- Phase 8c: debounce queue for Auto result recalculation
- Phase 9: linked project save/load
- Phase 10 prototype: service-level shared decode/cache scheduling

Phase 7 ROI result plumbing exists in the repository, but broader Analysis
Dialog work should wait until Phase 1-6 and Phase 9 verification is clean.
Phase 8c is intentionally a conservative sequential queue; shared parfeval
priority scheduling remains outside the MVP. Phase 10 currently starts with a
shared service prototype plus Studio/dashboard injection hooks before dashboard
decode paths are changed. Dashboard decode has an opt-in gate for targeted
runtime testing while legacy decode remains the default.
Current shared decode async execution is a MATLAB timer-based cooperative queue
drain, not parfeval/background worker scheduling. `SharedDecodeService.defaultDecoder`
is a mock/test fallback; production VideoReader decoding is used only when a
decoder function handle is injected.

Undo/Redo is session-scoped: each embedded dashboard receives a per-session
`UndoService`, ROI/marker operations push command objects, and Studio toolbar,
menu, status, and History dock state follow the active session.

See `docs/phase-stabilization-status.md` for the current stabilization
boundary.

## MATLAB Compatibility

Two-tier version policy:

- **Minimum runtime**: MATLAB R2021b (release 9.11). Older releases
  fail fast with a clear error from `FlightReviewStudio.m` because
  several UI primitives (uitree multi-select, uibutton `Icon`
  property, uifigure `uigridlayout` semantics the ribbon relies on)
  were introduced in R2021b.
- **Verified targets**: MATLAB R2025a / R2026a, plus MATLAB Online.
  Releases between R2021b and R2025a may work but receive no
  regression test coverage; users on those releases see a one-time
  console warning at launch.
- Windows paths, including non-ASCII paths, should be verified in MATLAB.

Likely toolbox dependencies:

- Image Processing Toolbox
- Parallel Computing Toolbox for async frame decode paths

## Verification

After pulling updates in MATLAB Online, clear cached classes before running
diagnostics:

```matlab
clear classes
rehash toolboxcache

results05 = flightdash.studio.diag.verifyPhase0_5();
results1  = flightdash.studio.diag.verifyPhase1();
results2  = flightdash.studio.diag.verifyPhase2();
results3  = flightdash.studio.diag.verifyPhase3();
results4  = flightdash.studio.diag.verifyPhase4();
results37 = flightdash.studio.diag.verifyPhase3_Phase7();
quick37   = flightdash.studio.diag.verifyPhase3_Phase7(false); % skip stress tests
results5  = flightdash.studio.diag.verifyPhase5();
results6  = flightdash.studio.diag.verifyPhase6();
results8  = flightdash.studio.diag.verifyPhase8();
results9  = flightdash.studio.diag.verifyPhase9();
results10 = flightdash.studio.diag.verifyPhase10();
vrSmoke   = flightdash.studio.diag.verifyPhase10VideoReaderSmoke();
risk      = flightdash.studio.diag.verifyRiskRegressionTests();
polish    = flightdash.studio.diag.verifyThemeAndLayoutPolish();
% Optional, requires a user-supplied video file:
% stress = flightdash.studio.diag.verifyPhase10LargeVideoStress("path/to/video.avi");
multi     = flightdash.studio.diag.runMultiInstanceTests();
full      = runFullStabilizationTests();
isolated  = runAllTestCodesWithCleanup(); % reset after every test function
```

Important manual/runtime scenarios:

- create and delete multiple embedded dashboard tabs
- switch tabs while dragging markers or splitters
- perform ROI/marker edits in multiple tabs and verify undo/redo remains
  isolated per tab
- close a tab that has undo history and verify the remaining tabs keep their
  own undo stacks
- save `temp.frsproj` and confirm no `temp.frsproj.zip` remains
- load a project whose external flight/video files are missing
- save/load under a Korean or other non-ASCII path
- verify standalone `FlightDataDashboard` still launches

## Known Limitations

- `.frsproj` v1 is linked mode only.
- Pack Project and relative path repair are not implemented yet.
- OriginPro-style floating/docking windows are limited by MATLAB UI support.
- Status bar values are partly placeholders.
- Object Manager covers MVP handles and does not yet expose a full plot/ROI
  object hierarchy.
- History panel is an MVP undo/redo list for the active session.
- Full Recalculate UX is deferred; Phase 8a/8b/8c currently provide service-level MVP coverage.
- Shared decode remains opt-in; large AVI performance and MATLAB Online runtime
  behavior still require explicit validation.
- FlightDataDashboard still owns session/UI/video/layout/async/controller state;
  future refactor should move state ownership into SessionContext and
  DashboardStateStore.
