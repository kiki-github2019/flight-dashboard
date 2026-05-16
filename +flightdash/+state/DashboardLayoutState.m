classdef DashboardLayoutState < handle
    %DASHBOARDLAYOUTSTATE  Responsive-layout state facade (R4).
    %
    %   Mirrors the 11 layout-related properties declared on
    %   FlightDataDashboard. Same two-mode design as AsyncDecodeState
    %   (R3): unbound for unit tests, app-bound for the live dashboard.
    %
    %   R4 ships the live mirror. The legacy app.LayoutProfile /
    %   LastLayoutSize / etc. remain the source of truth — every existing
    %   ResponsiveLayoutManager call site is unchanged. New code that
    %   wants a focused layout handle calls app.getLayoutState() and
    %   reads the synchronized snapshot.
    %
    %   Owner: DashboardRuntime (co-owned with the app — both hold the
    %   same handle).

    properties (Access = public)
        LayoutProfile           char    = 'wide'
        LastLayoutSize          double  = [NaN, NaN]
        InResponsiveLayout      logical = false
        PreferredVideoWidth     double  = [NaN, NaN]
        ManualVideoWidth        double  = [NaN, NaN]
        ManualPanelWidths       cell    = {struct(), struct()}
        PanelSplitterFIdx       double  = 0
        PanelSplitterKind       char    = ''
        IsDraggingPanelSplitter logical = false
        LayoutHandles           struct  = struct()
        NormalFigurePosition    double  = [NaN, NaN, NaN, NaN]
    end

    properties (Access = private)
        AppRef
    end

    methods
        function obj = DashboardLayoutState(app)
            if nargin >= 1 && ~isempty(app) && isa(app, 'handle')
                obj.AppRef = app;
            end
        end

        function tf = isBound(obj)
            tf = ~isempty(obj.AppRef) && isa(obj.AppRef, 'handle') ...
                && isvalid(obj.AppRef);
        end

        function syncFromApp(obj)  %#ok<MANU>
            % R6 final: all 11 DashboardLayoutState fields are owned
            % by this handle (the app's properties are Dependent
            % forwards). Mirror is therefore a no-op. The method is
            % kept (rather than deleted) so app.getLayoutState() can
            % keep calling syncFromApp() without an ismethod guard.
        end

        function setLayoutProfile(obj, profile)
            % Convenience writer that updates the bound app + local
            % mirror. Behavior is identical to assigning app.LayoutProfile
            % directly today — exists so future call sites can stop
            % reaching into the app object.
            profile = char(profile);
            if obj.isBound() && isprop(obj.AppRef, 'LayoutProfile')
                obj.AppRef.LayoutProfile = profile;
            end
            obj.LayoutProfile = profile;
        end

        function setLastLayoutSize(obj, sz)
            if obj.isBound() && isprop(obj.AppRef, 'LastLayoutSize')
                obj.AppRef.LastLayoutSize = sz;
            end
            obj.LastLayoutSize = sz;
        end
    end
end
