# Event System and Undo/Redo Design Notes

## Session Event Rules

Studio mode hosts multiple embedded dashboards inside one MATLAB `uifigure`.
Every dashboard has an `ActiveSessionId`, and every event that affects dashboard
state should carry that session id.

Use these rules:

- Publish with `flightdash.util.AppEventData(channelIdx, payload, sessionId)`
  when the session id is known.
- Use `flightdash.util.EventBus.publish(eventName, data, targetSessionId)` when
  routing to a specific session from Studio infrastructure.
- Use `flightdash.util.EventBus.subscribeForApp(app, eventName, callback)` for
  dashboard-owned controllers. It filters embedded dashboards by
  `app.ActiveSessionId` and keeps standalone dashboards in broadcast mode.
- Use `flightdash.event.SessionScopedListener` for direct MATLAB listeners that
  receive event objects with `SessionId`.
- Keep callback-local `app.isActiveSession(d)` checks in legacy controllers.
  They are still useful as a second guard even when EventBus filtering is active.

Broadcast behavior is intentional when either the listener session id or event
session id is empty. This keeps legacy standalone flows compatible.

## Controller Migration Rule

`flightdash.controller.ControllerBase` is the preferred base for new
controllers. Existing controllers should migrate gradually only when they are
already being touched for functional work. Do not convert every controller in a
single Phase 4 patch.

The minimum contract for interactive controllers is:

- session identity via `SessionId` or dashboard `ActiveSessionId`
- optional `Router` property for `StudioMouseRouter`
- idempotent `cleanup`
- no direct figure-level `WindowButton*` ownership in embedded mode

## Undo/Redo Command Pattern

Each Studio dashboard receives a per-session `flightdash.studio.UndoService`.
Undoable actions are represented by `flightdash.command.Command` subclasses.

Current command families:

- `MoveROICommand` for graphics ROI or table-backed ROI movement
- `RoiRowsCommand` for table-backed ROI create/delete
- `MoveMarkerCommand` for marker movement or dashboard marker index changes
- `CreateROICommand` / `DeleteROICommand` for graphics ROI controller adapters

Command push convention:

- Use `undoService.push(command)` when the UI action has already happened and
  the command is recording history.
- Use `undoService.push(command, true)` only when the command should execute the
  action as part of pushing it.

This distinction prevents duplicate ROI row insert/delete operations.

`UndoService.MaxDepth` is the canonical stack limit. `MaxHistory` is a
compatibility alias for older plans and tests.

## UI State Flow

`UndoService` emits both a MATLAB `StateChanged` event and an EventBus
`UndoStateChanged` event. Studio listens to the service event and updates:

- toolbar Undo/Redo buttons
- Edit menu Undo/Redo items
- status bar action messages
- right-dock History panel

Only the active workspace tab's undo service should drive visible UI state.
