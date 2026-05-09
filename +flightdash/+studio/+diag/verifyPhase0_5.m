function results = verifyPhase0_5()
%VERIFYPHASE0_5 Phase 0.5 verification: encoding / formatting / entry parse smoke checks.
%
% Usage:
%   results = flightdash.studio.diag.verifyPhase0_5();

    fprintf('\n=== Phase 0.5 verification: Encoding / Formatting Stabilization ===\n\n');

    tests = {
        'P0.5-1', @checkRepoRootAndKeyFiles
        'P0.5-2', @checkEntryFilesReadable
        'P0.5-3', @checkPackageFilesReadable
        'P0.5-4', @checkLikelyOneLineCommentRisk
        'P0.5-5', @checkMFileParseSmoke
        'P0.5-6', @checkGitattributes
        'P0.5-7', @checkMojibakeRisk
        'P0.5-8', @checkMainEntryResolution
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});

    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};

        try
            [ok, msg, status] = fn();
            if nargin(fn) < 0 %#ok<NASGU>
                % no-op; keeps older MATLAB analyzers quiet for function handle metadata
            end

            if nargin < 0 %#ok<UNRCH>
                status = '';
            end

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

        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);

    passCount = sum(strcmp({results.Result}, 'PASS'));
    totalCount = numel(results);
    fprintf('\n%d / %d Phase 0.5 checks passed.\n', passCount, totalCount);
end

% -------------------------------------------------------------------------
% Checks
% -------------------------------------------------------------------------

function [ok, msg, status] = checkRepoRootAndKeyFiles()
    status = '';

    root = repoRoot();
    required = {
        fullfile(root, 'FlightReviewStudio.m')
        fullfile(root, 'FlightDataDashboard.m')
        fullfile(root, '+flightdash', 'FlightDataDashboard.m')
        fullfile(root, '+flightdash', '+studio', 'FlightReviewStudioApp.m')
        fullfile(root, '+flightdash', '+studio', '+diag', 'verifyPhase4.m')
    };

    missing = {};
    for i = 1:numel(required)
        if ~isfile(required{i})
            missing{end+1} = relpath(required{i}, root); %#ok<AGROW>
        end
    end

    ok = isempty(missing);
    if ok
        msg = sprintf('Repository root resolved and %d key files exist', numel(required));
    else
        msg = sprintf('Missing key files: %s', strjoin(missing, ', '));
    end
end

function [ok, msg, status] = checkEntryFilesReadable()
    status = '';

    root = repoRoot();
    files = {
        fullfile(root, 'FlightReviewStudio.m')
        fullfile(root, 'FlightDataDashboard.m')
    };

    bad = {};
    for i = 1:numel(files)
        [txt, err] = readTextFile(files{i});
        if ~isempty(err) || isempty(txt)
            bad{end+1} = sprintf('%s (%s)', relpath(files{i}, root), err); %#ok<AGROW>
        end
    end

    ok = isempty(bad);
    if ok
        msg = 'Root entry files are readable';
    else
        msg = sprintf('Unreadable entry files: %s', strjoin(bad, '; '));
    end
end

function [ok, msg, status] = checkPackageFilesReadable()
    status = '';

    root = repoRoot();
    files = listMFiles(fullfile(root, '+flightdash'));

    if isempty(files)
        ok = false;
        msg = 'No package .m files found under +flightdash';
        return;
    end

    unreadable = {};
    for i = 1:numel(files)
        [txt, err] = readTextFile(files{i}); %#ok<ASGLU>
        if ~isempty(err)
            unreadable{end+1} = sprintf('%s (%s)', relpath(files{i}, root), err); %#ok<AGROW>
        end
    end

    ok = isempty(unreadable);
    if ok
        msg = sprintf('%d package .m files are readable', numel(files));
    else
        msg = sprintf('Unreadable package files: %s', strjoin(firstN(unreadable, 5), '; '));
    end
end

