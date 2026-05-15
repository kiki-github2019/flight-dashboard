# Flight Dashboard Integrated Review Report for 1st–9th Reviews  
## Rewritten Version Including Code

## 0. Purpose of This Document

This document reorganizes and consolidates the **1st–9th review contents** from the uploaded `grok review_260513_2053.md`, and includes the main MATLAB code and patch suggestions from the uploaded file directly in the report body.

The main purposes are:

```text
1. Integrate repeated review points from the 1st–9th reviews into one executable modification plan.
2. Organize problems, target files, risk levels, and verification methods by phase.
3. Include the key code patches from the uploaded file without omitting them.
4. Structure the document so that it can be directly used as input for ChatGPT / Codex / Gemini / Claude cowork.
5. Clarify file-level modification plans so future work can be separated into commit / PR units.
```

---

# 1. Overall Integrated Conclusion

The 1st–9th reviews can be summarized into the following four core problem areas.

```text
1. Actual CSV / option1.dat column mapping failure
2. Incomplete initial Studio display for Project Explorer / Session / Dashboard
3. Inconsistency between standalone FlightDataDashboard and Studio embedded execution
4. Need to stabilize ProjectExplorerPanel / WorkspaceManager / WelcomeTab switching
```

The structural stability based on automated tests has improved significantly, but from a real GUI usage perspective, the following workflow still needs to be stabilized.

```text
Launch FlightReviewStudio
→ Display Project Explorer
→ Auto-create Session 1
→ Activate Dashboard tab
→ Load Flight 1 CSV
→ Synchronize video and data
→ Switch session / analyze / save
```

The final priorities are organized as follows.

```text
1. Column Mapping Fix
2. Session 1 Auto-create
3. Project Explorer refresh / expand / select
4. Workspace WelcomeTab → Dashboard transition
5. Standalone / embedded consistency for FlightDataDashboard
6. Real-time video slider preview
7. Mouse drag lock stabilization
8. Manager / Detail / ROI / Analyzer cleanup
9. Layout / readability / file name display / gauge / Range button improvements
```

---

# 2. Overall Modification Priority Principles

The overall priority principles proposed in the 1st review were maintained throughout the 2nd–9th reviews.

```text
1. Crash / data loading failure
   - Highest priority because it blocks the user workflow itself.

2. Session / Studio stability
   - Stabilize Project Explorer, Workspace, multi-session behavior, and tab switching.

3. Core UI/UX behavior
   - Video-data synchronization, real-time drag behavior, visibility, and ROI mode.

4. Readability / layout
   - Broken layout during maximization, button/editbox width, and color contrast.

5. Improvements / additional features
   - Data plot slider, file name display, and gauge indicator improvements.

6. Legacy / standalone
   - Compatibility for standalone FlightDataDashboard execution.
```

---

# 3. Integrated Phase-Based Modification Plan

## Phase A — Immediate Fixes  
### High Risk / Blocking

| Priority | Problem | Modification | Main Files | Risk |
|---|---|---|---|---|
| 1 | Roll/Pitch mapping error during CSV loading | Add tolerant mapping for option1.dat / CSV headers | `FlightDataLoader.m`, `AppConstants.m` | High |
| 2 | Project Explorer not visible on initial launch | Auto-create Session 1 + refresh/expand Explorer | `FlightReviewStudioApp.m`, `ProjectExplorerPanel.m` | Medium |
| 3 | Difference between standalone and embedded Dashboard | Unify layout based on RootContainer | `FlightDataDashboard.m` | Medium |
| 4 | Figure management problems for Manager / Detail / ROI / Analyzer | Per-session figure registry / bring-to-front policy | `AuxWindowManager`, future `FigureManager` | Medium–High |

---

## Phase B — Behavior Improvements  
### Medium Risk

| Priority | Problem | Modification |
|---|---|---|
| 5 | Video slider does not update in real time during drag | Apply `ValueChangingFcn` + throttled preview |
| 6 | Coastline lat/lon range display problem | Apply XLim/YLim based on data extent + padding |
| 7 | Buttons/editboxes stretch during maximization | Apply fixed-width columns / spacer columns |
| 8 | Too many panels visible at initial session display | Default visible setup centered on Current Flight Info + H Data View Panel |
| 9 | ROI button behavior is unclear | ROI mode guidance, cursor, ESC cancel, and state machine |

---

## Phase C — UI / Readability Improvements

```text
1. Improve color contrast for panel titles / frame labels / slider labels.
2. Improve Pitch / Roll / Heading gauge triangle indicator size and color.
3. Display Flight 1 / Flight 2 file names in the GUI.
4. Add a slider for the flight-data plot.
5. Implement the Range button or disable it with a tooltip.
```

---

## Phase D — Detailed Improvements and Legacy

```text
1. Check why AVI FPS is displayed as fixed values such as Flight 1 = 230 and Flight 2 = 830.
2. Prevent crosshair cursor sticking / freeze during mouse drag.
3. Implement details for Detail / Show checkbox / Analyzer functions.
4. Review standalone legacy compatibility for FlightDataDashboard.
```

