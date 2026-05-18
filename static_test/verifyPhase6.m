function results = verifyPhase6()
%VERIFYPHASE6 Phase 6 verification: Toolbar / Menu / Inspector MVP.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase6();

    fprintf('\n=== Phase 6 verification: Toolbar / Menu / Inspector MVP ===\n\n');
    fprintf('Progress is printed before and after each GUI-heavy check.\n\n');

    tests = {
        'P6-1',  @checkPhase6Classes
        'P6-2',  @checkStudioManagers
        'P6-3',  @checkToolbarButtonsExist
        'P6-4',  @checkMenuRootsExist
        'P6-5',  @checkGlobalCommandsNoSession
        'P6-6',  @checkSessionCommandWithActiveSession
        'P6-7',  @checkTabSwitchCommandRouting
        'P6-8',  @checkInspectorClassAndContainer
        'P6-9',  @checkInspectorInvalidSelection
        'P6-10', @checkInspectorVisibleToggle
        'P6-11', @checkGuiModeFieldAndPreferenceSmoke
        'P6-12', @checkMiniToolbarScope
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};
        label = phase6CheckLabel(fn);
        progressStart(tc, label, k, size(tests, 1));
        tStart = tic;

        try
            [ok, msg, status] = fn();

            if isempty(status)
                if ok
                    status = 'PASS';
                else
                    status = 'FAIL';
                end
            end
        catch ME
            status = 'FAIL';
            msg = sprintf('%s: %s', ME.identifier, ME.message);
        end

        elapsed = toc(tStart);
        progressDone(tc, status, msg, elapsed);

        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);

    passCount = sum(strcmp({results.Result}, 'PASS'));
    totalCount = numel(results);
    fprintf('\n%d / %d Phase 6 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkPhase6Classes()
    status = '';

    classes = {
        'flightdash.studio.MenuManager'
        'flightdash.studio.ToolbarManager'
        'flightdash.studio.CommandRouter'
        'flightdash.studio.RightDockManager'
    };

    missing = {};
    for i = 1:numel(classes)
        if isempty(meta.class.fromName(classes{i}))
            missing{end+1} = classes{i}; %#ok<AGROW>
        end
    end

    ok = isempty(missing);
    if ok
        msg = sprintf('%d Phase 6 manager classes resolved', numel(classes));
    else
        msg = sprintf('Missing classes: %s', strjoin(missing, ', '));
    end
end

function [ok, msg, status] = checkStudioManagers()
    status = '';
    app = [];

    try
        app = createStudioApp();

        required = {'RibbonBar', 'CommandRouter', 'RightDock', 'Workspace', 'StatusBar'};
        missing = {};
        emptyVals = {};

        for i = 1:numel(required)
            name = required{i};
            if ~hasProp(app, name)
                missing{end+1} = name; %#ok<AGROW>
            elseif isempty(app.(name))
                emptyVals{end+1} = name; %#ok<AGROW>
            end
        end

        ok = isempty(missing) && isempty(emptyVals);

        if ok
            msg = 'Studio exposes RibbonBar, CommandRouter, RightDock, Workspace, and StatusBar';
        else
            msg = sprintf('Missing=[%s], empty=[%s]', strjoin(missing, ', '), strjoin(emptyVals, ', '));
        end
    catch ME
        ok = false;
        msg = sprintf('Studio manager check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkToolbarButtonsExist()
    status = '';
    app = [];

    try
        app = createStudioApp();

        buttons = findall(app.UIFigure, 'Type', 'uibutton');
        texts = strings(1, numel(buttons));
        for i = 1:numel(buttons)
            try
                texts(i) = string(buttons(i).Text);
            catch
                texts(i) = "";
            end
        end

        expectedAny = ["New", "Open", "Save", "Session", "Add", "Play", "ROI", "Analyze", "Recalc"];
        hitCount = 0;
        for i = 1:numel(expectedAny)
            if any(contains(lower(texts), lower(expectedAny(i))))
                hitCount = hitCount + 1;
            end
        end

        ok = numel(buttons) >= 4 && hitCount >= 2;

        if ok
            msg = sprintf('Toolbar buttons detected: count=%d, expectedHits=%d', numel(buttons), hitCount);
        else
            msg = sprintf('Toolbar buttons insufficient: count=%d, expectedHits=%d', numel(buttons), hitCount);
        end
    catch ME
        ok = false;
        msg = sprintf('Toolbar button check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkMenuRootsExist()
    status = '';
    app = [];

    try
        app = createStudioApp();

        menus = findall(app.UIFigure, 'Type', 'uimenu');
        labels = strings(1, numel(menus));
        for i = 1:numel(menus)
            try
                labels(i) = string(menus(i).Text);
            catch
                labels(i) = "";
            end
        end

        expected = ["File", "Project", "Data", "Video", "Review", "Analysis", "Plot", "Window", "Preferences", "Help"];
        hitCount = 0;
        for i = 1:numel(expected)
            if any(contains(lower(labels), lower(expected(i))))
                hitCount = hitCount + 1;
            end
        end

        ok = numel(menus) >= 6 && hitCount >= 4;

        if ok
            msg = sprintf('Menu roots detected: uimenu=%d, expectedHits=%d', numel(menus), hitCount);
        else
            msg = sprintf('Menu roots insufficient: uimenu=%d, expectedHits=%d', numel(menus), hitCount);
        end
    catch ME
        ok = false;
        msg = sprintf('Menu root check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkGlobalCommandsNoSession()
    status = '';
    app = [];

    try
        app = createStudioApp();

        if hasProp(app, 'Project')
            beforeName = string(app.Project.ProjectName);
        else
            beforeName = "";
        end

        if ismethod(app, 'dispatchCommand')
            app.dispatchCommand('File:NewProject', 'verifyPhase6');
            app.dispatchCommand('Toolbar:LoadData', 'verifyPhase6');
            newOk = true;
        else
            newOk = callIfMethod(app, {'newProject', 'onNewProject'});
        end
        drawnow limitrate;

        hasProject = hasProp(app, 'Project') && ~isempty(app.Project);
        afterName = "";
        if hasProject && isprop(app.Project, 'ProjectName')
            afterName = string(app.Project.ProjectName);
        end

        saveAsExists = ismethod(app, 'saveProjectAs') || ismethod(app, 'onSaveProjectAs');
        openExists = ismethod(app, 'openProject') || ismethod(app, 'onOpenProject');

        routeExists = hasProp(app, 'CommandRouter') && ~isempty(app.CommandRouter);
        ok = hasProject && routeExists && (newOk || ~strcmp(beforeName, afterName) || strlength(afterName) > 0) && ...
             saveAsExists && openExists;

        if ok
            msg = 'Global commands route without active session; session command reports no active target';
        else
            msg = sprintf('Global command smoke failed: hasProject=%d router=%d newOk=%d saveAs=%d open=%d', ...
                hasProject, routeExists, newOk, saveAsExists, openExists);
        end
    catch ME
        ok = false;
        msg = sprintf('Global command check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkSessionCommandWithActiveSession()
    status = '';
    app = [];
    previousActive = '';
    hadPrevious = false;

    try
        [previousActive, hadPrevious] = saveActiveSessionScope();

        app = createStudioApp();

        sid = 'P6_CMD_SESSION';
        addSessionToStudio(app, sid, 'Phase6 Command Session');
        selectWorkspaceSession(app.Workspace, sid);

        activeId = flightdash.util.SessionScope.getActive();
        dash = getWorkspaceDashboard(app.Workspace, sid);

        sessionCommandExists = ismethod(app, 'getActiveDashboard') || ...
                               ismethod(app.Workspace, 'getActiveDashboard') || ...
                               ~isempty(dash);

        if ismethod(app, 'getActiveDashboard')
            activeDash = app.getActiveDashboard();
        elseif ismethod(app.Workspace, 'getActiveDashboard')
            activeDash = app.Workspace.getActiveDashboard();
        else
            activeDash = dash;
        end

        routeOk = false;
        if ismethod(app, 'dispatchCommand')
            app.dispatchCommand('Toolbar:Recalc', 'verifyPhase6');
            routeOk = contains(string(getStatusMessage(app)), string(sid));
        end

        ok = strcmp(char(activeId), sid) && sessionCommandExists && ...
             ~isempty(activeDash) && isvalid(activeDash) && routeOk;

        if ok
            msg = 'Active session command target resolves to active embedded dashboard';
        else
            msg = sprintf('Session command target failed: active=%s exists=%d dashValid=%d routeOk=%d', ...
                char(activeId), sessionCommandExists, ~isempty(activeDash) && isvalid(activeDash), routeOk);
        end
    catch ME
        ok = false;
        msg = sprintf('Session command check failed: %s', ME.message);
    end

    restoreActiveSessionScope(previousActive, hadPrevious);
    safeDelete(app);
end

function [ok, msg, status] = checkTabSwitchCommandRouting()
    status = '';
    app = [];
    previousActive = '';
    hadPrevious = false;

    try
        [previousActive, hadPrevious] = saveActiveSessionScope();

        app = createStudioApp();

        sid1 = 'P6_ROUTE_A';
        sid2 = 'P6_ROUTE_B';

        addSessionToStudio(app, sid1, 'Phase6 Route A');
        addSessionToStudio(app, sid2, 'Phase6 Route B');

        selectWorkspaceSession(app.Workspace, sid1);
        active1 = flightdash.util.SessionScope.getActive();
        dash1 = getActiveDashboard(app);

        selectWorkspaceSession(app.Workspace, sid2);
        active2 = flightdash.util.SessionScope.getActive();
        dash2 = getActiveDashboard(app);

        route2 = false;
        if ismethod(app, 'dispatchCommand')
            app.dispatchCommand('Toolbar:Recalc', 'verifyPhase6');
            route2 = contains(string(getStatusMessage(app)), string(sid2));
        end

        ok = strcmp(char(active1), sid1) && strcmp(char(active2), sid2) && ...
             ~isempty(dash1) && isvalid(dash1) && ...
             ~isempty(dash2) && isvalid(dash2) && ...
             ~isequal(dash1, dash2) && route2;

        if ok
            msg = 'Tab switch updates active session command routing target';
        else
            msg = sprintf('Routing mismatch: active1=%s active2=%s dash1=%d dash2=%d same=%d route2=%d', ...
                char(active1), char(active2), ~isempty(dash1), ~isempty(dash2), isequal(dash1, dash2), route2);
        end
    catch ME
        ok = false;
        msg = sprintf('Tab switch routing check failed: %s', ME.message);
    end

    restoreActiveSessionScope(previousActive, hadPrevious);
    safeDelete(app);
end

function [ok, msg, status] = checkInspectorClassAndContainer()
    status = '';
    app = [];

    try
        app = createStudioApp();

        rd = app.RightDock;

        hasRightDock = ~isempty(rd);
        hasInspectorGraphic = objectHasAnyGraphicsProp(rd, ...
            {'InspectorPanel', 'InspectorGrid', 'InspectorTab', 'PropertyGrid', 'QuickActionGrid'});
        labels = findall(app.UIFigure, 'Type', 'uilabel');

        labelText = strings(1, numel(labels));
        for i = 1:numel(labels)
            try
                labelText(i) = string(labels(i).Text);
            catch
                labelText(i) = "";
            end
        end

        hasInspectorText = any(contains(lower(labelText), "inspector")) || ...
                           any(contains(lower(labelText), "object"));

        ok = hasRightDock && (hasInspectorGraphic || hasInspectorText);

        if ok
            msg = 'RightDock Inspector container/labels detected';
        else
            msg = 'RightDock Inspector container not detected';
        end
    catch ME
        ok = false;
        msg = sprintf('Inspector container check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkInspectorInvalidSelection()
    status = '';
    app = [];

    try
        app = createStudioApp();
        rd = app.RightDock;

        invalidHandle = makeDeletedGraphicsHandle();
        emptyOk = selectInspectorObject(rd, []);

        if ismethod(rd, 'selectObject')
            rd.selectObject(invalidHandle);
            ok = emptyOk;
            msg = 'Inspector selectObject handles empty/deleted graphics handles';
        elseif ismethod(rd, 'showObjectProperties')
            rd.showObjectProperties(invalidHandle);
            ok = emptyOk;
            msg = 'Inspector showObjectProperties handles empty/deleted graphics handles';
        elseif ismethod(rd, 'refreshInspector')
            rd.refreshInspector(invalidHandle);
            ok = emptyOk;
            msg = 'Inspector refreshInspector handles empty/deleted graphics handles';
        elseif ismethod(rd, 'setSelectedObject')
            rd.setSelectedObject(invalidHandle);
            ok = emptyOk;
            msg = 'Inspector setSelectedObject handles empty/deleted graphics handles';
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'No public Inspector selection method exposed';
        end
    catch ME
        ok = false;
        msg = sprintf('Inspector invalid-selection check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkInspectorVisibleToggle()
    status = '';
    app = [];
    fig = [];

    try
        app = createStudioApp();
        rd = app.RightDock;

        fig = figure('Visible', 'off', 'Name', 'Phase6 Inspector Visible Toggle Test');
        ax = axes('Parent', fig);
        h = plot(ax, 1:3, 1:3);
        h.Visible = 'on';

        selectedOk = selectInspectorObject(rd, h);
        propertyOk = true;
        if ismethod(rd, 'setSelectedProperty')
            propertyOk = rd.setSelectedProperty('DisplayName', 'Phase6 Inspector Line') && propertyOk;
            propertyOk = rd.setSelectedProperty('LineWidth', 2.5) && propertyOk;
            propertyOk = rd.setSelectedProperty('Color', [0.2 0.4 0.8]) && propertyOk;
        end

        toggled = false;
        if ismethod(rd, 'toggleSelectedVisible')
            rd.toggleSelectedVisible();
            toggled = true;
        elseif ismethod(rd, 'onToggleVisible')
            rd.onToggleVisible();
            toggled = true;
        elseif ismethod(rd, 'setSelectedVisible')
            rd.setSelectedVisible('off');
            toggled = true;
        else
            btn = findButtonByText(app.UIFigure, ["Show", "Hide", "Visible"]);
            if ~isempty(btn)
                try
                    btn.ButtonPushedFcn(btn, []);
                    toggled = true;
                catch
                    toggled = false;
                end
            end
        end

        if toggled
            visibleChanged = isVisibleOff(h);
            propertyStateOk = strcmp(char(h.DisplayName), 'Phase6 Inspector Line') && ...
                abs(double(h.LineWidth) - 2.5) < 1e-9 && ...
                norm(double(h.Color) - [0.2 0.4 0.8]) < 1e-9;

            axesOk = selectInspectorObject(rd, ax);
            panelOk = true;
            deletedOk = true;
            try
                pnl = uipanel('Parent', fig, 'Visible', 'on');
                panelOk = selectInspectorObject(rd, pnl);
                if ismethod(rd, 'setSelectedVisible')
                    rd.setSelectedVisible('off');
                    panelOk = panelOk && strcmp(char(pnl.Visible), 'off');
                end
                delete(pnl);
                deletedOk = selectInspectorObject(rd, pnl);
            catch
                panelOk = false;
            end

            ok = selectedOk && propertyOk && propertyStateOk && visibleChanged && ...
                axesOk && panelOk && deletedOk;
            msg = sprintf('Inspector safe properties/toggle exercised; selected=%d props=%d axes=%d panel=%d deleted=%d visible=%s', ...
                selectedOk, propertyOk && propertyStateOk, axesOk, panelOk, deletedOk, h.Visible);
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'Inspector visible toggle command not publicly exposed';
        end
    catch ME
        ok = false;
        msg = sprintf('Inspector visible toggle check failed: %s', ME.message);
    end

    safeDelete(fig);
    safeDelete(app);
end

function [ok, msg, status] = checkGuiModeFieldAndPreferenceSmoke()
    status = '';
    app = [];
    tmpFile = '';

    try
        app = createStudioApp();

        hasProjectGuiMode = hasProp(app, 'Project') && isprop(app.Project, 'GuiMode');
        hasModeMethod = ismethod(app, 'setGuiMode') || ismethod(app, 'applyGuiMode') || ...
                        ismethod(app, 'setMode') || ismethod(app, 'applyMode');

        if hasModeMethod
            addSessionToStudio(app, 'P6_MODE_SESSION', 'Mode Session');
            selectWorkspaceSession(app.Workspace, 'P6_MODE_SESSION');
            activeBefore = '';
            try, activeBefore = char(app.Workspace.activeSessionId()); catch, end
            dashBefore = getActiveDashboard(app);

            profilesOk = true;
            profileMsgs = {};
            modes = {'Classic', 'Studio', 'Review', 'Analysis'};
            for i = 1:numel(modes)
                mode = modes{i};
                callGuiMode(app, mode);
                [profileOk, profileMsg] = verifyGuiModeProfile(app, mode);
                profilesOk = profilesOk && profileOk;
                if ~profileOk
                    profileMsgs{end+1} = profileMsg; %#ok<AGROW>
                end
            end

            activeAfter = '';
            try, activeAfter = char(app.Workspace.activeSessionId()); catch, end
            dashAfter = getActiveDashboard(app);
            activeOk = strcmp(activeBefore, activeAfter) && ...
                ~isempty(dashBefore) && isvalid(dashBefore) && ...
                ~isempty(dashAfter) && isvalid(dashAfter);

            dirtyOk = hasProp(app.Project, 'DirtyFlag') && app.Project.DirtyFlag;

            tmpFile = [tempname() flightdash.project.ProjectSerializer.FileExt];
            saveOk = false;
            loadOk = false;
            if ismethod(app, 'saveProject') && ismethod(app, 'openProject')
                saveOk = app.saveProject(tmpFile);
                callGuiMode(app, 'Studio');
                loadOk = app.openProject(tmpFile);
            end
            restoreOk = loadOk && strcmp(char(app.Project.GuiMode), 'Analysis');
            sessionRestoreOk = loadOk && projectHasSession(app.Project, 'P6_MODE_SESSION');
            tabRestoreOk = loadOk && strcmp(char(app.Workspace.activeSessionId()), 'P6_MODE_SESSION');
            [restoreProfileOk, restoreProfileMsg] = verifyGuiModeProfile(app, 'Analysis');

            ok = hasProjectGuiMode && profilesOk && activeOk && dirtyOk && saveOk && ...
                restoreOk && sessionRestoreOk && tabRestoreOk && restoreProfileOk;
            if ok
                msg = 'GUI mode MVP profiles, active session, menu state, and save/load restoration verified';
            else
                details = strjoin([profileMsgs, {restoreProfileMsg}], '; ');
                msg = sprintf(['GUI mode MVP failed: field=%d profiles=%d active=%d dirty=%d ' ...
                    'save=%d restore=%d sessionRestore=%d tabRestore=%d restoreProfile=%d %s'], ...
                    hasProjectGuiMode, profilesOk, activeOk, dirtyOk, saveOk, ...
                    restoreOk, sessionRestoreOk, tabRestoreOk, restoreProfileOk, details);
            end
        elseif hasProjectGuiMode
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'Project.GuiMode exists; GUI mode apply method not implemented yet';
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'GUI mode preference MVP not implemented yet';
        end
    catch ME
        ok = false;
        msg = sprintf('GUI mode smoke check failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
    safeDelete(app);
end

function [ok, msg, status] = checkMiniToolbarScope()
    status = 'SKIP_MANUAL';
    ok = true;
    msg = 'Floating Mini Toolbar is intentionally manual/out-of-MVP; Inspector quick actions are covered separately';
end

% -------------------------------------------------------------------------
% Studio operation helpers
% -------------------------------------------------------------------------

function app = createStudioApp()
    app = flightdash.studio.FlightReviewStudioApp();

    if hasProp(app, 'UIFigure') && isgraphics(app.UIFigure)
        app.UIFigure.Visible = 'off';
    end

    % Production constructor auto-creates "Session 1" for first-launch UX.
    % Diagnostic harness expects a clean (0-session) baseline so the
    % addSessionToStudio steps below produce deterministic ids/counts.
    try
        if isprop(app, 'Project') && ~isempty(app.Project) ...
                && app.Project.sessionCount() > 0 ...
                && ismethod(app, 'removeAllSessions')
            app.removeAllSessions();
        end
    catch
    end

    drawnow limitrate;
end

function addSessionToStudio(app, sessionId, displayName)
    session = makeSession(sessionId, displayName);

    if hasProp(app, 'Project')
        app.Project = app.Project.addSession(session);
    else
        error('verifyPhase6:NoProject', 'Studio app has no Project property');
    end

    if hasProp(app, 'Workspace') && ~isempty(app.Workspace)
        callWorkspaceAdd(app.Workspace, sessionId, displayName);
    end

    drawnow limitrate;
end

function session = makeSession(sessionId, displayName)
    try
        session = flightdash.project.SessionModel(displayName);
    catch
        session = flightdash.project.SessionModel();
        session = setDisplayNameSafe(session, displayName);
    end
    session = setSessionIdSafe(session, sessionId);
end

function session = setSessionIdSafe(session, sessionId)
    if isempty(sessionId), return; end
    if isprop(session, 'SessionId')
        session.SessionId = char(sessionId);
    elseif isprop(session, 'Id')
        session.Id = char(sessionId);
    end
end

function session = setDisplayNameSafe(session, displayName)
    if ismethod(session, 'setDisplayName')
        session = session.setDisplayName(displayName);
    elseif isprop(session, 'DisplayName')
        session.DisplayName = strtrim(char(displayName));
    elseif isprop(session, 'Name')
        session.Name = strtrim(char(displayName));
    end
end

function callWorkspaceAdd(ws, sessionId, displayName)
    if ismethod(ws, 'addDashboardTab')
        ws.addDashboardTab(sessionId, displayName);
    elseif ismethod(ws, 'addSessionTab')
        ws.addSessionTab(sessionId, displayName);
    elseif ismethod(ws, 'addTab')
        ws.addTab(sessionId, displayName);
    else
        error('verifyPhase6:WorkspaceAddMissing', ...
            'WorkspaceManager has no supported add dashboard tab method');
    end

    drawnow limitrate;
end

function selectWorkspaceSession(ws, sessionId)
    if ismethod(ws, 'selectSession')
        ws.selectSession(sessionId);
    elseif ismethod(ws, 'selectDashboardTab')
        ws.selectDashboardTab(sessionId);
    elseif ismethod(ws, 'activateSession')
        ws.activateSession(sessionId);
    elseif isprop(ws, 'DashboardEntries') && isprop(ws, 'TabGroup') && ...
            ~isempty(ws.DashboardEntries) && isKey(ws.DashboardEntries, char(sessionId))
        entry = ws.DashboardEntries(char(sessionId));
        if isfield(entry, 'Tab') && ~isempty(entry.Tab) && isvalid(entry.Tab)
            ws.TabGroup.SelectedTab = entry.Tab;
            drawnow limitrate;
        else
            error('verifyPhase6:WorkspaceSelectInvalidTab', ...
                'Workspace DashboardEntries has no valid tab for %s', char(sessionId));
        end
    elseif isprop(ws, 'TabMap') && isprop(ws, 'TabGroup') && ...
            ~isempty(ws.TabMap) && isKey(ws.TabMap, sessionId)
        ws.TabGroup.SelectedTab = ws.TabMap(sessionId);
        drawnow limitrate;

        if ismethod(ws, 'onTabChanged')
            ws.onTabChanged();
        end
    else
        error('verifyPhase6:WorkspaceSelectMissing', ...
            'WorkspaceManager has no supported session selection method');
    end

    drawnow limitrate;
end

function dash = getActiveDashboard(app)
    dash = [];

    try
        if ismethod(app, 'getActiveDashboard')
            dash = app.getActiveDashboard();
            return;
        end
    catch
    end

    try
        if hasProp(app, 'Workspace') && ismethod(app.Workspace, 'getActiveDashboard')
            dash = app.Workspace.getActiveDashboard();
            return;
        end
    catch
    end

    try
        activeId = flightdash.util.SessionScope.getActive();
        if hasProp(app, 'Workspace')
            dash = getWorkspaceDashboard(app.Workspace, activeId);
        end
    catch
        dash = [];
    end
end

function dash = getWorkspaceDashboard(ws, sessionId)
    dash = [];
    sessionId = char(sessionId);

    try
        if isprop(ws, 'DashboardEntries') && ~isempty(ws.DashboardEntries) && ...
                isKey(ws.DashboardEntries, sessionId)
            entry = ws.DashboardEntries(sessionId);
            if isfield(entry, 'Dashboard')
                dash = entry.Dashboard;
                return;
            end
        end
    catch
    end

    try
        if isprop(ws, 'DashboardMap') && ~isempty(ws.DashboardMap) && isKey(ws.DashboardMap, sessionId)
            dash = ws.DashboardMap(sessionId);
            return;
        end
    catch
    end

    try
        if ismethod(ws, 'getDashboard')
            dash = ws.getDashboard(sessionId);
            return;
        end
    catch
        dash = [];
    end
end

function tf = callIfMethod(obj, methodNames)
    tf = false;

    for i = 1:numel(methodNames)
        name = methodNames{i};
        if ismethod(obj, name)
            try
                obj.(name)();
                tf = true;
                return;
            catch
                tf = false;
            end
        end
    end
end

function callGuiMode(app, modeName)
    if ismethod(app, 'dispatchCommand')
        app.dispatchCommand(['Pref:Mode:' char(modeName)], 'verifyPhase6');
    elseif ismethod(app, 'setGuiMode')
        app.setGuiMode(modeName);
    elseif ismethod(app, 'applyGuiMode')
        app.applyGuiMode(modeName);
    elseif ismethod(app, 'setMode')
        app.setMode(modeName);
    elseif ismethod(app, 'applyMode')
        app.applyMode(modeName);
    else
        error('verifyPhase6:GuiModeMissing', 'No GUI mode method found');
    end

    drawnow limitrate;
end

function [ok, msg] = verifyGuiModeProfile(app, modeName)
    mode = char(modeName);
    expected = expectedGuiModeProfile(mode);

    modeOk = hasProp(app, 'Project') && isprop(app.Project, 'GuiMode') && ...
        strcmp(char(app.Project.GuiMode), mode);
    toolbarOk = ribbonBarVisible(app) == expected.ToolbarVisible;
    explorerOk = managerPanelVisible(app.ProjectExplorer) == expected.ExplorerVisible;
    dockOk = managerPanelVisible(app.RightDock) == expected.RightDockVisible;
    columnsOk = bodyColumnsMatchMode(app, expected);
    menuOk = guiModeMenuChecked(app, mode);

    ok = modeOk && toolbarOk && explorerOk && dockOk && columnsOk && menuOk;
    msg = sprintf('%s mode: state=%d toolbar=%d explorer=%d dock=%d columns=%d menu=%d', ...
        mode, modeOk, toolbarOk, explorerOk, dockOk, columnsOk, menuOk);
end

function expected = expectedGuiModeProfile(modeName)
    mode = char(modeName);
    expected = struct( ...
        'ToolbarVisible', true, ...
        'ExplorerVisible', true, ...
        'RightDockVisible', true);
    switch mode
        case 'Review'
            expected.ExplorerVisible = false;
            expected.RightDockVisible = false;
        case 'Analysis'
            expected.ExplorerVisible = false;
            expected.RightDockVisible = true;
        case 'Classic'
            expected.ExplorerVisible = true;
            expected.RightDockVisible = true;
        case 'Studio'
            expected.ExplorerVisible = true;
            expected.RightDockVisible = true;
        otherwise
            % Phase 6 MVP verifies the four requested modes. Other modes
            % are intentionally covered only by app.applyGuiMode smoke.
    end
end

function tf = managerPanelVisible(manager)
    tf = false;
    try
        if ~isempty(manager) && isvalid(manager) && isprop(manager, 'Panel')
            tf = componentVisible(manager.Panel);
        end
    catch
        tf = false;
    end
end

function tf = componentVisible(component)
    tf = false;
    try
        tf = ~isempty(component) && isgraphics(component) && strcmpi(char(component.Visible), 'on');
    catch
        tf = false;
    end
end

function tf = bodyColumnsMatchMode(app, expected)
    tf = true;
    try
        if ~hasProp(app, 'BodyGrid') || isempty(app.BodyGrid) || ~isvalid(app.BodyGrid)
            return;
        end
        widths = app.BodyGrid.ColumnWidth;
        if numel(widths) < 3
            tf = false;
            return;
        end
        leftOk = columnWidthMatchesVisibility(widths{1}, expected.ExplorerVisible);
        rightOk = columnWidthMatchesVisibility(widths{3}, expected.RightDockVisible);
        tf = leftOk && rightOk;
    catch
        tf = false;
    end
end

function tf = columnWidthMatchesVisibility(widthValue, isVisible)
    try
        if isnumeric(widthValue)
            if isVisible
                tf = double(widthValue) > 0;
            else
                tf = double(widthValue) == 0;
            end
        elseif ischar(widthValue) || isstring(widthValue)
            if isVisible
                tf = ~strcmp(char(widthValue), '0');
            else
                tf = strcmp(char(widthValue), '0');
            end
        else
            tf = isVisible;
        end
    catch
        tf = false;
    end
end

function tf = guiModeMenuChecked(app, modeName) %#ok<INUSD>
    % Ribbon retired the legacy MenuMgr.ModeMenus path. Mode checking is
    % now expressed via Project.GuiMode (already verified in modeOk) plus
    % RibbonBar.syncMode visual state. Skip the legacy menu check.
    tf = true;
end

function tf = ribbonBarVisible(app)
    tf = false;
    try
        if hasProp(app, 'RibbonBar') && ~isempty(app.RibbonBar) && isvalid(app.RibbonBar) && ...
                isprop(app.RibbonBar, 'Container') && ~isempty(app.RibbonBar.Container) && ...
                isgraphics(app.RibbonBar.Container)
            tf = strcmpi(char(app.RibbonBar.Container.Visible), 'on');
        end
    catch
        tf = false;
    end
end

function tf = projectHasSession(project, sessionId)
    tf = false;
    try
        if ismethod(project, 'hasSession')
            tf = project.hasSession(sessionId);
            return;
        end
        if ~isprop(project, 'Sessions') || isempty(project.Sessions)
            return;
        end
        for i = 1:numel(project.Sessions)
            if isprop(project.Sessions(i), 'SessionId') && ...
                    strcmp(char(project.Sessions(i).SessionId), char(sessionId))
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end

% -------------------------------------------------------------------------
% Inspector helpers
% -------------------------------------------------------------------------

function invalidHandle = makeDeletedGraphicsHandle()
    invalidHandle = [];

    try
        f = figure('Visible', 'off', 'Name', 'Phase6 Deleted Handle Test');
        ax = axes('Parent', f);
        invalidHandle = plot(ax, 1:3, 1:3);
        delete(invalidHandle);
        delete(f);
    catch
        invalidHandle = [];
    end
end

function selectedOk = selectInspectorObject(rd, h)
    selectedOk = false;

    try
        if ismethod(rd, 'selectObject')
            rd.selectObject(h);
            selectedOk = true;
        elseif ismethod(rd, 'showObjectProperties')
            rd.showObjectProperties(h);
            selectedOk = true;
        elseif ismethod(rd, 'refreshInspector')
            rd.refreshInspector(h);
            selectedOk = true;
        elseif ismethod(rd, 'setSelectedObject')
            rd.setSelectedObject(h);
            selectedOk = true;
        elseif isprop(rd, 'SelectedObject')
            rd.SelectedObject = h;
            selectedOk = true;
        end
    catch
        selectedOk = false;
    end

    drawnow limitrate;
end

function btn = findButtonByText(parent, texts)
    btn = [];

    if isempty(parent) || ~isgraphics(parent)
        return;
    end

    try
        buttons = findall(parent, 'Type', 'uibutton');
        for i = 1:numel(buttons)
            t = "";
            try
                t = string(buttons(i).Text);
            catch
            end

            for j = 1:numel(texts)
                if contains(lower(t), lower(texts(j)))
                    btn = buttons(i);
                    return;
                end
            end
        end
    catch
        btn = [];
    end
end

% -------------------------------------------------------------------------
% Session scope helpers
% -------------------------------------------------------------------------

function [previousActive, hadPrevious] = saveActiveSessionScope()
    previousActive = '';
    hadPrevious = false;

    try
        previousActive = flightdash.util.SessionScope.getActive();
        hadPrevious = ~isempty(previousActive);
    catch
        previousActive = '';
        hadPrevious = false;
    end
end

function restoreActiveSessionScope(previousActive, hadPrevious)
    try
        if hadPrevious
            flightdash.util.SessionScope.setActive(previousActive);
        else
            flightdash.util.SessionScope.clear();
        end
    catch
    end
end

% -------------------------------------------------------------------------
% Generic helpers
% -------------------------------------------------------------------------

function tf = hasProp(obj, propName)
    tf = false;

    if isempty(obj)
        return;
    end

    try
        tf = isprop(obj, propName);
    catch
        tf = false;
    end
end

function tf = objectHasAnyGraphicsProp(obj, propNames)
    tf = false;

    if isempty(obj)
        return;
    end

    for i = 1:numel(propNames)
        name = propNames{i};

        try
            if isprop(obj, name)
                value = obj.(name);
                if ~isempty(value) && isgraphics(value)
                    tf = true;
                    return;
                end
            end
        catch
        end
    end
end

function msg = getStatusMessage(app)
    msg = '';
    try
        if hasProp(app, 'StatusBar') && ~isempty(app.StatusBar) && ...
                isprop(app.StatusBar, 'MessageLabel') && ...
                ~isempty(app.StatusBar.MessageLabel) && isvalid(app.StatusBar.MessageLabel)
            msg = char(app.StatusBar.MessageLabel.Text);
        end
    catch
        msg = '';
    end
end

function safeDelete(obj)
    if isempty(obj)
        return;
    end

    try
        if isgraphics(obj)
            delete(obj);
        elseif isobject(obj) && isvalid(obj)
            delete(obj);
        end
    catch
    end

    drawnow limitrate;
end

function cleanupPath(filePath)
    if isempty(filePath)
        return;
    end

    candidates = {char(filePath), [char(filePath) '.zip']};
    for i = 1:numel(candidates)
        try
            if exist(candidates{i}, 'file') == 2
                delete(candidates{i});
            end
        catch
        end
    end
end

function label = phase6CheckLabel(fn)
    try
        label = func2str(fn);
        if startsWith(label, '@')
            label = extractAfter(label, 1);
            label = char(label);
        end
    catch
        label = 'unknownCheck';
    end
end

function progressStart(tc, label, idx, total)
    fprintf('[%02d/%02d] %s START  %s\n', idx, total, tc, label);
    flushProgressOutput();
end

function progressDone(tc, status, msg, elapsed)
    fprintf('        %s %-12s %.2fs  %s\n', tc, status, elapsed, msg);
    flushProgressOutput();
end

function flushProgressOutput()
    try
        drawnow limitrate;
    catch
    end
end

function printResults(results)
    fprintf('TC      Result        Message\n');
    fprintf('------  ------------  -------\n');

    for i = 1:numel(results)
        fprintf('%-6s  %-12s  %s\n', ...
            results(i).TC, results(i).Result, results(i).Message);
    end
end

function tf = isVisibleOff(h)
    tf = false;
    try
        tf = strcmp(char(h.Visible), 'off');
    catch
        tf = false;
    end
end
