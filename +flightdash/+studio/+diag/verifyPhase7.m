function results = verifyPhase7()
%VERIFYPHASE7 Phase 7 verification: AnalysisService / ROI result model.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase7();

    fprintf('\n=== Phase 7 verification: Analysis Service / ROI Results ===\n\n');
    fprintf('Progress is printed before and after each check.\n\n');

    tests = {
        'P7-1', @checkPhase7Classes
        'P7-2', @checkDefaultTheme
        'P7-3', @checkSingleRoiAnalysis
        'P7-4', @checkReviewResultConversion
        'P7-5', @checkProjectRegistration
        'P7-6', @checkSerializerRoundTrip
        'P7-7', @checkProjectExplorerResultNode
        'P7-8', @checkDashboardWiringMethods
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};
        label = phase7CheckLabel(fn);
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
            ok = false; %#ok<NASGU>
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
    fprintf('\n%d / %d Phase 7 checks passed.\n', passCount, numel(results));
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkPhase7Classes()
    status = '';
    classes = {
        'flightdash.analysis.AnalysisService'
        'flightdash.analysis.RoiStatisticsAnalyzer'
        'flightdash.model.RoiAnalyzer'
        'flightdash.project.ReviewResultModel'
        'flightdash.project.AnalysisThemeModel'
    };
    missing = {};
    for k = 1:numel(classes)
        if isempty(meta.class.fromName(classes{k}))
            missing{end+1} = classes{k}; %#ok<AGROW>
        end
    end
    ok = isempty(missing);
    if ok
        msg = 'Analysis service, ROI facade, and result/theme models resolved';
    else
        msg = sprintf('Missing classes: %s', strjoin(missing, ', '));
    end
end

function [ok, msg, status] = checkDefaultTheme()
    status = '';
    p = flightdash.project.ProjectModel('Phase7');
    [p, theme] = flightdash.analysis.AnalysisService.ensureDefaultThemes(p);
    ok = numel(p.AnalysisThemes) == 1 && theme.IsDefault && ...
        strcmp(theme.AnalysisType, 'RoiStats') && ...
        strcmp(theme.ThemeId, flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId);
    if ok
        msg = 'Default ROI statistics AnalysisThemeModel is created once';
    else
        msg = 'Default ROI statistics theme was not created correctly';
    end
end

function [ok, msg, status] = checkSingleRoiAnalysis()
    status = '';
    [request, ~] = sampleRequest();
    result = flightdash.analysis.AnalysisService.run(request);
    ok = strcmp(result.Status, 'OK') && strcmp(result.AnalysisType, 'RoiStats') && ...
        isequal(result.TimeRange, [2 4]) && isfield(result.ComputedValues, 'Mean') && ...
        isfinite(result.ComputedValues.Mean);
    if ok
        msg = sprintf('Single ROI analyzed: %s=%s, %s=%s', ...
            result.ComputedValues.SignalName, result.ComputedValues.MeanText, ...
            result.ComputedValues.MetricName, result.ComputedValues.MetricText);
    else
        msg = 'Single ROI AnalysisResult missing expected values';
    end
end

function [ok, msg, status] = checkReviewResultConversion()
    status = '';
    [request, ~] = sampleRequest();
    analysisResult = flightdash.analysis.AnalysisService.run(request);
    model = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);
    ok = isa(model, 'flightdash.project.ReviewResultModel') && ...
        strcmp(model.SessionId, request.SessionId) && strcmp(model.ResultType, 'ROI') && ...
        model.ChannelIdx == request.ChannelIdx && ...
        strcmp(model.AnalysisThemeId, flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId) && ...
        isfield(model.ComputedValues, 'MetricName') && ~isempty(model.ComputeFnSpec);
    if ok
        msg = sprintf('ReviewResultModel created: %s', model.ResultId);
    else
        msg = 'AnalysisResult -> ReviewResultModel conversion mismatch';
    end
end

function [ok, msg, status] = checkProjectRegistration()
    status = '';
    [request, session] = sampleRequest();
    analysisResult = flightdash.analysis.AnalysisService.run(request);
    model = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);

    p = flightdash.project.ProjectModel('Phase7');
    p = p.addSession(session);
    [p, ~] = flightdash.analysis.AnalysisService.ensureDefaultThemes(p);
    p = p.addResult(model);

    ok = numel(p.Results) == 1 && numel(p.AnalysisThemes) == 1 && ...
        strcmp(p.Results(1).SessionId, session.SessionId);
    if ok
        msg = 'ProjectModel registers ROI ReviewResultModel and default theme';
    else
        msg = 'ProjectModel result/theme registration failed';
    end
end

