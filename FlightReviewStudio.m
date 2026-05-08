function app = FlightReviewStudio()
%FLIGHTREVIEWSTUDIO Launch the FlightDataReviewStudio shell.
%   Creates the OriginPro-style integrated shell that will host one or
%   more FlightDataDashboard sessions inside a project workspace.
%
%   Usage:
%       FlightReviewStudio()           % launch with empty project
%       app = FlightReviewStudio()     % return handle to the studio app
%
%   Phase 1 status:
%   - Renders the empty shell only (menu, toolbar, project explorer,
%     workspace tabgroup, right dock, status bar).
%   - No project/session/figure model wiring yet (Phase 2).
%   - No FlightDataDashboard embedding yet (Phase 3).
%
%   Minimum requirement: MATLAB R2021b (uitree multi-select / Icon).

    if verLessThan('matlab', '9.11')
        error('FlightReviewStudio:UnsupportedMatlab', ...
            'FlightReviewStudio requires MATLAB R2021b or newer.');
    end

    studioApp = flightdash.studio.FlightReviewStudioApp();
    if nargout > 0
        app = studioApp;
    end
end
