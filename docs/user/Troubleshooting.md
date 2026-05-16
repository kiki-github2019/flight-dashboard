# Troubleshooting

## "Required critical flight-data columns were not mapped"

The CSV is missing one or more of **Time / Lat / Lon / Alt**. Either
edit the CSV header or supply an `option*.dat` whose block 1 maps the
required key to the actual column.

Roll / Pitch / Heading are **optional**: missing values produce a
warning + a disabled attitude gauge, never a hard failure.

## Video slider feels laggy

The slider uses a 30 Hz timer with `BusyMode='drop'`. If your video
codec decodes slowly the timer drops ticks instead of queueing them.
Enable `app.DebugMode = true` and after a 5-second drag call:

```matlab
flightdash.util.ScrubBench.snapshot()
```

Compare `Ticks` (expected) vs `CacheHits + SyncDecodes` (actual).
Big gaps → consider proxy video or smaller resolution.

## "Invalid or deleted object" during drag

A modal dialog opened mid-drag. The router's `forceEndAllDrag` should
recover automatically on the next mouse-up; if it does not, close any
open file-pickers and switch tabs to clear stale state.

## Project does not remember Light/Dark theme

Theme persistence requires a saved project (`Project.GuiTheme` is
written to the `.frsproj`). Toggling theme in an *Untitled* project
flips the colours but does not persist across restarts.

## CSV loaded but mapping looks wrong

Use **File → Load Data** to re-run the Import Wizard (Phase E) which
shows the column-to-key mapping table and lets you pick a different
`option*.dat` interactively.

## How to attach diagnostic info to a bug report

**Help → Export Support Bundle** (Phase D) collects logs, manifest,
and the active `option*.dat` files into a zip. Do not include raw
video unless explicitly asked.
