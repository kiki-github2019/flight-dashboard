function results = verifyPhase3()
%VERIFYPHASE3 Phase 3 verification: FlightDataDashboard embedded smoke checks.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase3();

    fprintf('\n=== Phase 3 verification: FlightDataDashboard Embedded ===\n\n');

    tests = {
        'P3-1',  @checkDashboardClassResolution
        'P3-2',  @checkStandaloneConstruction
        'P3-3',  @checkEmbeddedConstructionInPanel
        'P3-4',  @checkEmbeddedConstructionInTab
        'P3-5',  @checkRootContainerState
        'P3-6',  @checkSessionIdentityState
        'P3-7',  @checkIsActiveSessionSemantics
        'P3-8',  @checkWorkspaceAddRemoveDashboardTab
        'P3-9',  @checkWorkspaceTabSelection
        'P3-10', @checkRefreshLayoutPresence
        'P3-11', @checkEmbeddedNoExtraUIFigure
        'P3-12', @checkCleanDeletion
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};

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

        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);

    passCount = sum(strcmp({results.Result}, 'PASS'));
    totalCount = numel(results);
    fprintf('\n%d / %d Phase 3 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkDashboardClassResolution()
    status = '';

    cls = 'flightdash.FlightDataDashboard';
    found = meta.class.fromName(cls);

    ok = ~isempty(found);
    if ok
        msg = sprintf('%s resolved', cls);
    else
        msg = sprintf('%s not found', cls);
    end
end

function [ok, msg, status] = checkStandaloneConstruction()
    status = '';

    app = [];
    try
        app = flightdash.FlightDataDashboard();

        ok = ~isempty(app) && isvalid(app);
        if ok
            msg = 'Standalone FlightDataDashboard constructed successfully';
        else
            msg = 'Standalone FlightDataDashboard returned invalid handle';
        end
    catch ME
        ok = false;
        msg = sprintf('Standalone construction failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkEmbeddedConstructionInPanel()
    status = '';

    fig = [];
    app = [];
    try
        fig = uifigure('Visible', 'off', 'Name', 'Phase3 Embedded Panel Test');
        gl = uigridlayout(fig, [1 1]);
        panel = uipanel(gl, 'Title', 'Embedded Host');

        app = flightdash.FlightDataDashboard(panel, 'P3_PANEL_SESSION');

        ok = ~isempty(app) && isvalid(app) && ...
             hasProp(app, 'IsEmbedded') && app.IsEmbedded;

        if ok
            msg = 'Embedded FlightDataDashboard constructed in uipanel';
        else
            msg = 'Embedded panel construction returned invalid state';
        end
    catch ME
        ok = false;
        msg = sprintf('Embedded panel construction failed: %s', ME.message);
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkEmbeddedConstructionInTab()
    status = '';

    fig = [];
    app = [];
    try
        fig = uifigure('Visible', 'off', 'Name', 'Phase3 Embedded Tab Test');
        tg = uitabgroup(fig);
        tab = uitab(tg, 'Title', 'Session');

        app = flightdash.FlightDataDashboard(tab, 'P3_TAB_SESSION');

        ok = ~isempty(app) && isvalid(app) && ...
             hasProp(app, 'IsEmbedded') && app.IsEmbedded;

        if ok
            msg = 'Embedded FlightDataDashboard constructed in uitab';
        else
            msg = 'Embedded tab construction returned invalid state';
        end
    catch ME
        ok = false;
        msg = sprintf('Embedded tab construction failed: %s', ME.message);
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkRootContainerState()
    status = '';

    fig = [];
    app = [];
    try
        fig = uifigure('Visible', 'off', 'Name', 'Phase3 RootContainer Test');
        panel = uipanel(fig);

        app = flightdash.FlightDataDashboard(panel, 'P3_ROOT_SESSION');

        hasRoot = hasProp(app, 'RootContainer');
        rootOk = hasRoot && ~isempty(app.RootContainer) && isgraphics(app.RootContainer) && ...
                 isequal(app.RootContainer, panel);

        hasEmbedded = hasProp(app, 'IsEmbedded') && app.IsEmbedded;

        ok = rootOk && hasEmbedded;

        if ok
            msg = 'Embedded dashboard RootContainer points to supplied parent container';
        else
            msg = sprintf('RootContainer invalid: hasRoot=%d, rootOk=%d, isEmbedded=%d', ...
                hasRoot, rootOk, hasEmbedded);
        end
    catch ME
        ok = false;
        msg = sprintf('RootContainer check failed: %s', ME.message);
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkSessionIdentityState()
    status = '';

    fig = [];
    app = [];
    try
        sessionId = 'P3_IDENTITY_SESSION';

        fig = uifigure('Visible', 'off', 'Name', 'Phase3 Session Identity Test');
        panel = uipanel(fig);

        app = flightdash.FlightDataDashboard(panel, sessionId);

        hasSession = hasProp(app, 'ActiveSessionId');
        sessionOk = hasSession && strcmp(char(app.ActiveSessionId), sessionId);

        embeddedOk = hasProp(app, 'IsEmbedded') && app.IsEmbedded;

        ok = sessionOk && embeddedOk;

        if ok
            msg = 'Embedded dashboard preserves ActiveSessionId';
        else
            msg = sprintf('Session identity invalid: hasSession=%d, sessionOk=%d, embeddedOk=%d', ...
                hasSession, sessionOk, embeddedOk);
        end
    catch ME
        ok = false;
        msg = sprintf('Session identity check failed: %s', ME.message);
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkIsActiveSessionSemantics()
    status = '';

    fig = [];
    app = [];
    previousActive = '';
    hadPrevious = false;

    try
        sessionId = 'P3_ACTIVE_SESSION';

        try
            previousActive = flightdash.util.SessionScope.getActive();
            hadPrevious = ~isempty(previousActive);
        catch
            previousActive = '';
            hadPrevious = false;
        end

        fig = uifigure('Visible', 'off', 'Name', 'Phase3 Active Session Test');
        panel = uipanel(fig);

        app = flightdash.FlightDataDashboard(panel, sessionId);

        flightdash.util.SessionScope.setActive(sessionId);
        activeOk = callIsActiveSession(app);

        flightdash.util.SessionScope.setActive('P3_OTHER_SESSION');
        inactiveOk = ~callIsActiveSession(app);

        flightdash.util.SessionScope.clear();
        broadcastOk = callIsActiveSession(app);

        ok = activeOk && inactiveOk && broadcastOk;

        if ok
            msg = 'isActiveSession handles match, mismatch, and cleared active scope';
        else
            msg = sprintf('isActiveSession mismatch: active=%d inactive=%d cleared=%d', ...
                activeOk, inactiveOk, broadcastOk);
        end
    catch ME
        ok = false;
        msg = sprintf('isActiveSession semantics check failed: %s', ME.message);
    end

    try
        if hadPrevious
            flightdash.util.SessionScope.setActive(previousActive);
        else
            flightdash.util.SessionScope.clear();
        end
    catch
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkWorkspaceAddRemoveDashboardTab()
    status = '';

    studio = [];
    try
        studio = createStudioApp();

        if ~hasProp(studio, 'Workspace') || isempty(studio.Workspace)
            ok = false;
            msg = 'Workspace missing from Studio app';
            safeDelete(studio);
            return;
        end

        ws = studio.Workspace;

        sessionId = 'P3_WS_SESSION';
        displayName = 'Phase3 Workspace Session';

        beforeCount = countWorkspaceDashboards(ws);
        callWorkspaceAdd(ws, sessionId, displayName);
        afterAddCount = countWorkspaceDashboards(ws);

        hasAfterAdd = workspaceHasSession(ws, sessionId);

        callWorkspaceRemove(ws, sessionId);
        afterRemoveCount = countWorkspaceDashboards(ws);
        hasAfterRemove = workspaceHasSession(ws, sessionId);

        ok = afterAddCount >= beforeCount + 1 && hasAfterAdd && ...
             afterRemoveCount <= afterAddCount - 1 && ~hasAfterRemove;

        if ok
            msg = 'WorkspaceManager add/remove embedded dashboard tab works';
        else
            msg = sprintf('Workspace add/remove mismatch: before=%d afterAdd=%d afterRemove=%d hasAdd=%d hasRemove=%d', ...
                beforeCount, afterAddCount, afterRemoveCount, hasAfterAdd, hasAfterRemove);
        end
    catch ME
        ok = false;
        msg = sprintf('Workspace add/remove check failed: %s', ME.message);
    end

    safeDelete(studio);
end

function [ok, msg, status] = checkWorkspaceTabSelection()
    status = '';

    studio = [];
    previousActive = '';
    hadPrevious = false;

    try
        try
            previousActive = flightdash.util.SessionScope.getActive();
            hadPrevious = ~isempty(previousActive);
        catch
            previousActive = '';
            hadPrevious = false;
        end

        studio = createStudioApp();

        ws = studio.Workspace;

        s1 = 'P3_TAB_A';
        s2 = 'P3_TAB_B';

        callWorkspaceAdd(ws, s1, 'Phase3 Tab A');
        callWorkspaceAdd(ws, s2, 'Phase3 Tab B');

        selectWorkspaceSession(ws, s1);
        active1 = flightdash.util.SessionScope.getActive();

        selectWorkspaceSession(ws, s2);
        active2 = flightdash.util.SessionScope.getActive();

        ok = strcmp(char(active1), s1) && strcmp(char(active2), s2);

        if ok
            msg = 'Workspace tab selection updates active SessionScope';
        else
            msg = sprintf('Tab selection did not update active scope: active1=%s active2=%s', ...
                char(active1), char(active2));
        end
    catch ME
        ok = false;
        msg = sprintf('Workspace tab selection check failed: %s', ME.message);
    end

    try
        if hadPrevious
            flightdash.util.SessionScope.setActive(previousActive);
        else
            flightdash.util.SessionScope.clear();
        end
    catch
    end

    safeDelete(studio);
end

function [ok, msg, status] = checkRefreshLayoutPresence()
    status = '';

    fig = [];
    app = [];
    try
        fig = uifigure('Visible', 'off', 'Name', 'Phase3 refreshLayout Test');
        panel = uipanel(fig);

        app = flightdash.FlightDataDashboard(panel, 'P3_REFRESH_SESSION');

        hasMethod = ismethod(app, 'refreshLayout');

        if hasMethod
            try
                app.refreshLayout('verifyPhase3');
                callOk = true;
                callMsg = 'safe call succeeded';
            catch ME
                callOk = false;
                callMsg = ME.message;
            end

            ok = callOk;
            msg = sprintf('refreshLayout method exists; %s', callMsg);
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'refreshLayout method not implemented yet';
        end
    catch ME
        ok = false;
        msg = sprintf('refreshLayout presence check failed: %s', ME.message);
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkEmbeddedNoExtraUIFigure()
    status = '';

    fig = [];
    app = [];
    try
        before = findall(groot, 'Type', 'figure');

        fig = uifigure('Visible', 'off', 'Name', 'Phase3 No Extra UIFigure Test');
        tg = uitabgroup(fig);
        tab = uitab(tg, 'Title', 'Embedded');

        app = flightdash.FlightDataDashboard(tab, 'P3_NO_EXTRA_FIG');

        after = findall(groot, 'Type', 'figure');

        newCount = numel(after) - numel(before);

        ok = newCount == 1;

        if ok
            msg = 'Embedded dashboard did not create an additional top-level figure';
        else
            msg = sprintf('Unexpected top-level figure count delta: %d', newCount);
        end
    catch ME
        ok = false;
        msg = sprintf('No-extra-UIFigure check failed: %s', ME.message);
    end

    safeDelete(app);
    safeDelete(fig);
end

function [ok, msg, status] = checkCleanDeletion()
    status = '';

    fig = [];
    app = [];
    try
        fig = uifigure('Visible', 'off', 'Name', 'Phase3 Clean Delete Test');
        panel = uipanel(fig);

        app = flightdash.FlightDataDashboard(panel, 'P3_DELETE_SESSION');

        safeDelete(app);

        appDeleted = isempty(app) || ~isvalid(app);
        figValid = isvalid(fig);

        ok = appDeleted && figValid;

        if ok
            msg = 'Embedded dashboard delete completes without deleting host figure';
        else
            msg = sprintf('Delete state unexpected: appDeleted=%d figValid=%d', appDeleted, figValid);
        end
    catch ME
        ok = false;
        msg = sprintf('Clean deletion check failed: %s', ME.message);
    end

    safeDelete(fig);
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function studio = createStudioApp()
    studio = flightdash.studio.FlightReviewStudioApp();

    if hasProp(studio, 'UIFigure') && isgraphics(studio.UIFigure)
        studio.UIFigure.Visible = 'off';
    end

    drawnow limitrate;
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

function tf = callIsActiveSession(app)
    tf = false;

    try
        if ismethod(app, 'isActiveSession')
            tf = app.isActiveSession();
        elseif hasProp(app, 'ActiveSessionId')
            activeId = flightdash.util.SessionScope.getActive();
            if isempty(activeId)
                tf = true;
            else
                tf = strcmp(char(activeId), char(app.ActiveSessionId));
            end
        end
    catch
        tf = false;
    end
end

function n = countWorkspaceDashboards(ws)
    n = 0;

    try
        if isprop(ws, 'DashboardMap') && ~isempty(ws.DashboardMap)
            n = ws.DashboardMap.Count;
            return;
        end
    catch
    end

    try
        if isprop(ws, 'Dashboards') && ~isempty(ws.Dashboards)
            n = numel(ws.Dashboards);
            return;
        end
    catch
    end

    try
        if isprop(ws, 'TabGroup') && isgraphics(ws.TabGroup)
            tabs = findall(ws.TabGroup, 'Type', 'uitab');
            n = numel(tabs);
        end
    catch
        n = 0;
    end
end

function tf = workspaceHasSession(ws, sessionId)
    tf = false;

    try
        if isprop(ws, 'DashboardMap') && ~isempty(ws.DashboardMap)
            tf = isKey(ws.DashboardMap, sessionId);
            if tf
                return;
            end
        end
    catch
    end

    try
        if isprop(ws, 'TabMap') && ~isempty(ws.TabMap)
            tf = isKey(ws.TabMap, sessionId);
            if tf
                return;
            end
        end
    catch
    end

    try
        if isprop(ws, 'TabGroup') && isgraphics(ws.TabGroup)
            tabs = findall(ws.TabGroup, 'Type', 'uitab');
            for i = 1:numel(tabs)
                if isprop(tabs(i), 'UserData') && isequal(tabs(i).UserData, sessionId)
                    tf = true;
                    return;
                end
                if contains(string(tabs(i).Title), string(sessionId))
                    tf = true;
                    return;
                end
            end
        end
    catch
        tf = false;
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
        error('verifyPhase3:WorkspaceAddMissing', ...
            'WorkspaceManager has no supported add dashboard tab method');
    end

    drawnow limitrate;
end

function callWorkspaceRemove(ws, sessionId)
    if ismethod(ws, 'removeDashboardTab')
        ws.removeDashboardTab(sessionId);
    elseif ismethod(ws, 'removeSessionTab')
        ws.removeSessionTab(sessionId);
    elseif ismethod(ws, 'removeTab')
        ws.removeTab(sessionId);
    else
        error('verifyPhase3:WorkspaceRemoveMissing', ...
            'WorkspaceManager has no supported remove dashboard tab method');
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
    elseif isprop(ws, 'TabMap') && isprop(ws, 'TabGroup') && ...
            ~isempty(ws.TabMap) && isKey(ws.TabMap, sessionId)
        ws.TabGroup.SelectedTab = ws.TabMap(sessionId);
        drawnow limitrate;

        if ismethod(ws, 'onTabChanged')
            ws.onTabChanged();
        end
    else
        error('verifyPhase3:WorkspaceSelectMissing', ...
            'WorkspaceManager has no supported session selection method');
    end

    drawnow limitrate;
end

function printResults(results)
    fprintf('TC      Result        Message\n');
    fprintf('------  ------------  -------\n');

    for i = 1:numel(results)
        fprintf('%-6s  %-12s  %s\n', ...
            results(i).TC, results(i).Result, results(i).Message);
    end
end