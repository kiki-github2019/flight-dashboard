function results = verifyRiskRegressionTests()
%VERIFYRISKREGRESSIONTESTS
% Risk-focused regression tests for FlightReviewStudio / FlightDataDashboard.
%
% Tests included:
%   RISK-1  OptionFilePath external_links.json inclusion
%   RISK-2  sample project path resolution from WorkspaceManager
%   RISK-3  Korean / non-ASCII .frsproj save/load round-trip
%   RISK-4  silent / empty catch static scan
%   RISK-5  multi-session tab deletion resource cleanup
%   RISK-6  embedded session deletion must not delete existing parpool
%   RISK-7  option*.dat parser section handling
%   RISK-8  Pack Project duplicate filename / relative path handling
%   RISK-9  static guard for isfield(app, ...) class-object misuse
%
% Usage:
%   clear classes
%   rehash toolboxcache
%   results = flightdash.studio.diag.verifyRiskRegressionTests();
%   struct2table(results)

    fprintf('\n=== Risk Regression Tests: FlightReviewStudio / FlightDataDashboard ===\n\n');

    tests = {
        'RISK-1', @checkOptionFileExternalLink
        'RISK-2', @checkSampleProjectPath
        'RISK-3', @checkKoreanNonAsciiSaveLoad
        'RISK-4', @checkSilentCatchStaticScan
        'RISK-5', @checkMultiSessionDeleteResourceCleanup
        'RISK-6', @checkEmbeddedDeleteKeepsParpool
        'RISK-7', @checkOptionFileParserSections
        'RISK-8', @checkPackProjectCollisionAndRelativeLinks
        'RISK-9', @checkNoAppIsfieldClassMisuse
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};

        fprintf('[%s] Running...\n', tc);
        t0 = tic;

        try
            [status, msg] = fn();
        catch ME
            status = 'FAIL';
            msg = sprintf('%s: %s', ME.identifier, ME.message);
        end

        elapsed = toc(t0);
        fprintf('[%s] %s - %s (%.2fs)\n\n', tc, status, msg, elapsed);

        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    fprintf('=== Summary ===\n');
    printSummary(results);
end

% =========================================================================
% RISK-1
% =========================================================================
function [status, msg] = checkOptionFileExternalLink()
% Verify that OptionFilePath is included in external_links.json.
%
% Expected future behavior:
%   external_links.json should contain kind='option_file' entries.
%
% Current repository may FAIL this test if collectExternalLinks() only records
% FlightFilePath and VideoFilePath.

    requireClass('flightdash.project.ProjectSerializer');
    requireClass('flightdash.project.ProjectModel');
    requireClass('flightdash.project.SessionModel');

    outDir = tempname();
    mkdir(outDir);
    cleanup = onCleanup(@() safeRmdir(outDir)); %#ok<NASGU>

    option1 = fullfile(outDir, 'option_flight_1.dat');
    option2 = fullfile(outDir, '옵션_비행_2.dat');

    writeTextFile(option1, "dummy option 1");
    writeTextFile(option2, "dummy option 2");

    project = flightdash.project.ProjectModel('Risk OptionFilePath Test');
    sess = flightdash.project.SessionModel('Session Option Test');
    sess.SessionId = 'RISK_OPT_001';

    if ~isprop(sess, 'OptionFilePath')
        status = 'SKIP';
        msg = 'SessionModel has no OptionFilePath property.';
        return;
    end

    sess.OptionFilePath = {option1, option2};

    if isprop(sess, 'FlightFilePath')
        sess.FlightFilePath = {fullfile(outDir, 'flight1.csv'), ''};
    end
    if isprop(sess, 'VideoFilePath')
        sess.VideoFilePath = {'', fullfile(outDir, 'video2.avi')};
    end

    project = project.addSession(sess);

    frs = fullfile(outDir, 'option_link_test.frsproj');
    flightdash.project.ProjectSerializer.save(project, frs);

    unzipDir = fullfile(outDir, 'unzipped');
    mkdir(unzipDir);
    unzip(frs, unzipDir);

    externalPath = fullfile(unzipDir, 'external_links.json');
    if ~isfile(externalPath)
        status = 'FAIL';
        msg = 'external_links.json was not created.';
        return;
    end

    data = jsondecode(fileread(externalPath));

    if ~isfield(data, 'links')
        status = 'FAIL';
        msg = 'external_links.json has no links field.';
        return;
    end

    links = data.links;
    if isempty(links)
        status = 'FAIL';
        msg = 'external_links.json links is empty.';
        return;
    end

    kinds = collectStructFieldAsCell(links, 'kind');
    paths = collectStructFieldAsCell(links, 'absolutePath');

    hasOptionKind = any(strcmp(kinds, 'option_file')) || ...
                    any(strcmp(kinds, 'option')) || ...
                    any(strcmp(kinds, 'option_data'));

    hasOptionPath1 = any(strcmp(paths, option1));
    hasOptionPath2 = any(strcmp(paths, option2));

    if hasOptionKind && hasOptionPath1 && hasOptionPath2
        status = 'PASS';
        msg = 'OptionFilePath entries are included in external_links.json.';
    else
        status = 'FAIL';
        msg = sprintf(['OptionFilePath not fully represented in external_links.json. ', ...
                       'hasOptionKind=%d, hasOptionPath1=%d, hasOptionPath2=%d. ', ...
                       'ProjectSerializer.collectExternalLinks() likely needs OptionFilePath support.'], ...
                       hasOptionKind, hasOptionPath1, hasOptionPath2);
    end
