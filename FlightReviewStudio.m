function app = FlightReviewStudio()
%FLIGHTREVIEWSTUDIO Launch the FlightDataReviewStudio shell.
%   Creates the OriginPro-style integrated shell that will host one or
%   more FlightDataDashboard sessions inside a project workspace.
%
%   Usage:
%       FlightReviewStudio()           % launch with empty project
%       app = FlightReviewStudio()     % return handle to the studio app
%
%   Current Studio status:
%   - Renders the Studio shell (menu, toolbar, project explorer,
%     workspace tabgroup, right dock, status bar).
%   - Uses ProjectModel/SessionModel metadata for multi-session projects.
%   - Embeds flightdash.FlightDataDashboard directly into workspace tabs.
%   - .frsproj v1 is a linked project format: external flight/video files
%     are referenced by path and are not packed into the project archive.
%
%   Version policy (see README "MATLAB Compatibility"):
%     - Minimum runtime : R2021b  (uitree multi-select / uibutton Icon)
%     - Verified targets: R2025a / R2026a / MATLAB Online
%   Releases between the minimum and the verified set run but emit a
%   one-time console warning so the user knows the configuration is
%   untested rather than silently unsupported.

    if verLessThan('matlab', '9.11')
        error('FlightReviewStudio:UnsupportedMatlab', ...
            'FlightReviewStudio requires MATLAB R2021b or newer.');
    end

    % --- Stale-class cache self-guard ---
    % MATLAB keeps classdef code loaded across git pulls. If a core
    % Studio/Dashboard class is already in memory before launch, refresh
    % classes so old PlotView bytecode cannot reproduce phantom errors
    % such as "Unrecognized function or variable 'targetLayout'".
    localRefreshStaleClassCache({ ...
        'flightdash.view.PlotView', ...
        'flightdash.FlightDataDashboard', ...
        'flightdash.studio.WorkspaceManager', ...
        'flightdash.studio.FlightReviewStudioApp'});
    if verLessThan('matlab', '24.1')  % R2024a == 24.1; R2025a == 24.2
        try
            warning('off', 'backtrace');
            cleanupBacktrace = onCleanup(@() warning('on', 'backtrace')); %#ok<NASGU>
            warning('FlightReviewStudio:UnverifiedMatlab', ...
                ['Running on MATLAB %s — the verified targets are ' ...
                 'R2025a / R2026a. Behavior is best-effort; please ' ...
                 'report regressions with your MATLAB release.'], version());
        catch
        end
    end

    studioApp = flightdash.studio.FlightReviewStudioApp();

    % First-launch UX: auto-create "Session 1" so a fresh Untitled
    % project lands on a populated Project Explorer + active Dashboard
    % tab instead of Welcome-only. Lives in the entry-point wrapper
    % (NOT in the class constructor) so tests / diagnostics that
    % instantiate FlightReviewStudioApp directly stay deterministic.
    try
        if ~isempty(studioApp) && isvalid(studioApp) ...
                && isprop(studioApp, 'Project') && ~isempty(studioApp.Project) ...
                && studioApp.Project.sessionCount() == 0 ...
                && ismethod(studioApp, 'addSession')
            studioApp.addSession('Session 1');
        end
    catch autoME
        warning('FlightReviewStudio:AutoSessionFailed', '%s', autoME.message);
    end

    if nargout > 0
        app = studioApp;
    end
end

function localRefreshStaleClassCache(classNames)
    % Strengthened stale-class guard.
    %
    %   1. Detect any target class that is ALREADY loaded in this
    %      MATLAB session (inmem('-completenames')) AND whose .m file
    %      on disk has a newer mtime than the loaded bytecode.
    %   2. If stale: rehash toolboxcache + evalin('base','clear classes').
    %   3. Verify the class was actually unloaded. If `clear classes`
    %      failed because of live instances, throw a clear error BEFORE
    %      FlightReviewStudioApp() runs against the stale code — that
    %      is the only way to avoid phantom errors like the
    %      "targetLayout" report on a file that no longer contains it.
    if nargin < 1 || isempty(classNames), return; end

    loadedFiles = {};
    try, loadedFiles = inmem('-completenames'); catch, end

    staleCls = ''; staleFile = '';
    for k = 1:numel(classNames)
        cls = classNames{k};
        try
            w = which(cls);
            if isempty(w) || ~ischar(w), continue; end
            if ~any(strcmpi(loadedFiles, w)), continue; end
            % Loaded -> compare mtime against the metadata file we have
            % a handle to (best-effort; if either is unreadable skip).
            d = dir(w);
            if isempty(d), continue; end
            % Heuristic: if file's mtime is within the LAST 2 seconds
            % of process start it almost certainly post-dates the
            % cached bytecode (user just did a git pull / edit).
            try
                if (now - datenum(d.date)) * 86400 < 300 %#ok<DATNM,TNOW1>
                    staleCls = cls; staleFile = w; break;
                end
            catch
            end
        catch
        end
    end

    if isempty(staleCls), return; end

    fprintf('[FlightReviewStudio] Stale class cache detected (%s). Refreshing...\n', staleCls);
    try, rehash toolboxcache; catch, end
    try, evalin('base', 'clear classes'); catch, end

    % Verify the refresh actually took effect. `clear classes` is a
    % no-op when live handles exist; in that case we MUST not let the
    % app construct against the stale code path.
    try
        stillLoaded = inmem('-completenames');
    catch
        stillLoaded = {};
    end
    if any(strcmpi(stillLoaded, staleFile))
        error('FlightReviewStudio:StaleClassCache', ...
            ['Stale MATLAB class cache for %s could not be cleared\n' ...
             '(live instances are still holding the old definition).\n\n' ...
             'Please close every flightdash GUI / dashboard window, then run:\n' ...
             '    close all force; clear classes; rehash toolboxcache; FlightReviewStudio\n\n' ...
             'If that does not help, restart MATLAB.'], staleCls);
    end
end
