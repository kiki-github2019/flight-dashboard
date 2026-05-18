function results = verifyStudioWorkspaceUx()
%VERIFYSTUDIOWORKSPACEUX Regression checks for session-open workspace UX.

    fprintf('\n=== Studio Workspace UX verification ===\n\n');

    tests = {
        'UX-1', @checkSessionCommandGating
        'UX-2', @checkWelcomeAndExplorerFocus
        'UX-3', @checkInitialDashboardPanelState
        'UX-4', @checkExplorerNodeTooltips
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});
    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};
        try
            [status, msg] = fn();
        catch ME
            status = 'FAIL';
            msg = sprintf('%s: %s', ME.identifier, ME.message);
        end
        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
        fprintf('%s  %-5s  %s\n', tc, status, msg);
    end
end

function [status, msg] = checkSessionCommandGating()
    [app, cleanupObj, skipMsg] = createStudioApp(); %#ok<ASGLU>
    if ~isempty(skipMsg), status = 'SKIP'; msg = skipMsg; return; end

    app.applySessionStateUI();
    drawnow limitrate;

    disabledIds = {'Data:LoadFlight1', 'Video:Snapshot', 'Sync:Flight', ...
        'Review:AddRoi', 'Analysis:RoiStats', 'Plot:AddSelected'};
    enabledIds = {'File:NewProject', 'File:OpenProject', ...
        'Project:AddSession', 'Pref:Theme:Toggle'};

    bad = {};
    for k = 1:numel(disabledIds)
        b = findRibbonButton(app.RibbonBar, disabledIds{k});
        if isempty(b) || b.Enabled
            bad{end+1} = disabledIds{k}; %#ok<AGROW>
        end
    end
    for k = 1:numel(enabledIds)
        b = findRibbonButton(app.RibbonBar, enabledIds{k});
        if isempty(b) || ~b.Enabled
            bad{end+1} = enabledIds{k}; %#ok<AGROW>
        end
    end

    homeNew = findRibbonButton(app.RibbonBar, 'File:NewProject');
    dropdownOk = false;
    try
        dropdownOk = homeNew.DropdownEnabled.isKey('Plot:NewComparison') && ...
            ~homeNew.DropdownEnabled('Plot:NewComparison');
    catch
    end

    if isempty(bad) && dropdownOk
        status = 'PASS';
        msg = 'Session-gated ribbon buttons and dropdown items are disabled before a session opens.';
    else
        status = 'FAIL';
        msg = sprintf('Unexpected command availability: %s', strjoin(bad, ', '));
    end
end

function [status, msg] = checkWelcomeAndExplorerFocus()
    [app, cleanupObj, skipMsg] = createStudioApp(); %#ok<ASGLU>
    if ~isempty(skipMsg), status = 'SKIP'; msg = skipMsg; return; end

    hasWelcomeBefore = hasWelcomeTab(app);
    sessionId = app.addSession('UX Session A');
    drawnow limitrate;

    if isempty(sessionId)
        status = 'FAIL';
        msg = 'addSession returned an empty session id.';
        return;
    end

    welcomeGone = ~hasWelcomeTab(app);
    activeOk = strcmp(char(app.Workspace.activeSessionId()), char(sessionId));

    sessionId2 = app.addSession('UX Session B');
    drawnow limitrate;
    selectOk = false;
    if ~isempty(sessionId2)
        selectOk = app.ProjectExplorer.selectSession(sessionId);
        drawnow limitrate;
    end
    explorerOk = selectOk && strcmp(char(app.Workspace.activeSessionId()), char(sessionId));

    if hasWelcomeBefore && welcomeGone && activeOk && explorerOk
        status = 'PASS';
        msg = 'Welcome tab hides after session open and Explorer session selection focuses the tab.';
    else
        status = 'FAIL';
        msg = sprintf('welcomeBefore=%d welcomeGone=%d activeOk=%d explorerOk=%d', ...
            hasWelcomeBefore, welcomeGone, activeOk, explorerOk);
    end
end