function [ok, msg, status] = checkSerializerRoundTrip()
    status = '';
    tmpFile = [tempname() '.frsproj'];
    cleaner = onCleanup(@() cleanupFile(tmpFile)); %#ok<NASGU>

    [request, session] = sampleRequest();
    analysisResult = flightdash.analysis.AnalysisService.run(request);
    model = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);
    p = flightdash.project.ProjectModel('Phase7');
    p = p.addSession(session);
    [p, ~] = flightdash.analysis.AnalysisService.ensureDefaultThemes(p);
    p = p.addResult(model);

    flightdash.project.ProjectSerializer.save(p, tmpFile);
    loaded = flightdash.project.ProjectSerializer.load(tmpFile);

    ok = isfile(tmpFile) && numel(loaded.Results) == 1 && numel(loaded.AnalysisThemes) == 1 && ...
        strcmp(loaded.Results(1).ResultId, model.ResultId) && ...
        isfield(loaded.Results(1).ComputedValues, 'SignalName');
    if ok
        msg = 'ProjectSerializer round-trips ROI ReviewResultModel metadata';
    else
        msg = 'Result/theme metadata did not survive ProjectSerializer round-trip';
    end
end

function [ok, msg, status] = checkProjectExplorerResultNode()
    status = '';
    app = [];
    try
        app = flightdash.studio.FlightReviewStudioApp();
        [request, session] = sampleRequest();
        app.Project = app.Project.addSession(session);
        analysisResult = flightdash.analysis.AnalysisService.run(request);
        model = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);
        app.registerReviewResult(model);
        drawnow limitrate;
        ok = treeContainsText(app.ProjectExplorer.Tree, model.ResultId);
        if ok
            msg = 'Project Explorer shows ROI ReviewResultModel under results';
        else
            msg = 'Project Explorer did not show the saved result id';
        end
    catch ME
        ok = false;
        msg = sprintf('%s: %s', ME.identifier, ME.message);
    end
    try
        if ~isempty(app) && isvalid(app), delete(app); end
    catch
    end
end

function [ok, msg, status] = checkDashboardWiringMethods()
    status = '';
    dashMeta = meta.class.fromName('flightdash.FlightDataDashboard');
    roiMeta = meta.class.fromName('flightdash.controller.RoiController');
    dashMethods = {dashMeta.MethodList.Name};
    roiMethods = {roiMeta.MethodList.Name};
    ok = any(strcmp(dashMethods, 'registerReviewResult')) && ...
        any(strcmp(roiMethods, 'registerSelectedResult'));
    if ok
        msg = 'Dashboard/RoiController expose Phase 7 registration hooks';
    else
        msg = 'Missing Dashboard or ROI controller registration hook';
    end
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function [request, session] = sampleRequest()
    time = (0:0.5:6)';
    roll = time + 1;
    rollTarget = ones(size(time)) * 3;
    raw = table(time, roll, rollTarget, 'VariableNames', {'Time', 'Roll', 'RollTarget'});
    rows = {2, 4, 'Roll', '--', '--'};
    session = flightdash.project.SessionModel('Phase 7 Session');
    session.SessionId = 'S_PHASE7';
    request = flightdash.analysis.AnalysisService.makeRoiStatisticsRequest( ...
        session.SessionId, 1, 1, rows, time, raw, struct('IsSynced', false), ...
        flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId);
end

function tf = treeContainsText(tree, needle)
    tf = false;
    try
        nodes = tree.Children;
        for k = 1:numel(nodes)
            if nodeContainsText(nodes(k), needle)
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end

function tf = nodeContainsText(node, needle)
    tf = false;
    try
        if contains(char(node.Text), char(needle))
            tf = true;
            return;
        end
        kids = node.Children;
        for k = 1:numel(kids)
            if nodeContainsText(kids(k), needle)
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end

function cleanupFile(path)
    try
        if isfile(path), delete(path); end
    catch
    end
    try
        if isfile([path '.zip']), delete([path '.zip']); end
    catch
    end
end

function label = phase7CheckLabel(fn)
    name = func2str(fn);
    name = regexprep(name, '^@\(.*\)', '');
    name = regexprep(name, '^check', '');
    name = regexprep(name, '([a-z])([A-Z])', '$1 $2');
    label = strtrim(name);
    if isempty(label), label = func2str(fn); end
end

function progressStart(tc, label, idx, total)
    fprintf('[%s] START %d/%d - %s\n', tc, idx, total, label);
    drawnow limitrate;
end

function progressDone(tc, status, msg, elapsed)
    fprintf('[%s] %-15s %.2fs - %s\n', tc, status, elapsed, msg);
    drawnow limitrate;
end

function printResults(results)
    fprintf('\nTC      Result          Message\n');
    fprintf('------  --------------  -------\n');
    for i = 1:numel(results)
        fprintf('%-6s  %-14s  %s\n', results(i).TC, results(i).Result, results(i).Message);
    end
end