---

# 4. Core Fix 1 — Column Mapping Fix

## 4.1 Problem Summary

The following error occurred during actual GUI usage.

```text
Error : Required flight-data columns were not mapped : Roll, Pitch,
Check option1.dat or file headers.
```

The current loading flow is:

```text
parseFlightData
→ applyOptionFile
→ inferRequiredColumn
→ validateRequiredColumns
```

The causes are:

```text
1. High dependency on option1.dat format
2. Difference between test option1.dat and actual option1.dat format
3. requiredColumnCandidates does not sufficiently match actual CSV headers
4. Immediate error when any of Roll/Pitch fails to map
5. Insufficient tolerance for header differences such as case, spaces, units, parentheses, and underscores
```

---

## 4.2 `AppConstants.m` Modification Code

The uploaded file proposed adding `COLUMN_ALIASES` as follows.

```matlab
classdef AppConstants
    properties (Constant)
        MAX_PLOTS_PER_TAB     = 12
        % ...
        REQ_KEYS              = {'Time', 'Roll', 'Pitch', 'Heading', 'Alt', 'Lat', 'Lon'};

        % === Column Mapping Aliases ===
        COLUMN_ALIASES = struct( ...
            'Time',    {'time', 'timestamp', 't', 'sec', 'seconds'}, ...
            'Roll',    {'roll', 'rollangle', 'phi', 'bank', 'roll_deg', 'rolldeg', 'RollAngle'}, ...
            'Pitch',   {'pitch', 'pitchangle', 'theta', 'pitch_deg', 'pitchdeg', 'PitchAngle'}, ...
            'Heading', {'heading', 'yaw', 'course', 'track', 'hdg', 'psi', 'HeadingAngle'}, ...
            'Alt',     {'alt', 'altitude', 'height', 'alt_ft', 'altitude_ft'}, ...
            'Lat',     {'lat', 'latitude', 'lat_deg'}, ...
            'Lon',     {'lon', 'longitude', 'long', 'lon_deg'} ...
        );
    end
end
```

### Review Comment

The direction is correct. However, directly creating a complex struct with cell arrays inside `properties (Constant)` can sometimes cause syntax or version compatibility issues in MATLAB. A safer approach is to return the alias map from a static method.

### Recommended Alternative Code

```matlab
methods (Static)
    function aliases = columnAliases()
        aliases = struct();
        aliases.Time = {'time','timestamp','t','sec','seconds'};
        aliases.Roll = {'roll','rollangle','phi','bank','roll_deg','rolldeg','RollAngle'};
        aliases.Pitch = {'pitch','pitchangle','theta','pitch_deg','pitchdeg','PitchAngle'};
        aliases.Heading = {'heading','yaw','course','track','hdg','psi','HeadingAngle'};
        aliases.Alt = {'alt','altitude','height','alt_ft','altitude_ft'};
        aliases.Lat = {'lat','latitude','lat_deg'};
        aliases.Lon = {'lon','longitude','long','lon_deg'};
    end
end
```

Then `FlightDataLoader.m` can call it as follows.

```matlab
aliases = flightdash.util.AppConstants.columnAliases();
```

---

## 4.3 `FlightDataLoader.m` — Replacement Code for `inferRequiredColumn`

This is the strengthened version proposed in the uploaded file.

```matlab
function colName = inferRequiredColumn(obj, reqKey, csvHeaders)
    % 강화된 Column Inference: Exact → Normalized → Partial match
    colName = '';
    if isempty(csvHeaders), return; end

    normHeaders = cellfun(@(h) lower(strtrim(h)), csvHeaders, 'UniformOutput', false);
    reqLower = lower(strtrim(reqKey));

    % 1. Exact / Alias match (AppConstants.COLUMN_ALIASES 사용)
    aliases = flightdash.util.AppConstants.COLUMN_ALIASES;
    if isfield(aliases, reqKey)
        cands = [reqKey, aliases.(reqKey)];
    else
        cands = {reqKey};
    end

    for c = cands
        candNorm = lower(strtrim(c{1}));
        idx = find(strcmp(normHeaders, candNorm), 1, 'first');
        if ~isempty(idx)
            colName = csvHeaders{idx};
            return;
        end
    end

    % 2. Partial / Contains match (fallback)
    for i = 1:numel(normHeaders)
        if contains(normHeaders{i}, reqLower) || contains(reqLower, normHeaders{i})
            colName = csvHeaders{i};
            return;
        end
    end
end
```

### Review Comment

The direction is valid, but normalization based only on `lower(strtrim(...))` may not sufficiently handle headers such as:

```text
Roll(deg)
Roll Angle
roll-angle
roll_deg
Pitch [deg]
```

Therefore, the header normalization helper should be strengthened as follows.

```matlab
function out = normalizeHeaderName(~, in)
    out = lower(char(in));
    out = regexprep(out, '\(.*?\)', '');
    out = regexprep(out, '\[.*?\]', '');
    out = regexprep(out, '[^a-z0-9]', '');
end
```