end

% =========================================================================
% RISK-2
% =========================================================================
function [status, msg] = checkSampleProjectPath()
% Verify WorkspaceManager sample project path calculation.
%
% WorkspaceManager.m lives under:
%   <repo-root>/+flightdash/+studio/WorkspaceManager.m
%
% Therefore repo root is normally:
%   fileparts(fileparts(fileparts(which('flightdash.studio.WorkspaceManager'))))
%
% A common bug is using one too many '..', which points above repo-root.

    wmPath = which('flightdash.studio.WorkspaceManager');

    if isempty(wmPath)
        status = 'FAIL';
        msg = 'flightdash.studio.WorkspaceManager is not on MATLAB path.';
        return;
    end

    here = fileparts(wmPath);

    expectedRoot = normalizeFolder(fullfile(here, '..', '..'));
    suspiciousRoot = normalizeFolder(fullfile(here, '..', '..', '..'));

    expectedSample = fullfile(expectedRoot, 'sample_data', 'sample_project.frsproj');
    suspiciousSample = fullfile(suspiciousRoot, 'sample_data', 'sample_project.frsproj');

    sourceText = fileread(wmPath);
    usesTripleParent = contains(sourceText, "fullfile(root, 'sample_data'") && ...
                       (contains(sourceText, "'..', '..', '..'") || ...
                        contains(sourceText, '"..", "..", ".."'));

    if isfile(expectedSample) && ~isfile(suspiciousSample) && usesTripleParent
        status = 'FAIL';
        msg = sprintf(['Sample project likely resolves to wrong root. ', ...
                       'Expected sample exists: %s, but triple-parent sample does not: %s'], ...
                       expectedSample, suspiciousSample);
        return;
    end

    if ~isfile(expectedSample)
        status = 'SKIP';
        msg = sprintf(['sample_data/sample_project.frsproj not found under expected repo root. ', ...
                       'Path checked: %s. This is a path test skip, not an app failure.'], ...
                       expectedSample);
        return;
    end

    if usesTripleParent
        status = 'WARN';
        msg = sprintf(['WorkspaceManager appears to use triple-parent root traversal. ', ...
                       'Expected sample exists, but source should be reviewed. expected=%s'], ...
                       expectedSample);
        return;
    end

    status = 'PASS';
    msg = sprintf('Sample project path appears valid: %s', expectedSample);
end