function [ok, msg, status] = checkLikelyOneLineCommentRisk()
    status = '';

    root = repoRoot();
    files = {
        fullfile(root, 'FlightReviewStudio.m')
        fullfile(root, 'FlightDataDashboard.m')
        fullfile(root, '+flightdash', 'FlightDataDashboard.m')
        fullfile(root, '+flightdash', '+studio', 'FlightReviewStudioApp.m')
    };

    risky = {};
    for i = 1:numel(files)
        if ~isfile(files{i})
            continue;
        end

        [txt, err] = readTextFile(files{i});
        if ~isempty(err)
            risky{end+1} = sprintf('%s unreadable', relpath(files{i}, root)); %#ok<AGROW>
            continue;
        end

        lines = regexp(txt, '\r\n|\n|\r', 'split');
        nonEmpty = lines(~cellfun(@(s) isempty(strtrim(s)), lines));

        if numel(nonEmpty) <= 2
            risky{end+1} = sprintf('%s has only %d non-empty physical lines', ...
                relpath(files{i}, root), numel(nonEmpty)); %#ok<AGROW>
            continue;
        end

        for j = 1:numel(nonEmpty)
            s = strtrim(nonEmpty{j});
            if startsWith(s, '%') && contains(s, 'function ')
                risky{end+1} = sprintf('%s contains function text after line comment', ...
                    relpath(files{i}, root)); %#ok<AGROW>
                break;
            end
        end
    end

    ok = isempty(risky);
    if ok
        msg = 'No obvious one-line/comment-swallow formatting risk in key files';
    else
        msg = sprintf('Potential formatting risk: %s', strjoin(firstN(risky, 5), '; '));
    end
end

function [ok, msg, status] = checkMFileParseSmoke()
    status = '';

    root = repoRoot();
    files = {
        fullfile(root, 'FlightReviewStudio.m')
        fullfile(root, 'FlightDataDashboard.m')
        fullfile(root, '+flightdash', 'FlightDataDashboard.m')
        fullfile(root, '+flightdash', '+studio', 'FlightReviewStudioApp.m')
        fullfile(root, '+flightdash', '+project', 'ProjectModel.m')
        fullfile(root, '+flightdash', '+project', 'SessionModel.m')
        fullfile(root, '+flightdash', '+project', 'ProjectSerializer.m')
        fullfile(root, '+flightdash', '+util', 'AppEventData.m')
        fullfile(root, '+flightdash', '+util', 'SessionScope.m')
    };

    failures = {};
    for i = 1:numel(files)
        if ~isfile(files{i})
            failures{end+1} = sprintf('%s missing', relpath(files{i}, root)); %#ok<AGROW>
            continue;
        end

        try
            issues = checkcode(files{i}, '-id');
            fatal = filterLikelyFatalCheckcodeIssues(issues);
            if ~isempty(fatal)
                failures{end+1} = sprintf('%s: %s', relpath(files{i}, root), fatal{1}); %#ok<AGROW>
            end
        catch ME
            failures{end+1} = sprintf('%s: %s', relpath(files{i}, root), ME.message); %#ok<AGROW>
        end
    end

    ok = isempty(failures);
    if ok
        msg = sprintf('%d key MATLAB files passed parse-smoke checkcode scan', numel(files));
    else
        msg = sprintf('Parse-smoke issues: %s', strjoin(firstN(failures, 5), '; '));
    end
end

function [ok, msg, status] = checkGitattributes()
    status = '';

    root = repoRoot();
    file = fullfile(root, '.gitattributes');

    if ~isfile(file)
        ok = false;
        msg = '.gitattributes missing';
        return;
    end

    [txt, err] = readTextFile(file);
    if ~isempty(err)
        ok = false;
        msg = sprintf('.gitattributes unreadable: %s', err);
        return;
    end

    hasM = contains(txt, '*.m') && contains(lower(txt), 'text');
    hasEol = contains(lower(txt), 'eol=lf');

    ok = hasM && hasEol;
    if ok
        msg = '.gitattributes contains MATLAB text/LF normalization rule';
    else
        msg = '.gitattributes exists but lacks clear *.m text eol=lf normalization';
    end
end

function [ok, msg, status] = checkMojibakeRisk()
    status = '';

    root = repoRoot();
    files = listMFiles(root);

    patterns = buildMojibakePatterns();

    hits = {};
    maxFiles = min(numel(files), 250);

    for i = 1:maxFiles
        [txt, err] = readTextFile(files{i});
        if ~isempty(err)
            continue;
        end

        for p = 1:numel(patterns)
            if contains(txt, patterns{p})
                hits{end+1} = sprintf('%s contains "%s"', relpath(files{i}, root), patterns{p}); %#ok<AGROW>
                break;
            end
        end
    end

    ok = isempty(hits);
    if ok
        msg = sprintf('No common mojibake markers detected in %d scanned .m files', maxFiles);
    else
        msg = sprintf('Potential mojibake markers: %s', strjoin(firstN(hits, 8), '; '));
    end
