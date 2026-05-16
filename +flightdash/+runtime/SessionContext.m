classdef SessionContext < handle
    %SESSIONCONTEXT  Live view of a FlightDataDashboard's session identity.
    %
    %   Phase R1 — additive refactor scaffolding. This class does NOT
    %   own state; it is a Dependent-property facade over the existing
    %   FlightDataDashboard properties so callers can read session
    %   identity through a focused object without inheriting access to
    %   the full app surface.
    %
    %   Why a live view (not a snapshot): the app mutates ActiveSessionId
    %   when Studio retargets the dashboard between tabs. A snapshot
    %   would drift; a Dependent facade always reflects the truth.
    %
    %   Lifetime: SessionContext is held by the app and shares its
    %   lifetime. When the app's delete() runs, this handle goes out of
    %   scope alongside it. Do not cache references in unrelated
    %   components — they would outlive the app.
    %
    %   Future phases (R5) will route controller construction through
    %   this object so per-controller dependencies become explicit.

    properties (Access = private)
        AppRef  % flightdash.FlightDataDashboard — owning app
    end

    % [REFACTOR R7] Storage for fields inverted from the app. As each
    % identity property's external-read count reaches zero (via
    % adapter routing) it migrates from the Dependent block below to
    % this real-storage block. The app keeps the same property name
    % as a Dependent forward so legacy reads stay unchanged.
    properties (Access = public)
        UseSharedDecodeService  logical = false
        IsEmbedded              logical = false
        ActiveSessionId         char    = 'standalone'
        RootContainer                   = []
        SharedCacheService              = []
        SharedDecodeService             = []
        UndoService                     = []
        MouseRouter                     = []
    end

    properties (Dependent, SetAccess = private)
        UIFigure
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

    % -------- Dependent getters (live reads from app) --------
    methods
        function v = get.UIFigure(obj)
            v = [];
            if obj.isValidApp() && isprop(obj.AppRef, 'UIFigure')
                v = obj.AppRef.UIFigure;
            end
        end


    end
end