% =========================================================================
% RISK-3
% =========================================================================
function [status, msg] = checkKoreanNonAsciiSaveLoad()
% Verify save/load under Korean / non-ASCII path.

    requireClass('flightdash.project.ProjectSerializer');
    requireClass('flightdash.project.ProjectModel');
    requireClass('flightdash.project.SessionModel');

    baseDir = [tempname() '_한글_테스트'];
    mkdir(baseDir);
    cleanup = onCleanup(@() safeRmdir(baseDir)); %#ok<NASGU>

    projectPath = fullfile(baseDir, '비행리뷰_프로젝트_테스트.frsproj');

    project = flightdash.project.ProjectModel('한글 프로젝트 테스트');
    sess = flightdash.project.SessionModel('세션 1');
    sess.SessionId = 'RISK_KOR_001';

    if isprop(sess, 'FlightFilePath')
        sess.FlightFilePath = {fullfile(baseDir, '비행데이터1.csv'), ''};
    end
    if isprop(sess, 'VideoFilePath')
        sess.VideoFilePath = {'', fullfile(baseDir, '영상2.avi')};
    end
    if isprop(sess, 'OptionFilePath')
        sess.OptionFilePath = {fullfile(baseDir, '옵션1.dat'), fullfile(baseDir, '옵션2.dat')};
    end

    project = project.addSession(sess);

    flightdash.project.ProjectSerializer.save(project, projectPath);

    if ~isfile(projectPath)
        status = 'FAIL';
        msg = sprintf('Project file was not created at non-ASCII path: %s', projectPath);
        return;
    end

    if isfile([projectPath '.zip'])
        status = 'FAIL';
        msg = sprintf('Unexpected .zip residue remained: %s', [projectPath '.zip']);
        return;
    end

    loaded = flightdash.project.ProjectSerializer.load(projectPath);

    ok = isa(loaded, 'flightdash.project.ProjectModel') && ...
         strcmp(char(loaded.ProjectName), '한글 프로젝트 테스트') && ...
         numel(loaded.Sessions) == 1 && ...
         strcmp(char(loaded.Sessions(1).SessionId), 'RISK_KOR_001');

    if ok
        status = 'PASS';
        msg = 'Korean / non-ASCII path save/load round-trip succeeded.';
    else
        status = 'FAIL';
        msg = 'Korean / non-ASCII path save/load round-trip did not preserve expected metadata.';
    end
end

% =========================================================================
% RISK-4
% =========================================================================
function [status, msg] = checkSilentCatchStaticScan()
% Static scan for suspicious catch blocks.
%
% This is intentionally heuristic. It flags:
%   1. catch immediately followed by end
%   2. catch block with no log/warning/error/rethrow/disp/fprintf/uialert
%
% The test returns:
%   PASS: no suspicious catch blocks
%   WARN: suspicious catch blocks found
%
% This should normally be WARN until silent catches are cleaned up.

    root = repoRootFromKnownFile();

    if isempty(root) || ~isfolder(root)
        status = 'SKIP';
        msg = 'Could not determine repository root for static catch scan.';
        return;
    end

    files = dir(fullfile(root, '**', '*.m'));

    suspicious = {};
    maxReport = 25;

    loggingTokens = {
        'logCaught'
        'warning'
        'error'
        'rethrow'
        'disp'
        'fprintf'
        'uialert'
        'ErrorLog'
    };

    for i = 1:numel(files)
        fpath = fullfile(files(i).folder, files(i).name);

        % Skip this diagnostic file itself to avoid false positives.
        if endsWith(fpath, 'verifyRiskRegressionTests.m')
            continue;
        end

        try
            lines = splitlines(string(fileread(fpath)));
        catch
            continue;
        end

        for ln = 1:numel(lines)
            text = strtrim(lines(ln));

            if ~isCatchLine(text)
                continue;
            end

            [blockText, firstBodyLine, isEmpty] = collectCatchBlock(lines, ln);

            if isEmpty
                suspicious{end+1} = formatFinding(root, fpath, ln, 'empty catch block'); %#ok<AGROW>
            else
                hasLog = false;
                for t = 1:numel(loggingTokens)
                    if contains(blockText, loggingTokens{t})
                        hasLog = true;
                        break;
                    end
                end

                if ~hasLog
                    suspicious{end+1} = formatFinding(root, fpath, firstBodyLine, 'catch block without visible logging'); %#ok<AGROW>
                end
            end

            if numel(suspicious) >= maxReport
                break;
            end
        end

        if numel(suspicious) >= maxReport
            break;
        end
    end

    if isempty(suspicious)
        status = 'PASS';
        msg = 'No suspicious silent catch blocks found by static scan.';
    else
        status = 'WARN';
        msg = sprintf('Found %d suspicious catch block(s). First findings: %s', ...
            numel(suspicious), strjoin(suspicious, ' | '));
    end