end

function patterns = buildMojibakePatterns()
    patterns = {
        char(65533)
        ['?' char(50553)]
    };
end

function [ok, msg, status] = checkMainEntryResolution()
    status = '';

    entries = {'FlightReviewStudio', 'FlightDataDashboard'};
    resolved = {};
    unresolved = {};

    for i = 1:numel(entries)
        p = which(entries{i});
        if isempty(p)
            unresolved{end+1} = entries{i}; %#ok<AGROW>
        else
            resolved{end+1} = sprintf('%s -> %s', entries{i}, p); %#ok<AGROW>
        end
    end

    ok = isempty(unresolved);
    if ok
        msg = sprintf('Entries resolved: %s', strjoin(resolved, '; '));
    else
        msg = sprintf('Unresolved entries: %s', strjoin(unresolved, ', '));
    end
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function root = repoRoot()
    current = fileparts(mfilename('fullpath'));

    while true
        if isfile(fullfile(current, 'FlightDataDashboard.m')) && ...
           isfolder(fullfile(current, '+flightdash'))
            root = current;
            return;
        end

        parent = fileparts(current);
        if strcmp(parent, current)
            error('verifyPhase0_5:RepoRootNotFound', ...
                'Could not locate repository root from %s', fileparts(mfilename('fullpath')));
        end

        current = parent;
    end
end

function files = listMFiles(folder)
    if ~isfolder(folder)
        files = {};
        return;
    end

    listing = dir(folder);
    files = {};

    for i = 1:numel(listing)
        name = listing(i).name;

        if listing(i).isdir
            if strncmp(name, '.', 1)
                continue;
            end
            files = [files; listMFiles(fullfile(folder, name))]; %#ok<AGROW>
        else
            [~, ~, ext] = fileparts(name);
            if strcmpi(ext, '.m')
                files{end+1, 1} = fullfile(folder, name); %#ok<AGROW>
            end
        end
    end
end

function [txt, err] = readTextFile(file)
    txt = '';
    err = '';

    try
        fid = fopen(file, 'r', 'n', 'UTF-8');
        if fid < 0
            err = 'fopen failed';
            return;
        end

        cleaner = onCleanup(@() fclose(fid));
        bytes = fread(fid, Inf, '*char')';
        txt = char(bytes);
        clear cleaner;
    catch ME
        err = ME.message;
        txt = '';
    end
end

function fatal = filterLikelyFatalCheckcodeIssues(issues)
    fatal = {};

    if isempty(issues)
        return;
    end

    fatalIds = {
        'MLCERR'
        'PARSE'
        'SYNTAX'
    };

    for i = 1:numel(issues)
        id = '';
        msg = '';

        if isstruct(issues)
            if isfield(issues, 'id')
                id = char(issues(i).id);
            end
            if isfield(issues, 'message')
                msg = char(issues(i).message);
            elseif isfield(issues, 'messageText')
                msg = char(issues(i).messageText);
            end
        else
            msg = char(issues(i));
        end

        upperId = upper(id);
        upperMsg = upper(msg);

        isFatal = false;
        for k = 1:numel(fatalIds)
            if contains(upperId, fatalIds{k}) || contains(upperMsg, fatalIds{k})
                isFatal = true;
                break;
            end
        end

        if isFatal
            if isempty(id)
                fatal{end+1} = msg; %#ok<AGROW>
            else
                fatal{end+1} = sprintf('%s %s', id, msg); %#ok<AGROW>
            end
        end
    end
end

function out = relpath(pathValue, root)
    try
        pathValue = char(pathValue);
        root = char(root);

        if startsWith(pathValue, root)
            out = erase(pathValue, [root filesep]);
        else
            out = pathValue;
        end
    catch
        out = char(pathValue);
    end
end

function out = firstN(values, n)
    if numel(values) <= n
        out = values;
    else
        out = values(1:n);
        out{end+1} = sprintf('... +%d more', numel(values) - n);
    end
end

function printResults(results)
    fprintf('TC       Result        Message\n');
    fprintf('-------  ------------  -------\n');

    for i = 1:numel(results)
        fprintf('%-7s  %-12s  %s\n', ...
            results(i).TC, results(i).Result, results(i).Message);
    end
end

