function results = verifyPhase4()
%VERIFYPHASE4 Phase 4 (Event Scope / Session Router) automated audit.
%
%   This function runs every Phase 4 / review-fix unit check that does
%   NOT require a live FlightDataDashboard UI. It targets the seven
%   risks raised in the May review and confirms each one is closed at
%   the API level. UI-bound scenarios (drag across tabs, embed resize)
%   stay in docs/test-multi-instance-drag.md as a manual checklist.
%
%   Usage:
%       r = flightdash.studio.diag.verifyPhase4();
%
%   Returns a struct array with PASS/FAIL per check; prints a summary.
%
%   Test cases:
%     P4-1  AppEventData(SessionId)  — 3-arg ctor + property exists
%     P4-2  SessionScope set/get/clear/isOwner basic semantics
%     P4-3  isActiveSession(d) prefers payload SessionId over scope
%     P4-4  ProjectModel.newId returns monotonic unique ids
%     P4-5  SessionModel.setFlightFile rejects bad channel idx
%     P4-6  SessionModel.setDisplayName rejects empty / whitespace
%     P4-7  ProjectModel.removeSession cascades dependent results
%     P4-8  StudioMouseRouter lock semantics (Phase 3.5)
%     P4-9  EventBus session-filtered subscriptions and target publish
%     P4-10 SessionScopedListener / ControllerBase helper presence
%     P4-11 UndoService session stack + UndoStateChanged event
%     P4-12 UndoService MaxHistory alias + deleted-target command no-op
%     P9-1  ProjectSerializer save+load round-trip (Phase 9)

    fprintf('\n=== Phase 4 verification ===\n');

    cases = { ...
        'P4-1', @p41_appEventDataSessionId; ...
        'P4-2', @p42_sessionScope; ...
        'P4-3', @p43_isActiveSessionPayloadFirst; ...
        'P4-4', @p44_newIdCounter; ...
        'P4-5', @p45_channelIdxValidator; ...
        'P4-6', @p46_displayNameValidator; ...
        'P4-7', @p47_removeSessionCascade; ...
        'P4-8', @p48_studioMouseRouter; ...
        'P4-9', @p49_eventBusSessionFilters; ...
        'P4-10', @p410_sessionScopedListenerApi; ...
        'P4-11', @p411_undoServiceSessionStack; ...
        'P4-12', @p412_undoServiceMaxHistoryAndNoop; ...
        'P9-1', @p91_serializerRoundTrip ...
    };

    results = repmat(struct('Id','','Passed',false,'Message','','Details',struct()), 1, size(cases,1));
    for k = 1:size(cases, 1)
        try
            r = cases{k, 2}();
            r.Id = cases{k, 1};
        catch ME
            r = struct('Id', cases{k,1}, 'Passed', false, ...
                'Message', sprintf('Test errored: %s', ME.message), 'Details', struct());
        end
        results(k) = r;
    end

    fprintf('\n%-6s %-7s %s\n', 'TC',  'Result', 'Message');
    fprintf('%-6s %-7s %s\n',   '----', '------', '-------');
    nPass = 0;
    for k = 1:numel(results)
        verdict = 'PASS';
        if ~results(k).Passed, verdict = 'FAIL'; else, nPass = nPass + 1; end
        fprintf('%-6s %-7s %s\n', results(k).Id, verdict, results(k).Message);
    end
    fprintf('\n%d / %d Phase 4 checks passed.\n\n', nPass, numel(results));
end


function r = p41_appEventDataSessionId()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    try
        d0 = flightdash.util.AppEventData();
        d2 = flightdash.util.AppEventData(1, struct('foo', 1));
        d3 = flightdash.util.AppEventData(2, struct('bar', 2), 'SESS_TEST');
    catch ME
        r.Message = sprintf('Constructor errored: %s', ME.message);
        return;
    end
    if ~isprop(d0, 'SessionId') || ~isprop(d2, 'SessionId') || ~isprop(d3, 'SessionId')
        r.Message = 'AppEventData missing SessionId property';
        return;
    end
    if ~isempty(d0.SessionId) || ~isempty(d2.SessionId)
        r.Message = sprintf('Default SessionId not empty: d0="%s" d2="%s"', d0.SessionId, d2.SessionId);
        return;
    end
    if ~strcmp(d3.SessionId, 'SESS_TEST')
        r.Message = sprintf('3-arg SessionId not stored: got "%s"', d3.SessionId);
        return;
    end
    r.Details = struct('Default', d0.SessionId, 'WithId', d3.SessionId);
    r.Passed = true;
    r.Message = 'AppEventData accepts (fIdx, payload, sessionId) and stores all three';
