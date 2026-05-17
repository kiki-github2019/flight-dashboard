function results = runMultiInstanceTests()
%RUNMULTIINSTANCETESTS Phase 3c automated checks (TC-1..TC-3).
%   Implements the three automated scenarios from
%   docs/test-multi-instance-drag.md so the Phase 3 design assumptions
%   can be verified on the user's actual MATLAB Online installation
%   without manually wiring temporary scripts.
%
%   Usage:
%       results = flightdash.studio.diag.runMultiInstanceTests();
%
%   Returns a struct array with one element per test case:
%       results(k).Id          'TC-1' | 'TC-2' | 'TC-3'
%       results(k).Passed      logical
%       results(k).Message     short outcome description
%       results(k).Details     struct with raw counters
%
%   The function prints a summary table to the console. TC-4 and TC-5
%   are inherently manual (they need a real flight dashboard with
%   visible UI) and stay in the doc as a checklist.

    fprintf('\n=== FlightReviewStudio multi-instance diagnostics ===\n');

    results = repmat(struct('Id', '', 'Passed', false, 'Message', '', 'Details', struct()), 1, 3);
    results(1) = tc1_singleSlotMotionFcn();
    results(2) = tc2_sessionIdGate();
    results(3) = tc3_throttlePrefixIsolation();

    fprintf('\n%-6s %-7s %s\n', 'TC', 'Result', 'Message');
    fprintf('%-6s %-7s %s\n', '----', '------', '-------');
    for k = 1:numel(results)
        verdict = 'PASS';
        if ~results(k).Passed, verdict = 'FAIL'; end
        fprintf('%-6s %-7s %s\n', results(k).Id, verdict, results(k).Message);
    end
    fprintf('\nTC-4 and TC-5 are manual (see docs/test-multi-instance-drag.md).\n\n');
end


function r = tc1_singleSlotMotionFcn()
    r = struct('Id', 'TC-1', 'Passed', false, ...
        'Message', '', 'Details', struct('cb1Hits', 0, 'cb2Hits', 0));
    fig = [];
    try
        fig = uifigure('Name', 'TC-1 single-slot motion fcn', 'Visible', 'off');
        setappdata(fig, 'counter', struct('cb1', 0, 'cb2', 0));
        fig.WindowButtonMotionFcn = @(~,~) tc1_bumpCounter(fig, 'cb1');
        % Simulate motion — MATLAB Online cannot synthesize real mouse
        % events from a script, so we directly invoke the callbacks.
        for k = 1:3, fig.WindowButtonMotionFcn(); end
        % Now register cb2 — should overwrite cb1.
        fig.WindowButtonMotionFcn = @(~,~) tc1_bumpCounter(fig, 'cb2');
        for k = 1:3, fig.WindowButtonMotionFcn(); end
        c = getappdata(fig, 'counter');
        r.Details.cb1Hits = c.cb1;
        r.Details.cb2Hits = c.cb2;
        % Pass condition: cb1 stopped at first batch (3), cb2 incremented
        r.Passed = (c.cb1 == 3) && (c.cb2 == 3);
        if r.Passed
            r.Message = sprintf('cb1=%d frozen, cb2=%d incremented (single-slot confirmed)', c.cb1, c.cb2);
        else
            r.Message = sprintf('Unexpected: cb1=%d cb2=%d', c.cb1, c.cb2);
        end
    catch ME
        r.Message = sprintf('Test errored: %s', ME.message);
    end
    if ~isempty(fig) && isvalid(fig), delete(fig); end
end


function tc1_bumpCounter(fig, name)
    c = getappdata(fig, 'counter');
    c.(name) = c.(name) + 1;
    setappdata(fig, 'counter', c);
end


function r = tc2_sessionIdGate()
    r = struct('Id', 'TC-2', 'Passed', false, ...
        'Message', '', 'Details', struct('cb1Hits', 0, 'cb2Hits', 0));
    fig = [];
    try
        fig = uifigure('Name', 'TC-2 SessionId gate', 'Visible', 'off');
        state = struct('activeSessionId', 'S001', 'cb1Hits', 0, 'cb2Hits', 0);
        setappdata(fig, 'state', state);
        fig.WindowButtonMotionFcn = @(~,~) tc2_dispatch(fig);

        % Phase A: active=S001
        for k = 1:5, fig.WindowButtonMotionFcn(); end
        s = getappdata(fig, 'state');
        a1 = s.cb1Hits; a2 = s.cb2Hits;

        % Phase B: switch to S002
        s.activeSessionId = 'S002';
        setappdata(fig, 'state', s);
        for k = 1:5, fig.WindowButtonMotionFcn(); end
        s = getappdata(fig, 'state');
        r.Details.cb1Hits = s.cb1Hits;
        r.Details.cb2Hits = s.cb2Hits;
        r.Passed = (a1 == 5) && (a2 == 0) && (s.cb1Hits == 5) && (s.cb2Hits == 5);
        if r.Passed
            r.Message = 'Master dispatch + SessionId gate routes correctly';
        else
            r.Message = sprintf('Mismatch: phaseA cb1=%d cb2=%d, phaseB cb1=%d cb2=%d', ...
                a1, a2, s.cb1Hits, s.cb2Hits);
        end
    catch ME
        r.Message = sprintf('Test errored: %s', ME.message);
    end
    if ~isempty(fig) && isvalid(fig), delete(fig); end
end


function tc2_dispatch(fig)
    s = getappdata(fig, 'state');
    if strcmp(s.activeSessionId, 'S001')
        s.cb1Hits = s.cb1Hits + 1;
    elseif strcmp(s.activeSessionId, 'S002')
        s.cb2Hits = s.cb2Hits + 1;
    end
    setappdata(fig, 'state', s);
end


function r = tc3_throttlePrefixIsolation()
    r = struct('Id', 'TC-3', 'Passed', false, ...
        'Message', '', 'Details', struct());
    try
        throttle = flightdash.util.Throttle.instance();
        key1 = 'TC3_S001:Slot';
        key2 = 'TC3_S002:Slot';
        try, throttle.reset(key1); catch, end
        try, throttle.reset(key2); catch, end

        h1a = throttle.hit(key1, 1, 1.0);   % first hit -> false (passes)
        h1b = throttle.hit(key1, 1, 1.0);   % immediate -> true (throttled)
        h2a = throttle.hit(key2, 1, 1.0);   % independent first hit -> false

        r.Details.S001_first  = h1a;
        r.Details.S001_second = h1b;
        r.Details.S002_first  = h2a;
        r.Passed = (h1a == false) && (h1b == true) && (h2a == false);
        if r.Passed
            r.Message = 'SessionId-prefixed throttle keys are isolated per session';
        else
            r.Message = sprintf('Unexpected: S001(%d,%d) S002(%d)', h1a, h1b, h2a);
        end
        try, throttle.reset(key1); catch, end
        try, throttle.reset(key2); catch, end
    catch ME
        r.Message = sprintf('Test errored: %s', ME.message);
    end
end