The recommended `inferRequiredColumn` using that helper is:

```matlab
function colName = inferRequiredColumn(obj, reqKey, csvHeaders)
    colName = '';
    if isempty(csvHeaders)
        return;
    end

    normHeaders = cellfun(@(h) obj.normalizeHeaderName(h), ...
        csvHeaders, 'UniformOutput', false);

    reqNorm = obj.normalizeHeaderName(reqKey);

    % 1. Build candidate list
    aliases = flightdash.util.AppConstants.columnAliases();
    if isfield(aliases, reqKey)
        candidates = [{reqKey}, aliases.(reqKey)];
    else
        candidates = {reqKey};
    end

    % 2. Exact normalized match
    for cIdx = 1:numel(candidates)
        candNorm = obj.normalizeHeaderName(candidates{cIdx});
        idx = find(strcmp(normHeaders, candNorm), 1, 'first');
        if ~isempty(idx)
            colName = csvHeaders{idx};
            return;
        end
    end

    % 3. Partial fallback
    for hIdx = 1:numel(normHeaders)
        hNorm = normHeaders{hIdx};
        if contains(hNorm, reqNorm) || contains(reqNorm, hNorm)
            colName = csvHeaders{hIdx};
            return;
        end
    end
end
```

---

## 4.4 `FlightDataLoader.m` — Replacement Code for `validateRequiredColumns`

The uploaded file proposed the following version.

```matlab
function validateRequiredColumns(obj, dataTbl, mappedCols, fIdx)
    reqKeys = flightdash.util.AppConstants.REQ_KEYS;
    missing = {};

    for i = 1:numel(reqKeys)
        key = reqKeys{i};
        mapped = mappedCols.(key);
        if isempty(mapped) || ~ismember(mapped, dataTbl.Properties.VariableNames)
            missing{end+1} = key;
        end
    end

    if ~isempty(missing)
        msg = sprintf('Required columns not fully mapped: %s\n' + ...
                     'File: option%d.dat or headers mismatch.', ...
                     strjoin(missing, ', '), fIdx);

        critical = {'Time','Lat','Lon','Alt'};
        if ~isempty(intersect(missing, critical))
            error('flightdash:DataMapping:MissingCritical', msg);
        else
            warning('flightdash:DataMapping:MissingOptional', msg);
        end
    end
end
```

### Review Comment

The main concept is correct.

```text
Critical columns:
- Time
- Lat
- Lon
- Alt

Optional but recommended:
- Roll
- Pitch
- Heading
```

However, using `+` for character array concatenation inside `sprintf` can cause errors depending on MATLAB version and char/string context. The safer form is:

```matlab
msg = sprintf(['Required columns not fully mapped: %s\n', ...
               'File: option%d.dat or headers mismatch.'], ...
               strjoin(missing, ', '), fIdx);
```

Also, `mappedCols.(key)` may fail if the field does not exist, so an `isfield` guard is needed.

### Recommended Final Code

```matlab
function validateRequiredColumns(obj, dataTbl, mappedCols, fIdx)
    %#ok<INUSD>
    reqKeys = flightdash.util.AppConstants.REQ_KEYS;
    missing = {};

    vars = dataTbl.Properties.VariableNames;

    for i = 1:numel(reqKeys)
        key = reqKeys{i};

        if ~isfield(mappedCols, key)
            missing{end+1} = key; %#ok<AGROW>
            continue;
        end

        mapped = mappedCols.(key);

        if isempty(mapped) || ~ismember(mapped, vars)
            missing{end+1} = key; %#ok<AGROW>
        end
    end

    if isempty(missing)
        return;
    end

    msg = sprintf(['Required columns not fully mapped: %s\n', ...
                   'File: option%d.dat or CSV headers mismatch.'], ...
                   strjoin(missing, ', '), fIdx);

    critical = {'Time','Lat','Lon','Alt'};
    critMissing = intersect(missing, critical);

    if ~isempty(critMissing)
        error('flightdash:DataMapping:MissingCritical', ...
            '%s\nCritical columns missing: %s', ...
            msg, strjoin(critMissing, ', '));
    else
        warning('flightdash:DataMapping:MissingOptional', '%s', msg);
    end
end
```

---

# 5. Core Fix 2 — Auto-Create Session 1 in `FlightReviewStudioApp.m`

## 5.1 Problem Summary

The following initial-launch issue was reported.

```text
Project Explorer does not appear.
Only the Welcome tab appears.
Because no session is automatically created, Explorer / Workspace appears empty.
```

---

## 5.2 Constructor Replacement Code Proposed in the Uploaded File

