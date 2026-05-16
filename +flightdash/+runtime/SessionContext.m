classdef SessionContext < handle
    %SESSIONCONTEXT  Storage for a FlightDataDashboard's session identity.
    %
    %   Owns the nine session-identity fields the R1 brief identified
    %   (ActiveSessionId / IsEmbedded / RootContainer / UIFigure /
    %   MouseRouter / SharedCacheService / SharedDecodeService /
    %   UndoService / UseSharedDecodeService).
    %
    %   History: R1 introduced this class as a Dependent live-view
    %   over the app's properties (no ownership change). R7 inverted
    %   ownership one field at a time so this handle is now the real
    %   storage. The app keeps the same property names as Dependent
    %   forwards declared on FlightDataDashboard so every legacy read
    %   and write keeps compiling.
    %
    %   Lifetime: held by the app and shares its lifetime. When the
    %   app's delete() runs, this handle goes out of scope alongside
    %   it. Do not cache references in unrelated components — they
    %   would outlive the app.

    properties (Access = private)
        AppRef  % flightdash.FlightDataDashboard — owning app
    end

    properties (Access = public)
        UseSharedDecodeService  logical = false
        IsEmbedded              logical = false
        ActiveSessionId         char    = 'standalone'
        RootContainer                   = []
        UIFigure                        = []
        SharedCacheService              = []
        SharedDecodeService             = []
        UndoService                     = []
        MouseRouter                     = []
    end

    methods
        function obj = SessionContext(app)
            obj.AppRef = app;
        end

        function tf = isValidApp(obj)
            tf = ~isempty(obj.AppRef) && isa(obj.AppRef, 'handle') ...
                && isvalid(obj.AppRef);
        end

        function tag = describe(obj)
            % Human-readable one-liner — useful for logCaught tags.
            if obj.isValidApp()
                if obj.IsEmbedded, mode = 'embedded'; else, mode = 'standalone'; end
                tag = sprintf('session=%s mode=%s', obj.ActiveSessionId, mode);
            else
                tag = 'session=<invalid>';
            end
        end
    end

end