function [status, msg] = checkInitialDashboardPanelState()
    [app, cleanupObj, skipMsg] = createStudioApp(); %#ok<ASGLU>
    if ~isempty(skipMsg), status = 'SKIP'; msg = skipMsg; return; end

    sessionId = app.addSession('UX Initial Panels');
    drawnow limitrate;
    if isempty(sessionId)
        status = 'FAIL';
        msg = 'addSession returned an empty session id.';
        return;
    end

    dash = app.getActiveDashboard();
    if isempty(dash) || ~isvalid(dash)
        status = 'FAIL';
        msg = 'No active embedded dashboard after session open.';
        return;
    end

    ui = dash.UI(1);
    flagsOk = isfield(ui, 'PanelVisible') && ...
        isfield(ui.PanelVisible, 'attitude') && ~ui.PanelVisible.attitude && ...
        isfield(ui.PanelVisible, 'map') && ~ui.PanelVisible.map && ...
        isfield(ui.PanelVisible, 'video') && ~ui.PanelVisible.video;

    hiddenOk = panelHidden(ui, 'panelAttitude') && ...
        panelHidden(ui, 'panelMapAlt') && panelHidden(ui, 'panelVideo');
    infoOk = panelVisible(ui, 'infoContent') && panelVisible(ui, 'plotPanel');

    if flagsOk && hiddenOk && infoOk
        status = 'PASS';
        msg = 'Initial dashboard shows current flight data and plot area; attitude/map/video are hidden.';
    else
        status = 'FAIL';
        msg = sprintf('flagsOk=%d hiddenOk=%d infoOk=%d', flagsOk, hiddenOk, infoOk);
    end
end

function [status, msg] = checkExplorerNodeTooltips()
    [app, cleanupObj, skipMsg] = createStudioApp(); %#ok<ASGLU>
    if ~isempty(skipMsg), status = 'SKIP'; msg = skipMsg; return; end

    nodeNames = {'Sessions', 'FlightData', 'Videos', 'Graphs', 'Roi', ...
        'Sync', 'Snapshots', 'Reports', 'Notes', 'Themes'};
    missing = {};
    for k = 1:numel(nodeNames)
        name = nodeNames{k};
        try
            node = app.ProjectExplorer.Roots.(name);
            if isempty(node) || ~isvalid(node) || ~isprop(node, 'Tooltip') || isempty(node.Tooltip)
                missing{end+1} = name; %#ok<AGROW>
            end
        catch
            missing{end+1} = name; %#ok<AGROW>
        end
    end

    if isempty(missing)
        status = 'PASS';
        msg = 'Project Explorer root nodes expose hover tooltips where MATLAB supports them.';
    else
        status = 'WARN';
        msg = sprintf('Tooltip unavailable or unsupported for: %s', strjoin(missing, ', '));
    end
end

function [app, cleanupObj, skipMsg] = createStudioApp()
    app = [];
    skipMsg = '';
    cleanupObj = [];
    try
        app = flightdash.studio.FlightReviewStudioApp();
        cleanupObj = onCleanup(@() safeDelete(app));
        drawnow limitrate;
    catch ME
        skipMsg = sprintf('Studio GUI unavailable: %s', ME.message);
        cleanupObj = onCleanup(@() safeDelete(app));
    end
end

function safeDelete(app)
    try
        if ~isempty(app) && isvalid(app)
            delete(app);
        end
    catch
    end
    try, close all force; catch, end
end

function tf = hasWelcomeTab(app)
    tf = false;
    try
        tf = ~isempty(app.Workspace.WelcomeTab) && isvalid(app.Workspace.WelcomeTab);
    catch
    end
end

function b = findRibbonButton(ribbon, cmdId)
    b = [];
    try
        for ti = 1:numel(ribbon.Tabs)
            tab = ribbon.Tabs{ti};
            for gi = 1:numel(tab.Groups)
                group = tab.Groups{gi};
                for bi = 1:numel(group.Buttons)
                    candidate = group.Buttons{bi};
                    if strcmp(candidate.CmdId, cmdId)
                        b = candidate;
                        return;
                    end
                    for di = 1:numel(candidate.DropdownItems)
                        item = candidate.DropdownItems{di};
                        if iscell(item) && numel(item) >= 2 && strcmp(char(item{2}), cmdId)
                            b = candidate;
                            return;
                        end
                    end
                end
            end
        end
    catch
        b = [];
    end
end

function tf = panelHidden(ui, fieldName)
    tf = false;
    try
        tf = isfield(ui, fieldName) && ~isempty(ui.(fieldName)) && ...
            isvalid(ui.(fieldName)) && strcmpi(char(ui.(fieldName).Visible), 'off');
    catch
        tf = false;
    end
end

function tf = panelVisible(ui, fieldName)
    tf = false;
    try
        tf = isfield(ui, fieldName) && ~isempty(ui.(fieldName)) && ...
            isvalid(ui.(fieldName)) && strcmpi(char(ui.(fieldName).Visible), 'on');
    catch
        tf = false;
    end
end
