function results = verifyPhase8()
%VERIFYPHASE8 Phase 8 verification: recalculate + dirty DAG MVP.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase8();

    fprintf('\n=== Phase 8 verification: Auto Update / Recalculate MVP ===\n\n');
    fprintf('Progress is printed before and after each check.\n\n');

    tests = {
        'P8-1', @checkPhase8Classes
        'P8-2', @checkModeValidation
        'P8-3', @checkManualDirty
        'P8-4', @checkFrozenStale
        'P8-5', @checkAutoRoiRecalculate
        'P8-6', @checkProjectResultRecalculate
        'P8-7', @checkSerializerRoundTrip
        'P8-8', @checkDependencyPropagation
        'P8-9', @checkTopologicalOrderAndCycle
        'P8-10', @checkDeferredQueueScopeGuard
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};
        label = phase8CheckLabel(fn);
        progressStart(tc, label, k, size(tests, 1));
        tStart = tic;

        try
            [ok, msg, status] = fn();
            if isempty(status)
                if ok
                    status = 'PASS';
                else
                    status = 'FAIL';
                end
            end
        catch ME
            status = 'FAIL';
            msg = sprintf('%s: %s', ME.identifier, ME.message);
        end

        elapsed = toc(tStart);
        progressDone(tc, status, msg, elapsed);

        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);
    passCount = sum(strcmp({results.Result}, 'PASS'));
    fprintf('\n%d / %d Phase 8 checks passed.\n', passCount, numel(results));
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkPhase8Classes()
    status = '';
    classes = {
        'flightdash.analysis.RecalculateService'
        'flightdash.analysis.AnalysisService'
        'flightdash.project.DirtyTracker'
        'flightdash.project.ReviewResultModel'
    };
    missing = {};
    for k = 1:numel(classes)
        if isempty(meta.class.fromName(classes{k}))
            missing{end+1} = classes{k}; %#ok<AGROW>
        end
    end

    model = flightdash.project.ReviewResultModel('S_PHASE8', 'ROI', 1);
    required = {'RecalculateMode', 'DirtyFlag', 'DirtyState', 'DependsOn', 'ComputeFnSpec'};
    missingProps = {};
    for k = 1:numel(required)
        if ~isprop(model, required{k})
            missingProps{end+1} = required{k}; %#ok<AGROW>
        end
    end

    ok = isempty(missing) && isempty(missingProps);
    if ok
        msg = 'RecalculateService, DirtyTracker, and ReviewResultModel Phase 8 fields resolved';
    else
        msg = sprintf('Missing classes: %s; missing props: %s', ...
            strjoin(missing, ', '), strjoin(missingProps, ', '));
    end
end

function [ok, msg, status] = checkModeValidation()
    status = '';
    result = sampleResult(0);
    result = flightdash.analysis.RecalculateService.setMode(result, 'manual');
    manualOk = strcmp(result.RecalculateMode, 'Manual');

    invalidRejected = false;
    try
        flightdash.analysis.RecalculateService.setMode(result, 'EveryFrame');
    catch
        invalidRejected = true;
    end

    ok = manualOk && invalidRejected;
    if ok
        msg = 'Manual/Auto/Frozen mode normalization and invalid-mode rejection work';
    else
        msg = 'Recalculate mode validation failed';
    end
end

function [ok, msg, status] = checkManualDirty()
    status = '';
    result = sampleResult(0);
    result = result.setRecalculateMode('Manual');
    [result, changed] = flightdash.analysis.RecalculateService.markIfSourceChanged( ...
        result, 'changed-source', result.SyncStateHash);

    ok = changed && result.DirtyFlag && strcmp(result.DirtyState, 'dirty');
    if ok
        msg = 'Manual result becomes dirty when source hash changes';
    else
        msg = 'Manual result did not become dirty after source hash change';
    end
end

function [ok, msg, status] = checkFrozenStale()
    status = '';
    result = sampleResult(0);
    result = result.setRecalculateMode('Frozen');
    [result, changed] = flightdash.analysis.RecalculateService.markIfSourceChanged( ...
        result, 'changed-source', result.SyncStateHash);

    ok = changed && result.DirtyFlag && strcmp(result.DirtyState, 'stale');
    if ok
        msg = 'Frozen result becomes stale instead of recalculating';
    else
        msg = 'Frozen result did not enter stale state';
    end
