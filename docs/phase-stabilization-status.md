# Phase Stabilization Status

This note records the intended stabilization boundary before larger Phase 7 or
Phase 8 work is added.

## Current Focus

The current stabilization scope is:

- Phase 1: Studio shell
- Phase 2: project/session/value models
- Phase 3: embedded dashboard tabs
- Phase 4: session-scoped EventBus routing
- Phase 5: Project Explorer and Object Manager MVP
- Phase 6: toolbar/menu/Inspector/GUI mode MVP
- Phase 8a: single ROI result Manual/Auto/Frozen recalculate MVP
- Phase 8b: dirty dependency propagation and topological result ordering
- Phase 8c: debounce queue for Auto result recalculation
- Phase 9: linked `.frsproj` save/load

## Phase 7 Boundary

ROI result plumbing exists in the repository:

- `+flightdash/+analysis/AnalysisService.m`
- `+flightdash/+analysis/RoiStatisticsAnalyzer.m`
- `+flightdash/+studio/+diag/verifyPhase7.m`

Treat this as early work that should remain frozen until Phase 1-6 and Phase 9
verification is clean. Do not expand Analysis Dialog, batch analysis, or result
UI workflows during stabilization.

## Phase 8 Boundary

Phase 8a/8b/8c now have small recalculate, dirty graph, and queue services:

- `+flightdash/+analysis/RecalculateService.m`
- `+flightdash/+analysis/RecalculateQueue.m`
- `+flightdash/+project/DirtyTracker.m`
- `+flightdash/+studio/+diag/verifyPhase8.m`

The supported scope is intentionally narrow:

- one ROI `ReviewResultModel` can be marked Manual/Auto/Frozen
- source hash changes can mark results dirty/stale
- downstream result dependencies can be marked in topological order
- dependency cycles are rejected
- Auto results can be queued with debounce and latest-request coalescing

Do not assume the following exist until a later shared-worker phase starts:

- parfeval priority scheduling
- cross-session shared recalculation workers
- Frozen stale-result acknowledgement UI

## Linked Project Mode

`.frsproj` v1 stores metadata and external file paths only. It does not pack raw
flight logs or video bytes. Missing external files must be handled as linked
asset warnings, not as project corruption.
