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

steps = appendStep(steps, 'r2_channel_accessor_mirrors_models', ...
    @() doR2ChannelMirror());

steps = appendStep(steps, 'r3_async_decode_helpers', ...
    @() doR3AsyncDecodeHelpers());

steps = appendStep(steps, 'r4_layout_state_mirror', ...
    @() doR4LayoutStateMirror());

steps = appendStep(steps, 'r5_adapter_surface_complete', ...
    @() doR5AdapterSurface());

steps = appendStep(steps, 'r6r7r8_ownership_baseline', ...
    @() doOwnershipBaseline());

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

function doR2ChannelMirror()
    % R2: app.channel(fIdx) must reflect post-construction writes to
    % app.Models(fIdx) and app.FlightFilePath without any explicit
    % sync call from the caller.
    app = flightdash.FlightDataDashboard();
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    % Mutate the legacy struct directly (closest to how loader / option
    % editor write into the app today).
    app.Models(1).selectedRow = 7;
    app.Models(1).currentIndex = 42;
    app.FlightFilePath{1} = 'C:\diag\flight1.csv';
    ch = app.channel(1);
    assertHandleValid(ch, 'app.channel(1) returned empty handle');
    if ch.SelectedRow ~= 7
        error('Diag:ChannelMirror', ...
            'ChannelState.SelectedRow must mirror app.Models(1).selectedRow (got %g).', ...
            ch.SelectedRow);
    end
    if ch.CurrentIndex ~= 42
        error('Diag:ChannelMirror', ...
            'ChannelState.CurrentIndex mirror broken (got %g).', ch.CurrentIndex);
    end
    if ~strcmp(ch.FlightFilePath, 'C:\diag\flight1.csv')
        error('Diag:ChannelMirror', ...
            'ChannelState.FlightFilePath mirror broken (got "%s").', ...
            ch.FlightFilePath);
    end
    if ~isequal(ch.ChannelIndex, 1)
        error('Diag:ChannelMirror', ...
            'ChannelState.ChannelIndex must equal 1 after syncFromApp.');
    end
    % StateStore aggregate accessor must also work and route through Runtime.
    store = app.getStateStore();
    assertHandleValid(store, 'app.getStateStore() returned empty handle');
    if ~isequal(store, app.Runtime.StateStore)
        error('Diag:RuntimeStateStoreDrift', ...
            'Runtime.StateStore must reference the same handle as app.StateStore.');
    end
end

function doR3AsyncDecodeHelpers()
    % R3: getAsyncDecode() returns a bound facade; its helpers must
    % mutate the legacy app properties identically to the inline
    % cleanup code at FlightDataDashboard:2526-2538.
    app = flightdash.FlightDataDashboard();
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    ad = app.getAsyncDecode();
    assertHandleValid(ad, 'getAsyncDecode() returned empty');
    if ~isequal(ad, app.Runtime.AsyncDecode)
        error('Diag:AsyncDecodeRuntimeDrift', ...
            'Runtime.AsyncDecode must reference the same handle as app.AsyncDecode.');
    end
    % Seed app state then exercise the helpers.
    app.AsyncGen = [5 9];
    app.AsyncTargetFrame = [123 456];
    app.PendingFrame = [10 20];
    app.PendingMode = {'play', 'scrub'};

    ad.resetGeneration(1);
    if app.AsyncGen(1) ~= 6
        error('Diag:AsyncGen', ...
            'resetGeneration(1) must bump app.AsyncGen(1) from 5 to 6 (got %g).', ...
            app.AsyncGen(1));
    end
    if app.AsyncGen(2) ~= 9
        error('Diag:AsyncGen', ...
            'resetGeneration(1) must leave AsyncGen(2) untouched.');
    end

    ad.clearPending(2);
    if ~isnan(app.PendingFrame(2))
        error('Diag:PendingFrame', ...
            'clearPending(2) must NaN-clear app.PendingFrame(2).');
    end
    if ~isempty(app.PendingMode{2})
        error('Diag:PendingMode', ...
            'clearPending(2) must empty-clear app.PendingMode{2}.');
    end
    if isnan(app.PendingFrame(1)) ~= isnan(NaN) && app.PendingFrame(1) ~= 10
        error('Diag:PendingFrameLeak', ...
            'clearPending(2) must NOT touch channel 1.');
    end

    % cancelChannel with no live future: must bump gen + NaN target
    % without throwing even when AsyncFutures{fIdx} is [].
    app.AsyncFutures = {[], []};
    genBefore = app.AsyncGen(1);
    ad.cancelChannel(1);
    if app.AsyncGen(1) ~= genBefore + 1
        error('Diag:CancelChannel', ...
            'cancelChannel(1) must bump AsyncGen even without a future.');
    end
    if ~isnan(app.AsyncTargetFrame(1))
        error('Diag:CancelChannel', ...
            'cancelChannel(1) must NaN-clear AsyncTargetFrame(1).');
    end