end

% =========================================================================
% RISK-5
% =========================================================================
function [status, msg] = checkMultiSessionDeleteResourceCleanup()
% Create Studio app, add two sessions, delete one, and verify:
%   - deleted session removed from Workspace DashboardEntries
%   - UndoService for deleted session removed
%   - SharedCacheService invalidated deleted session entries
%   - MouseRouter remains valid
%   - remaining session still exists
%
% This is a GUI smoke test and may open a uifigure.

    requireClass('flightdash.studio.FlightReviewStudioApp');

    app = [];
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>

    app = flightdash.studio.FlightReviewStudioApp();

    if ~ismethod(app, 'addSession')
        status = 'FAIL';
        msg = 'FlightReviewStudioApp.addSession is not available.';
        return;
    end

    sid1 = app.addSession('Risk Session 1');
    sid2 = app.addSession('Risk Session 2');

    if isempty(sid1) || isempty(sid2) || strcmp(sid1, sid2)
        status = 'FAIL';
        msg = 'Could not create two distinct sessions.';
        return;
    end

    % Seed shared cache with deleted-session and surviving-session entries.
    try
        app.SharedCacheService.store(sid1, 1, 'risk_video_1.avi', 10, uint8(ones(4,4,3)));
        app.SharedCacheService.store(sid2, 1, 'risk_video_2.avi', 20, uint8(2*ones(4,4,3)));
    catch
        % If service is not available, the checks below will catch it.
    end

    if ~ismethod(app, 'removeSession')
        status = 'FAIL';
        msg = 'FlightReviewStudioApp.removeSession is not available.';
        return;
    end

    app.removeSession(sid1);
    drawnow;

    deletedStillInWorkspace = false;
    remainingStillInWorkspace = false;

    try
        deletedStillInWorkspace = app.Workspace.DashboardEntries.isKey(char(sid1));
        remainingStillInWorkspace = app.Workspace.DashboardEntries.isKey(char(sid2));
    catch
    end

    deletedUndoStillExists = false;
    try
        deletedUndoStillExists = app.UndoServices.isKey(char(sid1));
    catch
    end

    mouseRouterOk = false;
    try
        mouseRouterOk = ~isempty(app.MouseRouter) && isvalid(app.MouseRouter);
    catch
    end

    cacheDeletedGone = true;
    cacheRemainingAlive = true;

    try
        cacheDeletedGone = ~app.SharedCacheService.has(sid1, 1, 'risk_video_1.avi', 10);
        cacheRemainingAlive = app.SharedCacheService.has(sid2, 1, 'risk_video_2.avi', 20);
    catch
        cacheDeletedGone = false;
        cacheRemainingAlive = false;
    end

    if deletedStillInWorkspace
        status = 'FAIL';
        msg = sprintf('Deleted session still exists in Workspace.DashboardEntries: %s', sid1);
        return;
    end

    if ~remainingStillInWorkspace
        status = 'FAIL';
        msg = sprintf('Remaining session disappeared from Workspace.DashboardEntries: %s', sid2);
        return;
    end

    if deletedUndoStillExists
        status = 'FAIL';
        msg = sprintf('UndoService for deleted session still exists: %s', sid1);
        return;
    end

    if ~mouseRouterOk
        status = 'FAIL';
        msg = 'MouseRouter is missing or invalid after deleting one session.';
        return;
    end

    if ~cacheDeletedGone
        status = 'FAIL';
        msg = 'SharedCacheService still has deleted-session cache entries.';
        return;
    end

    if ~cacheRemainingAlive
        status = 'FAIL';
        msg = 'SharedCacheService lost surviving-session cache entries unexpectedly.';
        return;
    end

    status = 'PASS';
    msg = 'Multi-session delete cleanup preserved surviving resources and removed deleted-session resources.';
end

