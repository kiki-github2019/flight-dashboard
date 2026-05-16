classdef DashboardLayoutState < handle
    %DASHBOARDLAYOUTSTATE  Responsive-layout state scaffold (R4 prep).
    %
    %   Mirrors the 11 layout-related properties declared on
    %   FlightDataDashboard. R1 only declares the shape — the app keeps
    %   ownership. R4 will move these into this class and the app will
    %   forward via Dependent properties for compatibility.
    %
    %   Owner: DashboardRuntime.

    properties (Access = public)
        LayoutProfile           char   = 'wide'
        LastLayoutSize          double = [NaN, NaN]
        InResponsiveLayout      logical = false
        PreferredVideoWidth     double = [NaN, NaN]
        ManualVideoWidth        double = [NaN, NaN]
        ManualPanelWidths       cell   = {struct(), struct()}
        PanelSplitterFIdx       double = 0
        PanelSplitterKind       char   = ''
        IsDraggingPanelSplitter logical = false
        LayoutHandles           struct = struct()
        NormalFigurePosition    double = [NaN, NaN, NaN, NaN]
    end

    methods
        function obj = DashboardLayoutState()
        end
    end
end