```matlab
function app = FlightReviewStudioApp()
    try
        % Initialize an empty project before any UI accesses it.
        app.Project = flightdash.project.ProjectModel('Untitled');
        app.ensureSharedServices();
        app.ensureUndoServices();
        app.buildShell();
        app.applyGuiMode(app.Project.GuiMode, false);
        app.refreshTitle();

        % ==================== [2026-05-14] Studio 초기화 개선 ====================
        % 최초 실행 시 Session 1 자동 생성 + Project Explorer 활성화
        if app.Project.sessionCount() == 0
            fprintf('[Studio] Auto-creating default Session 1...\n');
            defaultId = app.addSession('Session 1');
            app.ActiveSessionId = defaultId;

            % Explorer 강제 refresh + expand
            if ~isempty(app.ProjectExplorer) && isvalid(app.ProjectExplorer)
                app.refreshExplorer();
                if ismethod(app.ProjectExplorer, 'refreshFromProject')
                    app.ProjectExplorer.refreshFromProject(app.Project);
                end
            end

            % Workspace 첫 번째 탭 활성화
            if ~isempty(app.Workspace) && isvalid(app.Workspace)
                app.Workspace.setActiveTab(1);
            end
        end
        % =================================================================

    catch ME
        if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
            delete(app.UIFigure);
        end
        rethrow(ME);
    end
end
```

---

## 5.3 Review Comment

This code is effective for improving the initial-launch UX. However, the following items must be checked.

```text
1. Whether app.addSession('Session 1') already sets ActiveSessionId internally
2. Whether app.addSession already calls refreshExplorer internally
3. Whether Workspace.setActiveTab(1) actually exists as a public method
4. Whether Session 1 is not duplicated when loading an existing project
```

Recommended policy:

```text
New project initial launch:
- Auto-create Session 1

Existing project load:
- Preserve saved session structure
- Do not auto-create Session 1

When all sessions are closed:
- Show WelcomeTab
```

---

# 6. Core Fix 3 — Strengthen `ProjectExplorerPanel.m` Refresh / Expand / Select

## 6.1 Problem Summary

Even if Project Explorer is created, tree expand/select may not happen immediately after initial launch or automatic session creation.

Possible causes include:

```text
1. Insufficient drawnow after rebuilding the tree
2. Timing issue when expanding the Sessions node
3. WelcomeTab remains active, making Explorer appear empty
4. refreshFromProject does not sufficiently update the selected state
```

---

## 6.2 Full Replacement Code for `refreshFromProject` from the Uploaded File

```matlab
function refreshFromProject(obj, project)
    % Rebuild the tree from a flightdash.project.ProjectModel.
    try
        if isempty(obj.Tree) || ~isvalid(obj.Tree), return; end
        if isempty(obj.Roots) || ~isfield(obj.Roots, 'Project'), return; end

        % Update root label
        if ~isempty(project) && ~isempty(project.ProjectName)
            obj.Roots.Project.Text = project.ProjectName;
        end

        % --- Sessions ---
        obj.replaceChildren(obj.Roots.Sessions);
        if ~isempty(project) && ~isempty(project.Sessions)
            for k = 1:numel(project.Sessions)
                s = project.Sessions(k);
                node = uitreenode(obj.Roots.Sessions, ...
                    'Text', sprintf('%s (%s)', s.DisplayName, s.SessionId), ...
                    'NodeData', struct('SessionId', s.SessionId, 'Kind', 'session'));
            end
        end

        % --- Analysis Themes ---
        obj.replaceChildren(obj.Roots.Themes);
        if ~isempty(project) && ~isempty(project.AnalysisThemes)
            for k = 1:numel(project.AnalysisThemes)
                t = project.AnalysisThemes(k);
                uitreenode(obj.Roots.Themes, ...
                    'Text', t.ThemeName, ...
                    'NodeData', struct('ThemeId', t.ThemeId, 'Kind', 'theme'));
            end
        end

        % --- Review / Analysis Results ---
        obj.replaceChildren(obj.Roots.Roi);
        obj.replaceChildren(obj.Roots.Sync);
        obj.replaceChildren(obj.Roots.Snapshots);
        if ~isempty(project) && ~isempty(project.Results)
            for k = 1:numel(project.Results)
                r = project.Results(k);
                parentNode = obj.resultRootFor(r);
                uitreenode(parentNode, ...
                    'Text', obj.resultLabel(r), ...
                    'NodeData', struct('ResultId', r.ResultId, ...
                        'SessionId', r.SessionId, 'Kind', 'result'));
            end
        end

        % ==================== [2026-05-14 강화] ====================
        drawnow limitrate;   % UI 즉시 반영

        try, expand(obj.Roots.Project); catch, end
        try, expand(obj.Roots.Sessions); catch, end
        try, expand(obj.Roots.Roi); catch, end

        % Session이 존재하면 첫 번째 Session 자동 선택 (Explorer에서 보이게)
        if ~isempty(project) && ~isempty(project.Sessions)
            firstSessionId = project.Sessions(1).SessionId;
            obj.selectSession(firstSessionId);
        end
        % =======================================================
    catch ME
        warning('ProjectExplorerPanel:RefreshFailed', ME.message);
    end
end
```

---

## 6.3 Review Comment and Recommended Improvement Code

The code is effective, but always selecting the first session during refresh can change the session the user is currently viewing.

Recommended policy:

```text
1. Select ActiveSessionId if it exists.
2. Select the first session only when ActiveSessionId is empty.
```

Also, the warning syntax is safer in the following form.

