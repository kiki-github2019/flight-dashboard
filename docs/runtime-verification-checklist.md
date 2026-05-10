# Runtime Verification Checklist

Run these checks in MATLAB Online or desktop MATLAB after serializer or embedded
Studio changes.

## Serializer

- Save `temp.frsproj` and confirm `temp.frsproj.zip` is not left behind.
- Round-trip project, session, figure, result, theme, GUI mode, and external-link
  metadata.
- Save and load under a Korean or other non-ASCII path.
- Load a project whose linked flight/video files are missing; metadata must load
  and missing files must be treated as linked-asset warnings.

## Embedded Studio

- Open two dashboard tabs, drag a marker in each, and confirm the inactive tab is
  unchanged.
- Switch tabs while dragging and confirm no callback exception is thrown.
- Delete a tab during idle, playback, and after video load; no stale callback or
  future should update a deleted dashboard.
- Close the Studio after multiple tabs; standalone global cleanup must not run
  per embedded tab.

## Phase Boundary

- Treat Phase 7 as ROI result plumbing only.
- Treat Phase 8a/8b/8c as service-level Recalculate MVP only.
- Do not start Phase 10 shared decode/cache work until Phase 1-6 and Phase 9
  diagnostics are clean in MATLAB runtime.