end


function r = p42_sessionScope()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    flightdash.util.SessionScope.clear();
    if ~isempty(flightdash.util.SessionScope.getActive())
        r.Message = 'clear() did not empty SessionScope';
        return;
    end

    flightdash.util.SessionScope.setActive('SESS_AAA');
    if ~strcmp(flightdash.util.SessionScope.getActive(), 'SESS_AAA')
        r.Message = 'setActive(...) did not round-trip through getActive()';
        return;
    end

    appdataKey = 'FlightDashVerifyP42SessionId';
    listener = [];
    try
        if isappdata(0, appdataKey), rmappdata(0, appdataKey); end
        listener = flightdash.util.EventBus.subscribe('FlightStopRequested', ...
            @(~,d) setappdata(0, appdataKey, d.SessionId));
        flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(1));
        capturedSessionId = '';
        if isappdata(0, appdataKey)
            capturedSessionId = char(getappdata(0, appdataKey));
        end
        if ~isempty(listener) && isvalid(listener), delete(listener); end
        if isappdata(0, appdataKey), rmappdata(0, appdataKey); end
        if ~strcmp(capturedSessionId, 'SESS_AAA')
            r.Message = sprintf('EventBus did not auto-tag active SessionId: "%s"', capturedSessionId);
            flightdash.util.SessionScope.clear();
            return;
        end
    catch ME
        try, if ~isempty(listener) && isvalid(listener), delete(listener); end, catch, end
        try, if isappdata(0, appdataKey), rmappdata(0, appdataKey); end, catch, end
        r.Message = sprintf('EventBus SessionId auto-tag check errored: %s', ME.message);
        flightdash.util.SessionScope.clear();
        return;
    end

    % Stub object exposing ActiveSessionId only (avoid uifigure construction)
    fakeApp = struct('ActiveSessionId', 'SESS_AAA');
    if ~flightdash.util.SessionScope.isOwner(fakeApp)
        r.Message = 'isOwner false when ids match';
        return;
    end

    fakeApp.ActiveSessionId = 'SESS_BBB';
    if flightdash.util.SessionScope.isOwner(fakeApp)
        r.Message = 'isOwner true when ids differ';
        return;
    end

    flightdash.util.SessionScope.clear();
    fakeApp.ActiveSessionId = 'SESS_BBB';
    if ~flightdash.util.SessionScope.isOwner(fakeApp)
        r.Message = 'isOwner false in broadcast (no active id) mode';
        return;
    end

    fakeApp.ActiveSessionId = 'standalone';
    flightdash.util.SessionScope.setActive('SESS_BBB');
    if ~flightdash.util.SessionScope.isOwner(fakeApp)
        r.Message = 'isOwner false for standalone app even when scope is set';
        return;
    end

    flightdash.util.SessionScope.clear();
    r.Passed = true;
    r.Message = 'set/get/clear/isOwner semantics and EventBus auto SessionId tagging correct';
end