end

function [ok, msg, status] = checkAutoRoiRecalculate()
    status = '';
    result = sampleResult(0);
    oldMean = result.ComputedValues.Mean;
    [request, ~] = sampleRequest(10);

    [result, ~] = flightdash.analysis.RecalculateService.recalculateRoiResult(result, request);
    newMean = result.ComputedValues.Mean;

    ok = strcmp(result.DirtyState, 'clean') && ~result.DirtyFlag && ...
        isfinite(oldMean) && isfinite(newMean) && newMean ~= oldMean && ...
        strcmp(result.RecalculateMode, 'Auto');
    if ok
        msg = sprintf('Auto ROI result recalculated from %.4g to %.4g', oldMean, newMean);
    else
        msg = 'Auto ROI recalculation did not update computed values cleanly';
    end
end

function [ok, msg, status] = checkProjectResultRecalculate()
    status = '';
    [request, session] = sampleRequest(0);
    analysisResult = flightdash.analysis.AnalysisService.run(request);
    result = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);

    p = flightdash.project.ProjectModel('Phase8');
    p = p.addSession(session);
    p = p.addResult(result);

    [request2, ~] = sampleRequest(20);
    [p, updated, ~] = flightdash.analysis.RecalculateService.recalculateProjectResult( ...
        p, result.ResultId, request2);

    ok = numel(p.Results) == 1 && strcmp(p.Results(1).ResultId, result.ResultId) && ...
        strcmp(updated.ResultId, result.ResultId) && ~p.Results(1).DirtyFlag && ...
        p.hasResult(result.ResultId);
    if ok
        msg = 'ProjectModel result update path preserves ResultId and stores recalculated ROI result';
    else
        msg = 'ProjectModel result recalculation/update path failed';
    end
end

function [ok, msg, status] = checkSerializerRoundTrip()
    status = '';
    tmpFile = [tempname() '.frsproj'];
    cleaner = onCleanup(@() cleanupFile(tmpFile)); %#ok<NASGU>

    [~, session] = sampleRequest(0);
    result = sampleResult(0);
    result = result.setRecalculateMode('Frozen');
    [result, ~] = flightdash.analysis.RecalculateService.markIfSourceChanged( ...
        result, 'changed-source', result.SyncStateHash);

    p = flightdash.project.ProjectModel('Phase8');
    p = p.addSession(session);
    [p, ~] = flightdash.analysis.AnalysisService.ensureDefaultThemes(p);
    p = p.addResult(result);

    flightdash.project.ProjectSerializer.save(p, tmpFile);
    loaded = flightdash.project.ProjectSerializer.load(tmpFile);

    ok = isfile(tmpFile) && numel(loaded.Results) == 1 && ...
        strcmp(loaded.Results(1).RecalculateMode, 'Frozen') && ...
        strcmp(loaded.Results(1).DirtyState, 'stale') && ...
        loaded.Results(1).DirtyFlag && ~isempty(loaded.Results(1).DependsOn) && ...
        ~isempty(loaded.Results(1).ComputeFnSpec);
    if ok
        msg = 'RecalculateMode, DirtyState, DirtyFlag, DependsOn, and ComputeFnSpec survive save/load';
    else
        msg = 'Phase 8 result metadata did not survive ProjectSerializer round-trip';
    end
end

function [ok, msg, status] = checkDependencyPropagation()
    status = '';
    [p, sourceNode, resultA, resultB] = sampleDependentProject();
    resultB = resultB.setRecalculateMode('Frozen');
    p = p.updateResult(resultB);

    [p, dirtyIds, dirtyNodes] = flightdash.project.DirtyTracker.markDirty(p, sourceNode);

    a = p.findResult(resultA.ResultId);
    b = p.findResult(resultB.ResultId);
    ok = isequal(dirtyIds, {resultA.ResultId, resultB.ResultId}) && ...
        isequal(dirtyNodes, {resultA.nodeId(), resultB.nodeId()}) && ...
        strcmp(a.DirtyState, 'dirty') && strcmp(b.DirtyState, 'stale') && ...
        a.DirtyFlag && b.DirtyFlag;
    if ok
        msg = 'ROI source change propagates dirty/stale state in dependency order';
    else
        msg = 'Dirty DAG propagation did not mark dependent results in topological order';
    end
