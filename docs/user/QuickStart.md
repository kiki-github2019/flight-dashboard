# Quick Start — Flight Review Studio

## 1. Launch

```matlab
addpath(genpath(pwd))
FlightReviewStudio
```

A blank project named *Untitled* opens with **Session 1** pre-created.
Project Explorer is on the left, Workspace tabs are in the centre, and
the Inspector / Object Manager dock is on the right.

## 2. Load flight data and video

In the active Dashboard tab, click **Flight 1** to pick the flight
data CSV for channel 1. If an `option1.dat` mapping file sits in the
same folder it will be applied automatically; otherwise the loader
falls back to its built-in alias table and warns about any missing
optional columns (Roll / Pitch / Heading).

Repeat with **Flight 2** for channel 2 (uses `option2.dat`).

Load video for either channel from the per-channel header bar.

## 3. Synchronise video to data

Use **Sync Time** to align a known timestamp between the video frame
and a flight-data row. After sync, dragging the video slider also
moves the data marker (and vice versa).

## 4. Add ROI / run analysis

- Toolbar **ROI** drops an ROI marker on the active plot.
- Toolbar **Analyze** opens the ROI Statistics dialog. Pick a
  variable + `[T0, T1]` range; the result is saved into the project
  and appears under **Project Explorer → Results**.

## 5. Save the project

**File → Save** writes a `.frsproj` zip containing the metadata.
External flight / video / option files are linked by path.

For a full asset-bundled copy use **File → Pack Project** (Phase F).

## 6. Theme

Toolbar **Theme** flips between Light and Dark for the chrome. Plot
colours are never overridden.