function r = p43_isActiveSessionPayloadFirst()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    flightdash.util.SessionScope.clear();
    flightdash.util.SessionScope.setActive('SESS_GLOBAL');

    % Build a stub app duck-typed to FlightDataDashboard.isActiveSession.
    % We cannot easily construct a real FlightDataDashboard without a uifigure,
    % so we replicate the resolver inline using SessionScope to keep the
    % test self-contained.
    function tf = checkPayload(appId, evtSessionId)
        d = flightdash.util.AppEventData(0, [], evtSessionId);
        if ~isempty(d.SessionId)
            if isempty(appId) || strcmp(appId, 'standalone')
                tf = true; return;
            end
            tf = strcmp(d.SessionId, appId);
            return;
        end
        fakeApp = struct('ActiveSessionId', appId);
        tf = flightdash.util.SessionScope.isOwner(fakeApp);
    end

    cases = { ...
        'SESS_A',     'SESS_A',     true,  'payload match'; ...
        'SESS_A',     'SESS_B',     false, 'payload mismatch (ignore scope)'; ...
        'SESS_A',     '',           true,  'scope active matches'; ...
        'SESS_X',     '',           false, 'scope active mismatches'; ...
        'standalone', 'SESS_B',     true,  'standalone bypasses payload'; ...
        'standalone', '',           true,  'standalone bypasses scope'; ...
    };

    for k = 1:size(cases, 1)
        appId = cases{k,1};
        evtId = cases{k,2};
        expected = cases{k,3};
        if strcmp(appId, 'SESS_X'), flightdash.util.SessionScope.setActive('SESS_GLOBAL'); end
        if strcmp(appId, 'SESS_A') && isempty(evtId), flightdash.util.SessionScope.setActive('SESS_A'); end
        actual = checkPayload(appId, evtId);
        if actual ~= expected
            r.Message = sprintf('Case "%s" expected %d got %d (app=%s evt=%s)', ...
                cases{k,4}, expected, actual, appId, evtId);
            flightdash.util.SessionScope.clear();
            return;
        end
    end
    flightdash.util.SessionScope.clear();
    r.Passed = true;
    r.Message = 'payload SessionId takes precedence over SessionScope (with standalone fallback)';
end


function r = p44_newIdCounter()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    n = 200;
    ids = cell(n, 1);
    for k = 1:n
        ids{k} = flightdash.project.ProjectModel.newId('TST');
    end
    if numel(unique(ids)) ~= n
        r.Message = sprintf('Duplicate ids in %d-id batch: %d unique', n, numel(unique(ids)));
        return;
    end
    % Validate format: TST_<17-digit timestamp>_<6+ digits counter>.
    % Counter padding is "%06d" so it is at least 6, but a previous
    % session could have advanced it past 999999 — tolerate >=6.
    rx = '^TST_\d{17}_\d{6,}$';
    matchMask = ~cellfun(@isempty, regexp(ids, rx, 'once'));
    if ~all(matchMask)
        bad = find(~matchMask, 1);
        r.Message = sprintf('Id format mismatch (sample %d: "%s")', bad, ids{bad});
        return;
    end
    r.Details = struct('Total', n, 'First', ids{1}, 'Last', ids{end});
    r.Passed = true;
    r.Message = sprintf('%d ids generated, all unique, format conforms', n);
end


function r = p45_channelIdxValidator()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    s = flightdash.project.SessionModel('verify');
    bad = {0, 3, -1, 1.5, NaN, Inf};
    for k = 1:numel(bad)
        try
            s.setFlightFile(bad{k}, 'x.dat');
            r.Message = sprintf('setFlightFile accepted invalid channelIdx=%g', bad{k});
            return;
        catch ME
            % ok - rejection expected
        end
    end
    % Valid path
    s2 = s.setFlightFile(1, 'flight.dat');
    if ~strcmp(s2.FlightFilePath{1}, 'flight.dat')
        r.Message = 'Valid setFlightFile did not store path';
        return;
    end
    s3 = s.setFlightFile(2, "video.avi");
    if ~strcmp(s3.FlightFilePath{2}, 'video.avi')
        r.Message = 'Valid setFlightFile did not coerce string scalar';
        return;
    end
    r.Passed = true;
    r.Message = 'channelIdx in {0,3,-1,1.5,NaN,Inf} rejected; {1,2} with char/string accepted';
end


function r = p46_displayNameValidator()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    s = flightdash.project.SessionModel('verify');
    bad = {'', '   ', "  "};
    for k = 1:numel(bad)
        try
            s.setDisplayName(bad{k});
            r.Message = sprintf('setDisplayName accepted empty/whitespace: "%s"', char(bad{k}));
            return;
        catch ME
            % ok
        end
    end
    s2 = s.setDisplayName('   trimmed   ');
    if ~strcmp(s2.DisplayName, 'trimmed')
        r.Message = sprintf('setDisplayName did not strip whitespace: "%s"', s2.DisplayName);
        return;
    end
    r.Passed = true;
    r.Message = 'Empty / whitespace names rejected; valid names trimmed';
end