```matlab
warning('ProjectExplorerPanel:RefreshFailed', '%s', ME.message);
```

### Recommended Supplementary Code

```matlab
% Prefer active session if it exists
targetSessionId = '';

try
    if ~isempty(obj.App) && isvalid(obj.App) && isprop(obj.App, 'ActiveSessionId')
        targetSessionId = char(obj.App.ActiveSessionId);
    end
catch
    targetSessionId = '';
end

if isempty(targetSessionId) && ~isempty(project) && ~isempty(project.Sessions)
    targetSessionId = char(project.Sessions(1).SessionId);
end

if ~isempty(targetSessionId)
    obj.selectSession(targetSessionId);
end
```

catch block:

```matlab
catch ME
    warning('ProjectExplorerPanel:RefreshFailed', '%s', ME.message);
end
```

---

# 7. Core Fix 4 — `WorkspaceManager.m` WelcomeTab Transition

## 7.1 Problem Summary

Even when Session 1 is created, if the Workspace remains on WelcomeTab, the user may feel that the Dashboard was not created.

Therefore, after `addDashboardTab`, the newly created Dashboard tab must become active.

---

## 7.2 Replacement Code for the End of `addDashboardTab` from the Uploaded File

```matlab
obj.DashboardEntries(sessionId) = struct( ...
    'SessionId', sessionId, ...
    'Tab',       tab, ...
    'Dashboard', dash);

% ==================== [2026-05-14] WelcomeTab 강제 전환 ====================
obj.TabGroup.SelectedTab = tab;
obj.onTabChanged();

% WelcomeTab이 여전히 선택되어 있으면 Dashboard로 강제 전환
if ~isempty(obj.WelcomeTab) && isvalid(obj.WelcomeTab) && ...
   isequal(obj.TabGroup.SelectedTab, obj.WelcomeTab)
    obj.TabGroup.SelectedTab = tab;
    obj.onTabChanged();   % 다시 호출하여 layout refresh
end
% =================================================================
```

---

## 7.3 Strengthened Code for the Beginning of `onTabChanged` from the Uploaded File

```matlab
function onTabChanged(obj)
    try
        drawnow limitrate;   % ← UI 안정성 강화

        newId = obj.activeSessionId();
        if ~isempty(obj.App) && isvalid(obj.App)
            obj.App.ActiveSessionId = newId;
            if ~isempty(obj.App.StatusBar)
                obj.App.StatusBar.setActiveSession(newId);
            end
        end

        if isempty(newId) || strcmp(newId, 'standalone')
            flightdash.util.SessionScope.clear();
        else
            flightdash.util.SessionScope.setActive(newId);
        end

        obj.refreshActiveLayout('tabActivated');
        obj.refreshActiveInspector();
        obj.refreshActiveUndoUi();
    catch ME
        warning('WorkspaceManager:onTabChanged', ME.message);
    end
end
```

---

## 7.4 Review Comment

The direction is valid. The following refinements would make it safer.

```text
1. Use drawnow limitrate only in limited places such as immediately after tab creation/switching.
2. Prefer warning syntax: warning('id','%s',ME.message).
3. If SelectedTab = tab is already applied in addDashboardTab, the WelcomeTab check is mostly a safety net.
4. A separate policy is needed to return to WelcomeTab when all sessions are closed.
```

Recommended warning syntax:

```matlab
catch ME
    warning('WorkspaceManager:onTabChanged', '%s', ME.message);
end
```

---

# 8. Core Fix 5 — Standalone / Embedded Consistency for `FlightDataDashboard.m`

## 8.1 Problem Summary

User feedback:

```text
When running FlightDataDashboard.m standalone, the screen looks completely different.
Even after pressing Flight 1 and selecting a CSV, it does not process it.
It is completely different from the Dashboard that appears after adding a session in FlightReviewStudio.
```

Target behavior:

```text
FlightDataDashboard()
→ standalone mode
→ create its own uifigure
→ use the same Dashboard UI/logic as Studio embedded mode

flightdash.FlightDataDashboard(parentContainer, sessionId)
→ embedded mode
→ render inside Studio tab/panel
```

---

## 8.2 Embedded Mode Reinforcement Code from the Uploaded File

```matlab
if embeddedMode
    app.IsEmbedded = true;
    app.ActiveSessionId = char(sessionId);
    app.RootContainer = parentContainer;

    % Embedded에서는 UIFigure을 Studio figure로 연결 (중요!)
    if isprop(parentContainer, 'Parent') && ~isempty(parentContainer.Parent)
        app.UIFigure = ancestor(parentContainer, 'uifigure');
    end
else
    % Standalone
    app.IsEmbedded = false;
    app.ActiveSessionId = 'standalone';
    app.createStandaloneFigure();  % 별도 메서드로 분리 추천
end
```

Alternative reinforcement code from the 7th review:

```matlab
if embeddedMode
    app.IsEmbedded      = true;
    app.ActiveSessionId = char(sessionId);
    app.RootContainer   = parentContainer;

    % Embedded 모드에서는 Studio의 UIFigure 연결
    if ~isempty(parentContainer) && isvalid(parentContainer)
        fig = ancestor(parentContainer, 'matlab.ui.Figure');
        if ~isempty(fig)
            app.UIFigure = fig;
        end
    end
end
```

