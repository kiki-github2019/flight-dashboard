function results = FlightReviewStudioTestSuite()
%FLIGHTREVIEWSTUDIOTESTSUITE  Canonical sequential runner for static_test.
%
%   Performs the workspace + cache cleanup commands the user requested
%   (close all force / clear all force / clear classes / rehash
%   toolboxcache) BEFORE enumerating tests, then runs
%   every canonical test function inside ./static_test/:
%     - matlab.unittest.TestCase subclass : every Test method counted
%       separately and dispatched via matlab.unittest.TestSuite.fromMethod
%     - other classdef helpers           : reported as SKIP
%     - function-style .m                : top-level function executed
%
%   Progress messages on the command window have the shape
%       [k/N] <test-function-name>  ... STATUS
%   so the user can see which test (out of how many) is currently
%   running.
%
%   Saves command-window output through MATLAB diary() to
%   Test_result_yyyymmdd_HHMMSS.log in this file's folder, then writes a
%   filtered warning/FAIL summary to Test_result_yyyymmdd_HHMMSS_with error.log.
%
%   Usage:
%     results = FlightReviewStudioTestSuite();
%
%   Returns: struct array (File, Function, Status, Detail, Error).

    here = fileparts(mfilename('fullpath'));
    stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<DATST,TNOW1>
    logPath = fullfile(here, sprintf('Test_result_%s.log', stamp));
    errorLogPath = fullfile(here, sprintf('Test_result_%s_with error.log', stamp));
    diary(logPath);
    diaryCleanup = onCleanup(@() localFinishDiaryLog(logPath, errorLogPath)); %#ok<NASGU>
    fprintf('[FlightReviewStudioTestSuite] diary log started: %s\n', logPath);

    % --- pre-test cleanup ----------------------------------------------
    %#ok<*CLALL>
    close all force;
    evalin('base', 'clear all force');
    evalin('base', 'clear classes');
    rehash toolboxcache;

    staticDir = fullfile(here, 'static_test');
    if ~isfolder(staticDir)
        warning('FlightReviewStudioTestSuite:NoStaticFolder', ...
            'static_test folder missing at %s', staticDir);
        results = repmat(localEmptyResult(), 0, 1);
        return;
    end
    addpath(here);
    addpath(staticDir);

    % --- enumerate every test entry ------------------------------------
    fprintf('\n[FlightReviewStudioTestSuite] enumerating test functions in %s ...\n', staticDir);
    entries = localBuildEntries(staticDir);
    total = numel(entries);
    fprintf('[FlightReviewStudioTestSuite] %d test function(s) discovered.\n\n', total);

    results = repmat(localEmptyResult(), total, 1);

    for k = 1:total
        e = entries(k);
        cleanupGuard = onCleanup(@() localCleanupEnvironment(e.Display));
        % Progress line: which K-th of total N + the test function name.
        fprintf('  [%d/%d] %s  ... ', k, total, e.Display);
        try
            detail = localExecuteEntry(e);
            results(k) = struct('File', e.File, 'Function', e.Display, ...
                'Status', 'PASS', 'Detail', detail, 'Error', '');
            fprintf('PASS  (%s)\n', detail);
        catch ME
            if strcmpi(ME.identifier, 'FlightReviewStudioTestSuite:Skip')
                results(k) = struct('File', e.File, 'Function', e.Display, ...
                    'Status', 'SKIP', 'Detail', ME.message, 'Error', '');
                fprintf('SKIP  (%s)\n', ME.message);
            else
                results(k) = struct('File', e.File, 'Function', e.Display, ...
                    'Status', 'FAIL', 'Detail', '', 'Error', ME.message);
                fprintf('FAIL  %s\n', ME.message);
            end
        end
        clear cleanupGuard
    end

    nPass = sum(strcmp({results.Status}, 'PASS'));
    nFail = sum(strcmp({results.Status}, 'FAIL'));
    nSkip = sum(strcmp({results.Status}, 'SKIP'));
    fprintf('\n[FlightReviewStudioTestSuite] summary: %d PASS / %d FAIL / %d SKIP (total %d)\n', ...
        nPass, nFail, nSkip, total);
end

% ---------- enumeration ----------------------------------------------------

