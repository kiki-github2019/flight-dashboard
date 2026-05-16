# Project File Editor — Plan reconciled with current `main`

Status: pre-implementation checklist
Scope: this is a planning document. **No production code is changed
by this commit.** Subsequent commits will implement the phases below.

## 1. Inventory of existing support classes (verified on `main`)

### Already present — DO NOT recreate

| Item | Path | Role in editor design |
|---|---|---|
| `SessionModel.OptionFilePath` | `+flightdash/+project/SessionModel.m` | Per-channel option*.dat path; serializer already round-trips |
| `ProjectSerializer` round-trip of `OptionFilePath`, `PlotTabs`, `VideoSyncState`, `FlightSyncState`, `FlightFilePath`, `VideoFilePath`, `GuiTheme` | `+flightdash/+project/ProjectSerializer.m` | No schema bump needed for Sections 1 / 2 / 3 / 4 / 5 |
| `ProjectModel.GuiTheme` | `+flightdash/+project/ProjectModel.m` | Theme persistence (Phase 11) |
| `UserPreferences` | `+flightdash/+util/UserPreferences.m` | Recent projects on Start Page |
| `VersionInfo` | `+flightdash/+util/VersionInfo.m` | About dialog content |
| `RuntimeDiagnostics` | `+flightdash/+util/RuntimeDiagnostics.m` | First-run check / Start Page footer |
| `ProjectPacker` | `+flightdash/+project/ProjectPacker.m` | **Structured** (data/video/config) folder pack — keep distinct from Export Everything |
| `ProjectHealthChecker` | `+flightdash/+project/ProjectHealthChecker.m` | Powers Section 8 — reuse `check(project)` against deep copy |
| `MissingFileRepairDialog` | `+flightdash/+ui/MissingFileRepairDialog.m` | Section 6 "Repair…" button delegates here |
| `ImportFlightDataWizard` | `+flightdash/+ui/ImportFlightDataWizard.m` | Live mapping preview UI reference; reuses `FlightDataLoader.previewMapping` |
| `FlightDataLoader.previewMapping` | `+flightdash/+model/FlightDataLoader.m` (line 366) | Sustainable / Live Mapping preview in Sections 3 / 4 |
| `AboutDialog`, `LicenseDialog` | `+flightdash/+ui/` | Help menu skeleton |
| `MemoryMonitor`, `ScrubBench`, `SupportBundle` | `+flightdash/+util/` | Diagnostic infra (already used by editor's Section 8) |
| Start Page + Recent Projects | `WorkspaceManager.buildStartPage` | Editor can call `Workspace.refreshStartPage` after saves |

### NOT present — must be added

| Item | Notes |
|---|---|
| `OptionFileParser` | I/O — read / write / backup / validate. Disk-side complement to the in-memory `OptionFileModel`. Lossless `RawLine` preservation per Block-2 row required. |
| `OptionFileModel` | State + `Dirty` flag, parsed Block 1 (mapping) + Block 2 (display metadata table). |
| `PlotTabConfigModel` | Per-tab schema record (FlightIndex / TabId / TabTitle / Plots). |
| `PlotConfigModel` | Per-plot struct helpers (XField/YField/XLim/YLim/Size/Visible/SyncXGroup). |
| `ProjectAssetModel` | Per-asset snapshot for Section 6 (Role / Path / Exists / Size / ModifiedTime). |
| `ProjectExporter` | Flat-layout snapshot copy (different from `ProjectPacker`'s structured layout). |
| `ProjectFileEditorDialog` + `+pfe/` sub-tab builders | Top-level dialog + 8 sections. |
| `ProjectModel.AutoReloadOnOpen` field | New scalar logical (default true). Serializer fallback in `fieldChar` style. |
| Dashboard wrappers (§4) | `applyOptionFileModel` / `applyProjectPlotConfigs` / `applyProjectAssetChanges` / `refreshFlightDataTable` / `refreshPlotFieldChoices` / `refreshDashboardLightweight`. |
| `Project:EditDetails` command id | Menu + CommandRouter dispatch. |
| `File:ExportEverything` command id | Menu + CommandRouter dispatch (PFE-F). |

## 2. Reconciled phase split

Renames the earlier 6-phase plan to **PFE-0 through PFE-6** with one
explicit no-UI foundation phase that lands tested model code before
any dialog appears. Each phase is its own commit.

| Phase | Title | Surface | Risk |
|---|---|---|---|
| **PFE-0 Pre** | This document — reconcile plan to current main | docs only | None |
| **PFE-1** | Option parser foundation | `OptionFileParser` + `OptionFileModel` (model code only, no UI), 3 round-trip tests | Low (file-format integrity) |
| **PFE-2** | Dashboard read-only wrappers + `Project:EditDetails` stub | 6 wrapper methods on `FlightDataDashboard` (no-op stubs + smoke tests), `Project:EditDetails` command dispatching to a `disp` placeholder + menu entry | Low (additive, headless-testable) |
| **PFE-3** | `ProjectFileEditorDialog` shell | Empty dialog `uifigure`, left nav, 8 section placeholders, 5 dirty flags, debounce timer, close prompt, single-instance focus | Low |
| **PFE-4** | Sections 1 / 2 / 6 — Files & Sync, Cross-Sync, Project Assets | File path edit + AVI swap + sync editors + asset table with `Repair…` delegating to existing `MissingFileRepairDialog` | Medium |
| **PFE-5** | Sections 3 / 4 — option1.dat / option2.dat editors | Both blocks editable, live mapping preview via existing `FlightDataLoader.previewMapping`, lossless save with rotating backup | Medium |
| **PFE-6** | Sections 5 / 7 / 8 — Plot editor + Apply Queue + Health | Plot table + inspector + 5-scope X-range propagation, Apply Queue uses existing dirty flags, Health uses existing `ProjectHealthChecker` | Medium |
| **PFE-7 (optional)** | Export Everything to Folder | New `ProjectExporter` (flat snapshot) + button in Apply Queue + `File:ExportEverything` menu/command + T16 tests. Distinct from existing `ProjectPacker`. | Low-Medium |
| **PFE-8** | 8-step open-project progress dialog + `AutoReloadOnOpen` | Wraps existing `openProject` path; adds `ProjectModel.AutoReloadOnOpen` + serializer fallback. T15 backward-compat test. | Medium |

## 3. Reuse-vs-build decision matrix per editor section

| Editor section | Reuses (already exists) | New code |
|---|---|---|
| 1 Files & Sync | `SessionModel.FlightFilePath / VideoFilePath / VideoSyncState`, `FlightDataLoader` | Editor sub-tab `FilesSyncTab` + dashboard wrappers |
| 2 Flight Data Sync | `Project.FlightSyncState` | Editor sub-tab `CrossSyncTab` |
| 3 option1.dat | `FlightDataLoader.previewMapping`, `SessionModel.OptionFilePath` | `OptionFileParser`, `OptionFileModel`, `Option1Tab` |
| 4 option2.dat | same as 3 | `Option2Tab` (reuses Option1Tab builder with channel=2) |
| 5 Plot Tabs | `Project.Sessions(k).PlotTabs` (already round-tripped) | `PlotTabConfigModel`, `PlotConfigModel`, `PlotEditorTab`, 5-scope propagation helper, in-place plot apply wrapper |
| 6 Project Assets | `MissingFileRepairDialog`, `ProjectHealthChecker` | `ProjectAssetModel`, `ProjectAssetsTab` |
| 7 Apply / Save Queue | existing serializer save path | `ApplyQueueTab` + 5 dirty-flag accessors |
| 8 Project Health | `ProjectHealthChecker.check` | `ProjectHealthTab` (presentation only) |
| Export Everything (PFE-7) | none (deliberately separate from `ProjectPacker`) | `ProjectExporter` + Apply Queue button + menu shortcut |

## 4. Naming alignment with existing code

- Sub-package: `+flightdash/+studio/+pfe/` for sub-tab builders (matches
  existing `+flightdash/+studio/+diag/` style).
- Menu/command id: `Project:EditDetails` (matches existing
  `Project:HealthCheck` style).
- Test name family: `test_T15_*` for editor logic, `test_T16_*` for
  Export Everything (matches existing `test_T11_…` smoke tests).

## 5. Constraints inherited from `main`

1. `ProjectSerializer` is value-class oriented — every editor commit
   replaces `app.Project` with the mutated deep copy on Apply.
2. `WorkspaceManager.refreshStartPage` already updates the Recent
   Projects list — editor's Save path should call it after a
   successful write so Start Page stays in sync.
3. `MissingFileRepairDialog` mutates `app.Project.Sessions` directly —
   when the editor invokes it from Section 6, the editor's deep-copy
   protection must be re-applied or the dialog must operate on the
   editor's copy. Decision: pass the editor's deep-copy reference
   into the repair dialog rather than `app.Project`.
4. `ProjectHealthChecker.check` already treats option files as roles
   (`option1_dat`, `option2_dat`) — Section 8 reads its output
   verbatim.
5. `ProjectPacker` exists for structured packed projects. **Export
   Everything (PFE-7) is the FLAT snapshot complement** — they do not
   replace each other.
6. `FlightDataLoader.previewMapping` is the single source of truth for
   the Live Mapping preview — editor must call it, not re-implement.
7. No new fields on `SessionModel` are required. The only new
   `ProjectModel` field is `AutoReloadOnOpen` (PFE-8).

## 6. Implementation checklist (per phase)

### PFE-1 — Option parser foundation

- [ ] `+flightdash/+project/OptionFileParser.m` static
      `read(path) / write(model, path) / backup(path) / validate(model, csvHeaders)`.
- [ ] `+flightdash/+project/OptionFileModel.m` state class with
      Mapping table, Display table (incl. `RawLine` column),
      HeaderComments / SectionComments cells, `Dirty` flag.
- [ ] Backup file naming: `<name>.bak_yyyymmdd_HHMMSS`. Keep last 5.
- [ ] Lossless write: emit untouched rows from `RawLine`; touched
      rows reformat from structured fields.
- [ ] Tests:
  - `test_T15_OptionFileParser_RoundTripPreservesRawLines`
  - `test_T15_OptionFileBackupRotation`
  - `test_T15_OptionFileParser_MissingBlock2_LoadsBlankDisplay`

### PFE-2 — Dashboard wrappers + command stub

- [ ] On `FlightDataDashboard`: add public methods
      `applyOptionFileModel`, `applyProjectPlotConfigs`,
      `applyProjectAssetChanges`, `refreshFlightDataTable`,
      `refreshPlotFieldChoices`, `refreshDashboardLightweight`.
      Each starts as a thin wrapper around existing internal logic.
- [ ] Register `Project:EditDetails` command id in
      `CommandRouter.commandScope` (global).
- [ ] `MenuManager` adds `Project > Edit Project Details…`.
- [ ] Initial dispatch: `obj.setStatus('Project File Editor — Phase
      PFE-3 not yet landed')`.
- [ ] Smoke tests:
  - `test_T15_DashboardWrapper_NoOpStubsDoNotThrow`
  - `test_T15_ProjectEditDetails_CommandRegistered`

### PFE-3 — Editor shell

- [ ] `+flightdash/+studio/ProjectFileEditorDialog.m` handle class.
- [ ] Single `uifigure`, `Resize='on'`, modeless, single-instance
      via `app.ProjectEditor` slot.
- [ ] Left nav with 8 section labels; 8 empty `uigridlayout` hosts.
- [ ] 5 dirty flags + `markDirty(kind)` + `scheduleAutoApply` (0.7 s
      `singleShot`, `BusyMode='drop'`).
- [ ] Close-prompt 3-way dialog (Save All / Discard / Cancel).
- [ ] `FlightReviewStudioApp.openProjectFileEditor` +
      `confirmProjectEditorClose`.
- [ ] Tests:
  - `test_T15_Editor_OpenCloseSingleInstance`
  - `test_T15_Editor_DirtyFlagSetTriggersClosePrompt`

### PFE-4 → PFE-8 — see §2 table

Detailed checklists deferred until PFE-3 lands and exposes the
section host API.

## 7. Validation policy

Every phase commit must pass:

```matlab
clear classes
rehash toolboxcache
results = runtests('FlightReviewStudioTestSuite');
table(results)
```

Headless / MATLAB Online environments rely on the existing
`try/catch + assumeFail` pattern; do not introduce a test that
hard-requires a uifigure.

## 8. Open questions deferred to implementation phases

- AVI hot-swap path: confirm whether the editor's
  `applyProjectAssetChanges` calls into the existing
  `FileController.loadAviFile(fIdx, path)` or whether a thinner
  reload API is needed. Resolve in PFE-4.
- Plot in-place apply: confirm whether existing axes carry handles
  reachable from `Models(fIdx).UI(...).axes`, or whether the
  dashboard needs an explicit `getPlotAxesByTabId` accessor.
  Resolve in PFE-6.
- `AutoReloadOnOpen` default for legacy `.frsproj`: spec says true.
  Confirm no existing project regression in PFE-8.

## 9. Non-goals of this commit

- No changes to any `.m` production file.
- No new menu entries.
- No new commands.
- No new tests.
- No schema changes.

This commit is documentation-only: the reconciled plan + checklist.