---

## 8.3 Recommended `createLayout` Structure

```matlab
if app.IsEmbedded
    parentForLayout = app.RootContainer;
else
    parentForLayout = app.UIFigure;
end

app.createLayout(parentForLayout);
```

Or handle it inside `createLayout()` as follows.

```matlab
function createLayout(app)
    if ~isempty(app.RootContainer) && isvalid(app.RootContainer)
        parent = app.RootContainer;
    else
        parent = app.UIFigure;
    end

    % Create all uigridlayout/uipanel objects using parent
end
```

---

## 8.4 Need to Strengthen `cleanupHandleProperty`

This issue was repeatedly confirmed in the uploaded reviews and later checks.

Dangerous code pattern:

```matlab
if isobject(h) && isvalid(h)
```

If `h` is a handle array, `isvalid(h)` can return a logical array and cause conditional failure or skipped cleanup.

Recommended code:

```matlab
function cleanupHandleProperty(app, propName)
    try
        if ~isprop(app, propName)
            return;
        end

        h = app.(propName);
        if isempty(h)
            app.(propName) = [];
            return;
        end

        if isobject(h)
            for n = 1:numel(h)
                try
                    item = h(n);

                    if isa(item, 'handle') && isvalid(item)
                        if ismethod(item, 'cleanup')
                            try
                                item.cleanup();
                            catch ME
                                app.logCaught(ME, ...
                                    ['ControllerCleanup:' propName ':cleanup:item']);
                            end
                        end

                        try
                            delete(item);
                        catch ME
                            app.logCaught(ME, ...
                                ['ControllerCleanup:' propName ':delete:item']);
                        end
                    end
                catch ME
                    app.logCaught(ME, ...
                        ['ControllerCleanup:' propName ':item']);
                end
            end
        end

        app.(propName) = [];

    catch ME
        app.logCaught(ME, ['ControllerCleanup:' propName]);
    end
end
```

---

# 9. Core Fix 6 — Real-Time Video Slider Preview

## 9.1 Problem Summary

Current behavior:

```text
When dragging the video player slider, the screen remains frozen and changes only after release.
```

Required behavior:

```text
Preview frames during drag.
After release, commit the final frame and synchronize data / plot / status.
```

---

## 9.2 Recommended Implementation Structure

```matlab
slider.ValueChangingFcn = @(src, evt) app.onVideoSliderChanging(fIdx, evt.Value);
slider.ValueChangedFcn  = @(src, evt) app.onVideoSliderChanged(fIdx, src.Value);
```

During drag:

```matlab
function onVideoSliderChanging(app, fIdx, value)
    frameNo = round(value);

    % Apply throttle
    if ~app.shouldUpdatePreview(fIdx, frameNo)
        return;
    end

    % Quickly update only video preview
    app.requestFrame(fIdx, frameNo, 'slider-preview');

    % If synchronized, lightly update data marker preview
    if app.VideoSyncState(fIdx).IsSynced
        app.previewSyncedDataMarker(fIdx, frameNo);
    end
end
```

After release:

```matlab
function onVideoSliderChanged(app, fIdx, value)
    frameNo = round(value);

    % Confirm final frame
    app.goToFrame(fIdx, frameNo, 'slider-final');

    % Fully update plot, marker, status, and synced data index
    app.commitSyncedFrameState(fIdx, frameNo);
end
```

---

# 10. Core Fix 7 — Stabilize Mouse Drag / Cursor Lock

## 10.1 Problem Summary

User feedback:

```text
After repeatedly adjusting panel spacing and dragging the star marker,
the crosshair cursor does not disappear and the operation freezes.
```

Possible causes:

```text
1. Missing WindowButtonUpFcn handling
2. Exception during drag motion callback
3. Missing MouseRouter lock release
4. State conflict between ROI mode / marker drag / splitter drag
5. Active drag controller remains during tab switch or close
```

---

## 10.2 Recommended Helper Code

```matlab
function forceEndAllDrag(app, reason)
    %#ok<INUSD>
    try, app.State = 'IDLE'; catch, end
    try, app.IsDraggingSplitter = false; catch, end
    try, app.IsDraggingPanelSplitter = false; catch, end
    try, app.IsDraggingPanner = false; catch, end

    try
        if ~isempty(app.MarkerDragCtrl) && isvalid(app.MarkerDragCtrl)
            app.MarkerDragCtrl.stopDrag();
            app.MarkerDragCtrl.clearDraggedMarker();
        end
    catch
    end

    try
        if ~isempty(app.PannerCtrl) && isvalid(app.PannerCtrl)
            app.PannerCtrl.stopDrag();
        end
    catch
    end

    try
        if ~isempty(app.MouseRouter) && isvalid(app.MouseRouter)
            app.MouseRouter.releaseDragLock();
        end
    catch
    end

    try
        if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
            app.UIFigure.Pointer = 'arrow';
        end
    catch
    end
end
```

