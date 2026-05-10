function results = verifyLinkedSaveLoadAndMultiSessionStability(varargin)
%VERIFYLINKEDSAVELOADANDMULTISESSIONSTABILITY
% Automated no-user-interaction verification for:
%   1) linked .frsproj save/load
%   2) exact extension handling, no unwanted .frsproj.zip residue
%   3) missing linked asset tolerance
%   4) multi-session FlightReviewStudio GUI smoke/stress stability
%
% Usage:
%   results = verifyLinkedSaveLoadAndMultiSessionStability();
%
% Optional:
%   results = verifyLinkedSaveLoadAndMultiSessionStability( ...
%       'NumSessions', 3, ...
%       'TabSwitchCycles', 5, ...
%       'RunGui', true, ...
%       'KeepTempFiles', false, ...
%       'Strict', false);
%
% Notes:
%   - Run from the repository root or ensure the repository root is on path.
%   - This script avoids uigetfile/uiputfile by always passing explicit paths.
%   - GUI tests are skipped automatically if uifigure cannot be created.
%   - It does not require flight/video real data; it uses lightweight dummy linked assets.

    p = inputParser;
    p.addParameter('NumSessions', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('TabSwitchCycles', 5, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('RunGui', true, @(x) islogical(x) || isnumeric(x));
    p.addParameter('KeepTempFiles', false, @(x) islogical(x) || isnumeric(x));
    p.addParameter('Strict', false, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opts = p.Results;

    opts.NumSessions = double(opts.NumSessions);
    opts.TabSwitchCycles = double(opts.TabSwitchCycles);
    opts.RunGui = logical(opts.RunGui);
    opts.KeepTempFiles = logical(opts.KeepTempFiles);
    opts.Strict = logical(opts.Strict);

    ctx = struct();
    ctx.Opts = opts;
    ctx.WorkDir = tempname;
    ctx.Project = [];
    ctx.LoadedProject = [];
    ctx.ProjectPath = fullfile(ctx.WorkDir, 'linked_save_load_test.frsproj');
    ctx.GuiProjectPath = fullfile(ctx.WorkDir, 'gui_roundtrip_test.frsproj');
    ctx.App = [];
    ctx.CreatedAssetPaths = {};
    ctx.MissingAssetPath = '';

    if ~exist(ctx.WorkDir, 'dir')
        mkdir(ctx.WorkDir);
    end

    cleanupObj = onCleanup(@() localCleanup(ctx.WorkDir, opts.KeepTempFiles));

    results = localInitResults(ctx);

    [results, ctx] = localRunStep(results, ctx, ...
        'Environment: required classes and entry points exist', ...
        @localCheckEnvironment);

    [results, ctx] = localRunStep(results, ctx, ...
        'Create linked ProjectModel with multiple SessionModel entries', ...
        @localCreateLinkedProject);

    [results, ctx] = localRunStep(results, ctx, ...
        'ProjectSerializer.save creates exact .frsproj file only', ...
        @localSaveLinkedProject);

    [results, ctx] = localRunStep(results, ctx, ...
        'ProjectSerializer.load round-trip preserves linked session paths', ...
        @localLoadLinkedProject);

    [results, ctx] = localRunStep(results, ctx, ...
        'Linked project load tolerates missing external asset path', ...
        @localMissingLinkedAssetLoad);

    if opts.RunGui
        [results, ctx] = localRunStep(results, ctx, ...
            'GUI capability check: uifigure can be created', ...
            @localCheckGuiCapability);

        if isfield(ctx, 'GuiAvailable') && ctx.GuiAvailable
            [results, ctx] = localRunStep(results, ctx, ...
                'FlightReviewStudio launches without user interaction', ...
                @localLaunchStudio);

            [results, ctx] = localRunStep(results, ctx, ...
                'Add multiple embedded dashboard sessions', ...
                @localAddMultipleGuiSessions);

            [results, ctx] = localRunStep(results, ctx, ...
                'Repeated active tab/session switching remains stable', ...
                @localStressTabSwitching);

            [results, ctx] = localRunStep(results, ctx, ...
                'Repeated GUI mode switching remains stable', ...
                @localStressGuiModes);

            [results, ctx] = localRunStep(results, ctx, ...
                'Studio save/open project round-trip with embedded sessions', ...
                @localStudioSaveOpenRoundTrip);

            [results, ctx] = localRunStep(results, ctx, ...
                'Remove all sessions and delete Studio cleanly', ...
                @localDeleteStudioCleanly);
        else
            results = localAppendResult(results, ...
                'GUI tests skipped', ...
                'SKIP', ...
                'uifigure is not available in this MATLAB execution environment.', ...
                0);
        end
    else
        results = localAppendResult(results, ...
            'GUI tests skipped', ...
            'SKIP', ...
            'RunGui=false.', ...
            0);
    end

    results.EndTime = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    results.Summary = localMakeSummary(results);

    localPrintSummary(results);

    if opts.Strict && results.Summary.Fail > 0
        error('verifyLinkedSaveLoadAndMultiSessionStability:Failed', ...
            'One or more verification steps failed. See results.Checks.');
    end
end

% =========================================================================
% Steps
% =========================================================================

function ctx = localCheckEnvironment(ctx)
    assert(exist('FlightReviewStudio', 'file') == 2, ...
        'FlightReviewStudio.m was not found on the MATLAB path.');

    assert(exist('flightdash.project.ProjectModel', 'class') == 8, ...
        'flightdash.project.ProjectModel class was not found.');

    assert(exist('flightdash.project.SessionModel', 'class') == 8, ...
        'flightdash.project.SessionModel class was not found.');

    assert(exist('flightdash.project.ProjectSerializer', 'class') == 8, ...
        'flightdash.project.ProjectSerializer class was not found.');

    assert(exist('flightdash.studio.FlightReviewStudioApp', 'class') == 8, ...
        'flightdash.studio.FlightReviewStudioApp class was not found.');

    rehash;
end

function ctx = localCreateLinkedProject(ctx)
    opts = ctx.Opts;

    project = flightdash.project.ProjectModel('Automated Linked SaveLoad Test');

    for k = 1:opts.NumSessions
        sessionName = sprintf('Auto Session %02d', k);
        sess = flightdash.project.SessionModel(sessionName);

        flightPath = fullfile(ctx.WorkDir, sprintf('flight_%02d.csv', k));
        videoPath  = fullfile(ctx.WorkDir, sprintf('video_%02d.avi', k));

        localWriteTextFile(flightPath, sprintf("time,altitude\n0,%d\n1,%d\n", k, k + 100));
        localWriteBinaryFile(videoPath, uint8([0 1 2 3 4 5 6 7 8 9]));

        sess = sess.setFlightFile(1, flightPath);
        sess = sess.setVideoFile(1, videoPath);

        if k == 1
            missingPath = fullfile(ctx.WorkDir, 'missing_external_asset.csv');
            sess = sess.setFlightFile(2, missingPath);
            ctx.MissingAssetPath = missingPath;
        end

        project = project.addSession(sess);

        ctx.CreatedAssetPaths{end+1} = flightPath; %#ok<AGROW>
        ctx.CreatedAssetPaths{end+1} = videoPath; %#ok<AGROW>
    end

    assert(project.sessionCount() == opts.NumSessions, ...
        'Project session count mismatch after addSession.');

    ctx.Project = project;
end

function ctx = localSaveLinkedProject(ctx)
    flightdash.project.ProjectSerializer.save(ctx.Project, ctx.ProjectPath);

    assert(isfile(ctx.ProjectPath), ...
        'ProjectSerializer.save did not create the requested .frsproj file.');

    assert(~isfile([ctx.ProjectPath '.zip']), ...
        'Unexpected .frsproj.zip residue exists.');

    inspectDir = fullfile(ctx.WorkDir, 'inspect_frsproj');
    if exist(inspectDir, 'dir')
        rmdir(inspectDir, 's');
    end
    mkdir(inspectDir);

    files = unzip(ctx.ProjectPath, inspectDir);
    fileNames = localNormalizeFileList(files);

    assert(any(contains(fileNames, 'manifest.json')), ...
        'manifest.json was not found inside the .frsproj archive.');

    assert(any(contains(fileNames, 'project.json')), ...
        'project.json was not found inside the .frsproj archive.');

    assert(any(contains(fileNames, 'external_links.json')), ...
        'external_links.json was not found inside the .frsproj archive.');
end

function ctx = localLoadLinkedProject(ctx)
    loaded = flightdash.project.ProjectSerializer.load(ctx.ProjectPath);

    assert(isa(loaded, 'flightdash.project.ProjectModel'), ...
        'Loaded object is not a ProjectModel.');

    assert(strcmp(loaded.ProjectName, ctx.Project.ProjectName), ...
        'ProjectName was not preserved after load.');

    assert(loaded.sessionCount() == ctx.Project.sessionCount(), ...
        'Session count was not preserved after load.');

    for k = 1:ctx.Project.sessionCount()
        src = ctx.Project.Sessions(k);
        dst = loaded.Sessions(k);

        assert(strcmp(src.DisplayName, dst.DisplayName), ...
            'Session DisplayName mismatch after load.');

        assert(strcmp(src.FlightFilePath{1}, dst.FlightFilePath{1}), ...
            'FlightFilePath{1} mismatch after load.');

        assert(strcmp(src.VideoFilePath{1}, dst.VideoFilePath{1}), ...
            'VideoFilePath{1} mismatch after load.');
    end

    ctx.LoadedProject = loaded;
end

function ctx = localMissingLinkedAssetLoad(ctx)
    if isempty(ctx.CreatedAssetPaths)
        error('No linked assets were created.');
    end

    % Delete one asset that is referenced by the saved project.
    victim = ctx.CreatedAssetPaths{1};
    if isfile(victim)
        delete(victim);
    end

    loaded = flightdash.project.ProjectSerializer.load(ctx.ProjectPath);

    assert(isa(loaded, 'flightdash.project.ProjectModel'), ...
        'Project load failed after linked asset deletion.');

    assert(loaded.sessionCount() == ctx.Project.sessionCount(), ...
        'Session count changed after loading with missing linked asset.');

    assert(strcmp(loaded.Sessions(1).FlightFilePath{1}, victim), ...
        'Missing linked asset path was not preserved.');

    ctx.LoadedProjectAfterMissingAsset = loaded;
end

function ctx = localCheckGuiCapability(ctx)
    ctx.GuiAvailable = false;

    try
        f = uifigure('Visible', 'off', 'Name', 'GUI capability check');
        drawnow;
        delete(f);
        ctx.GuiAvailable = true;
    catch ME
        ctx.GuiAvailable = false;
        ctx.GuiUnavailableReason = ME.message;
    end
end

function ctx = localLaunchStudio(ctx)
    app = FlightReviewStudio();

    assert(~isempty(app), ...
        'FlightReviewStudio did not return an app handle.');

    assert(isvalid(app), ...
        'Returned FlightReviewStudio app handle is invalid.');

    assert(isprop(app, 'UIFigure') && ~isempty(app.UIFigure) && isvalid(app.UIFigure), ...
        'Studio UIFigure is missing or invalid.');

    % Hide the window to keep the test non-interactive and less disruptive.
    try
        app.UIFigure.Visible = 'off';
    catch
    end

    drawnow;

    ctx.App = app;
end

function ctx = localAddMultipleGuiSessions(ctx)
    app = ctx.App;
    opts = ctx.Opts;

    assert(~isempty(app) && isvalid(app), ...
        'Studio app is not available.');

    sessionIds = cell(1, opts.NumSessions);

    for k = 1:opts.NumSessions
        name = sprintf('GUI Auto Session %02d', k);
        sessionIds{k} = app.addSession(name);
        drawnow limitrate;

        assert(~isempty(sessionIds{k}), ...
            'addSession returned an empty SessionId.');
    end

    assert(app.Project.sessionCount() == opts.NumSessions, ...
        'Studio Project session count mismatch after addSession.');

    assert(~isempty(app.Workspace) && isvalid(app.Workspace), ...
        'Workspace manager is missing or invalid.');

    if isprop(app.Workspace, 'DashboardEntries')
        assert(app.Workspace.DashboardEntries.Count == opts.NumSessions, ...
            'Workspace DashboardEntries count mismatch.');
    end

    ctx.GuiSessionIds = sessionIds;
end

function ctx = localStressTabSwitching(ctx)
    app = ctx.App;
    ids = ctx.GuiSessionIds;
    opts = ctx.Opts;

    assert(~isempty(ids), 'No GUI session IDs available.');

    for cycle = 1:opts.TabSwitchCycles
        for k = 1:numel(ids)
            sid = ids{k};

            tf = app.Workspace.selectSession(sid);
            drawnow limitrate;
            pause(0.02);

            assert(tf, 'Workspace.selectSession returned false.');

            activeId = app.activeSessionIdFromWorkspace();
            assert(strcmp(activeId, sid), ...
                'Active session mismatch after selectSession.');
        end
    end
end

function ctx = localStressGuiModes(ctx)
    app = ctx.App;

    modes = {'Classic', 'Studio', 'Review', 'Analysis', 'Plot', 'Report', 'Compact', 'Review'};

    for cycle = 1:2
        for k = 1:numel(modes)
            app.setGuiMode(modes{k});
            drawnow limitrate;
            pause(0.02);

            currentMode = app.currentGuiMode();
            assert(strcmpi(currentMode, modes{k}), ...
                'GUI mode did not update as expected.');
        end
    end
end

function ctx = localStudioSaveOpenRoundTrip(ctx)
    app = ctx.App;
    opts = ctx.Opts;

    tf = app.saveProject(ctx.GuiProjectPath);
    drawnow;

    assert(tf, 'app.saveProject returned false.');
    assert(isfile(ctx.GuiProjectPath), ...
        'Studio saveProject did not create the requested file.');
    assert(~isfile([ctx.GuiProjectPath '.zip']), ...
        'Unexpected .frsproj.zip residue after Studio saveProject.');

    app.newProject();
    drawnow;

    assert(app.Project.sessionCount() == 0, ...
        'newProject did not clear sessions.');

    tf = app.openProject(ctx.GuiProjectPath);
    drawnow;

    assert(tf, 'app.openProject returned false.');
    assert(app.Project.sessionCount() == opts.NumSessions, ...
        'openProject did not restore the expected number of sessions.');

    if isprop(app.Workspace, 'DashboardEntries')
        assert(app.Workspace.DashboardEntries.Count == opts.NumSessions, ...
            'openProject did not restore expected workspace dashboard tabs.');
    end
end

function ctx = localDeleteStudioCleanly(ctx)
    app = ctx.App;

    assert(~isempty(app) && isvalid(app), ...
        'Studio app is not available for cleanup test.');

    app.removeAllSessions();
    drawnow;

    assert(app.Project.sessionCount() == 0, ...
        'removeAllSessions did not clear Project sessions.');

    if isprop(app.Workspace, 'DashboardEntries')
        assert(app.Workspace.DashboardEntries.Count == 0, ...
            'removeAllSessions did not clear DashboardEntries.');
    end

    delete(app);
    drawnow;

    ctx.App = [];
end

% =========================================================================
% Test harness helpers
% =========================================================================

function results = localInitResults(ctx)
    results = struct();
    results.StartTime = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    results.EndTime = '';
    results.WorkDir = ctx.WorkDir;
    results.ProjectPath = ctx.ProjectPath;
    results.GuiProjectPath = ctx.GuiProjectPath;
    results.Checks = table( ...
        strings(0,1), strings(0,1), strings(0,1), zeros(0,1), ...
        'VariableNames', {'Name', 'Status', 'Message', 'DurationSec'});
    results.Summary = struct('Pass', 0, 'Fail', 0, 'Skip', 0, 'Total', 0);
end

function [results, ctx] = localRunStep(results, ctx, name, fcn)
    t = tic;

    try
        ctx = fcn(ctx);
        results = localAppendResult(results, name, 'PASS', 'OK', toc(t));
    catch ME
        msg = sprintf('%s: %s', ME.identifier, ME.message);
        results = localAppendResult(results, name, 'FAIL', msg, toc(t));

        % Best-effort console stack trace for fast debugging.
        fprintf(2, '\n[FAIL] %s\n%s\n', name, msg);
        for k = 1:numel(ME.stack)
            fprintf(2, '  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
        end
    end
end

function results = localAppendResult(results, name, status, message, durationSec)
    newRow = table( ...
        string(name), string(status), string(message), durationSec, ...
        'VariableNames', {'Name', 'Status', 'Message', 'DurationSec'});
    results.Checks = [results.Checks; newRow];
end

function summary = localMakeSummary(results)
    statuses = results.Checks.Status;

    summary = struct();
    summary.Pass = sum(statuses == "PASS");
    summary.Fail = sum(statuses == "FAIL");
    summary.Skip = sum(statuses == "SKIP");
    summary.Total = height(results.Checks);
end

function localPrintSummary(results)
    fprintf('\n============================================================\n');
    fprintf('verifyLinkedSaveLoadAndMultiSessionStability\n');
    fprintf('Started : %s\n', results.StartTime);
    fprintf('Ended   : %s\n', results.EndTime);
    fprintf('WorkDir : %s\n', results.WorkDir);
    fprintf('============================================================\n');

    disp(results.Checks);

    fprintf('\nSummary: PASS=%d, FAIL=%d, SKIP=%d, TOTAL=%d\n', ...
        results.Summary.Pass, ...
        results.Summary.Fail, ...
        results.Summary.Skip, ...
        results.Summary.Total);

    if results.Summary.Fail == 0
        fprintf('RESULT: PASS\n');
    else
        fprintf(2, 'RESULT: FAIL\n');
    end
end

function names = localNormalizeFileList(files)
    names = strings(size(files));

    for k = 1:numel(files)
        names(k) = string(strrep(files{k}, filesep, '/'));
    end
end

function localWriteTextFile(path, textValue)
    fid = fopen(path, 'w');
    assert(fid > 0, 'Failed to create text file: %s', path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', char(textValue));
end

function localWriteBinaryFile(path, bytes)
    fid = fopen(path, 'w');
    assert(fid > 0, 'Failed to create binary file: %s', path);
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, bytes, 'uint8');
end

function localCleanup(workDir, keepTempFiles)
    % Close stray non-interactive test windows/dialogs as a last resort.
    try
        figs = findall(groot, 'Type', 'figure');
        for k = 1:numel(figs)
            try
                nm = '';
                if isprop(figs(k), 'Name')
                    nm = char(figs(k).Name);
                end

                if contains(nm, 'GUI capability check') || ...
                   contains(nm, 'FlightDataReviewStudio') || ...
                   contains(nm, 'FlightReviewStudio') || ...
                   contains(nm, 'Save Project Failed') || ...
                   contains(nm, 'Open Project Failed') || ...
                   contains(nm, 'Embed FlightDataDashboard failed')
                    delete(figs(k));
                end
            catch
            end
        end
    catch
    end

    if ~keepTempFiles
        try
            if exist(workDir, 'dir')
                rmdir(workDir, 's');
            end
        catch
            fprintf(2, 'Warning: failed to remove temp dir: %s\n', workDir);
        end
    else
        fprintf('Temp files preserved: %s\n', workDir);
    end
end