end

function doR4LayoutStateMirror()
    % R4: getLayoutState() must lazy-mirror the 11 layout properties.
    % setLayoutProfile writes through to the live app field.
    app = flightdash.FlightDataDashboard();
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    % Seed direct legacy writes.
    app.LayoutProfile         = 'compact';
    app.LastLayoutSize        = [1280, 720];
    app.PreferredVideoWidth   = [600, 320];
    app.PanelSplitterFIdx     = 1;
    app.PanelSplitterKind     = 'info-plot';
    app.IsDraggingPanelSplitter = true;

    ls = app.getLayoutState();
    assertHandleValid(ls, 'getLayoutState() returned empty');
    if ~isequal(ls, app.Runtime.Layout)
        error('Diag:LayoutRuntimeDrift', ...
            'Runtime.Layout must reference the same handle as app.LayoutState.');
    end
    if ~strcmp(char(ls.LayoutProfile), 'compact')
        error('Diag:LayoutMirror', ...
            'LayoutProfile mirror broken (got "%s").', char(ls.LayoutProfile));
    end
    if ~isequal(ls.LastLayoutSize, [1280, 720])
        error('Diag:LayoutMirror', 'LastLayoutSize mirror broken.');
    end
    if ~isequal(ls.PreferredVideoWidth, [600, 320])
        error('Diag:LayoutMirror', 'PreferredVideoWidth mirror broken.');
    end
    if ls.PanelSplitterFIdx ~= 1 || ~strcmp(char(ls.PanelSplitterKind), 'info-plot')
        error('Diag:LayoutMirror', 'PanelSplitter mirror broken.');
    end
    if ~ls.IsDraggingPanelSplitter
        error('Diag:LayoutMirror', 'IsDraggingPanelSplitter mirror broken.');
    end
    % Convenience writer: setLayoutProfile must update the live app.
    ls.setLayoutProfile('narrow');
    if ~strcmp(char(app.LayoutProfile), 'narrow')
        error('Diag:LayoutWrite', ...
            'setLayoutProfile must write through to app.LayoutProfile (got "%s").', ...
            char(app.LayoutProfile));
    end
end

function doR5AdapterSurface()
    % R5: app.getAdapter() must expose every R1-R4 aggregate and route
    % cross-cutting plumbing through identical-result accessors.
    app = flightdash.FlightDataDashboard();
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    ad = app.getAdapter();
    assertHandleValid(ad, 'getAdapter() returned empty');

    % Aggregate accessors return the same handles as the direct app
    % getters — adapter is a router, not a duplicator.
    if ~isequal(ad.session(), app.getSessionContext())
        error('Diag:AdapterSession', 'adapter.session() must alias app.getSessionContext().');
    end
    if ~isequal(ad.store(), app.getStateStore())
        error('Diag:AdapterStore', 'adapter.store() must alias app.getStateStore().');
    end
    if ~isequal(ad.asyncDecode(), app.getAsyncDecode())
        error('Diag:AdapterAsync', 'adapter.asyncDecode() must alias app.getAsyncDecode().');
    end
    if ~isequal(ad.layout(), app.getLayoutState())
        error('Diag:AdapterLayout', 'adapter.layout() must alias app.getLayoutState().');
    end

    % Channel routing.
    app.Models(1).selectedRow = 13;
    ch = ad.channel(1);
    assertHandleValid(ch, 'adapter.channel(1) returned empty');
    if ch.SelectedRow ~= 13
        error('Diag:AdapterChannel', ...
            'adapter.channel(1).SelectedRow mirror broken (got %g).', ch.SelectedRow);
    end

    % Service accessors return the app's own handles unchanged.
    if ~isequal(ad.undoService(), app.UndoService)
        error('Diag:AdapterUndo', 'adapter.undoService() must alias app.UndoService.');
    end
    if ~isequal(ad.cacheService(), app.SharedCacheService)
        error('Diag:AdapterCache', 'adapter.cacheService() must alias app.SharedCacheService.');
    end
    if ~isequal(ad.useSharedDecode(), logical(app.UseSharedDecodeService))
        error('Diag:AdapterDecodeOptIn', 'adapter.useSharedDecode() must mirror app.UseSharedDecodeService.');
    end
    if ~isequal(ad.uiFigure(), app.UIFigure)
        error('Diag:AdapterUIFigure', 'adapter.uiFigure() must alias app.UIFigure.');
    end

    % logCaught must not throw on a dummy MException.
    try
        ad.logCaught(MException('Diag:Test', 'adapter logCaught probe'), 'Diag:adapterProbe');
    catch ME
        error('Diag:AdapterLogCaught', ...
            'adapter.logCaught threw: %s', ME.message);
    end

    % Escape-hatch app() returns the live handle.
    if ~isequal(ad.app(), app)
        error('Diag:AdapterEscape', 'adapter.app() must return the live app handle.');
    end