Call locations:

```text
1. WindowButtonUpFcn
2. WindowKeyPressFcn when Esc is pressed
3. tab switch
4. tab close
5. figure close
6. catch block of drag motion callback
7. ROI mode cancel
```

---

# 11. Core Fix 8 — ROI / Manager / Detail / Analyzer UX

## 11.1 Problem Summary

User feedback:

```text
When pressing the ROI button, the entire plot becomes orange but the next action is unclear.
It is hard to know which Flight/Tab the Manager/Detail/ROI/Analyzer figure belongs to.
The Show checkbox does not change anything.
After clicking the session GUI, the auxiliary figure disappears.
```

---

## 11.2 Recommended Structure

### Object context

```text
SessionId
ChannelIdx
PanelId
TabId
ObjectId
```

### Example figure titles

```text
ROI Manager - Session 1 / Flight 1
Plot Detail - Session 2 / Flight 2 / Altitude
Analyzer - Session 1 / Flight 1 / H Panel
```

### Figure registry

```matlab
% pseudo-code
key = sprintf('%s:%s:%d', sessionId, toolName, channelIdx);

if obj.FigureMap.isKey(key)
    fig = obj.FigureMap(key);
    if isvalid(fig)
        figure(fig);
        return;
    end
end

fig = uifigure('Name', titleText);
obj.FigureMap(key) = fig;
```

### ROI mode guidance

```text
StatusBar:
ROI mode - drag over Data View Panel to select range. Esc to cancel.

Cursor:
crosshair

Plot overlay:
semi-transparent selection guide

Toolbar button:
active state display
```

### Separate InteractionMode

```text
normal
markerDrag
roiSelect
pan
splitterDrag
```

---

# 12. Integrated Application Order

## Step 1 — Column Mapping Fix

Target files:

```text
+flightdash/+model/FlightDataLoader.m
+flightdash/+util/AppConstants.m
```

Verification:

```matlab
clear classes
rehash toolboxcache

results = runtests('FlightReviewStudioTestSuite');
table(results)

runAllTestCodesWithCleanup
```

Manual verification:

```text
Flight 1 button
→ Select actual CSV
→ Mapping succeeds or gives warning even when option1.dat format differs
→ Roll/Pitch missing does not block full loading
```

---

## Step 2 — Improve Studio Initialization

Target file:

```text
+flightdash/+studio/FlightReviewStudioApp.m
```

Verification:

```text
Launch FlightReviewStudio
→ Auto-create Session 1
→ Display Session 1 in Project Explorer
→ Activate Dashboard tab
```

---

## Step 3 — Strengthen Project Explorer

Target file:

```text
+flightdash/+studio/ProjectExplorerPanel.m
```

Verification:

```matlab
results = runtests('FlightReviewStudioTestSuite', ...
    'ProcedureName', 'test_T5_Explorer_Selection');
table(results)
```

Manual verification:

```text
Session add / rename / duplicate / delete
→ tree refresh
→ active session selection maintained
```

---

## Step 4 — WorkspaceManager WelcomeTab Transition

Target file:

```text
+flightdash/+studio/WorkspaceManager.m
```

Verification:

```text
Immediately after auto-creating Session 1
→ Dashboard tab, not WelcomeTab, is active
```

---

## Step 5 — Unify Standalone / Embedded Dashboard

Target files:

```text
FlightDataDashboard.m
+flightdash/FlightDataDashboard.m
```

Verification:

```matlab
FlightDataDashboard
FlightReviewStudio
```

Check:

```text
Compare standalone and Studio embedded dashboard layout / Flight 1 loading / video loading behavior
```

---

# 13. Automated Test Strategy

## Basic test suite

```matlab
clear classes
rehash toolboxcache

results = runtests('FlightReviewStudioTestSuite');
table(results)
```

## Full runner

```matlab
runAllTestCodesWithCleanup
```

## Phase diagnostics

```matlab
flightdash.studio.diag.verifyPhase3()
flightdash.studio.diag.verifyPhase4()
flightdash.studio.diag.verifyPhase5()
flightdash.studio.diag.verifyPhase6()
flightdash.studio.diag.verifyPhase7()
flightdash.studio.diag.verifyPhase8()
flightdash.studio.diag.verifyPhase9()
flightdash.studio.diag.verifyPhase10()
```

---

# 14. Manual GUI Test Checklist

## 14.1 Studio initial launch

```text
1. Launch FlightReviewStudio.
2. Confirm Project Explorer is visible.
3. Confirm Session 1 is automatically created.
4. Confirm Dashboard tab is active.
5. Confirm WelcomeTab is not still active.
```

---

## 14.2 CSV loading

```text
1. Click Flight 1.
2. Select actual CSV.
3. Confirm Roll/Pitch mapping error is gone.
4. Confirm clear error message when a critical column is missing.
5. Confirm warning + UI disabled behavior when optional columns are missing.
```

---

## 14.3 Standalone Dashboard

