classdef DashboardRuntime < handle
    %DASHBOARDRUNTIME  Top-level runtime aggregate for a FlightDataDashboard.
    %
    %   Phase R1 scaffold. The plan (per refactor brief): DashboardRuntime
    %   eventually owns SessionContext + DashboardStateStore +
    %   DashboardLayoutState + AsyncDecodeState so controllers can depend
    %   on this single facade instead of the 5900-line app object.
    %
    %   R1 status: container only. No state has been moved yet — the app
    %   still owns everything. This file exists so subsequent phases can
    %   land additively without renaming or moving files.
    %
    %   Lifetime: created by the app constructor (R2+ work) and deleted
    %   with the app. Holds back-references; never holds duplicated state.

    properties (Access = public)
        Session   flightdash.runtime.SessionContext = ...
            flightdash.runtime.SessionContext.empty
        StateStore       = []  % flightdash.state.DashboardStateStore (R2)
        Layout           = []  % flightdash.state.DashboardLayoutState (R4)
        AsyncDecode      = []  % flightdash.state.AsyncDecodeState  (R3)
    end

    properties (Access = private)
        AppRef
    end

    methods
        function obj = DashboardRuntime(app)
            obj.AppRef = app;
            obj.Session = flightdash.runtime.SessionContext(app);
        end

        function tf = isValidApp(obj)
            tf = ~isempty(obj.AppRef) && isa(obj.AppRef, 'handle') ...
                && isvalid(obj.AppRef);
        end

        function app = app(obj)
            % Escape hatch: controllers that have not yet migrated still
            % need the full app. R5 adapter will reduce these call sites.
            app = obj.AppRef;
        end
    end
end
