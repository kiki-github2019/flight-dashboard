function results = FlightReviewStudioTestSuite()
%FLIGHTREVIEWSTUDIOTESTSUITE  Sequential runner for static_test/*.m files.
%
%   Performs the workspace + cache cleanup commands the user requested
%   (close all force / clear all force / clear classes / rehash
%   toolboxcache) BEFORE invoking any test, then iterates every .m file
%   under ./static_test/ and runs it:
%     - classdef matlab.unittest.TestCase  -> runtests(name)
%     - other classdef helpers             -> skipped (treated as PASS)
%     - function-style .m                  -> str2func(name)() invocation
%
%   On any failure, writes a Claude-Code / ChatGPT-Cowork follow-up
%   prompt to a UTF-8 .txt file, then renames it to .log so Notepad
%   opens it without a file-type prompt.
%
%   Usage:
%     results = FlightReviewStudioTestSuite();
%
%   Returns: struct array (File, Status, Detail, Error).

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
        results = repmat(struct('File','','Status','','Detail','','Error',''), 0, 1);
        return;
    end
    addpath(staticDir);

    files = dir(fullfile(staticDir, '*.m'));
    nFiles = numel(files);
    results = repmat(struct('File','','Status','','Detail','','Error',''), nFiles, 1);
    failures = repmat(struct('file','','name','','identifier','','message','','stack',''), 0, 1);

    fprintf('\n[FlightReviewStudioTestSuite] running %d static_test file(s)\n', nFiles);
    for k = 1:nFiles
        relFile = files(k).name;
        [~, name, ~] = fileparts(relFile);
        fprintf('  %2d/%2d  %s ... ', k, nFiles, relFile);
        try
            detail = localExecuteOne(fullfile(staticDir, relFile), name);
            results(k) = struct('File', relFile, 'Status', 'PASS', 'Detail', detail, 'Error', '');
            fprintf('PASS  (%s)\n', detail);
        catch ME
            results(k) = struct('File', relFile, 'Status', 'FAIL', 'Detail', '', 'Error', ME.message);
            failures(end+1, 1) = struct( ...
                'file', relFile, 'name', name, ...
                'identifier', ME.identifier, 'message', ME.message, ...
                'stack', localStackString(ME.stack)); %#ok<AGROW>
            fprintf('FAIL  %s\n', ME.message);
        end
    end

    nPass = sum(strcmp({results.Status}, 'PASS'));
    nFail = sum(strcmp({results.Status}, 'FAIL'));
    fprintf('\n[FlightReviewStudioTestSuite] summary: %d PASS / %d FAIL\n', nPass, nFail);

    if ~isempty(failures)
        logPath = localWriteFailureLog(here, failures);
        fprintf('[FlightReviewStudioTestSuite] failure log written: %s\n', logPath);
    end
end

% ---------- helpers --------------------------------------------------------

function detail = localExecuteOne(absPath, name)
    txt = fileread(absPath);
    isClass = ~isempty(regexp(txt, '^\s*classdef\b', 'once', 'lineanchors'));
    if isClass
        mc = meta.class.fromName(name);
        if isempty(mc)
            error('FlightReviewStudioTestSuite:ClassNotFound', ...
                'Cannot resolve metaclass for %s', name);
        end
        if localIsTestCase(mc)
            r = runtests(name);
            passCount = sum([r.Passed]);
            failCount = sum(~[r.Passed]);
            detail = sprintf('runtests: %d pass / %d fail / %d total', ...
                passCount, failCount, numel(r));
            if failCount > 0
                failedNames = arrayfun(@(t) string(t.Name), r(~[r.Passed]));
                error('FlightReviewStudioTestSuite:TestCaseFailures', ...
                    'TestCase %s failed: %s', name, strjoin(failedNames, ', '));
            end
        else
            detail = 'classdef helper — skipped';
        end
        return;
    end
    % Function file — invoke the top-level function once.
    fnh = str2func(name);
    out = fnh();
    detail = localSummarize(out);
end

function tf = localIsTestCase(mc)
    tf = false;
    try
        supers = mc.SuperclassList;
        while ~isempty(supers)
            names = arrayfun(@(s) string(s.Name), supers);
            if any(names == "matlab.unittest.TestCase"), tf = true; return; end
            nextSupers = matlab.metadata.Class.empty;
            for k = 1:numel(supers)
                nextSupers = [nextSupers; supers(k).SuperclassList]; %#ok<AGROW>
            end
            supers = nextSupers;
        end
    catch
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
        'following static_test files failed. Please diagnose and ' ...
        'propose minimal-risk fixes (no broad refactor). Preserve ' ...
        'adapter-based controller behavior and MATLAB R2025a/R2026a + ' ...
        'MATLAB Online compatibility. Then run runtests again to ' ...
        'verify.\n\n']);
    fprintf(fid, 'Failures (%d):\n', numel(failures));
    for k = 1:numel(failures)
        f = failures(k);
        fprintf(fid, '\n[%d] %s (function: %s)\n', k, f.file, f.name);
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