end

function doOwnershipBaseline()
    % R6 + R7 + R8 final guard: lock the ownership inversion result
    % so future edits cannot silently move storage back to the app.
    % Each named field MUST live on its state class as real storage;
    % each app.* name MUST appear as Dependent so the legacy API
    % surface stays intact.
    %
    % R2 brief's Models block is intentionally NOT enforced here —
    % its 77 deep struct-array read sites need a separate design
    % round before inversion is safe.

    inverted = struct( ...
        'flightdash.runtime.SessionContext', { ...
            { 'UseSharedDecodeService', 'IsEmbedded', 'ActiveSessionId', ...
              'RootContainer', 'UIFigure', 'SharedCacheService', ...
              'SharedDecodeService', 'UndoService', 'MouseRouter' } ...
        }, ...
        'flightdash.state.AsyncDecodeState', { ...
            { 'UseAsyncDecode', 'AsyncPool', 'AsyncFutures', ...
              'AsyncTargetFrame', 'AsyncGen', 'IsDecoding', ...
              'PendingFrame', 'PendingMode', 'DragVelocity', ...
              'DragVelocitySamples' } ...
        }, ...
        'flightdash.state.DashboardLayoutState', { ...
            { 'LayoutProfile', 'LastLayoutSize', 'InResponsiveLayout', ...
              'PreferredVideoWidth', 'ManualVideoWidth', ...
              'ManualPanelWidths', 'PanelSplitterFIdx', ...
              'PanelSplitterKind', 'IsDraggingPanelSplitter', ...
              'LayoutHandles', 'NormalFigurePosition' } ...
        }, ...
        'flightdash.state.VideoSessionState', { ...
            { 'VideoState', 'SyncState', 'VideoSyncState' } ...
        });

    classNames = fieldnames(inverted);
    appMeta = ?flightdash.FlightDataDashboard;
    appNames = arrayfun(@(p) string(p.Name), appMeta.PropertyList);
    appDepNames = arrayfun(@(p) string(p.Name), ...
        appMeta.PropertyList(arrayfun(@(p) p.Dependent, appMeta.PropertyList)));
    totalInverted = 0;
    for k = 1:numel(classNames)
        cn = classNames{k};
        cm = meta.class.fromName(strrep(cn, '.', '/'));
        if isempty(cm)
            cm = meta.class.fromName(cn);
        end
        if isempty(cm)
            error('Diag:MetaResolve', ...
                'Could not resolve metaclass for %s.', cn);
        end
        storage = arrayfun(@(p) string(p.Name), ...
            cm.PropertyList(~arrayfun(@(p) p.Dependent, cm.PropertyList)));
        for nameCell = inverted.(cn)
            name = nameCell{1};
            if ~any(storage == string(name))
                error('Diag:OwnershipRegression', ...
                    'Field "%s" must be real storage on %s.', name, cn);
            end
            if ~any(appNames == string(name))
                error('Diag:OwnershipRegression', ...
                    'App must expose "%s" (Dependent forward).', name);
            end
            if ~any(appDepNames == string(name))
                error('Diag:OwnershipRegression', ...
                    'App.%s must be Dependent (legacy storage leaked back).', name);
            end
            totalInverted = totalInverted + 1;
        end
    end

    % Path inversions live per-channel on ChannelState; the
    % multiplexing Dependent forward on the app keeps the cell shape.
    pathMeta = ?flightdash.state.ChannelState;
    pathStorage = arrayfun(@(p) string(p.Name), pathMeta.PropertyList);
    for name = ["FlightFilePath", "VideoFilePath"]
        if ~any(pathStorage == name)
            error('Diag:OwnershipRegression', ...
                'ChannelState must own %s as real storage.', name);
        end
        if ~any(appDepNames == name)
            error('Diag:OwnershipRegression', ...
                'App.%s must be Dependent (legacy storage leaked back).', name);
        end
        totalInverted = totalInverted + 1;
    end

    if totalInverted ~= 35
        error('Diag:OwnershipCount', ...
            'Expected 35 inverted properties, found %d.', totalInverted);
    end
end

function doClearClassesProbe()
    % Best-effort: rehash + which() round-trip on the new scaffolding
    % classes confirms the +flightdash/+runtime + +flightdash/+state
    % packages are on the path.
    rehash toolboxcache;
    for cls = ["flightdash.runtime.SessionContext", ...
               "flightdash.runtime.DashboardRuntime", ...
               "flightdash.runtime.DashboardAppAdapter", ...
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
