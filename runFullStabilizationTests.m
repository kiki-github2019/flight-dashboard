function results = runFullStabilizationTests()
%RUNFULLSTABILIZATIONTESTS Run the stabilization gate suites.
%   Covers the main Studio suite, Phase 3 mouse stress tests, Phase 4
%   EventBus tests, Undo/Redo tests, and the combined Phase 3 + Phase 7
%   diagnostic.

    fprintf('==================================================\n');
    fprintf('     FlightReviewStudio FULL STABILIZATION TEST\n');
    fprintf('==================================================\n\n');

    rehash toolboxcache;

    results = struct();

    fprintf('Running main FlightReviewStudioTestSuite...\n');
    results.Main = FlightReviewStudioTestSuite();

    fprintf('\nRunning Phase 3 mouse stress/property suite...\n');
    mouseStressSuite = matlab.unittest.TestSuite.fromClass( ...
        ?flightdash.studio.FlightReviewStudioStressTests);
    results.MouseStress = run(mouseStressSuite);

    fprintf('\nRunning Phase 4 event system suite...\n');
    results.Events = runtests('eventSystemTestSuite');

    fprintf('\nRunning Undo/Redo suite...\n');
    results.UndoRedo = runtests('undoRedoTestSuite');

    fprintf('\nRunning combined Phase 3 + Phase 7 verifier...\n');
    % Stress is already run above, so skip it here to avoid duplicate cost.
    results.Combined = flightdash.studio.diag.verifyPhase3_Phase7(false);

    results.Summary = summarizeResults(results);

    fprintf('\n=== FINAL SUMMARY ===\n');
    fprintf('Passed Tests    : %d\n', results.Summary.Passed);
    fprintf('Failed Tests    : %d\n', results.Summary.Failed);
    fprintf('Incomplete Tests: %d\n', results.Summary.Incomplete);
    fprintf('Combined Overall: %s\n', passFail(results.Combined.Overall));
    fprintf('Overall         : %s\n', passFail(results.Summary.Overall));
end

function summary = summarizeResults(results)
    summary = struct('Passed', 0, 'Failed', 0, 'Incomplete', 0, 'Overall', false);

    fields = {'Main', 'MouseStress', 'Events', 'UndoRedo'};
    for k = 1:numel(fields)
        if ~isfield(results, fields{k})
            continue;
        end
        counts = countTestResults(results.(fields{k}));
        summary.Passed = summary.Passed + counts.Passed;
        summary.Failed = summary.Failed + counts.Failed;
        summary.Incomplete = summary.Incomplete + counts.Incomplete;
    end

    summary.Overall = summary.Failed == 0 && summary.Incomplete == 0 && ...
        isfield(results, 'Combined') && isfield(results.Combined, 'Overall') && ...
        logical(results.Combined.Overall);
end

function counts = countTestResults(testResults)
    counts = struct('Passed', 0, 'Failed', 0, 'Incomplete', 0);
    try
        if isstruct(testResults) && isfield(testResults, 'Status')
            statuses = string({testResults.Status});
            counts.Passed = sum(statuses == "PASS");
            counts.Failed = sum(statuses == "FAIL");
            counts.Incomplete = sum(statuses == "SKIP");
            return;
        end
        counts.Passed = sum([testResults.Passed]);
        counts.Failed = sum([testResults.Failed]);
        counts.Incomplete = sum([testResults.Incomplete]);
    catch
    end
end

function text = passFail(tf)
    if logical(tf)
        text = 'PASSED';
    else
        text = 'FAILED';
    end
end
