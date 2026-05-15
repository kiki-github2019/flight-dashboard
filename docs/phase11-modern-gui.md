# Phase 11 — Modern Responsive GUI and Real-Time Review UX

## Scope

Phase 11 is the front-end modernization pass that follows Phases 0–10
(backend stabilization, session/project model, embedded dashboard,
event scope, Project Explorer + Object Manager, Inspector + Mini
Toolbar, Project Save/Load, SharedDecodeService prototype).

Goal: make the GUI look and feel like a MATLAB-Desktop / OriginPro
style multi-pane application while keeping the existing
`uifigure`-based architecture and MATLAB 2025a+ / MATLAB Online
compatibility.

Out of scope (intentionally deferred):

- Full `DashboardPanel` / `VideoPlayerPanel` / `InstrumentsPanel` /
  `DataViewPanel` `ComponentContainer` split.
- GUI Layout Toolbox dependency.
- Undocumented `matlab.ui.internal.ToolGroup` chrome.
- Re-coloring plot data lines / patches / images.
- Full Analyzer / ROI redesign.

## Architectural choices

### Layout primary stack

```
uifigure
└── shellGrid     (3 rows × 1 col)   [Toolbar | Body | StatusBar]
    └── BodyGrid  (1 row  × 3 cols)  [ProjectExplorer | Workspace | RightDock]
        ├── ProjectExplorerPanel     (Column 1)
        ├── WorkspaceManager         (Column 2, uitabgroup)
        └── RightDockManager         (Column 3, uitabgroup:
                                       Inspector / ObjectManager /
                                       History / Analysis / Logs / Apps)
```

Why this and not a `[3×3] MainGrid`: keeping the existing `shellGrid`
plus `BodyGrid` two-tier layout preserved every Manager class
constructor signature and let Phase 11 ship incrementally without a
shell rewrite. The proposed `[3×3]` flat grid was evaluated and
deferred per `claude_code_post_patch_static_review_next_plan.md` §3.1.

### GUI modes

`Studio` (default), `Classic`, `Review`, `Analysis`, `Plot`, `Report`,
`Compact`, `DockedFigure`. Each mode adjusts:

- Toolbar visibility
- Project Explorer visibility + width
- RightDock visibility + width
- (DockedFigure) `UIFigure.WindowStyle = 'docked'` via the safe
  `applyWindowStyle` helper (silently degrades to `'normal'` on
  unsupported environments such as MATLAB Online).

### Theme

`+flightdash/+ui/StudioTheme.m` exposes two static palettes:

- `StudioTheme.light()` — default; preserves the previous chrome.
- `StudioTheme.dark()` — high-contrast for flight-data review.

`StudioTheme.apply(fig, theme)` walks `findall(fig)` and styles only
the chrome (`uipanel`, `uitab`, `uitabgroup`, `uigridlayout`,
`uilabel`, `uibutton`, edit fields, dropdowns, `Axes`, `UIAxes`).
**Plot data colors (Line / Patch / Image) are never re-themed.**
Gauge needle fills are referenced via the theme when available but
fall back to the high-contrast Phase 11 defaults
(Pitch=blue, Roll=red, Heading=green) when no theme struct is bound.

Toggle: `Pref:Theme:Toggle` command + Preferences menu entry +
toolbar `Theme` button.

### Video slider scrubbing

The drag path has three layers:

1. `VideoPanel.publishSliderChanging` (View) — `SLIDER_THROTTLE_S` pre-filter;
   resolves the active session via `SessionScope.getActive()` so multi-session
   throttle slots do not collide. Emits `SliderChanging`
   `AppEventData(fIdx, value, sessionId)`.
2. `PlaybackController.onSliderChanging` (Controller) — forwards to
   `FlightDataDashboard.onVdubSliderChanging`.
3. `FlightDataDashboard.onVdubSliderChanging` (App) — ultra-light: stores
   `SliderPendingFrame(fIdx)` and ensures the `SliderScrubTimer` is running.

`SliderScrubTimer` is `fixedSpacing`, `Period = 1/30`, `BusyMode = 'drop'`.
Its `TimerFcn` (`scrubTick`) reads the latest pending frame per channel,
hits the cache via `cacheGetFrame`, and only falls through to
`decodeFrameSync` on miss. `requestFrame` itself never blocks on the
sync path when the source is `drag` or `slider-preview` — it queues
via `queuePendingFrame` so the UI stays responsive.