function entries = localBuildEntries(staticDir)
    files = dir(fullfile(staticDir, '*.m'));
    entries = repmat(localEmptyEntry(), 0, 1);
    skipNames = {'runFullStabilizationTests', ...
        'runAllTestCodesWithCleanup', ...
        'run_studio_tests', ...
        'old_FlightReviewStudioCoreTestSuite', ...
        'verifyPhase3_Phase7', ...
        'verifyRiskRegressionT'};
    for k = 1:numel(files)
        relFile = files(k).name;
        [~, name, ~] = fileparts(relFile);
        if any(strcmp(name, skipNames))
            continue;
        end
        absPath = fullfile(staticDir, relFile);
        txt = fileread(absPath);
        isClass = ~isempty(regexp(txt, '^\s*classdef\b', 'once', 'lineanchors'));
        if isClass
            mc = meta.class.fromName(name);
            if isempty(mc)
                entries(end+1, 1) = localMakeEntry(relFile, name, 'function'); %#ok<AGROW>
                continue;
            end
            if localIsTestCase(mc)
                testMethods = localTestMethods(mc);
                if isempty(testMethods)
                    entries(end+1, 1) = localMakeEntry(relFile, name, 'skip-empty'); %#ok<AGROW>
                else
                    for ti = 1:numel(testMethods)
                        e = localMakeEntry(relFile, sprintf('%s/%s', name, testMethods{ti}), 'method');
                        e.Class = name;
                        e.Method = testMethods{ti};
                        entries(end+1, 1) = e; %#ok<AGROW>
                    end
                end
            else
                entries(end+1, 1) = localMakeEntry(relFile, name, 'skip-helper'); %#ok<AGROW>
            end
        else
            entries(end+1, 1) = localMakeEntry(relFile, name, 'function'); %#ok<AGROW>
        end
    end
end

function localCleanupEnvironment(~)
    try, close all force; catch, end
    try, evalin('base', 'clear all force'); catch, end
    % Do not call "clear classes" from this onCleanup callback. MATLAB can
    % still have cleanup-owned or toolbox-owned objects alive at this point,
    % which produces benign "Cannot clear this class" warnings in R2025a.
    try, rehash toolboxcache; catch, end
end

function r = localEmptyResult()
    r = struct('File', '', 'Function', '', 'Status', '', 'Detail', '', 'Error', '');
end

function e = localEmptyEntry()
    e = struct('File', '', 'Display', '', 'Kind', '', 'Class', '', 'Method', '');
end

function e = localMakeEntry(file, display, kind)
    e = localEmptyEntry();
    e.File = file; e.Display = display; e.Kind = kind;
end

function tf = localIsTestCase(mc)
    tf = false;
    try
        toScan = mc;
        seen = strings(0, 1);
        while ~isempty(toScan)
            names = arrayfun(@(s) string(s.Name), toScan);
            if any(names == "matlab.unittest.TestCase"), tf = true; return; end
            seen = [seen; names]; %#ok<AGROW>
            nextSupers = matlab.metadata.Class.empty;
            for k = 1:numel(toScan)
                nextSupers = [nextSupers; toScan(k).SuperclassList]; %#ok<AGROW>
            end
            % Drop already-seen to avoid diamond-graph loops.
            keep = true(numel(nextSupers), 1);
            for k = 1:numel(nextSupers)
                if any(seen == string(nextSupers(k).Name)), keep(k) = false; end
            end
            toScan = nextSupers(keep);
        end
    catch
    end
end

function names = localTestMethods(mc)
    names = {};
    try
        for k = 1:numel(mc.MethodList)
            m = mc.MethodList(k);
            if localMethodHasTestAttribute(m), names{end+1} = m.Name; end %#ok<AGROW>
        end
    catch
    end
end

function tf = localMethodHasTestAttribute(m)
    tf = false;
    try
        attrs = m.Test;
        tf = ~isempty(attrs) && islogical(attrs) && any(attrs);
    catch
    end
end

% ---------- dispatch ------------------------------------------------------

function detail = localExecuteEntry(e)
    switch e.Kind
        case 'method'
            r = runtests(sprintf('%s/%s', e.Class, e.Method));
            if isempty(r)
                error('FlightReviewStudioTestSuite:NoResult', ...
                    'runtests returned no result for %s', e.Display);
            end
            if all([r.Passed])
                detail = sprintf('runtests OK (%.3fs)', sum([r.Duration]));
            elseif all([r.Incomplete] | ~[r.Passed] & ~[r.Failed])
                error('FlightReviewStudioTestSuite:Skip', ...
                    'test incomplete (likely assumeFail)');
            else
                error('FlightReviewStudioTestSuite:TestCaseFailures', ...
                    'TestCase method %s failed', e.Display);
            end
        case 'function'
            fnh = str2func(e.Display);
            out = fnh();
            if isa(out, 'matlab.unittest.TestSuite')
                r = run(out);
                if isempty(r)
                    error('FlightReviewStudioTestSuite:NoResult', ...
                        'function suite returned no result for %s', e.Display);
                end
                if all([r.Passed])
                    detail = sprintf('functiontests OK (%.3fs)', sum([r.Duration]));
                elseif any([r.Failed])
                    error('FlightReviewStudioTestSuite:FunctionSuiteFailures', ...
                        'function suite %s failed', e.Display);
                else
                    error('FlightReviewStudioTestSuite:Skip', ...
                        'function suite incomplete');
                end
            else
                localFailOnVerifyStyleResult(out, e.Display);
                detail = localSummarize(out);
            end
        case {'skip-helper','skip-empty'}
            error('FlightReviewStudioTestSuite:Skip', '%s', e.Kind);
        otherwise
            error('FlightReviewStudioTestSuite:UnknownKind', ...
                'unknown entry kind: %s', e.Kind);
    end
