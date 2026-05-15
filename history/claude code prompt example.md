P0-1 + P0-2 — runtime/UX bundle. In CommandRouter.dispatchSession() add app = obj.App; immediately after the guard so the existing app references in the Toolbar:Analyze / Analysis:RoiStats / Analysis:SyncCheck / Analysis:SyncQuality cases resolve. Add toggleExplorer() and toggleRightDock() methods to FlightReviewStudioApp that flip Panel.Visible AND set BodyGrid.ColumnWidth{1} / {3} to 0 / saved width, then call Workspace.refreshActiveLayout('dockToggle'). Update CommandRouter cases Toolbar:ToggleExplorer / Toolbar:ToggleRightDock to prefer the app methods via ismethod(app, 'toggleExplorer') guard (graceful fall-through to legacy togglePanelVisible if the methods aren't there).

P1-1 — Drop duplicate syncFrameMarkersAndLabel calls in processFrameInternal (lines 2673/2676) and in the map-heading update block. Each tick currently writes the same frame label 2-3 times, wasting UI thread time during drag. Keep a single call at the top of the post-marker block and rely on the timer's 1/30 Period to coalesce repeated writes from successive ticks.
Deferred per MD §4: P0-3 VideoReader migration (portability concern, no runtime failure observed → not a blocker), P1-2 marker preview (perf-dependent), P2 large refactors.


[conclusion]
do both

[Response Rules]
- Do not print the entire code
- Do not print modified code
- Do not provide unnecessary explanations (maximum 1 line)
- Do not repeat existing code
- Do not print unnecessary steps

[Code Work Rules]
- Prioritize performance improvement
- Consider memory efficiency
- Consider exception handling
- If multiple improvement suggestions exist, present only two
- after complete modifying codes, show me message that do git push

[Absolute Rules]
- Minimize token usage for result output
- Maximize token usage for code work

[When creating any Git commit message, always append the current local timestamp at the end of the commit subject line.]

Required timestamp format:
@yyyy-mm-dd HH:MM:SS

Examples:
fix(ui): improve video slider scrubbing @2026-05-15 23:42:10
feat(studio): add default session initialization @2026-05-15 23:42:10
chore(test): update MATLAB verification scripts @2026-05-15 23:42:10

Rules:
1. Every git commit subject must end with the timestamp.
2. Use the current local system time at the moment the commit is created.
3. Keep the timestamp at the very end of the first commit message line.
4. Do not place extra text after the timestamp.
5. Use 24-hour time.
6. Use zero padding for month, day, hour, minute, and second.
7. If creating a multi-line commit message, only the first subject line needs the timestamp.

Before running git commit, generate the timestamp automatically.

For Linux/macOS/Termux/Git Bash:
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
git commit -m "fix(ui): improve video slider scrubbing @$TIMESTAMP"