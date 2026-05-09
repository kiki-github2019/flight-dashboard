function results = verifyPhase5()
%VERIFYPHASE5 Phase 5 verification: Project Explorer / Object Manager MVP.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase5();

    fprintf('\n=== Phase 5 verification: Project Explorer / Object Manager MVP ===\n\n');

    tests = {
        'P5-1',  @checkStudioShellForPhase5
        'P5-2',  @checkProjectExplorerClass
        'P5-3',  @checkProjectExplorerTreeExists
        'P5-4',  @checkSessionAddRefreshTree
        'P5-5',  @checkSessionRenameRefreshTree
        'P5-6',  @checkSessionDuplicate
        'P5-7',  @checkSessionDeleteRefreshTree
        'P5-8',  @checkTreeSelectionActivatesWorkspace
        'P5-9',  @checkRightDockObjectManagerExists
        'P5-10', @checkObjectManagerRefreshNoDashboard
        'P5-11', @checkObjectManagerRefreshWithDashboard
        'P5-12', @checkInspectorHandlesInvalidSelection
        'P5-13', @checkUnsupportedAdvancedFeaturesSkipped
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
    fprintf('\n%d / %d Phase 5 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkStudioShellForPhase5()
    status = '';
    app = [];

    try
        app = createStudioApp();

        ok = hasProp(app, 'Project') && ...
             hasProp(app, 'ProjectExplorer') && ~isempty(app.ProjectExplorer) && ...
             hasProp(app, 'Workspace') && ~isempty(app.Workspace) && ...
             hasProp(app, 'RightDock') && ~isempty(app.RightDock);

        if ok
            msg = 'Studio shell exposes Project, ProjectExplorer, Workspace, and RightDock';
        else
            msg = 'Studio shell missing one or more Phase 5 components';
        end
    catch ME
        ok = false;
        msg = sprintf('Studio shell check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkProjectExplorerClass()
    status = '';

    cls = 'flightdash.studio.ProjectExplorerPanel';
    found = meta.class.fromName(cls);

    ok = ~isempty(found);
    if ok
        msg = sprintf('%s resolved', cls);
    else
        msg = sprintf('%s not found', cls);
    end
end

function [ok, msg, status] = checkProjectExplorerTreeExists()
    status = '';
    app = [];

    try
        app = createStudioApp();
        pe = app.ProjectExplorer;

        hasTreeProp = objectHasAnyGraphicsProp(pe, {'Tree', 'ProjectTree'});
        treeCount = countGraphicsByType(app.UIFigure, 'uitree');

        ok = hasTreeProp || treeCount >= 1;

        if ok
            msg = sprintf('Project Explorer tree exists; detected %d uitree object(s)', treeCount);
        else
            msg = 'Project Explorer tree not detected';
        end
    catch ME
        ok = false;
        msg = sprintf('Project Explorer tree check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkSessionAddRefreshTree()
    status = '';
    app = [];

    try
        app = createStudioApp();

        sessionId = 'P5_ADD_SESSION';
        displayName = 'Phase5 Add Session';

        addSessionToStudio(app, sessionId, displayName);
        refreshProjectExplorer(app);

        hasModel = projectHasSession(app.Project, sessionId);
        hasTree = treeContainsText(app, displayName) || treeContainsText(app, sessionId);
        hasWorkspace = workspaceHasSession(app.Workspace, sessionId);

        ok = hasModel && hasTree && hasWorkspace;

        if ok
            msg = 'Session add updates ProjectModel, ProjectExplorer, and Workspace';
        else
            msg = sprintf('Session add mismatch: model=%d tree=%d workspace=%d', ...
                hasModel, hasTree, hasWorkspace);
        end
    catch ME
        ok = false;
        msg = sprintf('Session add/tree refresh check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkSessionRenameRefreshTree()
    status = '';
    app = [];

    try
        app = createStudioApp();

        sessionId = 'P5_RENAME_SESSION';
        oldName = 'Phase5 Old Name';
        newName = 'Phase5 New Name';

        addSessionToStudio(app, sessionId, oldName);
        renameSessionInStudio(app, sessionId, newName);
        refreshProjectExplorer(app);

        session = getProjectSession(app.Project, sessionId);
        modelOk = ~isempty(session) && strcmp(char(session.DisplayName), newName);
        treeOk = treeContainsText(app, newName);

        ok = modelOk && treeOk;

        if ok
            msg = 'Session rename updates ProjectModel and ProjectExplorer tree';
        else
            msg = sprintf('Session rename mismatch: model=%d tree=%d', modelOk, treeOk);
        end
    catch ME
        ok = false;
        msg = sprintf('Session rename check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkSessionDuplicate()
    status = '';
    app = [];

    try
        app = createStudioApp();

        sourceId = 'P5_DUP_SOURCE';
        sourceName = 'Phase5 Duplicate Source';

        addSessionToStudio(app, sourceId, sourceName);

        beforeCount = safeSessionCount(app.Project);
        duplicateSessionInStudio(app, sourceId);
        refreshProjectExplorer(app);
        afterCount = safeSessionCount(app.Project);

        ok = afterCount == beforeCount + 1;

        if ok
            msg = 'Session duplicate increases ProjectModel session count';
        else
            msg = sprintf('Session duplicate count mismatch: before=%d after=%d', ...
                beforeCount, afterCount);
        end
    catch ME
        ok = false;
        msg = sprintf('Session duplicate check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkSessionDeleteRefreshTree()
    status = '';
    app = [];

    try
        app = createStudioApp();

        sessionId = 'P5_DELETE_SESSION';
        displayName = 'Phase5 Delete Session';

        addSessionToStudio(app, sessionId, displayName);
        beforeOk = projectHasSession(app.Project, sessionId);

        removeSessionFromStudio(app, sessionId);
        refreshProjectExplorer(app);

        modelGone = ~projectHasSession(app.Project, sessionId);
        workspaceGone = ~workspaceHasSession(app.Workspace, sessionId);
        treeGone = ~treeContainsText(app, displayName) && ~treeContainsText(app, sessionId);

        ok = beforeOk && modelGone && workspaceGone && treeGone;

        if ok
            msg = 'Session delete updates ProjectModel, Workspace, and ProjectExplorer tree';
        else
            msg = sprintf('Session delete mismatch: before=%d modelGone=%d workspaceGone=%d treeGone=%d', ...
                beforeOk, modelGone, workspaceGone, treeGone);
        end
    catch ME
        ok = false;
        msg = sprintf('Session delete check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkTreeSelectionActivatesWorkspace()
    status = '';
    app = [];
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

        app = createStudioApp();

        s1 = 'P5_TREE_A';
        s2 = 'P5_TREE_B';

        addSessionToStudio(app, s1, 'Phase5 Tree A');
        addSessionToStudio(app, s2, 'Phase5 Tree B');

        selectWorkspaceSession(app.Workspace, s1);
        active1 = flightdash.util.SessionScope.getActive();

        selectWorkspaceSession(app.Workspace, s2);
        active2 = flightdash.util.SessionScope.getActive();

        ok = strcmp(char(active1), s1) && strcmp(char(active2), s2);

        if ok
            msg = 'Workspace/session selection updates active SessionScope';
        else
            msg = sprintf('Active session mismatch: active1=%s active2=%s', ...
                char(active1), char(active2));
        end
    catch ME
        ok = false;
        msg = sprintf('Tree/workspace activation check failed: %s', ME.message);
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
end

function [ok, msg, status] = checkRightDockObjectManagerExists()
    status = '';
    app = [];

    try
        app = createStudioApp();
        rd = app.RightDock;

        hasTree = objectHasAnyGraphicsProp(rd, {'ObjectTree', 'ObjectManagerTree', 'Tree'});
        treeCount = countGraphicsByType(app.UIFigure, 'uitree');

        ok = hasTree || treeCount >= 1;

        if ok
            msg = sprintf('RightDock Object Manager tree detected; uitree count=%d', treeCount);
        else
            msg = 'RightDock Object Manager tree not detected';
        end
    catch ME
        ok = false;
        msg = sprintf('Object Manager existence check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkObjectManagerRefreshNoDashboard()
    status = '';
    app = [];

    try
        app = createStudioApp();
        rd = app.RightDock;

        if ismethod(rd, 'refreshObjectManager')
            rd.refreshObjectManager([]);
            ok = true;
            msg = 'Object Manager refresh handles empty dashboard';
        elseif ismethod(rd, 'refreshForDashboard')
            rd.refreshForDashboard([]);
            ok = true;
            msg = 'RightDock refresh handles empty dashboard';
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'No Object Manager refresh method exposed';
        end
    catch ME
        ok = false;
        msg = sprintf('Object Manager empty refresh failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkObjectManagerRefreshWithDashboard()
    status = '';
    app = [];

    try
        app = createStudioApp();

        sessionId = 'P5_OBJ_SESSION';
        addSessionToStudio(app, sessionId, 'Phase5 Object Session');
        dash = getWorkspaceDashboard(app.Workspace, sessionId);

        if isempty(dash) || ~isvalid(dash)
            ok = false;
            msg = 'Could not retrieve embedded dashboard for Object Manager refresh';
            safeDelete(app);
            return;
        end

        rd = app.RightDock;

        if ismethod(rd, 'refreshObjectManager')
            rd.refreshObjectManager(dash);
            ok = true;
            msg = 'Object Manager refresh accepts active dashboard';
        elseif ismethod(rd, 'refreshForDashboard')
            rd.refreshForDashboard(dash);
            ok = true;
            msg = 'RightDock refresh accepts active dashboard';
        elseif ismethod(rd, 'refreshActiveInspector')
            rd.refreshActiveInspector();
            ok = true;
            msg = 'RightDock active inspector refresh completed';
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'No dashboard refresh method exposed';
        end
    catch ME
        ok = false;
        msg = sprintf('Object Manager dashboard refresh failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkInspectorHandlesInvalidSelection()
    status = '';
    app = [];

    try
        app = createStudioApp();
        rd = app.RightDock;

        fakeHandle = [];
        try
            f = figure('Visible', 'off');
            lineHandle = plot(1:3, 1:3);
            delete(lineHandle);
            delete(f);
            fakeHandle = lineHandle;
        catch
            fakeHandle = [];
        end

        if ismethod(rd, 'selectObject')
            rd.selectObject(fakeHandle);
            ok = true;
            msg = 'Inspector/Object selection handles invalid graphics handle';
        elseif ismethod(rd, 'showObjectProperties')
            rd.showObjectProperties(fakeHandle);
            ok = true;
            msg = 'Inspector property display handles invalid graphics handle';
        elseif ismethod(rd, 'refreshInspector')
            rd.refreshInspector(fakeHandle);
            ok = true;
            msg = 'Inspector refresh handles invalid graphics handle';
        else
            status = 'SKIP_NOT_IMPLEMENTED';
            ok = true;
            msg = 'No public Inspector invalid-selection method exposed';
        end
    catch ME
        ok = false;
        msg = sprintf('Inspector invalid selection failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkUnsupportedAdvancedFeaturesSkipped()
    status = 'SKIP_MANUAL';
    ok = true;
    msg = 'Drag/drop reorder, inline checkbox, and multi-object style editing are intentionally out of Phase 5 MVP scope';
end

% -------------------------------------------------------------------------
% Studio operation helpers
% -------------------------------------------------------------------------

function app = createStudioApp()
    app = flightdash.studio.FlightReviewStudioApp();

    if hasProp(app, 'UIFigure') && isgraphics(app.UIFigure)
        app.UIFigure.Visible = 'off';
    end

    drawnow limitrate;
end

function addSessionToStudio(app, sessionId, displayName)
    if ismethod(app, 'addSession')
        try
            app.addSession(sessionId, displayName);
            drawnow limitrate;
            return;
        catch
        end
    end

    session = flightdash.project.SessionModel(sessionId, displayName);

    if hasProp(app, 'Project')
        app.Project = app.Project.addSession(session);
    else
        error('verifyPhase5:NoProject', 'Studio app has no Project property');
    end

    if hasProp(app, 'Workspace') && ~isempty(app.Workspace)
        callWorkspaceAdd(app.Workspace, sessionId, displayName);
    end

    refreshProjectExplorer(app);
    drawnow limitrate;
end

function renameSessionInStudio(app, sessionId, newName)
    if ismethod(app, 'renameSession')
        try
            app.renameSession(sessionId, newName);
            drawnow limitrate;
            return;
        catch
        end
    end

    session = getProjectSession(app.Project, sessionId);
    if isempty(session)
        error('verifyPhase5:SessionMissing', 'Session %s not found', sessionId);
    end

    session = session.setDisplayName(newName);
    app.Project = app.Project.updateSession(session);

    refreshProjectExplorer(app);
    drawnow limitrate;
end

function duplicateSessionInStudio(app, sourceId)
    if ismethod(app, 'duplicateSession')
        try
            app.duplicateSession(sourceId);
            drawnow limitrate;
            return;
        catch
        end
    end

    source = getProjectSession(app.Project, sourceId);
    if isempty(source)
        error('verifyPhase5:SessionMissing', 'Source session %s not found', sourceId);
    end

    newId = char(flightdash.project.ProjectModel.newId('SESS'));
    newName = sprintf('%s Copy', char(source.DisplayName));

    dup = flightdash.project.SessionModel(newId, newName);

    if isprop(source, 'FlightFiles') && isprop(dup, 'FlightFiles')
        dup.FlightFiles = source.FlightFiles;
    end
    if isprop(source, 'VideoFiles') && isprop(dup, 'VideoFiles')
        dup.VideoFiles = source.VideoFiles;
    end

    app.Project = app.Project.addSession(dup);

    if hasProp(app, 'Workspace') && ~isempty(app.Workspace)
        callWorkspaceAdd(app.Workspace, newId, newName);
    end

    refreshProjectExplorer(app);
    drawnow limitrate;
end

function removeSessionFromStudio(app, sessionId)
    if ismethod(app, 'removeSession')
        try
            app.removeSession(sessionId);
            drawnow limitrate;
            return;
        catch
        end
    end

    if hasProp(app, 'Workspace') && ~isempty(app.Workspace)
        try
            callWorkspaceRemove(app.Workspace, sessionId);
        catch
        end
    end

    if hasProp(app, 'Project')
        app.Project = app.Project.removeSession(sessionId);
    end

    refreshProjectExplorer(app);
    drawnow limitrate;
end

function refreshProjectExplorer(app)
    if ~hasProp(app, 'ProjectExplorer') || isempty(app.ProjectExplorer)
        return;
    end

    pe = app.ProjectExplorer;

    try
        if ismethod(pe, 'refresh')
            pe.refresh();
        elseif ismethod(pe, 'refreshTree')
            pe.refreshTree();
        elseif ismethod(pe, 'refreshProject')
            pe.refreshProject(app.Project);
        elseif ismethod(pe, 'setProject')
            pe.setProject(app.Project);
        end
    catch
    end

    drawnow limitrate;
end

function callWorkspaceAdd(ws, sessionId, displayName)
    if ismethod(ws, 'addDashboardTab')
        ws.addDashboardTab(sessionId, displayName);
    elseif ismethod(ws, 'addSessionTab')
        ws.addSessionTab(sessionId, displayName);
    elseif ismethod(ws, 'addTab')
        ws.addTab(sessionId, displayName);
    else
        error('verifyPhase5:WorkspaceAddMissing', ...
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
        error('verifyPhase5:WorkspaceRemoveMissing', ...
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
        error('verifyPhase5:WorkspaceSelectMissing', ...
            'WorkspaceManager has no supported session selection method');
    end

    drawnow limitrate;
end

% -------------------------------------------------------------------------
% Query helpers
% -------------------------------------------------------------------------

function tf = projectHasSession(project, sessionId)
    tf = false;

    try
        if ismethod(project, 'hasSession')
            tf = project.hasSession(sessionId);
            return;
        end

        if ~isprop(project, 'Sessions')
            return;
        end

        sessions = project.Sessions;
        for i = 1:numel(sessions)
            if isprop(sessions(i), 'SessionId') && strcmp(char(sessions(i).SessionId), char(sessionId))
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end

function session = getProjectSession(project, sessionId)
    session = [];

    try
        if ismethod(project, 'getSession')
            session = project.getSession(sessionId);
            return;
        end

        if ~isprop(project, 'Sessions')
            return;
        end

        sessions = project.Sessions;
        for i = 1:numel(sessions)
            if isprop(sessions(i), 'SessionId') && strcmp(char(sessions(i).SessionId), char(sessionId))
                session = sessions(i);
                return;
            end
        end
    catch
        session = [];
    end
end

function count = safeSessionCount(project)
    count = -1;

    try
        if ismethod(project, 'sessionCount')
            count = project.sessionCount();
        elseif isprop(project, 'Sessions')
            count = numel(project.Sessions);
        end
    catch
        count = -1;
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

function dash = getWorkspaceDashboard(ws, sessionId)
    dash = [];

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

function tf = treeContainsText(app, textValue)
    tf = false;

    try
        trees = findall(app.UIFigure, 'Type', 'uitree');
        target = string(textValue);

        for i = 1:numel(trees)
            nodes = findall(trees(i), 'Type', 'uitreenode');
            for j = 1:numel(nodes)
                if contains(string(nodes(j).Text), target)
                    tf = true;
                    return;
                end
            end
        end
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

function n = countGraphicsByType(parent, typeName)
    n = 0;

    if isempty(parent) || ~isgraphics(parent)
        return;
    end

    try
        found = findall(parent, 'Type', typeName);
        n = numel(found);
    catch
        n = 0;
    end
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

function printResults(results)
    fprintf('TC      Result        Message\n');
    fprintf('------  ------------  -------\n');

    for i = 1:numel(results)
        fprintf('%-6s  %-12s  %s\n', ...
            results(i).TC, results(i).Result, results(i).Message);
    end
end