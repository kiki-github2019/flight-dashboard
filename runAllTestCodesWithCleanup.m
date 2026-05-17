function results = runAllTestCodesWithCleanup()
%RUNALLTESTCODESWITHCLEANUP Run every stabilization test entry with reset.
%   This runner executes test-suite elements one by one. After every test
%   function/test method/diagnostic function completes, it runs exactly the
%   requested cleanup sequence in the base workspace:
%
%       clear all force
%       clear classes
%       close all force
%       rehash toolboxcache
%
%   Wrapper runners such as run_studio_tests.m and runFullStabilizationTests.m
%   are not called here to avoid duplicate batches without per-function reset.

    clc;
    rootDir = fileparts(mfilename('fullpath'));
    if isempty(rootDir)
        rootDir = pwd;
    end
    addpath(rootDir);
    staticDir = fullfile(rootDir, 'static_test');
    if ~isfolder(staticDir)
        staticDir = rootDir;
    end
    addpath(staticDir);
    rehashToolboxcacheQuietly('startup');

    fprintf('==================================================\n');
    fprintf('  FlightReviewStudio ALL TEST CODES WITH CLEANUP\n');
    fprintf('==================================================\n\n');

    warningCleanup = suppressPathConflictWarnings(); %#ok<NASGU>
    entries = {};

    entries = appendEntries(entries, runSuiteElements( ...
        'old_FlightReviewStudioCoreTestSuite', ...
        @() matlab.unittest.TestSuite.fromClass(?old_FlightReviewStudioCoreTestSuite)));

    entries = appendEntries(entries, runSuiteElements( ...
        'FlightReviewStudioStressTests', ...
        @() matlab.unittest.TestSuite.fromClass(?flightdash.studio.FlightReviewStudioStressTests)));

    entries = appendEntries(entries, runSuiteElements( ...
        'eventSystemTestSuite', ...
        @() matlab.unittest.TestSuite.fromFile(fullfile(rootDir, 'eventSystemTestSuite.m'))));

    entries = appendEntries(entries, runSuiteElements( ...
        'undoRedoTestSuite', ...
        @() matlab.unittest.TestSuite.fromFile(fullfile(rootDir, 'undoRedoTestSuite.m'))));

    diagnostics = {
        'verifyPhase0_5',       @() flightdash.studio.diag.verifyPhase0_5()
        'verifyPhase1',         @() flightdash.studio.diag.verifyPhase1()
        'verifyPhase2',         @() flightdash.studio.diag.verifyPhase2()
        'verifyPhase3',         @() flightdash.studio.diag.verifyPhase3()
        'verifyPhase4',         @() flightdash.studio.diag.verifyPhase4()
        'verifyPhase5',         @() flightdash.studio.diag.verifyPhase5()
        'verifyPhase6',         @() flightdash.studio.diag.verifyPhase6()
        'verifyPhase7',         @() flightdash.studio.diag.verifyPhase7()
        'verifyPhase8',         @() flightdash.studio.diag.verifyPhase8()
        'verifyPhase9',         @() flightdash.studio.diag.verifyPhase9()
        'verifyPhase10',        @() flightdash.studio.diag.verifyPhase10()
        'verifyPhase3_Phase7',  @() flightdash.studio.diag.verifyPhase3_Phase7(false)
        'runMultiInstanceTests', @() flightdash.studio.diag.runMultiInstanceTests()
        };

    for k = 1:size(diagnostics, 1)
        entries{end+1} = runEntry(diagnostics{k, 1}, 'diagnostic', diagnostics{k, 2}); %#ok<AGROW>
    end

    results = struct();
    results.Entries = entries;
    results.Summary = summarizeEntries(entries);

    fprintf('\n=== ALL TEST CODES SUMMARY ===\n');
    fprintf('Entries     : %d\n', results.Summary.TotalEntries);
    fprintf('Passed      : %d\n', results.Summary.PassedEntries);
    fprintf('Failed      : %d\n', results.Summary.FailedEntries);
    fprintf('Incomplete  : %d\n', results.Summary.IncompleteEntries);
    fprintf('Overall     : %s\n', passFail(results.Summary.Overall));
end

function entries = runSuiteElements(groupName, suiteFactory)
    entries = {};
    try
        suite = suiteFactory();
        names = string({suite.Name});
    catch ME
        entries{1} = failedEntry(groupName, 'suite-discovery', ME);
        fprintf('FAILED suite discovery for %s: %s\n', groupName, ME.message);
        cleanupEnvironment(groupName);
        return;
    end

    for k = 1:numel(names)
        entries{end+1} = runEntry(char(names(k)), groupName, ... %#ok<AGROW>
            @() runSingleSuiteElement(suiteFactory, names(k)));
    end
end

function testResults = runSingleSuiteElement(suiteFactory, testName)
    suite = suiteFactory();
    names = string({suite.Name});
    idx = find(names == string(testName), 1, 'first');
    if isempty(idx)
        error('FlightDashboard:TestRunner:MissingTest', ...
            'Could not find test element "%s".', char(testName));
    end
    testResults = run(suite(idx));
end

function entry = runEntry(name, kind, fn)
    fprintf('\n--- RUN: %s [%s] ---\n', name, kind);
    t = tic;
    out = [];
    try
        out = fn();
        entry = summarizeOutput(name, kind, out, toc(t));
    catch ME
        entry = failedEntry(name, kind, ME);
        entry.DurationSeconds = toc(t);
        fprintf('FAILED: %s\n', ME.message);
    end

    out = []; %#ok<NASGU>
    cleanupEnvironment(name);
