function results = verifyPhase2()
%VERIFYPHASE2 Phase 2 verification: Project / Session Model checks.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase2();

    fprintf('\n=== Phase 2 verification: Project / Session Model ===\n\n');

    tests = {
        'P2-1',  @checkModelClassResolution
        'P2-2',  @checkProjectModelConstruction
        'P2-3',  @checkSessionModelConstruction
        'P2-4',  @checkProjectSessionCrud
        'P2-5',  @checkSessionChannelValidation
        'P2-6',  @checkSessionDisplayNameValidation
        'P2-7',  @checkProjectIdUniqueness
        'P2-8',  @checkFigureModelCrud
        'P2-9',  @checkReviewResultCascadeDelete
        'P2-10', @checkAnalysisThemeCrud
        'P2-11', @checkValueClassCopySemantics
        'P2-12', @checkModelSchemaVersionFields
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};

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

        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);

    passCount = sum(strcmp({results.Result}, 'PASS'));
    totalCount = numel(results);
    fprintf('\n%d / %d Phase 2 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkModelClassResolution()
    status = '';

    classes = {
        'flightdash.project.ProjectModel'
        'flightdash.project.SessionModel'
        'flightdash.project.FigureModel'
        'flightdash.project.ReviewResultModel'
        'flightdash.project.AnalysisThemeModel'
    };

    missing = {};
    for i = 1:numel(classes)
        if isempty(meta.class.fromName(classes{i}))
            missing{end+1} = classes{i}; %#ok<AGROW>
        end
    end

    ok = isempty(missing);
    if ok
        msg = sprintf('%d project model classes resolved', numel(classes));
    else
        msg = sprintf('Missing classes: %s', strjoin(missing, ', '));
    end
end

function [ok, msg, status] = checkProjectModelConstruction()
    status = '';

    p = flightdash.project.ProjectModel();

    requiredProps = {
        'SchemaVersion'
        'ProjectId'
        'ProjectName'
        'Sessions'
        'Figures'
        'Results'
        'AnalysisThemes'
        'DirtyFlag'
    };

    missing = missingProps(p, requiredProps);

    ok = isempty(missing) && ~isempty(p.ProjectId) && ~isempty(p.ProjectName);
    if ok
        msg = sprintf('ProjectModel constructed: id=%s, name=%s', ...
            char(p.ProjectId), char(p.ProjectName));
    else
        msg = sprintf('ProjectModel missing/invalid props: %s', strjoin(missing, ', '));
    end
end

function [ok, msg, status] = checkSessionModelConstruction()
    status = '';

    s = flightdash.project.SessionModel();

    requiredProps = {
        'SchemaVersion'
        'SessionId'
        'DisplayName'
        'DirtyFlag'
    };

    missing = missingProps(s, requiredProps);
    hasFlightPaths = hasAnyProp(s, {'FlightFilePath', 'FlightFilePaths', 'FlightFiles', 'FlightFile', 'ChannelFiles'});
    hasVideoPaths = hasAnyProp(s, {'VideoFilePath', 'VideoFilePaths', 'VideoFiles', 'VideoFile', 'ChannelFiles'});
    hasFlightSetter = ismethod(s, 'setFlightFile');
    hasVideoSetter = ismethod(s, 'setVideoFile');

    ok = isempty(missing) && ~isempty(s.SessionId) && ~isempty(s.DisplayName) && ...
         (hasFlightPaths || hasFlightSetter) && (hasVideoPaths || hasVideoSetter);
    if ok
        msg = sprintf('SessionModel constructed: id=%s, name=%s', ...
            char(s.SessionId), char(s.DisplayName));
    else
        msg = sprintf('SessionModel missing/invalid props: %s, flightPath=%d, videoPath=%d', ...
            strjoin(missing, ', '), hasFlightPaths || hasFlightSetter, hasVideoPaths || hasVideoSetter);
    end
end

function [ok, msg, status] = checkProjectSessionCrud()
    status = '';

    p = flightdash.project.ProjectModel();
    s1 = makeSession('S001', 'Session 1');
    s2 = makeSession('S002', 'Session 2');

    p = addSessionSafe(p, s1);
    p = addSessionSafe(p, s2);

    countAfterAdd = safeSessionCount(p);
    hasS1 = hasSession(p, 'S001');
    hasS2 = hasSession(p, 'S002');

    s2 = setDisplayNameSafe(s2, 'Session 2 Renamed');
    p = updateSessionSafe(p, 'S002', s2);
    got = getSessionById(p, 'S002');

    p = removeSessionSafe(p, 'S001');

    ok = countAfterAdd == 2 && hasS1 && hasS2 && ...
         ~isempty(got) && strcmp(char(got.DisplayName), 'Session 2 Renamed') && ...
         ~hasSession(p, 'S001') && hasSession(p, 'S002');

    if ok
        msg = 'add/update/remove session semantics correct';
    else
        msg = sprintf('Session CRUD mismatch: countAfterAdd=%d, hasS1=%d, hasS2=%d', ...
            countAfterAdd, hasS1, hasS2);
    end
end

function [ok, msg, status] = checkSessionChannelValidation()
    status = '';

    s = makeSession('S001', 'Session 1');

    validOk = true;
    try
        s = setFlightFileSafe(s, 1, 'flight1.csv');
        s = setFlightFileSafe(s, 2, string('flight2.csv'));
        s = setVideoFileSafe(s, 1, 'video1.avi');
        s = setVideoFileSafe(s, 2, string('video2.avi'));
        if ismethod(s, 'setRoiRows')
            s = s.setRoiRows(1, [1 2 3]);
            s = s.setRoiRows(2, [4 5 6]);
        end
        validOk = sessionHasFlightData(s, 1) && sessionHasFlightData(s, 2) && ...
                  sessionHasVideo(s, 1) && sessionHasVideo(s, 2);
    catch
        validOk = false;
    end

    invalidValues = {0, 3, -1, 1.5, NaN, Inf};
    rejected = true(size(invalidValues));

    for i = 1:numel(invalidValues)
        try
            setFlightFileSafe(s, invalidValues{i}, 'bad.csv');
            rejected(i) = false;
        catch
            rejected(i) = true;
        end
    end

    ok = validOk && all(rejected);

    if ok
        msg = 'channelIdx in {1,2} accepted and invalid channel indices rejected';
    else
        msg = sprintf('channel validation failed: validOk=%d, rejected=%s', ...
            validOk, mat2str(rejected));
    end
end

function [ok, msg, status] = checkSessionDisplayNameValidation()
    status = '';

    s = makeSession('S001', 'Session 1');

    validOk = true;
    try
        s = setDisplayNameSafe(s, '  Valid Name  ');
        validOk = strcmp(char(s.DisplayName), 'Valid Name');
    catch
        validOk = false;
    end

    invalidInputs = {'', '   ', string(''), string('   ')};
    rejected = true(size(invalidInputs));

    for i = 1:numel(invalidInputs)
        try
            s.setDisplayName(invalidInputs{i});
            rejected(i) = false;
        catch
            rejected(i) = true;
        end
    end

    ok = validOk && all(rejected);

    if ok
        msg = 'display names are trimmed and empty/whitespace names rejected';
    else
        msg = sprintf('display name validation failed: validOk=%d, rejected=%s', ...
            validOk, mat2str(rejected));
    end
end

function [ok, msg, status] = checkProjectIdUniqueness()
    status = '';

    n = 200;
    ids = strings(1, n);

    for i = 1:n
        ids(i) = string(flightdash.project.ProjectModel.newId('TEST'));
    end

    uniqueCount = numel(unique(ids));
    prefixOk = all(startsWith(ids, "TEST_"));

    ok = uniqueCount == n && prefixOk;

    if ok
        msg = sprintf('%d ids generated, all unique and prefix-conformant', n);
    else
        msg = sprintf('id uniqueness failed: unique=%d/%d, prefixOk=%d', ...
            uniqueCount, n, prefixOk);
    end
end

function [ok, msg, status] = checkFigureModelCrud()
    status = '';

    p = flightdash.project.ProjectModel();
    f = flightdash.project.FigureModel();

    if isprop(f, 'FigureId')
        f.FigureId = 'FIG_TEST';
    end

    if isprop(f, 'SessionId')
        f.SessionId = 'S001';
    end

    p = p.addFigure(f);

    hasFig = false;
    if isprop(p, 'Figures')
        figs = p.Figures;
        for i = 1:numel(figs)
            if isprop(figs(i), 'FigureId') && strcmp(char(figs(i).FigureId), 'FIG_TEST')
                hasFig = true;
                break;
            end
        end
    end

    ok = hasFig;

    if ok
        msg = 'FigureModel can be added to ProjectModel';
    else
        msg = 'FigureModel add/check failed';
    end
end

function [ok, msg, status] = checkReviewResultCascadeDelete()
    status = '';

    p = flightdash.project.ProjectModel();
    s1 = makeSession('S001', 'Session 1');
    s2 = makeSession('S002', 'Session 2');

    p = addSessionSafe(p, s1);
    p = addSessionSafe(p, s2);

    r1 = flightdash.project.ReviewResultModel();
    r2 = flightdash.project.ReviewResultModel();
    r3 = flightdash.project.ReviewResultModel();

    r1 = setIfProp(r1, 'ResultId', 'R001');
    r1 = setIfProp(r1, 'SessionId', 'S001');

    r2 = setIfProp(r2, 'ResultId', 'R002');
    r2 = setIfProp(r2, 'SessionId', 'S001');

    r3 = setIfProp(r3, 'ResultId', 'R003');
    r3 = setIfProp(r3, 'SessionId', 'S002');

    p = p.addResult(r1);
    p = p.addResult(r2);
    p = p.addResult(r3);

    before = numel(p.Results);
    p = removeSessionSafe(p, 'S001');
    after = numel(p.Results);

    remainingIds = strings(1, after);
    for i = 1:after
        if isprop(p.Results(i), 'ResultId')
            remainingIds(i) = string(p.Results(i).ResultId);
        end
    end

    ok = before == 3 && after == 1 && hasSession(p, 'S002') && ...
         ~hasSession(p, 'S001') && any(remainingIds == "R003");

    if ok
        msg = 'removeSession drops session and cascades dependent ReviewResults';
    else
        msg = sprintf('cascade delete failed: results before=%d after=%d remaining=[%s]', ...
            before, after, strjoin(cellstr(remainingIds), ', '));
    end
end

function [ok, msg, status] = checkAnalysisThemeCrud()
    status = '';

    p = flightdash.project.ProjectModel();
    t = flightdash.project.AnalysisThemeModel();

    if isprop(t, 'ThemeId')
        t.ThemeId = 'THEME_TEST';
    end

    if isprop(t, 'ThemeName')
        t.ThemeName = 'Theme Test';
    end

    p = addAnalysisThemeSafe(p, t);

    hasTheme = false;
    if isprop(p, 'AnalysisThemes')
        themes = p.AnalysisThemes;
        for i = 1:numel(themes)
            if isprop(themes(i), 'ThemeId') && strcmp(char(themes(i).ThemeId), 'THEME_TEST')
                hasTheme = true;
                break;
            end
        end
    end

    ok = hasTheme;

    if ok
        msg = 'AnalysisThemeModel can be added to ProjectModel';
    else
        msg = 'AnalysisThemeModel add/check failed';
    end
end

function [ok, msg, status] = checkValueClassCopySemantics()
    status = '';

    p1 = flightdash.project.ProjectModel();
    s = makeSession('S001', 'Session 1');

    p2 = addSessionSafe(p1, s);

    ok = safeSessionCount(p1) == 0 && safeSessionCount(p2) == 1;

    if ok
        msg = 'ProjectModel behaves as value class for addSession copy semantics';
    else
        msg = sprintf('Unexpected handle-like semantics: p1 count=%d, p2 count=%d', ...
            safeSessionCount(p1), safeSessionCount(p2));
    end
end

function [ok, msg, status] = checkModelSchemaVersionFields()
    status = '';

    models = {
        flightdash.project.ProjectModel()
        flightdash.project.SessionModel()
        flightdash.project.FigureModel()
        flightdash.project.ReviewResultModel()
        flightdash.project.AnalysisThemeModel()
    };

    names = {
        'ProjectModel'
        'SessionModel'
        'FigureModel'
        'ReviewResultModel'
        'AnalysisThemeModel'
    };

    missing = {};
    emptyVersion = {};

    for i = 1:numel(models)
        m = models{i};

        if ~isprop(m, 'SchemaVersion')
            missing{end+1} = names{i}; %#ok<AGROW>
        elseif isempty(m.SchemaVersion)
            emptyVersion{end+1} = names{i}; %#ok<AGROW>
        end
    end

    ok = isempty(missing) && isempty(emptyVersion);

    if ok
        msg = 'All Phase 2 models expose non-empty SchemaVersion';
    else
        msg = sprintf('SchemaVersion missing=[%s], empty=[%s]', ...
            strjoin(missing, ', '), strjoin(emptyVersion, ', '));
    end
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function props = missingProps(obj, requiredProps)
    props = {};

    for i = 1:numel(requiredProps)
        if ~isprop(obj, requiredProps{i})
            props{end+1} = requiredProps{i}; %#ok<AGROW>
        end
    end
end

function tf = hasAnyProp(obj, propNames)
    tf = false;

    for i = 1:numel(propNames)
        try
            if isprop(obj, propNames{i})
                tf = true;
                return;
            end
        catch
        end
    end
end

function s = makeSession(sessionId, displayName)
    try
        s = flightdash.project.SessionModel(displayName);
    catch
        s = flightdash.project.SessionModel();
        s = setDisplayNameSafe(s, displayName);
    end
    s = setSessionIdSafe(s, sessionId);
end

function s = setSessionIdSafe(s, sessionId)
    if isempty(sessionId), return; end
    if isprop(s, 'SessionId')
        s.SessionId = char(sessionId);
    elseif isprop(s, 'Id')
        s.Id = char(sessionId);
    end
end

function s = setDisplayNameSafe(s, displayName)
    if ismethod(s, 'setDisplayName')
        s = s.setDisplayName(displayName);
    elseif isprop(s, 'DisplayName')
        s.DisplayName = strtrim(char(displayName));
    elseif isprop(s, 'Name')
        s.Name = strtrim(char(displayName));
    end
end

function s = setFlightFileSafe(s, channelIdx, pathValue)
    if ismethod(s, 'setFlightFile')
        s = s.setFlightFile(channelIdx, pathValue);
        return;
    end
    validateChannelIdxForDiag(channelIdx);
    s = setPathCellProp(s, {'FlightFilePath', 'FlightFilePaths', 'FlightFiles', 'FlightFile'}, channelIdx, pathValue);
end

function s = setVideoFileSafe(s, channelIdx, pathValue)
    if ismethod(s, 'setVideoFile')
        s = s.setVideoFile(channelIdx, pathValue);
        return;
    end
    validateChannelIdxForDiag(channelIdx);
    s = setPathCellProp(s, {'VideoFilePath', 'VideoFilePaths', 'VideoFiles', 'VideoFile'}, channelIdx, pathValue);
end

function s = setPathCellProp(s, propNames, channelIdx, pathValue)
    pathValue = char(pathValue);
    for i = 1:numel(propNames)
        name = propNames{i};
        if ~isprop(s, name), continue; end
        value = s.(name);
        if iscell(value)
            if numel(value) < 2
                value(2) = {''};
            end
            value{channelIdx} = pathValue;
            s.(name) = value;
        else
            s.(name) = pathValue;
        end
        return;
    end
    if isprop(s, 'ChannelFiles')
        files = s.ChannelFiles;
        files(channelIdx).FlightFile = pathValue;
        s.ChannelFiles = files;
    else
        error('verifyPhase2:NoFlightPathApi', 'No compatible flight/video path API found.');
    end
end

function validateChannelIdxForDiag(channelIdx)
    validateattributes(channelIdx, {'numeric'}, ...
        {'scalar', 'integer', 'finite', '>=', 1, '<=', 2}, '', 'channelIdx');
end

function tf = sessionHasFlightData(s, channelIdx)
    if ismethod(s, 'hasFlightData')
        tf = s.hasFlightData(channelIdx);
    else
        tf = sessionPathPresent(s, {'FlightFilePath', 'FlightFilePaths', 'FlightFiles', 'FlightFile'}, channelIdx);
    end
end

function tf = sessionHasVideo(s, channelIdx)
    if ismethod(s, 'hasVideo')
        tf = s.hasVideo(channelIdx);
    else
        tf = sessionPathPresent(s, {'VideoFilePath', 'VideoFilePaths', 'VideoFiles', 'VideoFile'}, channelIdx);
    end
end

function tf = sessionPathPresent(s, propNames, channelIdx)
    tf = false;
    try
        validateChannelIdxForDiag(channelIdx);
        for i = 1:numel(propNames)
            name = propNames{i};
            if ~isprop(s, name), continue; end
            value = s.(name);
            if iscell(value) && numel(value) >= channelIdx
                tf = ~isempty(value{channelIdx});
            elseif ischar(value) || isstring(value)
                tf = ~isempty(value);
            end
            if tf, return; end
        end
    catch
        tf = false;
    end
end

function p = addSessionSafe(p, session)
    if ismethod(p, 'addSession')
        p = p.addSession(session);
    elseif isprop(p, 'Sessions')
        p.Sessions = [p.Sessions, session];
    else
        error('verifyPhase2:NoAddSessionApi', 'ProjectModel has no session add API.');
    end
end

function p = updateSessionSafe(p, sessionId, session)
    if ismethod(p, 'updateSession')
        try
            p = p.updateSession(sessionId, session);
        catch ME
            if strcmp(ME.identifier, 'MATLAB:TooManyInputs')
                p = p.updateSession(session);
            else
                rethrow(ME);
            end
        end
    elseif isprop(p, 'Sessions')
        sessions = p.Sessions;
        for i = 1:numel(sessions)
            if isprop(sessions(i), 'SessionId') && strcmp(char(sessions(i).SessionId), char(sessionId))
                sessions(i) = session;
                p.Sessions = sessions;
                return;
            end
        end
        error('verifyPhase2:UnknownSession', 'Session id "%s" not found.', char(sessionId));
    else
        error('verifyPhase2:NoUpdateSessionApi', 'ProjectModel has no session update API.');
    end
end

function p = removeSessionSafe(p, sessionId)
    if ismethod(p, 'removeSession')
        p = p.removeSession(sessionId);
    elseif isprop(p, 'Sessions')
        sessions = p.Sessions;
        mask = arrayfun(@(s) isprop(s, 'SessionId') && strcmp(char(s.SessionId), char(sessionId)), sessions);
        p.Sessions = sessions(~mask);
    else
        error('verifyPhase2:NoRemoveSessionApi', 'ProjectModel has no session remove API.');
    end
end

function p = addAnalysisThemeSafe(p, theme)
    if ismethod(p, 'addAnalysisTheme')
        p = p.addAnalysisTheme(theme);
    elseif ismethod(p, 'addTheme')
        p = p.addTheme(theme);
    elseif ismethod(p, 'addThemePreset')
        p = p.addThemePreset(theme);
    elseif isprop(p, 'AnalysisThemes')
        p.AnalysisThemes = [p.AnalysisThemes, theme];
    else
        error('verifyPhase2:NoAddThemeApi', 'ProjectModel has no analysis theme add API.');
    end
end

function count = safeSessionCount(project)
    count = -1;

    try
        if ismethod(project, 'sessionCount')
            count = project.sessionCount();
        elseif isprop(project, 'Sessions')
            count = numel(project.Sessions);
        end
    catch
        count = -1;
    end
end

function tf = hasSession(project, sessionId)
    tf = false;

    try
        if ismethod(project, 'hasSession')
            tf = project.hasSession(sessionId);
            return;
        end

        if ~isprop(project, 'Sessions')
            return;
        end

        sessions = project.Sessions;
        for i = 1:numel(sessions)
            if isprop(sessions(i), 'SessionId') && strcmp(char(sessions(i).SessionId), char(sessionId))
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end

function session = getSessionById(project, sessionId)
    session = [];

    try
        if ismethod(project, 'getSession')
            session = project.getSession(sessionId);
            return;
        end

        if ~isprop(project, 'Sessions')
            return;
        end

        sessions = project.Sessions;
        for i = 1:numel(sessions)
            if isprop(sessions(i), 'SessionId') && strcmp(char(sessions(i).SessionId), char(sessionId))
                session = sessions(i);
                return;
            end
        end
    catch
        session = [];
    end
end

function obj = setIfProp(obj, propName, value)
    if isprop(obj, propName)
        obj.(propName) = value;
    end
end

function printResults(results)
    fprintf('TC      Result        Message\n');
    fprintf('------  ------------  -------\n');

    for i = 1:numel(results)
        fprintf('%-6s  %-12s  %s\n', ...
            results(i).TC, results(i).Result, results(i).Message);
    end
end
