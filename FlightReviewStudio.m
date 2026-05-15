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
%   Minimum requirement: MATLAB R2021b (uitree multi-select / Icon).

    if verLessThan('matlab', '9.11')
        error('FlightReviewStudio:UnsupportedMatlab', ...
            'FlightReviewStudio requires MATLAB R2021b or newer.');
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