```text
1. Run FlightDataDashboard standalone.
2. Compare screen with Studio embedded dashboard.
3. Confirm Flight 1 button works.
4. Confirm CSV / AVI loading works.
```

---

## 14.4 Multi-session

```text
1. Add sessions.
2. Switch sessions.
3. Select sessions in Project Explorer.
4. Check Workspace tab active state.
5. Check Undo/Redo service isolation.
6. Check resource cleanup after session close.
```

---

## 14.5 Video / Data synchronization

```text
1. Load AVI.
2. Load flight data.
3. Confirm marker drag does not move video before synchronization.
4. Confirm marker drag moves video frame after synchronization.
5. Confirm real-time preview during video slider drag.
6. Confirm data marker / current value / status synchronization after release.
```

---

# 15. Risks and Mitigations

## 15.1 Risk of incorrect partial-match mapping

Problem:

```text
contains-based fallback can map the wrong header if it is too aggressive.
```

Mitigation:

```text
1. Exact normalized match first
2. Alias match second
3. Partial match only as the final fallback
4. If there are multiple candidates, show warning or mapping dialog
5. Consider adding a confidence score
```

---

## 15.2 Impact of Roll/Pitch warning handling

Problem:

```text
If attitude gauge or related analysis is displayed without Roll/Pitch, errors may occur.
```

Mitigation:

```text
1. Disable gauge panel when Roll/Pitch is missing.
2. Disable related analysis buttons + tooltip.
3. Show missing optional columns in the status bar.
```

---

## 15.3 Workflow change caused by Session 1 auto-create

Problem:

```text
Some users may expect an empty project state.
```

Mitigation:

```text
1. Auto-create only for a new project on initial launch.
2. Do not auto-create when loading an existing project.
3. Consider adding an AutoCreateDefaultSession setting.
```

---

## 15.4 Project Explorer refresh overwrites selection

Problem:

```text
If the first session is selected on every refresh, the user's current session may be changed unexpectedly.
```

Mitigation:

```text
Prefer ActiveSessionId.
Select the first session only when there is no ActiveSessionId.
```

---

## 15.5 Excessive drawnow calls

Problem:

```text
Too many drawnow limitrate calls can reduce performance.
```

Mitigation:

```text
Use it only at limited points such as initialization, session creation, tab switching, and refresh completion.
```

---

## 15.6 Handle-array cleanup problem

Problem:

```text
isvalid(handleArray) returns a logical array and may cause conditional errors.
```

Mitigation:

```text
Apply numel-based iterative cleanup.
```

---

# 16. Final Recommended Commit Structure

## Commit 1 — Column Mapping

```bash
git commit -m "fix(data): improve flight column mapping for option files and CSV headers"
```

Included files:

```text
+flightdash/+model/FlightDataLoader.m
+flightdash/+util/AppConstants.m
```

---

## Commit 2 — Studio Initialization

```bash
git commit -m "fix(studio): auto-create default session on initial launch"
```

Included file:

```text
+flightdash/+studio/FlightReviewStudioApp.m
```

---

## Commit 3 — Project Explorer / Workspace

```bash
git commit -m "fix(studio): synchronize Project Explorer and Workspace after session creation"
```

Included files:

```text
+flightdash/+studio/ProjectExplorerPanel.m
+flightdash/+studio/WorkspaceManager.m
```

---

## Commit 4 — Dashboard Compatibility / Cleanup

```bash
git commit -m "fix(dashboard): harden standalone embedded compatibility and handle cleanup"
```

Included files:

```text
FlightDataDashboard.m
+flightdash/FlightDataDashboard.m
```

---

## Commit 5 — Video / Drag UX

```bash
git commit -m "feat(ux): add responsive video scrubbing and drag-state recovery"
```

Included areas:

```text
Video slider callbacks
PlaybackController
MouseRouter
DragController
FlightDataDashboard.forceEndAllDrag
```

---

# 17. Final Integrated Judgment

The main point of the 1st–9th reviews is that before adding new features, the **basic user workflow must be stabilized first**.

The highest-priority workflow is:

```text
Launch FlightReviewStudio
→ Auto-create Session 1
→ Display Project Explorer
→ Activate Dashboard tab
→ Successfully load Flight 1 CSV
→ Successfully load video
→ Synchronize data/video
→ Stable session switch/save/close
```

The first tasks to perform are:

```text
1. Column Mapping Fix
2. Session 1 Auto-create
3. Project Explorer refresh/expand/select
4. Workspace WelcomeTab → Dashboard transition
5. Standalone/embedded consistency for FlightDataDashboard
```

Once items 1–5 are stable, development can move into UX completion work.

```text
6. Real-time video slider preview
7. Mouse drag lock stabilization
8. Manager / Detail / ROI / Analyzer cleanup
9. Layout / readability / file name display / gauge / Range button improvements
```

Therefore, the recommended development direction is:

```text
First stabilize data loading and the initial Studio screen.
Then finalize synchronization between session / workspace / explorer.
Then improve video-data synchronization UX and drag stability.
Finally clean up readability, auxiliary figures, and analysis functions.
```
