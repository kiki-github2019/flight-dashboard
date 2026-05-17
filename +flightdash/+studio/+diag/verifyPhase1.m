function results = verifyPhase1()
%VERIFYPHASE1 Phase 1 verification: FlightReviewStudio shell smoke checks.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase1();

    fprintf('\n=== Phase 1 verification: Studio Shell ===\n\n');

    tests = {
        'P1-1',  @checkStudioAppClassResolution
        'P1-2',  @checkStudioAppConstructDelete
        'P1-3',  @checkShellTopLevelHandles
        'P1-4',  @checkManagersExist
        'P1-5',  @checkMenuManager
        'P1-6',  @checkToolbarManager
        'P1-7',  @checkProjectExplorer
        'P1-8',  @checkWorkspaceManager
        'P1-9',  @checkRightDockManager
        'P1-10', @checkStatusBarManager
        'P1-11', @checkMouseRouterPresence
        'P1-12', @checkCleanDeletion
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};

        try
            [ok, msg, status] = fn();

            if nargin(fn) < 0 %#ok<NASGU>
                % no-op for older analyzer compatibility
            end

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
    fprintf('\n%d / %d Phase 1 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkStudioAppClassResolution()
    status = '';

    cls = 'flightdash.studio.FlightReviewStudioApp';
    found = meta.class.fromName(cls);

    ok = ~isempty(found);
    if ok
        msg = sprintf('%s resolved', cls);
    else
        msg = sprintf('%s not found', cls);
    end
end

function [ok, msg, status] = checkStudioAppConstructDelete()
    status = '';

    app = [];
    try
        app = createStudioApp();
        ok = ~isempty(app) && isvalid(app);
        if ok
            msg = 'FlightReviewStudioApp constructed successfully';
        else
            msg = 'FlightReviewStudioApp construction returned invalid handle';
        end
    catch ME
        ok = false;
        msg = sprintf('Construction failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkShellTopLevelHandles()
    status = '';

    app = [];
    try
        app = createStudioApp();

        missing = {};

        hasFigure = hasGraphicsProp(app, 'UIFigure');
        if ~hasFigure
            missing{end+1} = 'UIFigure'; %#ok<AGROW>
        end

        hasMain = hasGraphicsProp(app, 'MainGrid') || hasGraphicsProp(app, 'BodyGrid') || ...
            countGraphicsByType(app.UIFigure, 'uigridlayout') >= 1;
        if ~hasMain
            missing{end+1} = 'main/body grid'; %#ok<AGROW>
        end

        hasHeader = hasGraphicsProp(app, 'HeaderGrid') || hasGraphicsProp(app, 'HeaderPanel') || ...
            figureHasShellRegion(app.UIFigure, 'header');
        if ~hasHeader
            missing{end+1} = 'header region'; %#ok<AGROW>
        end

        hasBody = hasGraphicsProp(app, 'BodyGrid') || figureHasShellRegion(app.UIFigure, 'body');
        if ~hasBody
            missing{end+1} = 'body region'; %#ok<AGROW>
        end

        hasStatus = hasGraphicsProp(app, 'StatusBarGrid') || hasGraphicsProp(app, 'StatusBarPanel') || ...
            figureHasShellRegion(app.UIFigure, 'status');
        if ~hasStatus
            missing{end+1} = 'status region'; %#ok<AGROW>
        end

        ok = isempty(missing);
        if ok
            msg = 'Top-level shell graphics handles exist';
        else
            msg = sprintf('Missing shell regions: [%s]', strjoin(missing, ', '));
        end
    catch ME
        ok = false;
        msg = sprintf('Top-level handle check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkManagersExist()
    status = '';

    app = [];
    try
        app = createStudioApp();

        required = {
            'MenuMgr'
            'ToolbarMgr'
            'ProjectExplorer'
            'Workspace'
            'RightDock'
            'StatusBar'
        };

        missing = {};
        emptyVals = {};

        for i = 1:numel(required)
            name = required{i};

            if ~hasProp(app, name)
                missing{end+1} = name; %#ok<AGROW>
                continue;
            end

            value = app.(name);
            if isempty(value)
                emptyVals{end+1} = name; %#ok<AGROW>
            end
        end

        ok = isempty(missing) && isempty(emptyVals);
        if ok
            msg = 'Studio managers exist';
        else
            msg = sprintf('Missing: [%s], empty: [%s]', ...
                strjoin(missing, ', '), strjoin(emptyVals, ', '));
        end
    catch ME
        ok = false;
        msg = sprintf('Manager existence check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkMenuManager()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if ~hasProp(app, 'MenuMgr') || isempty(app.MenuMgr)
            ok = false;
            msg = 'MenuMgr missing';
            safeDelete(app);
            return;
        end

        menuMgr = app.MenuMgr;

        existing = menuRootNames(app.UIFigure);
        if isempty(existing) && hasProp(menuMgr, 'Roots') && isstruct(menuMgr.Roots)
            names = fieldnames(menuMgr.Roots);
            for i = 1:numel(names)
                try
                    if isgraphics(menuMgr.Roots.(names{i}))
                        existing{end+1} = names{i}; %#ok<AGROW>
                    end
                catch
                end
            end
        end

        ok = numel(existing) >= 4;
        if ok
            msg = sprintf('MenuManager created root menus: %s', strjoin(existing, ', '));
        else
            msg = sprintf('Too few root menus detected: %s', strjoin(existing, ', '));
        end
    catch ME
        ok = false;
        msg = sprintf('MenuManager check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkToolbarManager()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if ~hasProp(app, 'ToolbarMgr') || isempty(app.ToolbarMgr)
            ok = false;
            msg = 'ToolbarMgr missing';
            safeDelete(app);
            return;
        end

        tb = app.ToolbarMgr;

        hasContainer = false;
        containerNames = {'ToolbarGrid', 'RootGrid', 'Container', 'Panel'};
        for i = 1:numel(containerNames)
            if hasProp(tb, containerNames{i}) && isgraphics(tb.(containerNames{i}))
                hasContainer = true;
                break;
            end
        end

        buttonCount = countGraphicsByType(app.UIFigure, 'uibutton');

        ok = hasContainer || buttonCount > 0;
        if ok
            msg = sprintf('ToolbarManager initialized; detected %d uibutton objects', buttonCount);
        else
            msg = 'ToolbarManager exists but no toolbar container/buttons detected';
        end
    catch ME
        ok = false;
        msg = sprintf('ToolbarManager check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkProjectExplorer()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if ~hasProp(app, 'ProjectExplorer') || isempty(app.ProjectExplorer)
            ok = false;
            msg = 'ProjectExplorer missing';
            safeDelete(app);
            return;
        end

        pe = app.ProjectExplorer;

        hasTree = objectHasAnyGraphicsProp(pe, {'Tree', 'ProjectTree'});
        treeCount = countGraphicsByType(app.UIFigure, 'uitree');

        ok = hasTree || treeCount > 0;
        if ok
            msg = sprintf('ProjectExplorer initialized; detected %d uitree objects', treeCount);
        else
            msg = 'ProjectExplorer exists but no tree detected';
        end
    catch ME
        ok = false;
        msg = sprintf('ProjectExplorer check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkWorkspaceManager()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if ~hasProp(app, 'Workspace') || isempty(app.Workspace)
            ok = false;
            msg = 'Workspace missing';
            safeDelete(app);
            return;
        end

        ws = app.Workspace;

        hasTabGroup = objectHasAnyGraphicsProp(ws, {'TabGroup', 'WorkspaceTabs'});
        tabGroupCount = countGraphicsByType(app.UIFigure, 'uitabgroup');

        ok = hasTabGroup || tabGroupCount > 0;
        if ok
            msg = sprintf('Workspace initialized; detected %d uitabgroup objects', tabGroupCount);
        else
            msg = 'Workspace exists but no tab group detected';
        end
    catch ME
        ok = false;
        msg = sprintf('Workspace check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkRightDockManager()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if ~hasProp(app, 'RightDock') || isempty(app.RightDock)
            ok = false;
            msg = 'RightDock missing';
            safeDelete(app);
            return;
        end

        rd = app.RightDock;

        hasDock = objectHasAnyGraphicsProp(rd, {'RootGrid', 'Panel', 'TabGroup', 'InspectorPanel'});
        tabGroupCount = countGraphicsByType(app.UIFigure, 'uitabgroup');
        treeCount = countGraphicsByType(app.UIFigure, 'uitree');

        ok = hasDock || tabGroupCount >= 1 || treeCount >= 1;
        if ok
            msg = sprintf('RightDock initialized; tabgroups=%d, trees=%d', tabGroupCount, treeCount);
        else
            msg = 'RightDock exists but no dock graphics detected';
        end
    catch ME
        ok = false;
        msg = sprintf('RightDock check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkStatusBarManager()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if ~hasProp(app, 'StatusBar') || isempty(app.StatusBar)
            ok = false;
            msg = 'StatusBar missing';
            safeDelete(app);
            return;
        end

        sb = app.StatusBar;

        hasStatusGraphics = objectHasAnyGraphicsProp(sb, ...
            {'RootGrid', 'StatusGrid', 'MessageLabel', 'ProjectLabel', 'SessionLabel'});

        labelCount = countGraphicsByType(app.UIFigure, 'uilabel');

        ok = hasStatusGraphics || labelCount > 0;
        if ok
            msg = sprintf('StatusBar initialized; detected %d uilabel objects', labelCount);
        else
            msg = 'StatusBar exists but no labels detected';
        end
    catch ME
        ok = false;
        msg = sprintf('StatusBar check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkMouseRouterPresence()
    status = '';

    app = [];
    try
        app = createStudioApp();

        if hasProp(app, 'MouseRouter') && ~isempty(app.MouseRouter)
            ok = true;
            msg = 'Studio MouseRouter exists';
        elseif hasProp(app, 'UIFigure') && isgraphics(app.UIFigure) && ...
                isappdata(app.UIFigure, 'StudioMouseRouter')
            router = getappdata(app.UIFigure, 'StudioMouseRouter');
            ok = ~isempty(router);
            if ok
                msg = 'Studio MouseRouter found in UIFigure appdata';
            else
                msg = 'StudioMouseRouter appdata exists but is empty';
            end
        else
            ok = false;
            msg = 'Studio MouseRouter not found';
        end
    catch ME
        ok = false;
        msg = sprintf('MouseRouter presence check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkCleanDeletion()
    status = '';

    app = [];
    fig = [];
    try
        app = createStudioApp();

        if hasProp(app, 'UIFigure')
            fig = app.UIFigure;
        end

        safeDelete(app);

        if isempty(fig)
            ok = true;
            msg = 'Studio delete completed; no figure handle captured';
            return;
        end

        ok = ~isvalid(fig);
        if ok
            msg = 'Studio delete closes UIFigure cleanly';
        else
            msg = 'Studio delete completed but UIFigure is still valid';
            delete(fig);
        end
    catch ME
        safeDelete(app);
        if ~isempty(fig) && isvalid(fig)
            delete(fig);
        end

        ok = false;
        msg = sprintf('Clean deletion check failed: %s', ME.message);
    end
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function app = createStudioApp()
    app = flightdash.studio.FlightReviewStudioApp();

    if hasProp(app, 'UIFigure') && isgraphics(app.UIFigure)
        app.UIFigure.Visible = 'off';
        drawnow limitrate;
    else
        drawnow limitrate;
    end
end

function safeDelete(obj)
    if isempty(obj)
        return;
    end

    try
        if isvalid(obj)
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

function tf = hasGraphicsProp(obj, propName)
    tf = false;

    if ~hasProp(obj, propName)
        return;
    end

    try
        value = obj.(propName);
        tf = ~isempty(value) && isgraphics(value);
    catch
        tf = false;
    end
end

function tf = figureHasShellRegion(fig, regionName)
    tf = false;

    if isempty(fig) || ~isgraphics(fig)
        return;
    end

    gridCount = countGraphicsByType(fig, 'uigridlayout');
    panelCount = countGraphicsByType(fig, 'uipanel');
    labelCount = countGraphicsByType(fig, 'uilabel');

    switch lower(char(regionName))
        case 'header'
            tf = panelCount >= 1 || gridCount >= 2;
        case 'body'
            tf = gridCount >= 1;
        case 'status'
            tf = panelCount >= 2 || labelCount >= 1;
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

function names = menuRootNames(fig)
    names = {};

    if isempty(fig) || ~isgraphics(fig)
        return;
    end

    try
        menus = findall(fig, 'Type', 'uimenu');
    catch
        menus = [];
    end

    for i = 1:numel(menus)
        try
            parent = menus(i).Parent;
            if ~(~isempty(parent) && isequal(parent, fig))
                continue;
            end

            label = menuDisplayText(menus(i));
            if isempty(label)
                continue;
            end
            if ~any(strcmp(names, label))
                names{end+1} = label; %#ok<AGROW>
            end
        catch
        end
    end
end

function label = menuDisplayText(menuHandle)
    label = '';

    try
        if isprop(menuHandle, 'Text')
            label = char(menuHandle.Text);
        end
    catch
        label = '';
    end

    if isempty(label)
        try
            if isprop(menuHandle, 'Label')
                label = char(menuHandle.Label);
            end
        catch
            label = '';
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

function printResults(results)
    fprintf('TC      Result        Message\n');
    fprintf('------  ------------  -------\n');

    for i = 1:numel(results)
        fprintf('%-6s  %-12s  %s\n', ...
            results(i).TC, results(i).Result, results(i).Message);
    end
end
