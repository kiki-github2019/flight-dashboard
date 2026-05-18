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
%   On any failure, writes a Claude-Code / ChatGPT-Cowork follow-up
%   prompt to a UTF-8 .txt file, then renames it to .log so Notepad
%   opens it without a file-type prompt.
%
%   Usage:
%     results = FlightReviewStudioTestSuite();
%
%   Returns: struct array (File, Function, Status, Detail, Error).

    % --- pre-test cleanup ----------------------------------------------
    %#ok<*CLALL>
    close all force;
    evalin('base', 'clear all force');
    evalin('base', 'clear classes');
    rehash toolboxcache;

    here = fileparts(mfilename('fullpath'));
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
    failures = repmat(struct('file','','name','','identifier','','message','','stack',''), 0, 1);

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
                failures(end+1, 1) = struct( ...
                    'file', e.File, 'name', e.Display, ...
                    'identifier', ME.identifier, 'message', ME.message, ...
                    'stack', localStackString(ME.stack)); %#ok<AGROW>
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

    if ~isempty(failures)
        logPath = localWriteFailureLog(here, failures);
        fprintf('[FlightReviewStudioTestSuite] failure log written: %s\n', logPath);
    end
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
                detail = localSummarize(out);
            end
        case {'skip-helper','skip-empty'}
            error('FlightReviewStudioTestSuite:Skip', '%s', e.Kind);
        otherwise
            error('FlightReviewStudioTestSuite:UnknownKind', ...
                'unknown entry kind: %s', e.Kind);
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

function s = localStackString(stack)
    s = '';
    try
        n = min(numel(stack), 6);
        lines = cell(n, 1);
        for k = 1:n
            lines{k} = sprintf('  %s (%s:%d)', stack(k).name, ...
                stack(k).file, stack(k).line);
        end
        s = strjoin(lines, char(10));
    catch
    end
end

function logPath = localWriteFailureLog(rootDir, failures)
    % Compose a Claude Code / ChatGPT Cowork follow-up prompt and
    % write it as a UTF-8 .txt file, then rename to .log so Notepad
    % opens it directly (no file-type chooser prompt).
    stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<DATST,TNOW1>
    txtPath = fullfile(rootDir, sprintf('static_test_failures_%s.txt', stamp));
    logPath = fullfile(rootDir, sprintf('static_test_failures_%s.log', stamp));
    fid = fopen(txtPath, 'w', 'n', 'UTF-8');
    if fid == -1
        logPath = '';
        warning('FlightReviewStudioTestSuite:LogOpenFailed', ...
            'Cannot open %s for writing', txtPath);
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, ['You are continuing a Claude Code / ChatGPT Cowork session ' ...
        'on the MATLAB repo D:\\flightdashboard\\5. 4th\\root.\n\n']);
    fprintf(fid, ['FlightReviewStudioTestSuite just ran and the ' ...
        'following static_test entries failed. Please diagnose and ' ...
        'propose minimal-risk fixes (no broad refactor). Preserve ' ...
        'adapter-based controller behavior and MATLAB R2025a/R2026a + ' ...
        'MATLAB Online compatibility. Then run runtests again to ' ...
        'verify.\n\n']);
    fprintf(fid, 'Failures (%d):\n', numel(failures));
    for k = 1:numel(failures)
        f = failures(k);
        fprintf(fid, '\n[%d] file=%s function=%s\n', k, f.file, f.name);
        if ~isempty(f.identifier)
            fprintf(fid, '    identifier : %s\n', f.identifier);
        end
        fprintf(fid, '    message    : %s\n', f.message);
        if ~isempty(f.stack)
            fprintf(fid, '    stack:\n%s\n', f.stack);
        end
    end
    fprintf(fid, '\nFiles to consult:\n');
    fprintf(fid, '  - FlightReviewStudioTestSuite.m (runner)\n');
    fprintf(fid, '  - static_test\\ (test files)\n');
    fprintf(fid, '  - docs\\architecture.md (architecture snapshot)\n');
    fprintf(fid, '\nWhen done, commit with a timestamped subject:\n');
    fprintf(fid, '  fix(test): repair static_test failures @YYYY-MM-DD HH:MM:SS\n');
    clear cleaner;
    % .txt -> .log so Notepad opens it directly.
    try
        if isfile(logPath), delete(logPath); end
        movefile(txtPath, logPath);
    catch
        logPath = txtPath;
    end
end