% =========================================================================
% RISK-6
% =========================================================================
function [status, msg] = checkEmbeddedDeleteKeepsParpool()
% Verify deleting an embedded dashboard/session does not delete an existing
% parallel pool.
%
% This test does NOT create a new parpool. It only checks preservation of an
% already-existing pool, to avoid expensive or unwanted pool startup.

    pool = [];
    try
        pool = gcp('nocreate');
    catch ME
        status = 'SKIP';
        msg = sprintf('Parallel Computing Toolbox may be unavailable: %s', ME.message);
        return;
    end

    if isempty(pool)
        status = 'SKIP';
        msg = 'No existing parpool. Test skipped to avoid starting a pool automatically.';
        return;
    end

    poolBefore = pool;
    poolBeforeId = poolBefore.ID;

    requireClass('flightdash.studio.FlightReviewStudioApp');

    app = [];
    cleanup = onCleanup(@() safeDelete(app)); %#ok<NASGU>

    app = flightdash.studio.FlightReviewStudioApp();

    sid1 = app.addSession('Parpool Keep Session 1');
    sid2 = app.addSession('Parpool Keep Session 2');

    if isempty(sid1) || isempty(sid2)
        status = 'FAIL';
        msg = 'Could not create embedded sessions for parpool preservation test.';
        return;
    end

    app.removeSession(sid1);
    drawnow;

    poolAfter = gcp('nocreate');

    if isempty(poolAfter)
        status = 'FAIL';
        msg = 'Existing parpool was deleted after embedded session removal.';
        return;
    end

    if poolAfter.ID ~= poolBeforeId
        status = 'FAIL';
        msg = sprintf('Parpool changed after embedded session removal. before=%d, after=%d', ...
            poolBeforeId, poolAfter.ID);
        return;
    end

    status = 'PASS';
    msg = sprintf('Existing parpool remained alive after embedded session deletion. pool ID=%d', poolAfter.ID);
end

% =========================================================================
% RISK-7
% =========================================================================
function [status, msg] = checkOptionFileParserSections()
% Verify option*.dat section comments are explicit and robust.

    requireClass('flightdash.project.OptionFileParser');

    outDir = tempname();
    mkdir(outDir);
    cleanup = onCleanup(@() safeRmdir(outDir)); %#ok<NASGU>

    optionPath = fullfile(outDir, 'option2.dat');
    writeTextFile(optionPath, strjoin({ ...
        '# [mapping] maps flight data columns to FlightDashboard keys'
        '# mapping comments are preserved but do not create extra sections'
        'Time : time'
        'Roll : Flight2_ROLL'
        'Pitch : Flight2_PITCH'
        'Heading : Flight2_HEADING'
        'Alt : Flight2_ALT'
        'Lat : Flight2_LAT'
        'Lon : Flight2_LON'
        ''
        '# [display] field name, unit, numeric format, display order, scale factor'
        '# display comments are comments, not data'
        'time,s,%.3f,1,1'
        'Flight2_ROLL,deg/sec,%.3f,7,10'
        }, newline));

    model = flightdash.project.OptionFileParser.read(optionPath);
    timeMap = mappingValue(model, 'Time');
    rollMap = mappingValue(model, 'Roll');
    rollIdx = find(string(model.Display.FieldName) == "Flight2_ROLL", 1);

    if ~strcmp(timeMap, 'time') || ~strcmp(rollMap, 'Flight2_ROLL') || isempty(rollIdx)
        status = 'FAIL';
        msg = 'OptionFileParser did not preserve mapping/display rows with explicit section comments.';
        return;
    end
    if double(model.Display.ScaleFactor(rollIdx)) ~= 10
        status = 'FAIL';
        msg = 'OptionFileParser did not preserve display scale factor.';
        return;
    end

    legacyPath = fullfile(outDir, 'legacy_option2.dat');
    writeTextFile(legacyPath, strjoin({ ...
        '# mapping flight datas to key variables in codes for GUI of FlightDashBoard'
        'Time : time'
        'Roll : Flight2_ROLL'
        ''
        '# Flight data field name, unit, Floating-point display format, order in GUI, scale factor'
        'time,s,%.3f,1,1'
        }, newline));
    legacy = flightdash.project.OptionFileParser.read(legacyPath);
    if ~strcmp(mappingValue(legacy, 'Roll'), 'Flight2_ROLL') || height(legacy.Display) ~= 1
        status = 'FAIL';
        msg = 'OptionFileParser did not support legacy descriptive section comments.';
        return;
    end

    outPath = fullfile(outDir, 'written_option2.dat');
    flightdash.project.OptionFileParser.write(model, outPath);
    written = fileread(outPath);
    if ~contains(written, '# [mapping]') || ~contains(written, '# [display]')
        status = 'FAIL';
        msg = 'OptionFileParser.write did not emit explicit section markers.';
        return;
    end

    status = 'PASS';
    msg = 'OptionFileParser handles explicit and legacy section comments.';
