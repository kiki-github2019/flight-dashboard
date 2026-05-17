function results = verifyPhase3_Phase7(includeStress)
%VERIFYPHASE3_PHASE7 Combined Phase 3 mouse + Phase 7 result verification.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase3_Phase7();
%   results = flightdash.studio.diag.verifyPhase3_Phase7(false); % skip stress

    if nargin < 1 || isempty(includeStress)
        includeStress = true;
    end
    includeStress = logical(includeStress);

    fprintf('\n=== Phase 3 + Phase 7 verification ===\n\n');

    results = struct( ...
        'Phase3', [], ...
        'Phase7', [], ...
        'Stress', [], ...
        'Summary', struct( ...
            'Phase3Passed', false, ...
            'Phase7Passed', false, ...
            'StressPassed', ~includeStress, ...
            'IncludeStress', includeStress), ...
        'Overall', false, ...
        'Error', '');

    try
        fprintf('Running Phase 3 embedded/mouse diagnostics...\n');
        results.Phase3 = flightdash.studio.diag.verifyPhase3();
        results.Summary.Phase3Passed = allPassed(results.Phase3);

        fprintf('\nRunning Phase 7 minimal ROI result diagnostics...\n');
        results.Phase7 = flightdash.studio.diag.verifyPhase7();
        results.Summary.Phase7Passed = allPassed(results.Phase7);

        if includeStress
            fprintf('\nRunning Phase 3 mouse stress/property tests...\n');
            suite = matlab.unittest.TestSuite.fromClass( ...
                ?flightdash.studio.FlightReviewStudioStressTests);
            results.Stress = run(suite);
            results.Summary.StressPassed = allPassed(results.Stress);
        end

        results.Overall = results.Summary.Phase3Passed && ...
            results.Summary.Phase7Passed && results.Summary.StressPassed;

        if results.Overall
            fprintf('\n=== Phase 3 + Phase 7 verification PASSED ===\n');
        else
            fprintf('\n=== Phase 3 + Phase 7 verification FAILED ===\n');
            fprintf('Phase3Passed=%d Phase7Passed=%d StressPassed=%d\n', ...
                results.Summary.Phase3Passed, ...
                results.Summary.Phase7Passed, ...
                results.Summary.StressPassed);
        end
    catch ME
        results.Overall = false;
        results.Error = ME.message;
        fprintf('\n=== Phase 3 + Phase 7 verification ERRORED ===\n%s\n', ME.message);
        try
            flightdash.util.ErrorLog.log(ME, 'verifyPhase3_Phase7', false);
        catch
        end
    end
end

function tf = allPassed(phaseResults)
    tf = false;
    try
        if isempty(phaseResults)
            return;
        end
        if istable(phaseResults)
            if any(strcmpi(phaseResults.Properties.VariableNames, 'Result'))
                values = string(phaseResults.Result);
            elseif any(strcmpi(phaseResults.Properties.VariableNames, 'Status'))
                values = string(phaseResults.Status);
            else
                return;
            end
        elseif isstruct(phaseResults)
            if isfield(phaseResults, 'Result')
                values = string({phaseResults.Result});
            elseif isfield(phaseResults, 'Status')
                values = string({phaseResults.Status});
            else
                return;
            end
        elseif isobject(phaseResults)
            try
                passed = [phaseResults.Passed];
                failed = [phaseResults.Failed];
                incomplete = [phaseResults.Incomplete];
                tf = all(passed) && ~any(failed) && ~any(incomplete);
                return;
            catch
                return;
            end
        else
            return;
        end
        tf = ~any(upper(values) == "FAIL") && ~any(upper(values) == "ERROR");
    catch
        tf = false;
    end
end
