# sample_data — Bundled Sample Project Assets

This folder ships with Flight Review Studio and is referenced by the
**Open Sample Project** action on the Start Page.

## Contents

| File | Role |
|---|---|
| `option1.dat` | Column-mapping config for Flight 1 channel |
| `option2.dat` | Column-mapping config for Flight 2 channel |
| `sample_flight1.csv` (optional) | Small demo CSV for channel 1 |
| `sample_flight2.csv` (optional) | Small demo CSV for channel 2 |
| `sample_video1.avi`  (optional) | Demo video for channel 1 |
| `sample_video2.avi`  (optional) | Demo video for channel 2 |
| `sample_project.frsproj` (optional) | Pre-built project linking the above |

The two `option*.dat` files are **first-class project assets** and
must remain in this folder. They are also included by:

- **Pack Project** (output `config/option1.dat`, `config/option2.dat`)
- **Project Health Check** (`option1_dat`, `option2_dat` roles)
- **Missing File Repair** (locate/search workflow)
- **Support Bundle Export** (always included if available)
- **Import Flight Data Wizard** (mapping preview)

## How to extend

To ship a full demo project:

1. Drop a small flight CSV (≤ 1 MB) into this folder.
2. Drop a short matching AVI (≤ 5 MB) — consider Git LFS for video.
3. Run **File → New Project**, **Add Session**, load the CSV + AVI,
   set sync, then **File → Save Project As → sample_data/sample_project.frsproj**.
4. Commit the resulting `.frsproj` alongside the assets.

The Start Page Open Sample Project button opens `sample_project.frsproj`
when present; if absent the action shows a status-bar hint.