end

% =========================================================================
% RISK-8
% =========================================================================
function [status, msg] = checkPackProjectCollisionAndRelativeLinks()
% Verify Pack Project keeps duplicate basenames unique and portable.

    requireClass('flightdash.project.ProjectPacker');
    requireClass('flightdash.project.ProjectSerializer');
    requireClass('flightdash.project.ProjectHealthChecker');
    requireClass('flightdash.project.ProjectModel');
    requireClass('flightdash.project.SessionModel');

    outDir = tempname();
    mkdir(outDir);
    cleanup = onCleanup(@() safeRmdir(outDir)); %#ok<NASGU>

    srcA = fullfile(outDir, 'sourceA');
    srcB = fullfile(outDir, 'sourceB');
    dest = fullfile(outDir, 'packed');
    mkdir(srcA);
    mkdir(srcB);
    mkdir(dest);

    flightA = fullfile(srcA, 'flight.csv');
    flightB = fullfile(srcB, 'flight.csv');
    optionA = fullfile(srcA, 'option.dat');
    optionB = fullfile(srcB, 'option.dat');

    writeTextFile(flightA, "time,roll" + newline + "0,sourceA");
    writeTextFile(flightB, "time,roll" + newline + "0,sourceB");
    writeTextFile(optionA, "# [mapping]" + newline + "Roll : A_ROLL");
    writeTextFile(optionB, "# [mapping]" + newline + "Roll : B_ROLL");

    project = flightdash.project.ProjectModel('Pack Collision Test');
    sessA = flightdash.project.SessionModel('Collision A');
    sessB = flightdash.project.SessionModel('Collision B');
    sessA.FlightFilePath = {flightA, ''};
    sessB.FlightFilePath = {flightB, ''};
    sessA.OptionFilePath = {optionA, ''};
    sessB.OptionFilePath = {optionB, ''};
    project = project.addSession(sessA);
    project = project.addSession(sessB);

    opts = struct('IncludeVideo', false, 'Overwrite', true);
    result = flightdash.project.ProjectPacker.pack(project, dest, opts);
    if ~result.OK
        status = 'FAIL';
        msg = sprintf('ProjectPacker.pack failed: %s', strjoin(result.Warnings, ' | '));
        return;
    end

    packed = flightdash.project.ProjectSerializer.load(result.PackedProjectPath);
    packed.ProjectFolderPath = result.PackedRoot;
    if numel(packed.Sessions) ~= 2
        status = 'FAIL';
        msg = 'Packed project did not preserve both sessions.';
        return;
    end

    flightRel = {packed.Sessions.FlightFilePath};
    optionRel = {packed.Sessions.OptionFilePath};
    flightRel = cellfun(@(p) p{1}, flightRel, 'UniformOutput', false);
    optionRel = cellfun(@(p) p{1}, optionRel, 'UniformOutput', false);

    allRel = [flightRel, optionRel];
    if any(cellfun(@isAbsolutePathLocal, allRel))
        status = 'FAIL';
        msg = 'Packed project still contains absolute asset paths.';
        return;
    end
    if numel(unique(flightRel)) ~= 2 || numel(unique(optionRel)) ~= 2
        status = 'FAIL';
        msg = 'Duplicate source basenames were not rewritten to unique packed paths.';
        return;
    end

    flightDst = cellfun(@(p) fullfile(result.PackedRoot, strrep(p, '/', filesep)), ...
        flightRel, 'UniformOutput', false);
    optionDst = cellfun(@(p) fullfile(result.PackedRoot, strrep(p, '/', filesep)), ...
        optionRel, 'UniformOutput', false);
    if any(~cellfun(@isfile, [flightDst, optionDst]))
        status = 'FAIL';
        msg = 'One or more rewritten packed asset paths do not exist.';
        return;
    end
    if ~contains(fileread(flightDst{1}), 'sourceA') || ...
            ~contains(fileread(flightDst{2}), 'sourceB') || ...
            ~contains(fileread(optionDst{1}), 'A_ROLL') || ...
            ~contains(fileread(optionDst{2}), 'B_ROLL')
        status = 'FAIL';
        msg = 'Packed duplicate filenames did not preserve source-specific contents.';
        return;
    end

    report = flightdash.project.ProjectHealthChecker.check(packed);
    if ~flightdash.project.ProjectHealthChecker.isHealthy(report)
        status = 'FAIL';
        msg = sprintf('Packed project health check failed: %s', ...
            flightdash.project.ProjectHealthChecker.summarize(report));
        return;
    end

    status = 'PASS';
    msg = 'Pack Project keeps duplicate basenames unique and uses relative paths.';