end

function entry = summarizeOutput(name, kind, out, durationSeconds)
    entry = baseEntry(name, kind);
    entry.DurationSeconds = durationSeconds;

    if isa(out, 'matlab.unittest.TestResult')
        entry.Total = numel(out);
        entry.Passed = sum([out.Passed]);
        entry.Failed = sum([out.Failed]);
        entry.Incomplete = sum([out.Incomplete]);
        entry.Overall = entry.Failed == 0 && entry.Incomplete == 0;
        return;
    end

    entry.Total = 1;
    entry.Passed = double(diagnosticPassed(out));
    entry.Failed = double(~logical(entry.Passed));
    entry.Incomplete = 0;
    entry.Overall = logical(entry.Passed);
end

function tf = diagnosticPassed(out)
    tf = false;
    try
        if isstruct(out) && isfield(out, 'Overall')
            tf = logical(out.Overall);
            return;
        end
        if isstruct(out) && isfield(out, 'Result')
            values = upper(string({out.Result}));
            tf = ~any(values == "FAIL") && ~any(values == "ERROR");
            return;
        end
        if isstruct(out) && isfield(out, 'Status')
            values = upper(string({out.Status}));
            tf = ~any(values == "FAIL") && ~any(values == "ERROR");
            return;
        end
        if isstruct(out) && isfield(out, 'Passed')
            tf = all([out.Passed]);
            return;
        end
        if istable(out)
            names = string(out.Properties.VariableNames);
            if any(names == "Result")
                values = upper(string(out.Result));
                tf = ~any(values == "FAIL") && ~any(values == "ERROR");
                return;
            end
            if any(names == "Status")
                values = upper(string(out.Status));
                tf = ~any(values == "FAIL") && ~any(values == "ERROR");
                return;
            end
        end
        if islogical(out) || isnumeric(out)
            tf = logical(out);
            return;
        end
        tf = true;
    catch
        tf = false;
    end
end

function entry = failedEntry(name, kind, ME)
    entry = baseEntry(name, kind);
    entry.Total = 1;
    entry.Passed = 0;
    entry.Failed = 1;
    entry.Incomplete = 0;
    entry.Overall = false;
    entry.ErrorIdentifier = ME.identifier;
    entry.ErrorMessage = ME.message;
end

function entry = baseEntry(name, kind)
    entry = struct( ...
        'Name', char(name), ...
        'Kind', char(kind), ...
        'Total', 0, ...
        'Passed', 0, ...
        'Failed', 0, ...
        'Incomplete', 0, ...
        'Overall', false, ...
        'DurationSeconds', 0, ...
        'ErrorIdentifier', '', ...
        'ErrorMessage', '');
end

function summary = summarizeEntries(entries)
    summary = struct( ...
        'TotalEntries', numel(entries), ...
        'PassedEntries', 0, ...
        'FailedEntries', 0, ...
        'IncompleteEntries', 0, ...
        'Overall', false);

    for k = 1:numel(entries)
        entry = entries{k};
        if entry.Overall
            summary.PassedEntries = summary.PassedEntries + 1;
        elseif entry.Incomplete > 0
            summary.IncompleteEntries = summary.IncompleteEntries + 1;
        else
            summary.FailedEntries = summary.FailedEntries + 1;
        end
    end
    summary.Overall = summary.FailedEntries == 0 && summary.IncompleteEntries == 0;
end

function cleanupEnvironment(label)
    fprintf('--- CLEANUP after %s ---\n', char(label));
    try
        evalin('base', 'clear all force');
    catch ME
        warning('FlightDashboard:TestCleanup:ClearAllForce', ...
            'clear all force failed after %s: %s', char(label), ME.message);
    end
    try
        evalin('base', 'clear classes');
    catch ME
        warning('FlightDashboard:TestCleanup:ClearClasses', ...
            'clear classes failed after %s: %s', char(label), ME.message);
    end
    try
        evalin('base', 'close all force');
    catch ME
        warning('FlightDashboard:TestCleanup:CloseAllForce', ...
            'close all force failed after %s: %s', char(label), ME.message);
    end
    try
        rehashToolboxcacheQuietly(label);
    catch ME
        warning('FlightDashboard:TestCleanup:RehashToolboxcache', ...
            'rehash toolboxcache failed after %s: %s', char(label), ME.message);
    end
end

function rehashToolboxcacheQuietly(~)
    % MATLAB Online can warn repeatedly when a user-path function shadows
    % a builtin such as license(). Keep the required rehash while avoiding
    % one duplicate warning per test entry.
    warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
    warnState2 = warning('off', 'MATLAB:dispatcher:ShadowedMFile');
    restoreWarning = onCleanup(@() restoreWarnings(warnState, warnState2)); %#ok<NASGU>
    evalin('base', 'rehash toolboxcache');
end

function cleanupObj = suppressPathConflictWarnings()
    warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
    warnState2 = warning('off', 'MATLAB:dispatcher:ShadowedMFile');
    cleanupObj = onCleanup(@() restoreWarnings(warnState, warnState2));
end

function restoreWarnings(varargin)
    for k = 1:nargin
        try
            warning(varargin{k});
        catch
        end
    end
end

function entries = appendEntries(entries, newEntries)
    for k = 1:numel(newEntries)
        entries{end+1} = newEntries{k}; %#ok<AGROW>
    end
end

function text = passFail(tf)
    if logical(tf)
        text = 'PASSED';
    else
        text = 'FAILED';
    end
end
