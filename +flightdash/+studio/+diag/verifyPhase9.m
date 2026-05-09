function results = verifyPhase9()
%VERIFYPHASE9 Phase 9 verification: Project Save / Load / Serializer checks.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase9();

    fprintf('\n=== Phase 9 verification: Project Save / Load ===\n\n');

    tests = {
        'P9-1',  @checkSerializerClassResolution
        'P9-2',  @checkSaveProducesFrsprojFile
        'P9-3',  @checkSerializerRoundTripBasicProject
        'P9-4',  @checkSessionMetadataRoundTrip
        'P9-5',  @checkAnalysisThemeRoundTrip
        'P9-6',  @checkExternalLinksRoundTrip
        'P9-7',  @checkManifestAndZipContents
        'P9-8',  @checkOverwriteExistingFile
        'P9-9',  @checkLoadRejectsMissingFile
        'P9-10', @checkLoadRejectsInvalidArchive
        'P9-11', @checkStudioSaveLoadMethodsExist
        'P9-12', @checkOpenProjectSessionTabRestoreSmoke
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
    fprintf('\n%d / %d Phase 9 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkSerializerClassResolution()
    status = '';

    cls = 'flightdash.project.ProjectSerializer';
    found = meta.class.fromName(cls);

    ok = ~isempty(found);
    if ok
        msg = sprintf('%s resolved', cls);
    else
        msg = sprintf('%s not found', cls);
    end
end

function [ok, msg, status] = checkSaveProducesFrsprojFile()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        p = makeSampleProject();
        flightdash.project.ProjectSerializer.save(p, tmpFile);

        ok = isfile(tmpFile);

        if ok
            info = dir(tmpFile);
            msg = sprintf('save() produced .frsproj file, size=%d bytes', info.bytes);
        else
            candidates = findLikelyZipCandidates(tmpFile);
            msg = sprintf('save() did not produce requested file. Candidates: %s', ...
                strjoin(candidates, ', '));
        end
    catch ME
        ok = false;
        msg = sprintf('save() failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
    cleanupPath([tmpFile '.zip']);
end

function [ok, msg, status] = checkSerializerRoundTripBasicProject()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        p = makeSampleProject();
        flightdash.project.ProjectSerializer.save(p, tmpFile);
        loaded = flightdash.project.ProjectSerializer.load(tmpFile);

        ok = isa(loaded, 'flightdash.project.ProjectModel') && ...
             strcmp(char(loaded.ProjectName), char(p.ProjectName)) && ...
             strcmp(char(loaded.ProjectId), char(p.ProjectId));

        if ok
            msg = 'ProjectSerializer save/load round-trip preserves basic project identity';
        else
            msg = sprintf('Round-trip identity mismatch: saved=(%s,%s), loaded=(%s,%s)', ...
                safeChar(p.ProjectId), safeChar(p.ProjectName), ...
                safeChar(getPropOrEmpty(loaded, 'ProjectId')), safeChar(getPropOrEmpty(loaded, 'ProjectName')));
        end
    catch ME
        ok = false;
        msg = sprintf('Round-trip failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
end

function [ok, msg, status] = checkSessionMetadataRoundTrip()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        p = makeSampleProject();
        s1 = flightdash.project.SessionModel('P9_S001', 'Phase9 Session 1');
        s2 = flightdash.project.SessionModel('P9_S002', 'Phase9 Session 2');

        s1 = safeSetFlightFile(s1, 1, fullfile(tempdir, 'p9_flight1.csv'));
        s1 = safeSetVideoFile(s1, 1, fullfile(tempdir, 'p9_video1.avi'));
        s2 = safeSetFlightFile(s2, 2, string(fullfile(tempdir, 'p9_flight2.csv')));
        s2 = safeSetVideoFile(s2, 2, string(fullfile(tempdir, 'p9_video2.avi')));

        p = p.addSession(s1);
        p = p.addSession(s2);

        flightdash.project.ProjectSerializer.save(p, tmpFile);
        loaded = flightdash.project.ProjectSerializer.load(tmpFile);

        ls1 = getProjectSession(loaded, 'P9_S001');
        ls2 = getProjectSession(loaded, 'P9_S002');

        ok = ~isempty(ls1) && ~isempty(ls2) && ...
             strcmp(char(ls1.DisplayName), 'Phase9 Session 1') && ...
             strcmp(char(ls2.DisplayName), 'Phase9 Session 2') && ...
             safeSessionCount(loaded) == 2;

        if ok
            msg = 'Session metadata round-trip preserves ids, names, and session count';
        else
            msg = sprintf('Session metadata mismatch: count=%d, s1=%d, s2=%d', ...
                safeSessionCount(loaded), ~isempty(ls1), ~isempty(ls2));
        end
    catch ME
        ok = false;
        msg = sprintf('Session metadata round-trip failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
end

function [ok, msg, status] = checkAnalysisThemeRoundTrip()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        p = makeSampleProject();

        t = flightdash.project.AnalysisThemeModel();
        t = setIfProp(t, 'ThemeId', 'P9_THEME_001');
        t = setIfProp(t, 'ThemeName', 'Phase9 Theme');
        t = setIfProp(t, 'AnalysisType', 'ROIStatistics');
        t = setIfProp(t, 'IsDefault', true);

        p = p.addAnalysisTheme(t);

        flightdash.project.ProjectSerializer.save(p, tmpFile);
        loaded = flightdash.project.ProjectSerializer.load(tmpFile);

        theme = getThemeById(loaded, 'P9_THEME_001');

        ok = ~isempty(theme) && ...
             isprop(theme, 'ThemeName') && strcmp(char(theme.ThemeName), 'Phase9 Theme');

        if ok
            msg = 'AnalysisThemeModel round-trip preserves theme id/name';
        else
            msg = 'AnalysisThemeModel round-trip failed to restore test theme';
        end
    catch ME
        ok = false;
        msg = sprintf('AnalysisTheme round-trip failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
end

function [ok, msg, status] = checkExternalLinksRoundTrip()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        p = makeSampleProject();

        missingFlight = fullfile(tempdir, 'missing_phase9_flight.csv');
        missingVideo = fullfile(tempdir, 'missing_phase9_video.avi');

        cleanupPath(missingFlight);
        cleanupPath(missingVideo);

        s = flightdash.project.SessionModel('P9_LINKS', 'Phase9 Links');
        s = safeSetFlightFile(s, 1, missingFlight);
        s = safeSetVideoFile(s, 1, missingVideo);
        p = p.addSession(s);

        flightdash.project.ProjectSerializer.save(p, tmpFile);
        loaded = flightdash.project.ProjectSerializer.load(tmpFile);
        loadedSession = getProjectSession(loaded, 'P9_LINKS');

        flightOk = false;
        videoOk = false;

        if ~isempty(loadedSession)
            flightOk = cellStringContains(getPropOrEmpty(loadedSession, 'FlightFiles'), missingFlight);
            videoOk = cellStringContains(getPropOrEmpty(loadedSession, 'VideoFiles'), missingVideo);
        end

        ok = flightOk && videoOk;

        if ok
            msg = 'External linked asset paths round-trip even when files are missing';
        else
            msg = sprintf('External link round-trip mismatch: flightOk=%d videoOk=%d', flightOk, videoOk);
        end
    catch ME
        ok = false;
        msg = sprintf('External links round-trip failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
end

function [ok, msg, status] = checkManifestAndZipContents()
    status = '';

    tmpFile = makeTempFrsprojPath();
    outDir = tempname();

    try
        p = makeSampleProject();
        s = flightdash.project.SessionModel('P9_ZIP_SESSION', 'Phase9 Zip Session');
        p = p.addSession(s);

        flightdash.project.ProjectSerializer.save(p, tmpFile);

        mkdir(outDir);
        unzip(tmpFile, outDir);

        required = {
            fullfile(outDir, 'manifest.json')
            fullfile(outDir, 'project.json')
        };

        missing = {};
        for i = 1:numel(required)
            if ~isfile(required{i})
                missing{end+1} = required{i}; %#ok<AGROW>
            end
        end

        sessionJson = findFileByName(outDir, 'session.json');
        hasSessionJson = ~isempty(sessionJson);

        manifestOk = false;
        if isfile(fullfile(outDir, 'manifest.json'))
            txt = fileread(fullfile(outDir, 'manifest.json'));
            manifestOk = contains(txt, 'SchemaVersion') || contains(txt, 'schema') || ...
                         contains(lower(txt), 'manifest');
        end

        ok = isempty(missing) && hasSessionJson && manifestOk;

        if ok
            msg = 'Archive contains manifest.json, project.json, and session metadata';
        else
            msg = sprintf('Archive content mismatch: missing=%d sessionJson=%d manifestOk=%d', ...
                numel(missing), hasSessionJson, manifestOk);
        end
    catch ME
        ok = false;
        msg = sprintf('Manifest/archive content check failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
    cleanupPath(outDir);
end

function [ok, msg, status] = checkOverwriteExistingFile()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        p1 = makeSampleProject();
        p1.ProjectName = 'Phase9 Overwrite 1';

        p2 = makeSampleProject();
        p2.ProjectName = 'Phase9 Overwrite 2';

        flightdash.project.ProjectSerializer.save(p1, tmpFile);
        firstInfo = dir(tmpFile);

        flightdash.project.ProjectSerializer.save(p2, tmpFile);
        secondInfo = dir(tmpFile);

        loaded = flightdash.project.ProjectSerializer.load(tmpFile);

        ok = isfile(tmpFile) && firstInfo.bytes > 0 && secondInfo.bytes > 0 && ...
             strcmp(char(loaded.ProjectName), 'Phase9 Overwrite 2');

        if ok
            msg = 'save() safely overwrites an existing .frsproj file';
        else
            msg = sprintf('Overwrite mismatch: exists=%d firstBytes=%d secondBytes=%d loadedName=%s', ...
                isfile(tmpFile), firstInfo.bytes, secondInfo.bytes, safeChar(loaded.ProjectName));
        end
    catch ME
        ok = false;
        msg = sprintf('Overwrite check failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
end

function [ok, msg, status] = checkLoadRejectsMissingFile()
    status = '';

    tmpFile = makeTempFrsprojPath();
    cleanupPath(tmpFile);

    try
        flightdash.project.ProjectSerializer.load(tmpFile);
        ok = false;
        msg = 'load() unexpectedly accepted missing .frsproj file';
    catch ME
        ok = true;
        msg = sprintf('load() rejects missing file: %s', shortError(ME));
    end
end

function [ok, msg, status] = checkLoadRejectsInvalidArchive()
    status = '';

    tmpFile = makeTempFrsprojPath();

    try
        fid = fopen(tmpFile, 'w');
        if fid < 0
            error('verifyPhase9:WriteFailed', 'Could not create invalid archive test file');
        end
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, 'not a zip archive');
        clear cleaner;

        try
            flightdash.project.ProjectSerializer.load(tmpFile);
            ok = false;
            msg = 'load() unexpectedly accepted invalid archive';
        catch ME
            ok = true;
            msg = sprintf('load() rejects invalid archive: %s', shortError(ME));
        end
    catch ME
        ok = false;
        msg = sprintf('Invalid archive setup/check failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
end

function [ok, msg, status] = checkStudioSaveLoadMethodsExist()
    status = '';

    app = [];

    try
        app = createStudioApp();

        methods = {'newProject', 'saveProject', 'saveProjectAs', 'openProject'};
        present = false(size(methods));

        for i = 1:numel(methods)
            present(i) = ismethod(app, methods{i});
        end

        ok = all(present);

        if ok
            msg = 'Studio app exposes newProject/saveProject/saveProjectAs/openProject methods';
        else
            msg = sprintf('Missing Studio project methods: %s', strjoin(methods(~present), ', '));
        end
    catch ME
        ok = false;
        msg = sprintf('Studio save/load method check failed: %s', ME.message);
    end

    safeDelete(app);
end

function [ok, msg, status] = checkOpenProjectSessionTabRestoreSmoke()
    status = '';

    tmpFile = makeTempFrsprojPath();
    app = [];

    try
        p = makeSampleProject();
        p = p.addSession(flightdash.project.SessionModel('P9_OPEN_S001', 'Phase9 Open Session 1'));
        p = p.addSession(flightdash.project.SessionModel('P9_OPEN_S002', 'Phase9 Open Session 2'));

        flightdash.project.ProjectSerializer.save(p, tmpFile);

        app = createStudioApp();

        if ismethod(app, 'loadProjectFromFile')
            app.loadProjectFromFile(tmpFile);
        elseif ismethod(app, 'openProjectFile')
            app.openProjectFile(tmpFile);
        else
            status = 'SKIP_MANUAL';
            ok = true;
            msg = 'Studio openProject is UI-dialog based; direct file-open method not exposed';
            cleanupPath(tmpFile);
            safeDelete(app);
            return;
        end

        hasProject = hasProp(app, 'Project') && safeSessionCount(app.Project) == 2;
        hasTab1 = hasProp(app, 'Workspace') && workspaceHasSession(app.Workspace, 'P9_OPEN_S001');
        hasTab2 = hasProp(app, 'Workspace') && workspaceHasSession(app.Workspace, 'P9_OPEN_S002');

        ok = hasProject && hasTab1 && hasTab2;

        if ok
            msg = 'Direct project open restores project metadata and session tabs';
        else
            msg = sprintf('Open restore mismatch: project=%d tab1=%d tab2=%d', ...
                hasProject, hasTab1, hasTab2);
        end
    catch ME
        ok = false;
        msg = sprintf('Open project restore smoke failed: %s', ME.message);
    end

    cleanupPath(tmpFile);
    safeDelete(app);
end

% -------------------------------------------------------------------------
% Sample data helpers
% -------------------------------------------------------------------------

function p = makeSampleProject()
    p = flightdash.project.ProjectModel();

    if isprop(p, 'ProjectId')
        p.ProjectId = 'P9_PROJECT';
    end

    if isprop(p, 'ProjectName')
        p.ProjectName = 'Phase9 Serializer Test Project';
    end

    if isprop(p, 'DirtyFlag')
        p.DirtyFlag = false;
    end
end

function s = safeSetFlightFile(s, channelIdx, pathValue)
    if ismethod(s, 'setFlightFile')
        s = s.setFlightFile(channelIdx, pathValue);
    elseif isprop(s, 'FlightFiles')
        s.FlightFiles{channelIdx} = char(pathValue);
    end
end

function s = safeSetVideoFile(s, channelIdx, pathValue)
    if ismethod(s, 'setVideoFile')
        s = s.setVideoFile(channelIdx, pathValue);
    elseif isprop(s, 'VideoFiles')
        s.VideoFiles{channelIdx} = char(pathValue);
    end
end

function obj = setIfProp(obj, propName, value)
    if isprop(obj, propName)
        obj.(propName) = value;
    end
end

% -------------------------------------------------------------------------
% Query helpers
% -------------------------------------------------------------------------

function session = getProjectSession(project, sessionId)
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

function theme = getThemeById(project, themeId)
    theme = [];

    try
        if ~isprop(project, 'AnalysisThemes')
            return;
        end

        themes = project.AnalysisThemes;
        for i = 1:numel(themes)
            if isprop(themes(i), 'ThemeId') && strcmp(char(themes(i).ThemeId), char(themeId))
                theme = themes(i);
                return;
            end
        end
    catch
        theme = [];
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

function tf = workspaceHasSession(ws, sessionId)
    tf = false;

    try
        if isprop(ws, 'DashboardMap') && ~isempty(ws.DashboardMap)
            tf = isKey(ws.DashboardMap, sessionId);
            if tf
                return;
            end
        end
    catch
    end

    try
        if isprop(ws, 'TabMap') && ~isempty(ws.TabMap)
            tf = isKey(ws.TabMap, sessionId);
            if tf
                return;
            end
        end
    catch
    end

    try
        if isprop(ws, 'TabGroup') && isgraphics(ws.TabGroup)
            tabs = findall(ws.TabGroup, 'Type', 'uitab');
            for i = 1:numel(tabs)
                if isprop(tabs(i), 'UserData') && isequal(tabs(i).UserData, sessionId)
                    tf = true;
                    return;
                end
                if contains(string(tabs(i).Title), string(sessionId))
                    tf = true;
                    return;
                end
            end
        end
    catch
        tf = false;
    end
end

function value = getPropOrEmpty(obj, propName)
    value = [];

    try
        if isprop(obj, propName)
            value = obj.(propName);
        end
    catch
        value = [];
    end
end

function tf = cellStringContains(value, target)
    tf = false;

    try
        if iscell(value)
            for i = 1:numel(value)
                if strcmp(char(value{i}), char(target))
                    tf = true;
                    return;
                end
            end
        elseif isstring(value) || ischar(value)
            tf = any(strcmp(cellstr(string(value)), char(target)));
        end
    catch
        tf = false;
    end
end

function paths = findLikelyZipCandidates(filePath)
    candidates = {
        filePath
        [filePath '.zip']
        regexprep(filePath, '\.frsproj$', '.zip')
    };

    paths = {};
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            paths{end+1} = candidates{i}; %#ok<AGROW>
        end
    end

    if isempty(paths)
        paths = {'<none>'};
    end
end

function found = findFileByName(rootDir, fileName)
    found = {};

    if ~isfolder(rootDir)
        return;
    end

    listing = dir(rootDir);
    for i = 1:numel(listing)
        name = listing(i).name;

        if listing(i).isdir
            if strcmp(name, '.') || strcmp(name, '..')
                continue;
            end
            sub = findFileByName(fullfile(rootDir, name), fileName);
            found = [found; sub(:)]; %#ok<AGROW>
        else
            if strcmp(name, fileName)
                found{end+1, 1} = fullfile(rootDir, name); %#ok<AGROW>
            end
        end
    end
end

% -------------------------------------------------------------------------
% Studio helpers
% -------------------------------------------------------------------------

function app = createStudioApp()
    app = flightdash.studio.FlightReviewStudioApp();

    if hasProp(app, 'UIFigure') && isgraphics(app.UIFigure)
        app.UIFigure.Visible = 'off';
    end

    drawnow limitrate;
end

function tf = hasProp(obj, propName)
    tf = false;

    if isempty(obj)
        return;
    end

    try
        tf = isprop(obj, propName);
    catch
        tf = false;
    end
end

function safeDelete(obj)
    if isempty(obj)
        return;
    end

    try
        if isgraphics(obj)
            delete(obj);
        elseif isobject(obj) && isvalid(obj)
            delete(obj);
        end
    catch
    end

    drawnow limitrate;
end

% -------------------------------------------------------------------------
% File helpers
% -------------------------------------------------------------------------

function filePath = makeTempFrsprojPath()
    filePath = [tempname() '.frsproj'];
end

function cleanupPath(pathValue)
    if isempty(pathValue)
        return;
    end

    try
        if isfolder(pathValue)
            rmdir(pathValue, 's');
        elseif isfile(pathValue)
            delete(pathValue);
        end
    catch
    end
end

function s = safeChar(value)
    try
        if isempty(value)
            s = '';
        else
            s = char(string(value));
        end
    catch
        s = '<unprintable>';
    end
end

function s = shortError(ME)
    if isempty(ME.identifier)
        s = ME.message;
    else
        s = sprintf('%s: %s', ME.identifier, ME.message);
    end

    s = regexprep(s, '\s+', ' ');
    if strlength(string(s)) > 160
        s = char(extractBefore(string(s), 161));
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