On `ValueChangedFcn` release, `onVdubSliderChanged`:

1. Stops the timer + clears pending state.
2. `SharedDecodeService.advanceSessionGeneration(activeSessionId)` —
   discards stale in-flight decodes for this session.
3. Runs the full `goToFrame('final')` path + `prefetchAdjacentFrames`.

### SharedDecodeService priority

`WorkspaceManager.onTabChanged` calls
`app.SharedDecodeService.setActiveSession(newId)` so `priorityFor`
returns 0 for the active-session requests and 10 for background
sessions. Combined with the per-session `Generation` counter and
`coalesceStream`, stale background drags are silently discarded.

### Resize throttling

Both Studio shell `onUIFigureResized` and the standalone Dashboard
`onUIFigureResized` wrap the existing `LayoutMgr.applyLayout` call
with a tic/toc guard (`LastResizeTic` + `ResizeThrottleMs = 80`).
SizeChangedFcn bursts coalesce into one layout pass per ~80 ms
window. No new timer is added — avoids cleanup burden.

### Auto Session 1

The user-facing `FlightReviewStudio()` entry-point wrapper
auto-creates `Session 1` on a fresh Untitled project so the first
launch lands on a populated Project Explorer + active Dashboard tab.
Tests and `verifyPhase*` diagnostics that instantiate
`flightdash.studio.FlightReviewStudioApp()` directly **start with
a deterministic 0-session baseline** — the auto-create logic lives
in the wrapper, not the class constructor.

### Phase 7 — Analysis dialogs

`+flightdash/+analysis/AnalysisDialog` is a handle base class.
Subclasses provide `buildBody` / `readInputs` / `compute`. The base
dialog:

1. Builds a uifigure with session/channel context label, body grid,
   OK/Apply/Cancel + Save Theme buttons.
2. Inherits `app.CurrentThemeStruct.Background` on launch.
3. On Apply: subclass `compute()` returns a `struct`, the base wraps
   it in `ReviewResultModel`, calls `Project.addResult`, refreshes
   the Project Explorer, and publishes `AnalysisResultCreated` on
   the EventBus with the session id attached.

Two analyzers ship:

- `RoiStatisticsDialog` — Mean / Std / Min / Max / N over `[T0, T1]`.
- `SyncQualityDialog` — IsSynced / VideoFps / DataFps / FpsResidual /
  AnchorOffset / Verdict.

Entry points: `Toolbar:Analyze` (ROI), `Analysis:SyncQuality` (Sync).
`CommandRouter.openAnalysisDialog` switches the RightDock to the
`Analysis` tab as a visual cue, then shows the dialog.

## Files touched in Phase 11

```
+flightdash/+util/AppConstants.m
+flightdash/+model/FlightDataLoader.m
+flightdash/+project/ProjectModel.m
+flightdash/+studio/FlightReviewStudioApp.m
+flightdash/+studio/CommandRouter.m
+flightdash/+studio/MenuManager.m
+flightdash/+studio/ToolbarManager.m
+flightdash/+studio/ProjectExplorerPanel.m
+flightdash/+studio/WorkspaceManager.m
+flightdash/+studio/RightDockManager.m
+flightdash/+studio/StudioMouseRouter.m
+flightdash/+ui/StudioTheme.m
+flightdash/+analysis/AnalysisDialog.m
+flightdash/+analysis/RoiStatisticsDialog.m
+flightdash/+analysis/SyncQualityDialog.m
+flightdash/+view/VideoPanel.m
+flightdash/+controller/MarkerDragController.m
+flightdash/FlightDataDashboard.m
FlightReviewStudio.m
FlightReviewStudioTestSuite.m
+flightdash/+studio/+diag/verifyPhase6.m
```

## What is NOT in Phase 11

- `DashboardPanel` and friends (defer until parity).
- Plot data color re-theming.
- Manager / Detail / ROI / Analyzer popup figure redesign — only
  Analyzer has a Phase 7 home in the RightDock Analysis tab; ROI
  and Detail dialogs are still standalone figures.
