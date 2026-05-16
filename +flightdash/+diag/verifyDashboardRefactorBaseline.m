function report = verifyDashboardRefactorBaseline(varargin)
%VERIFYDASHBOARDREFACTORBASELINE  Smoke-test the R1-R5 refactor invariants.
%
%   report = flightdash.diag.verifyDashboardRefactorBaseline()
%
%   Exercises the dashboard's lifecycle in the configurations the
%   refactor brief calls out as load-bearing:
%     1. Standalone launch / delete (no embedding).
%     2. Embedded launch / delete inside a temporary uifigure/uitab.
%     3. Two embedded dashboards with distinct session IDs.
%     4. Deleting one embedded dashboard must not delete the host figure.
%     5. No new ErrorLog entries during basic launch / delete.
%     6. clear-classes / rehash compatibility (best effort, opt-in).
%
%   Returns a struct with fields:
%     - Steps         : table of step results
%     - HadFailures   : logical (true if any step failed)
%     - Errors        : cellstr of error messages
%
%   Headless-friendly: each step wraps construction in try/catch so a
%   missing display or graphics back-end is reported as a skipped step
%   rather than aborting the suite. Designed to be runnable from the
%   Phase-9 full-sweep harness AND from a bare `runtests` invocation.

p = inputParser;
p.addParameter('IncludeClearClassesProbe', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
includeClearProbe = logical(p.Results.IncludeClearClassesProbe);

steps = {};
errors = {};

steps = appendStep(steps, 'standalone_launch_delete', ...
    @() doStandaloneLaunchDelete());

steps = appendStep(steps, 'embedded_launch_delete', ...
    @() doEmbeddedLaunchDelete());

steps = appendStep(steps, 'two_embedded_distinct_sessions', ...
    @() doTwoEmbeddedDistinctSessions());

steps = appendStep(steps, 'embedded_delete_keeps_host_figure', ...
    @() doEmbeddedDeleteKeepsHostFigure());

steps = appendStep(steps, 'no_new_errorlog_entries', ...
    @() doNoNewErrorLogEntries());

if includeClearProbe
    steps = appendStep(steps, 'clear_classes_rehash_compat', ...
        @() doClearClassesProbe());
end

% Roll up.
report.Steps = stepsToTable(steps);
report.HadFailures = any(strcmp({steps.Status}, 'FAIL'));
for k = 1:numel(steps)
    if ~strcmp(steps(k).Status, 'PASS') && ~isempty(steps(k).Error)
        errors{end+1} = sprintf('[%s] %s', steps(k).Name, steps(k).Error); %#ok<AGROW>
    end
end
report.Errors = errors;
end

% ============================================================
% Step implementations
% ============================================================

function doStandaloneLaunchDelete()
    app = flightdash.FlightDataDashboard();
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    assertHandleValid(app, 'standalone app not constructed');
    assertHandleValid(app.UIFigure, 'standalone UIFigure missing');
    if ~strcmp(char(app.ActiveSessionId), 'standalone')
        error('Diag:StandaloneActiveSessionId', ...
            'Standalone ActiveSessionId must be ''standalone'', got "%s".', ...
            char(app.ActiveSessionId));
    end
    if app.IsEmbedded
        error('Diag:StandaloneIsEmbedded', ...
            'Standalone app must have IsEmbedded=false.');
    end
    assertSessionContextLive(app);
end

function doEmbeddedLaunchDelete()
    host = uifigure('Visible', 'off', 'Position', [0 0 800 600]);
    cleanupHost = onCleanup(@() safeDeleteFig(host)); %#ok<NASGU>
    tabs = uitabgroup(host);
    tab  = uitab(tabs, 'Title', 'Diag');
    app = flightdash.FlightDataDashboard(tab, 'S001');
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    assertHandleValid(app, 'embedded app not constructed');
    if ~app.IsEmbedded
        error('Diag:EmbeddedIsEmbedded', 'Embedded app must have IsEmbedded=true.');
    end
    if ~strcmp(char(app.ActiveSessionId), 'S001')
        error('Diag:EmbeddedSessionId', ...
            'Embedded ActiveSessionId mismatch: got "%s".', char(app.ActiveSessionId));
    end
    if ~isequal(ancestor(app.RootContainer, 'figure'), host)
        error('Diag:EmbeddedRootContainer', ...
            'Embedded RootContainer must climb to the host figure.');
    end
    assertSessionContextLive(app);
end

function doTwoEmbeddedDistinctSessions()
    host = uifigure('Visible', 'off', 'Position', [0 0 800 600]);
    cleanupHost = onCleanup(@() safeDeleteFig(host)); %#ok<NASGU>
    tabs = uitabgroup(host);
    tabA = uitab(tabs, 'Title', 'A');
    tabB = uitab(tabs, 'Title', 'B');
    appA = flightdash.FlightDataDashboard(tabA, 'S001');
    cleanupA = onCleanup(@() safeDelete(appA)); %#ok<NASGU>
    appB = flightdash.FlightDataDashboard(tabB, 'S002');
    cleanupB = onCleanup(@() safeDelete(appB)); %#ok<NASGU>
    if strcmp(char(appA.ActiveSessionId), char(appB.ActiveSessionId))
        error('Diag:DuplicateSessionId', ...
            'Two embedded dashboards must keep distinct SessionIds.');
    end
    if appA.SessionContext.ActiveSessionId == ...
            appB.SessionContext.ActiveSessionId %#ok<BDSCI>
        error('Diag:SessionContextLeak', ...
            'SessionContext facade must reflect each app''s identity.');
    end
end

function doEmbeddedDeleteKeepsHostFigure()
    host = uifigure('Visible', 'off', 'Position', [0 0 800 600]);
    cleanupHost = onCleanup(@() safeDeleteFig(host)); %#ok<NASGU>
    tabs = uitabgroup(host);
    tab  = uitab(tabs, 'Title', 'Diag');
    app = flightdash.FlightDataDashboard(tab, 'S001');
    delete(app);
    if ~isvalid(host)
        error('Diag:HostFigureDestroyed', ...
            'Deleting an embedded dashboard must NOT delete the host figure.');
    end
end

function doNoNewErrorLogEntries()
    sizeBefore = errorLogSize();
    app = flightdash.FlightDataDashboard();
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    delta = errorLogSize() - sizeBefore;
    if delta > 0
        error('Diag:ErrorLogGrew', ...
            'ErrorLog grew by %d entries during clean launch.', delta);
    end
end

function doClearClassesProbe()
    % Best-effort: rehash + which() round-trip on the new scaffolding
    % classes confirms the +flightdash/+runtime + +flightdash/+state
    % packages are on the path.
    rehash toolboxcache;
    for cls = ["flightdash.runtime.SessionContext", ...
               "flightdash.runtime.DashboardRuntime", ...
               "flightdash.state.ChannelState", ...
               "flightdash.state.VideoSessionState", ...
               "flightdash.state.AsyncDecodeState", ...
               "flightdash.state.DashboardLayoutState", ...
               "flightdash.state.DashboardStateStore"]
        if isempty(which(char(cls)))
            error('Diag:ClassNotOnPath', ...
                'Refactor scaffolding class "%s" not resolvable via which().', ...
                char(cls));
        end
    end
end

% ============================================================
% Helpers
% ============================================================

function steps = appendStep(steps, name, thunk)
    s = struct('Name', name, 'Status', 'SKIP', 'Error', '');
    try
        thunk();
        s.Status = 'PASS';
    catch ME
        s.Status = 'FAIL';
        s.Error  = ME.message;
    end
    if isempty(steps)
        steps = s;
    else
        steps(end+1) = s; %#ok<AGROW>
    end
end

function tbl = stepsToTable(steps)
    if isempty(steps)
        tbl = table('Size', [0 3], ...
            'VariableTypes', {'string', 'string', 'string'}, ...
            'VariableNames', {'Name', 'Status', 'Error'});
        return;
    end
    tbl = table(string({steps.Name}'), string({steps.Status}'), ...
        string({steps.Error}'), ...
        'VariableNames', {'Name', 'Status', 'Error'});
end

function assertHandleValid(h, msg)
    if isempty(h) || ~isa(h, 'handle') || ~isvalid(h)
        error('Diag:InvalidHandle', '%s', msg);
    end
end

function assertSessionContextLive(app)
    ctx = app.getSessionContext();
    if isempty(ctx) || ~isvalid(ctx)
        error('Diag:NoSessionContext', ...
            'getSessionContext() must return a valid handle.');
    end
    if ~strcmp(char(ctx.ActiveSessionId), char(app.ActiveSessionId))
        error('Diag:SessionContextDrift', ...
            'SessionContext.ActiveSessionId ("%s") must mirror app.ActiveSessionId ("%s").', ...
            char(ctx.ActiveSessionId), char(app.ActiveSessionId));
    end
    if ~isequal(ctx.IsEmbedded, app.IsEmbedded)
        error('Diag:SessionContextDrift', ...
            'SessionContext.IsEmbedded must mirror app.IsEmbedded.');
    end
end

function n = errorLogSize()
    n = 0;
    try
        if exist('flightdash.util.ErrorLog', 'class') == 8
            entries = flightdash.util.ErrorLog.entries(); %#ok<NASGU>
            if iscell(entries)
                n = numel(entries);
            elseif istable(entries) || isstruct(entries)
                n = numel(entries);
            end
        end
    catch
        n = 0;
    end
end

function safeDelete(app)
    try
        if ~isempty(app) && isa(app, 'handle') && isvalid(app)
            delete(app);
        end
    catch
    end
end

function safeDeleteFig(fig)
    try
        if ~isempty(fig) && isvalid(fig), delete(fig); end
    catch
    end
end