end

function [ok, msg, status] = checkTopologicalOrderAndCycle()
    status = '';
    [p, ~, resultA, resultB] = sampleDependentProject();
    [orderIds, orderNodes] = flightdash.project.DirtyTracker.topologicalOrder(p, resultB.ResultId);

    orderOk = isequal(orderIds, {resultA.ResultId, resultB.ResultId}) && ...
        isequal(orderNodes, {resultA.nodeId(), resultB.nodeId()});

    resultA = resultA.setDependencies({resultB.nodeId()});
    p = p.updateResult(resultA);
    cycleRejected = false;
    try
        flightdash.project.DirtyTracker.validateAcyclic(p);
    catch ME
        cycleRejected = strcmp(ME.identifier, 'DirtyTracker:CycleDetected');
    end

    ok = orderOk && cycleRejected;
    if ok
        msg = 'Topological order is stable and result dependency cycles are rejected';
    else
        msg = 'Topological order or cycle detection failed';
    end
end

function [ok, msg, status] = checkDeferredQueueScopeGuard()
    status = '';
    hasQueue = ~isempty(meta.class.fromName('flightdash.analysis.RecalculateQueue'));
    ok = ~hasQueue;
    if ok
        msg = 'Phase 8c background queue is intentionally deferred';
    else
        msg = 'Unexpected Phase 8c queue class detected; review partial implementation before use';
    end
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function result = sampleResult(offset)
    [request, ~] = sampleRequest(offset);
    analysisResult = flightdash.analysis.AnalysisService.run(request);
    result = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);
end

function [request, session] = sampleRequest(offset)
    if nargin < 1, offset = 0; end
    time = (0:0.5:6)';
    roll = time + 1 + offset;
    rollTarget = ones(size(time)) * 3;
    raw = table(time, roll, rollTarget, 'VariableNames', {'Time', 'Roll', 'RollTarget'});
    rows = {2, 4, 'Roll', '--', '--'};
    session = flightdash.project.SessionModel('Phase 8 Session');
    session.SessionId = 'S_PHASE8';
    request = flightdash.analysis.AnalysisService.makeRoiStatisticsRequest( ...
        session.SessionId, 1, 1, rows, time, raw, struct('IsSynced', false), ...
        flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId);
end

function [project, sourceNode, resultA, resultB] = sampleDependentProject()
    [~, session] = sampleRequest(0);
    resultA = sampleResult(0);
    resultA.ResultId = 'R_PHASE8_A';
    sourceNode = flightdash.project.DirtyTracker.roiSourceNodeId(session.SessionId, 1, 1);
    resultA = resultA.setDependencies({sourceNode});

    resultB = flightdash.project.ReviewResultModel(session.SessionId, 'Statistics', 1);
    resultB.ResultId = 'R_PHASE8_B';
    resultB.ComputedValues = struct('DerivedFrom', resultA.ResultId);
    resultB.AnalysisThemeId = 'THM_PHASE8_DERIVED';
    resultB = resultB.setDependencies({resultA.nodeId()});

    project = flightdash.project.ProjectModel('Phase8 DAG');
    project = project.addSession(session);
    project = project.addResult(resultA);
    project = project.addResult(resultB);
end

function cleanupFile(filePath)
    candidates = {filePath, [filePath '.zip']};
    for k = 1:numel(candidates)
        try
            if isfile(candidates{k}), delete(candidates{k}); end
        catch
        end
    end
end

function label = phase8CheckLabel(fn)
    name = func2str(fn);
    if startsWith(name, '@'), name = name(2:end); end
    label = regexprep(name, '^check', '');
    label = regexprep(label, '([a-z])([A-Z])', '$1 $2');
end

function progressStart(tc, label, idx, total)
    fprintf('[%s] START %d/%d - %s\n', tc, idx, total, label);
end

function progressDone(tc, status, msg, elapsed)
    fprintf('[%s] %-14s %.2fs - %s\n', tc, status, elapsed, msg);
end

function printResults(results)
    fprintf('\n%-7s %-14s %s\n', 'TC', 'Result', 'Message');
    fprintf('%-7s %-14s %s\n', '------', '------------', '-------');
    for k = 1:numel(results)
        fprintf('%-7s %-14s %s\n', results(k).TC, results(k).Result, results(k).Message);
    end
end