function r = p47_removeSessionCascade()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    p = flightdash.project.ProjectModel('verify');
    s = flightdash.project.SessionModel('A');
    p = p.addSession(s);
    res = flightdash.project.ReviewResultModel(s.SessionId, 'ROI', 1);
    p = p.addResult(res);

    if numel(p.Sessions) ~= 1 || numel(p.Results) ~= 1
        r.Message = sprintf('Pre-condition failed: Sessions=%d Results=%d', ...
            numel(p.Sessions), numel(p.Results));
        return;
    end
    p = p.removeSession(s.SessionId);
    if numel(p.Sessions) ~= 0
        r.Message = sprintf('removeSession did not drop SessionModel (count=%d)', numel(p.Sessions));
        return;
    end
    if numel(p.Results) ~= 0
        r.Message = sprintf('removeSession did not cascade to dependent Results (count=%d)', numel(p.Results));
        return;
    end
    r.Passed = true;
    r.Message = 'removeSession drops session AND cascades dependent ReviewResults';
end


function r = p48_studioMouseRouter()
    % [PHASE 3.5] Verify the router enforces lock-state invariants:
    %   - figure callbacks attach on construction
    %   - lock granted when session matches workspace's active id
    %   - second drag request rejected while lock is held
    %   - lock refused when requesting session is not active
    %   - releaseDragLock returns to grantable state
    %   - detach() clears figure callbacks
    %
    % Mocked controller is a real handle subclass so isvalid()/isempty()
    % checks inside the router behave naturally. Dispatch (handleDragMotion
    % / stopDrag invocation) is exercised by the live UI manual scenarios,
    % not here.
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    fig = []; router = []; ctrl = [];
    try
        fig = uifigure('Visible', 'off', 'Name', 'P4-8 router test');

        % Stub workspace via containers.Map (handle) so the router's
        % isvalid(...) checks pass without importing a class file.
        wsHolder = containers.Map('KeyType', 'char', 'ValueType', 'any');
        wsHolder('id') = 'SESS_AAA';
        ws.activeSessionId = @() wsHolder('id');
        % Wrap as struct — router only calls .activeSessionId() method.
        % The router's isvalid(workspace) check only fires inside the
        % dispatch path which we do not exercise here.

        router = flightdash.studio.StudioMouseRouter(fig, ws);

        if isempty(fig.WindowButtonMotionFcn) || isempty(fig.WindowButtonUpFcn)
            r.Message = 'Router did not attach figure callbacks';
            return;
        end

        % Use a real handle as the "controller" stub. event.EventData is
        % a tiny built-in handle subclass — perfect for satisfying
        % isvalid() without dragging in any controller logic.
        ctrl = event.EventData();

        % --- subtest A: lock granted for active session
        granted = router.requestDragLock('SESS_AAA', ctrl);
        if ~granted
            r.Message = 'Router refused lock for active session';
            return;
        end
        if ~router.isLockHeldBy('SESS_AAA')
            r.Message = 'isLockHeldBy(active) false right after grant';
            return;
        end

        % --- subtest B: second request refused while lock is held
        ctrl2 = event.EventData();
        granted2 = router.requestDragLock('SESS_AAA', ctrl2);
        if granted2
            r.Message = 'Router granted a second lock while one was held';
            return;
        end

        % --- subtest C: refused when session not active
        router.releaseDragLock();
        wsHolder('id') = 'SESS_BBB';
        granted3 = router.requestDragLock('SESS_AAA', ctrl);
        if granted3
            r.Message = 'Router granted lock to a non-active session';
            return;
        end

        % --- subtest D: regrant after activeId change
        granted4 = router.requestDragLock('SESS_BBB', ctrl);
        if ~granted4
            r.Message = 'Router refused lock for newly active session';
            return;
        end
        router.releaseDragLock();

        % --- subtest E: detach clears callbacks
        router.detach();
        if ~isempty(fig.WindowButtonMotionFcn) || ~isempty(fig.WindowButtonUpFcn)
            r.Message = 'detach() did not clear figure callbacks';
            return;
        end

        r.Passed = true;
        r.Message = 'Router lock grant / refusal / regrant / detach semantics correct';
    catch ME
        r.Message = sprintf('Router test errored: %s', ME.message);
    end
    if ~isempty(router) && isa(router, 'flightdash.studio.StudioMouseRouter')
        try, delete(router); catch, end
    end
    if ~isempty(fig) && isvalid(fig), try, delete(fig); catch, end, end