end

% =========================================================================
% RISK-9
% =========================================================================
function [status, msg] = checkNoAppIsfieldClassMisuse()
% Guard against treating class app handles as structs.

    root = repoRootFromKnownFile();
    if isempty(root) || ~isfolder(root)
        status = 'SKIP';
        msg = 'Could not determine repository root for isfield(app, ...) scan.';
        return;
    end

    patterns = {
        'isfield\s*\(\s*app\s*,'
        'isfield\s*\(\s*obj\.App\s*,'
    };
    files = dir(fullfile(root, '**', '*.m'));
    suspicious = {};

    for i = 1:numel(files)
        fpath = fullfile(files(i).folder, files(i).name);
        if endsWith(fpath, 'verifyRiskRegressionT.m')
            continue;
        end
        try
            lines = splitlines(string(fileread(fpath)));
        catch
            continue;
        end
        for ln = 1:numel(lines)
            text = strtrim(lines(ln));
            if text == "" || startsWith(text, "%")
                continue;
            end
            for p = 1:numel(patterns)
                if ~isempty(regexp(char(text), patterns{p}, 'once'))
                    suspicious{end+1} = formatFinding(root, fpath, ln, ...
                        'isfield(app, ...) class-object misuse'); %#ok<AGROW>
                    break;
                end
            end
            if numel(suspicious) >= 10
                break;
            end
        end
        if numel(suspicious) >= 10
            break;
        end
    end

    if isempty(suspicious)
        status = 'PASS';
        msg = 'No raw isfield(app, ...) or isfield(obj.App, ...) misuse patterns found.';
    else
        status = 'FAIL';
        msg = sprintf('Found %d app isfield misuse pattern(s): %s', ...
            numel(suspicious), strjoin(suspicious, ' | '));
    end
end

% =========================================================================
% Helper functions
% =========================================================================
function requireClass(className)
    if isempty(meta.class.fromName(className))
        error('RiskTests:MissingClass', 'Required class not found: %s', className);
    end
end

function writeTextFile(path, text)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        fid = fopen(path, 'w');
    end
    if fid < 0
        error('RiskTests:FileWriteFailed', 'Cannot write file: %s', path);
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', char(text));
end

function values = collectStructFieldAsCell(s, fieldName)
    values = {};

    if isempty(s)
        return;
    end

    if isstruct(s)
        for k = 1:numel(s)
            if isfield(s(k), fieldName)
                values{end+1} = char(string(s(k).(fieldName))); %#ok<AGROW>
            end
        end
    elseif iscell(s)
        for k = 1:numel(s)
            item = s{k};
            if isstruct(item) && isfield(item, fieldName)
                values{end+1} = char(string(item.(fieldName))); %#ok<AGROW>
            end
        end
    end
end

function value = mappingValue(model, key)
    value = '';
    idx = find(string(model.Mapping.Key) == string(key), 1);
    if ~isempty(idx)
        value = char(model.Mapping.MappedField(idx));
    end
end