end

function localFailOnVerifyStyleResult(out, displayName)
    try
        if isstruct(out) && isfield(out, 'Result')
            status = upper(string({out.Result}));
            if any(status == "FAIL" | status == "ERROR")
                error('FlightReviewStudioTestSuite:VerifyStyleFailures', ...
                    'verify-style function %s returned FAIL/ERROR', displayName);
            end
        end
        if isstruct(out) && isfield(out, 'Status')
            status = upper(string({out.Status}));
            if any(status == "FAIL" | status == "ERROR")
                error('FlightReviewStudioTestSuite:VerifyStyleFailures', ...
                    'verify-style function %s returned FAIL/ERROR', displayName);
            end
        end
        if isstruct(out) && isfield(out, 'Passed') && any(~logical([out.Passed]))
            error('FlightReviewStudioTestSuite:VerifyStyleFailures', ...
                'verify-style function %s returned failed Passed flag', displayName);
        end
        if isstruct(out) && isfield(out, 'Summary')
            summaries = {out.Summary};
            for i = 1:numel(summaries)
                s = summaries{i};
                if isstruct(s) && isfield(s, 'Fail') && double(s.Fail) > 0
                    error('FlightReviewStudioTestSuite:VerifyStyleFailures', ...
                        'verify-style function %s summary contains failures', displayName);
                end
            end
        end
    catch ME
        if strcmp(ME.identifier, 'FlightReviewStudioTestSuite:VerifyStyleFailures')
            rethrow(ME);
        end
    end
end

function s = localSummarize(out)
    s = '';
    try
        if isstruct(out) && isfield(out, 'Passed')
            s = sprintf('verify-style: %d/%d passed', sum([out.Passed]), numel(out));
        elseif isnumeric(out)
            s = sprintf('numeric return %s', mat2str(size(out)));
        elseif ischar(out) || isstring(out)
            s = char(out);
        else
            s = sprintf('returned %s', class(out));
        end
    catch
        s = 'completed';
    end
end

function localFinishDiaryLog(logPath, errorLogPath)
    try
        diary off;
    catch
    end
    localWriteKeywordErrorLog(logPath, errorLogPath);
end

function localWriteKeywordErrorLog(logPath, errorLogPath)
    lines = {};
    if isfile(logPath)
        try
            text = fileread(logPath);
            lines = regexp(text, '\r\n|\n|\r', 'split');
        catch ME
            lines = {sprintf('Failed to read diary log: %s', ME.message)};
        end
    else
        lines = {sprintf('Diary log file not found: %s', logPath)};
    end

    match = false(size(lines));
    for k = 1:numel(lines)
        line = lines{k};
        match(k) = ~isempty(regexpi(line, 'warning', 'once')) || ...
            ~isempty(regexp(line, 'FAIL', 'once'));
    end

    selected = false(size(lines));
    matchIdx = find(match);
    for i = 1:numel(matchIdx)
        idx = matchIdx(i);
        from = max(1, idx - 1);
        to = min(numel(lines), idx + 6);
        selected(from:to) = true;
    end

    fid = fopen(errorLogPath, 'w', 'n', 'UTF-8');
    if fid == -1
        warning('FlightReviewStudioTestSuite:ErrorLogOpenFailed', ...
            'Cannot open %s for writing', errorLogPath);
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'Source log: %s\n', logPath);
    fprintf(fid, 'Keywords: warning, FAIL\n\n');
    if isempty(matchIdx)
        fprintf(fid, 'No warning or FAIL entries found.\n');
    else
        fprintf(fid, 'Matched section count: %d\n\n', numel(matchIdx));
        lastWasGap = true;
        for k = 1:numel(lines)
            if selected(k)
                if lastWasGap
                    fprintf(fid, '---\n');
                    lastWasGap = false;
                end
                fprintf(fid, '%s\n', lines{k});
            else
                lastWasGap = true;
            end
        end
    end
end