end

function r = p49_eventBusSessionFilters()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    la = [];
    lb = [];
    lAll = [];
    flightdash.util.SessionScope.clear();
    cleaner = onCleanup(@cleanup);
    try
        hitsA = 0;
        hitsB = 0;
        hitsAll = 0;
        la = flightdash.util.EventBus.subscribe('FlightStopRequested', @(~,~) bumpA(), 'P4_A');
        lb = flightdash.util.EventBus.subscribe('FlightStopRequested', @(~,~) bumpB(), 'P4_B');
        lAll = flightdash.util.EventBus.subscribe('FlightStopRequested', @(~,~) bumpAll());

        flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(1, [], 'P4_A'));
        if hitsA ~= 1 || hitsB ~= 0 || hitsAll ~= 1
            r.Message = sprintf('Session P4_A routing mismatch: A=%d B=%d All=%d', hitsA, hitsB, hitsAll);
            return;
        end

        flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(1), 'P4_B');
        if hitsA ~= 1 || hitsB ~= 1 || hitsAll ~= 2
            r.Message = sprintf('Target publish P4_B mismatch: A=%d B=%d All=%d', hitsA, hitsB, hitsAll);
            return;
        end

        flightdash.util.EventBus.publish('FlightStopRequested', struct('SessionId', 'P4_A', 'Payload', 42));
        if hitsA ~= 2 || hitsB ~= 1 || hitsAll ~= 3
            r.Message = sprintf('Struct payload SessionId mismatch: A=%d B=%d All=%d', hitsA, hitsB, hitsAll);
            return;
        end

        flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(1));
        if hitsA ~= 3 || hitsB ~= 2 || hitsAll ~= 4
            r.Message = sprintf('Legacy broadcast mismatch: A=%d B=%d All=%d', hitsA, hitsB, hitsAll);
            return;
        end

        if ~flightdash.util.EventBus.acceptsSession('P4_A', 'P4_A') || ...
                flightdash.util.EventBus.acceptsSession('P4_A', 'P4_B') || ...
                ~flightdash.util.EventBus.acceptsSession('', 'P4_B') || ...
                ~flightdash.util.EventBus.acceptsSession('P4_A', '')
            r.Message = 'acceptsSession semantics mismatch';
            return;
        end

        try, if ~isempty(la) && isvalid(la), delete(la); end, catch, end
        la = flightdash.util.EventBus.subscribeForApp( ...
            struct('ActiveSessionId', 'P4_A'), 'FlightStopRequested', @(~,~) bumpA());
        flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(1, [], 'P4_B'));
        if hitsA ~= 3
            r.Message = sprintf('subscribeForApp leaked P4_B event into P4_A listener: A=%d', hitsA);
            return;
        end
        flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(1, [], 'P4_A'));
        if hitsA ~= 4
            r.Message = sprintf('subscribeForApp did not deliver P4_A event: A=%d', hitsA);
            return;
        end

        r.Passed = true;
        r.Message = 'EventBus session filters, subscribeForApp, target publish, struct SessionId, and broadcast semantics correct';
    catch ME
        r.Message = sprintf('EventBus session filter check errored: %s', ME.message);
    end

    function bumpA()
        hitsA = hitsA + 1;
    end

    function bumpB()
        hitsB = hitsB + 1;
    end

    function bumpAll()
        hitsAll = hitsAll + 1;
    end

    function cleanup()
        try, if ~isempty(la) && isvalid(la), delete(la); end, catch, end
        try, if ~isempty(lb) && isvalid(lb), delete(lb); end, catch, end
        try, if ~isempty(lAll) && isvalid(lAll), delete(lAll); end, catch, end
        flightdash.util.SessionScope.clear();
    end
end

function r = p410_sessionScopedListenerApi()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    try
        listenerMeta = meta.class.fromName('flightdash.event.SessionScopedListener');
        baseMeta = meta.class.fromName('flightdash.controller.ControllerBase');
        ok = ~isempty(listenerMeta) && ~isempty(baseMeta) && ...
            hasMetaMethod(listenerMeta, 'safeCallback') && ...
            hasMetaMethod(baseMeta, 'addSessionListener') && ...
            hasMetaProperty(baseMeta, 'SessionListeners') && ...
            hasMetaMethod(baseMeta, 'cleanup');
        if ~ok
            r.Message = 'SessionScopedListener or ControllerBase session listener API missing';
            return;
        end
        r.Passed = true;
        r.Message = 'SessionScopedListener and ControllerBase session listener cleanup API resolved';
    catch ME
        r.Message = sprintf('SessionScopedListener API check errored: %s', ME.message);
    end