function tf = isAbsolutePathLocal(pathValue)
    tf = false;
    try
        p = char(pathValue);
        if isempty(p), return; end
        tf = logical(java.io.File(p).isAbsolute());
    catch
        try
            p = char(pathValue);
            tf = startsWith(p, filesep) || startsWith(p, '\\') || ...
                ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'));
        catch
            tf = false;
        end
    end
end

function p = normalizeFolder(p)
    p = char(p);
    old = pwd;
    c = onCleanup(@() cd(old)); %#ok<NASGU>

    if isfolder(p)
        cd(p);
        p = pwd;
    else
        parent = fileparts(p);
        if isfolder(parent)
            cd(parent);
            p = fullfile(pwd, getLastPathPart(p));
        end
    end
end

function name = getLastPathPart(p)
    [~, name, ext] = fileparts(p);
    name = [name ext];
end

function root = repoRootFromKnownFile()
    root = '';

    candidates = {
        which('flightdash.studio.WorkspaceManager')
        which('flightdash.project.ProjectSerializer')
        which('FlightReviewStudio')
    };

    for k = 1:numel(candidates)
        p = candidates{k};
        if isempty(p)
            continue;
        end

        if endsWith(p, fullfile('+flightdash', '+studio', 'WorkspaceManager.m'))
            here = fileparts(p);
            root = normalizeFolder(fullfile(here, '..', '..'));
            return;
        end

        if endsWith(p, fullfile('+flightdash', '+project', 'ProjectSerializer.m'))
            here = fileparts(p);
            root = normalizeFolder(fullfile(here, '..', '..'));
            return;
        end

        if endsWith(p, 'FlightReviewStudio.m')
            root = fileparts(p);
            return;
        end
    end
end

function tf = isCatchLine(text)
    text = char(text);
    tf = ~isempty(regexp(text, '^\s*catch(\s+[\w_]+)?\s*(%.*)?$', 'once'));
end

function [blockText, firstBodyLine, isEmpty] = collectCatchBlock(lines, catchLine)
    blockLines = strings(0, 1);
    firstBodyLine = catchLine + 1;
    isEmpty = true;

    for j = catchLine+1:numel(lines)
        raw = lines(j);
        t = strtrim(raw);

        if startsWith(t, "%") || t == ""
            continue;
        end

        firstBodyLine = j;

        if ~isempty(regexp(char(t), '^\s*end\s*(%.*)?$', 'once'))
            blockText = "";
            isEmpty = true;
            return;
        end

        break;
    end

    for j = catchLine+1:numel(lines)
        raw = lines(j);
        t = strtrim(raw);

        if ~isempty(regexp(char(t), '^\s*end\s*(%.*)?$', 'once'))
            break;
        end

        if t ~= "" && ~startsWith(t, "%")
            isEmpty = false;
            blockLines(end+1, 1) = raw; %#ok<AGROW>
        end
    end

    blockText = strjoin(blockLines, newline);
end

function s = formatFinding(root, fpath, lineNo, reason)
    rel = fpath;
    try
        if startsWith(fpath, root)
            rel = extractAfter(fpath, strlength(root) + 1);
        end
    catch
    end

    s = sprintf('%s:%d %s', char(rel), lineNo, reason);
end

function safeRmdir(p)
    try
        if isfolder(p)
            rmdir(p, 's');
        end
    catch
    end
end

function safeDelete(h)
    try
        if ~isempty(h) && isa(h, 'handle') && isvalid(h)
            delete(h);
        end
    catch
    end
end

function printSummary(results)
    passCount = sum(strcmp({results.Result}, 'PASS'));
    failCount = sum(strcmp({results.Result}, 'FAIL'));
    warnCount = sum(strcmp({results.Result}, 'WARN'));
    skipCount = sum(strcmp({results.Result}, 'SKIP'));

    fprintf('PASS: %d\n', passCount);
    fprintf('FAIL: %d\n', failCount);
    fprintf('WARN: %d\n', warnCount);
    fprintf('SKIP: %d\n', skipCount);
    fprintf('TOTAL: %d\n', numel(results));

    if failCount > 0
        fprintf('\nFailed tests:\n');
        for k = 1:numel(results)
            if strcmp(results(k).Result, 'FAIL')
                fprintf('  %s - %s\n', results(k).TC, results(k).Message);
            end
        end
    end
end
