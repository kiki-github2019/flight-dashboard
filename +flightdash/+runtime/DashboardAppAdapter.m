classdef DashboardAppAdapter < handle
    %DASHBOARDAPPADAPTER  Service-boundary facade for controllers (R5).
    %
    %   Curated dependency target replacing direct reach-in to the
    %   5900-line FlightDataDashboard app object. Bundles the four R1-R4
    %   handles (SessionContext, DashboardStateStore, AsyncDecodeState,
    %   DashboardLayoutState) plus the cross-cutting plumbing
    %   controllers actually need:
    %
    %     - session()        : SessionContext
    %     - channel(fIdx)    : ChannelState (lazy-mirror via app)
    %     - store()          : DashboardStateStore (aggregate)
    %     - asyncDecode()    : AsyncDecodeState  (bound helpers)
    %     - layout()         : DashboardLayoutState
    %     - undoService() / cacheService() / decodeService() / undoService()
    %     - logCaught(ME, tag) : route to app.logCaught
    %     - dispatchCommand(cmdId, source) : forward to app.dispatchCommand
    %     - app()            : escape hatch (incremental migration only)
    %
    %   R5 ships the adapter and wires it into FlightDataDashboard.
    %   No controllers are migrated in this phase per the refactor
    %   brief: "Do not convert every controller at once."
    %
    %   Lifetime: owned by the app, holds a back-reference. Goes out of
    %   scope when the app's delete() runs. Controllers should accept
    %   the adapter in their constructor instead of caching a reference
    %   to it, so a deleted app cannot be reached through a stale handle.

    properties (Access = private)
        AppRef
    end

    methods
        function obj = DashboardAppAdapter(app)
            obj.AppRef = app;
        end

        function tf = isValidApp(obj)
            tf = ~isempty(obj.AppRef) && isa(obj.AppRef, 'handle') ...
                && isvalid(obj.AppRef);
        end

        % ===== Aggregate accessors =====

        function ctx = session(obj)
            ctx = flightdash.runtime.SessionContext.empty;
            if ~obj.isValidApp(), return; end
            if ismethod(obj.AppRef, 'getSessionContext')
                ctx = obj.AppRef.getSessionContext();
            end
        end

        function ch = channel(obj, fIdx)
            ch = flightdash.state.ChannelState.empty;
            if ~obj.isValidApp(), return; end
            if nargin < 2, fIdx = []; end
            if ismethod(obj.AppRef, 'channel')
                ch = obj.AppRef.channel(fIdx);
            end
        end

        function s = store(obj)
            s = flightdash.state.DashboardStateStore.empty;
            if ~obj.isValidApp(), return; end
            if ismethod(obj.AppRef, 'getStateStore')
                s = obj.AppRef.getStateStore();
            end
        end

        function ad = asyncDecode(obj)
            ad = flightdash.state.AsyncDecodeState.empty;
            if ~obj.isValidApp(), return; end
            if ismethod(obj.AppRef, 'getAsyncDecode')
                ad = obj.AppRef.getAsyncDecode();
            end
        end

        function ls = layout(obj)
            ls = flightdash.state.DashboardLayoutState.empty;
            if ~obj.isValidApp(), return; end
            if ismethod(obj.AppRef, 'getLayoutState')
                ls = obj.AppRef.getLayoutState();
            end
        end

        % ===== Service accessors =====
        % These return the existing service handles unchanged. The
        % adapter only narrows the *call surface*, not the services
        % themselves.

        function svc = undoService(obj)
            svc = [];
            if obj.isValidApp() && isprop(obj.AppRef, 'UndoService')
                svc = obj.AppRef.UndoService;
            end
        end

        function svc = cacheService(obj)
            svc = [];
            if obj.isValidApp() && isprop(obj.AppRef, 'SharedCacheService')
                svc = obj.AppRef.SharedCacheService;
            end
        end

        function svc = decodeService(obj)
            svc = [];
            if obj.isValidApp() && isprop(obj.AppRef, 'SharedDecodeService')
                svc = obj.AppRef.SharedDecodeService;
            end
        end

        function tf = useSharedDecode(obj)
            tf = false;
            if obj.isValidApp() && isprop(obj.AppRef, 'UseSharedDecodeService')
                tf = logical(obj.AppRef.UseSharedDecodeService);
            end
        end

        function fig = uiFigure(obj)
            fig = [];
            if obj.isValidApp() && isprop(obj.AppRef, 'UIFigure')
                fig = obj.AppRef.UIFigure;
            end
        end

        function container = rootContainer(obj)
            container = [];
            if obj.isValidApp() && isprop(obj.AppRef, 'RootContainer')
                container = obj.AppRef.RootContainer;
            end
        end

        % ===== Session convenience =====
        % These short-circuits collapse two of the most common
        % escape-hatch patterns from the controller migration. Both
        % return safe defaults when the app is gone so callers do not
        % need additional isvalid() guards.

        function tf = isActiveSession(obj, varargin)
            % Forwards to app.isActiveSession; returns false when the
            % app is deleted (matches the safe-default the controllers
            % previously had via obj.Adapter.app().isActiveSession()).
            tf = false;
            if ~obj.isValidApp(), return; end
            try
                tf = obj.AppRef.isActiveSession(varargin{:});
            catch
                tf = false;
            end
        end

        function sid = activeSessionId(obj)
            % Returns the active session id ('standalone' as fallback)
            % without the verbose session() null-check the controller
            % migration commit had to write at every undo-command site.
            sid = 'standalone';
            if ~obj.isValidApp(), return; end
            try
                if isprop(obj.AppRef, 'ActiveSessionId') ...
                        && ~isempty(obj.AppRef.ActiveSessionId)
                    sid = char(obj.AppRef.ActiveSessionId);
                end
            catch
            end
        end

        function tf = isEmbedded(obj)
            % Returns the IsEmbedded flag with safe-default false when
            % the app is gone. Used by drag controllers to choose
            % between WindowButton callbacks and StudioMouseRouter.
            tf = false;
            if ~obj.isValidApp(), return; end
            try
                if isprop(obj.AppRef, 'IsEmbedded')
                    tf = logical(obj.AppRef.IsEmbedded);
                end
            catch
            end
        end

        % ===== Cross-cutting plumbing =====

        function logCaught(obj, ME, tag)
            % Forward to app.logCaught when available. Never throws —
            % adapters must not be a new failure surface.
            try
                if obj.isValidApp() && ismethod(obj.AppRef, 'logCaught')
                    obj.AppRef.logCaught(ME, tag);
                end
            catch
            end
        end

        function dispatchCommand(obj, cmdId, source)
            if nargin < 3, source = 'Adapter'; end
            try
                if obj.isValidApp() && ismethod(obj.AppRef, 'dispatchCommand')
                    obj.AppRef.dispatchCommand(cmdId, source);
                end
            catch ME
                obj.logCaught(ME, 'Adapter:dispatchCommand');
            end
        end

        % ===== Escape hatch =====

        function appHandle = app(obj)
            % Direct app handle for code that has not been migrated yet.
            % Use sparingly — every call site of obj.app() is a future
            % migration candidate.
            appHandle = obj.AppRef;
        end
    end
end