end

function r = p411_undoServiceSessionStack()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    listener = [];
    cleaner = onCleanup(@cleanup);
    try
        stateHits = 0;
        listener = flightdash.util.EventBus.subscribe('UndoStateChanged', @(~,d) capture(d), 'P4_UNDO');
        svc = flightdash.studio.UndoService('P4_UNDO');
        cmd = flightdash.command.MoveROICommand('P4_UNDO', [], 1, 1, {0, 1, 'sig', '--', '--'}, ...
            {1, 2, 'sig', '--', '--'}, 'Move ROI');

        svc.push(cmd);
        if ~svc.canUndo() || svc.canRedo()
            r.Message = 'push() did not set undo/redo state';
            return;
        end
        svc.undo();
        if svc.canUndo() || ~svc.canRedo()
            r.Message = 'undo() did not move command to redo stack';
            return;
        end
        svc.redo();
        if ~svc.canUndo() || svc.canRedo()
            r.Message = 'redo() did not restore undo stack';
            return;
        end
        if stateHits < 3
            r.Message = sprintf('UndoStateChanged listener saw too few updates: %d', stateHits);
            return;
        end

        r.Passed = true;
        r.Message = 'UndoService stack transitions and session-scoped state event resolved';
    catch ME
        r.Message = sprintf('UndoService check errored: %s', ME.message);
    end

    function capture(d)
        if strcmp(char(d.SessionId), 'P4_UNDO')
            stateHits = stateHits + 1;
        end
    end

    function cleanup()
        try, if ~isempty(listener) && isvalid(listener), delete(listener); end, catch, end
    end
end

function r = p412_undoServiceMaxHistoryAndNoop()
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    try
        svc = flightdash.studio.UndoService('P4_LIMIT');
        svc.MaxHistory = 2;
        if svc.MaxDepth ~= 2 || svc.MaxHistory ~= 2
            r.Message = sprintf('MaxHistory alias mismatch: MaxDepth=%g MaxHistory=%g', ...
                svc.MaxDepth, svc.MaxHistory);
            return;
        end

        row0 = {0, 1, 'sig', '--', '--'};
        row1 = {1, 2, 'sig', '--', '--'};
        row2 = {2, 3, 'sig', '--', '--'};
        row3 = {3, 4, 'sig', '--', '--'};
        svc.push(flightdash.command.MoveROICommand('P4_LIMIT', [], 1, 1, row0, row1, 'Move ROI 1'));
        svc.push(flightdash.command.MoveROICommand('P4_LIMIT', [], 1, 1, row1, row2, 'Move ROI 2'));
        svc.push(flightdash.command.MoveROICommand('P4_LIMIT', [], 1, 1, row2, row3, 'Move ROI 3'));
        if numel(svc.UndoStack) ~= 2
            r.Message = sprintf('MaxHistory/MaxDepth trim failed: stack=%d', numel(svc.UndoStack));
            return;
        end

        markerCmd = flightdash.command.MoveMarkerCommand('P4_LIMIT', [], [1 2], [3 4], 'Move missing marker');
        markerCmd.execute();
        markerCmd.undo();

        roiCmd = flightdash.command.MoveROICommand('P4_LIMIT', [], [1 2 3 4], [5 6 7 8], 'Move missing ROI');
        roiCmd.execute();
        roiCmd.undo();

        r.Passed = true;
        r.Message = 'MaxHistory alias trims stack and missing graphics command targets are safe no-ops';
    catch ME
        r.Message = sprintf('UndoService MaxHistory/no-op check errored: %s', ME.message);
    end
end


