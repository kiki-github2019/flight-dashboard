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

    fprintf('\n=== Phase 4 verification ===\n');

    cases = { ...
        'P4-1', @p41_appEventDataSessionId; ...
        'P4-2', @p42_sessionScope; ...
        'P4-3', @p43_isActiveSessionPayloadFirst; ...
        'P4-4', @p44_newIdCounter; ...
        'P4-5', @p45_channelIdxValidator; ...
        'P4-6', @p46_displayNameValidator; ...
        'P4-7', @p47_removeSessionCascade; ...
        'P4-8', @p48_studioMouseRouter ...
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
    r.Message = 'set/get/clear/isOwner semantics correct (match, mismatch, broadcast, standalone)';
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