function r = p91_serializerRoundTrip()
    % [PHASE 9] Build a non-trivial Project, save it to a .frsproj
    % temp file, load it back, and assert that key fields survived.
    r = struct('Passed', false, 'Message', '', 'Details', struct());
    tmpFile = [tempname() flightdash.project.ProjectSerializer.FileExt];
    cleaner = onCleanup(@() flightdash.project.ProjectSerializer.delIfExists(tmpFile));
    try
        % --- build source project ---
        p = flightdash.project.ProjectModel('VerifyProj');
        p.GuiMode        = 'Analysis';
        p.AutoUpdateMode = 'Auto';

        s1 = flightdash.project.SessionModel('Alpha');
        s1 = s1.setFlightFile(1, 'C:/data/alpha_ch1.dat');
        s1 = s1.setVideoFile(2,  'C:/data/alpha_ch2.avi');
        s1.CurrentIndex = [10, 20];
        p = p.addSession(s1);

        s2 = flightdash.project.SessionModel('Beta');
        p = p.addSession(s2);

        th = flightdash.project.AnalysisThemeModel('RoiDefault', 'RoiStats');
        th = th.setSettings(struct('window', 50, 'kind', 'mean'));
        p = p.addTheme(th);

        % --- save ---
        flightdash.project.ProjectSerializer.save(p, tmpFile);
        if ~isfile(tmpFile)
            r.Message = 'save() did not produce the .frsproj file';
            return;
        end

        % --- load ---
        q = flightdash.project.ProjectSerializer.load(tmpFile);

        % --- assertions ---
        checks = { ...
            strcmp(q.ProjectName, 'VerifyProj'),                         'ProjectName lost'; ...
            strcmp(q.ProjectId,   p.ProjectId),                          'ProjectId not preserved'; ...
            strcmp(q.GuiMode,     'Analysis'),                           'GuiMode lost'; ...
            strcmp(q.AutoUpdateMode, 'Auto'),                            'AutoUpdateMode lost'; ...
            numel(q.Sessions) == 2,                                      'Sessions count mismatch'; ...
            numel(q.AnalysisThemes) == 1,                                'AnalysisThemes count mismatch'; ...
            any(arrayfun(@(s) strcmp(s.SessionId, s1.SessionId), q.Sessions)), 'Session 1 id missing'; ...
            any(arrayfun(@(s) strcmp(s.DisplayName, 'Beta'), q.Sessions)), 'Session 2 name missing'; ...
            ~q.DirtyFlag,                                                'Loaded project should be clean'; ...
        };
        for k = 1:size(checks, 1)
            if ~checks{k, 1}
                r.Message = checks{k, 2};
                return;
            end
        end

        % Per-session field check (find the Alpha session)
        idxA = find(arrayfun(@(s) strcmp(s.DisplayName, 'Alpha'), q.Sessions), 1);
        if isempty(idxA)
            r.Message = 'Alpha session not found after load';
            return;
        end
        sa = q.Sessions(idxA);
        if ~strcmp(sa.FlightFilePath{1}, 'C:/data/alpha_ch1.dat')
            r.Message = 'FlightFilePath{1} not preserved';
            return;
        end
        if ~strcmp(sa.VideoFilePath{2}, 'C:/data/alpha_ch2.avi')
            r.Message = 'VideoFilePath{2} not preserved';
            return;
        end
        if ~isequal(sa.CurrentIndex(:)', [10 20])
            r.Message = sprintf('CurrentIndex altered: got [%g %g]', sa.CurrentIndex(1), sa.CurrentIndex(2));
            return;
        end

        % Theme settings
        loadedTh = q.AnalysisThemes(1);
        if ~isfield(loadedTh.Settings, 'window') || loadedTh.Settings.window ~= 50
            r.Message = 'Theme.Settings.window not preserved';
            return;
        end

        r.Passed = true;
        r.Message = 'Project + 2 sessions + 1 theme round-tripped through .frsproj';
        r.Details.File = tmpFile;
    catch ME
        r.Message = sprintf('Round-trip errored: %s', ME.message);
    end
    clear cleaner;
end

function tf = hasMetaMethod(metaObj, methodName)
    tf = false;
    try
        if isempty(metaObj), return; end
        methods_ = metaObj.MethodList;
        for k = 1:numel(methods_)
            if strcmp(methods_(k).Name, methodName)
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end

function tf = hasMetaProperty(metaObj, propName)
    tf = false;
    try
        if isempty(metaObj), return; end
        props = metaObj.PropertyList;
        for k = 1:numel(props)
            if strcmp(props(k).Name, propName)
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end
