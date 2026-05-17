classdef ControllerBase < handle
    %CONTROLLERBASE Optional base for future Studio-aware controllers.
    %
    % Existing controllers are not forced to inherit from this class. It
    % provides a small, safe contract for new drag/click controllers:
    % session identity, optional StudioMouseRouter locking, listener
    % tracking, and idempotent cleanup.

    properties
        Dashboard = []
        Adapter   = []   % flightdash.runtime.DashboardAppAdapter (R5+ controllers)
        Router = []
        SessionId char = ''
        IsDragging logical = false
        IsEnabled logical = false
    end

    properties (Access = protected)
        StartPoint double = [0 0]
        OriginalState = []
        Listeners cell = {}
        SessionListeners cell = {}
    end

    methods
        function obj = ControllerBase(input)
            % Accept a Dashboard (legacy), DashboardAppAdapter (R5+),
            % or FlightDataDashboard (auto-resolves to adapter). Sets
            % both .Dashboard and .Adapter when resolvable so the
            % helper methods route through whichever surface the
            % subclass uses.
            if nargin < 1, input = []; end
            if isa(input, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = input;
                try
                    appHandle = input.app();
                    if isa(appHandle, 'flightdash.FlightDataDashboard')
                        obj.Dashboard = appHandle;
                    end
                catch
                end
            elseif isa(input, 'flightdash.FlightDataDashboard')
                obj.Dashboard = input;
                try
                    if ismethod(input, 'getAdapter')
                        obj.Adapter = input.getAdapter();
                    end
                catch
                end
            elseif ~isempty(input)
                % Unknown / future input shape — store as Adapter if it
                % quacks like one (has dispatchCommand), else Dashboard.
                if isstruct(input) && isfield(input, 'dispatchCommand')
                    obj.Adapter = input;
                else
                    obj.Dashboard = input;
                end
            end
            try
                if ~isempty(obj.Adapter) && ismethod(obj.Adapter, 'activeSessionId')
                    obj.SessionId = char(obj.Adapter.activeSessionId());
                elseif ~isempty(obj.Dashboard) && isprop(obj.Dashboard, 'ActiveSessionId')
                    obj.SessionId = char(obj.Dashboard.ActiveSessionId);
                end
                fig = obj.uiFigure();
                if ~isempty(fig) && isvalid(fig) && isappdata(fig, 'StudioMouseRouter')
                    obj.Router = getappdata(fig, 'StudioMouseRouter');
                end
            catch ME
                obj.logCaught(ME, 'ControllerBase:ctor');
            end
        end

        function appHandle = app(obj)
            % Returns the underlying FlightDataDashboard (or empty).
            appHandle = [];
            if ~isempty(obj.Adapter)
                try
                    if isa(obj.Adapter, 'flightdash.runtime.DashboardAppAdapter')
                        appHandle = obj.Adapter.app();
                    elseif isstruct(obj.Adapter) && isfield(obj.Adapter, 'app')
                        appHandle = obj.Adapter.app();
                    end
                catch
                end
            end
            if isempty(appHandle), appHandle = obj.Dashboard; end
        end

        function fig = uiFigure(obj)
            fig = [];
            try
                if ~isempty(obj.Adapter) && ismethod(obj.Adapter, 'uiFigure')
                    fig = obj.Adapter.uiFigure();
                end
                if isempty(fig) && ~isempty(obj.Dashboard) && isvalid(obj.Dashboard) ...
                        && isprop(obj.Dashboard, 'UIFigure')
                    fig = obj.Dashboard.UIFigure;
                end
            catch
            end
        end

        function dispatchCommand(obj, cmdId, source)
            if nargin < 3, source = 'Controller'; end
            try
                if ~isempty(obj.Adapter) && ismethod(obj.Adapter, 'dispatchCommand')
                    obj.Adapter.dispatchCommand(char(cmdId), char(source));
                    return;
                end
                appHandle = obj.app();
                if ~isempty(appHandle) && ismethod(appHandle, 'dispatchCommand')
                    appHandle.dispatchCommand(char(cmdId), char(source));
                end
            catch ME
                obj.logCaught(ME, 'ControllerBase:dispatchCommand');
            end
        end

        function enableInteraction(obj) %#ok<MANU>
            % Subclasses may override.
        end

        function tf = requestDragLock(obj, pointerType, gesture)
            if nargin < 2 || isempty(pointerType), pointerType = 'fleur'; end
            if nargin < 3 || isempty(gesture), gesture = 'drag'; end
            tf = false;
            if ~obj.canInteract()
                return;
            end
            if isempty(obj.Router) || ~isvalid(obj.Router)
                tf = true;  % standalone or non-router controller path
                return;
            end
            try
                tf = obj.Router.requestDragLock(obj.SessionId, obj, pointerType, gesture);
            catch ME
                obj.logCaught(ME, 'ControllerBase:requestDragLock');
                tf = false;
            end
        end

        function releaseDragLock(obj)
            try
                if ~isempty(obj.Router) && isvalid(obj.Router) && ...
                        ismethod(obj.Router, 'isLockHeldBy') && obj.Router.isLockHeldBy(obj.SessionId)
                    obj.Router.releaseDragLock();
                end
            catch ME
                obj.logCaught(ME, 'ControllerBase:releaseDragLock');
            end
            obj.IsDragging = false;
        end

        function tf = isActiveSession(obj, varargin)
            tf = true;
            try
                if ~isempty(obj.Adapter) && ismethod(obj.Adapter, 'isActiveSession')
                    tf = obj.Adapter.isActiveSession(varargin{:});
                    return;
                end
                if isempty(obj.Dashboard) || ~isvalid(obj.Dashboard)
                    tf = false;
                    return;
                end
                if ismethod(obj.Dashboard, 'isActiveSession')
                    tf = obj.Dashboard.isActiveSession(varargin{:});
                end
            catch
                tf = false;
            end
        end

        function onButtonDown(obj, src, event)
            if ~obj.requestDragLock()
                return;
            end
            try
                obj.IsDragging = true;
                obj.StartPoint = obj.getCurrentMousePoint();
                obj.OriginalState = obj.captureState();
                obj.onDragStarted(src, event);
            catch ME
                obj.releaseDragLock();
                obj.logCaught(ME, 'ControllerBase:onButtonDown');
            end
        end

        function onDragStarted(obj, ~, ~) %#ok<MANU>
            % Subclasses may override.
        end

        function handleDragMotion(obj)
            if ~obj.IsDragging || ~obj.canInteract()
                return;
            end
            try
                obj.doDragMotion();
            catch ME
                obj.releaseDragLock();
                obj.logCaught(ME, 'ControllerBase:handleDragMotion');
            end
        end

        function doDragMotion(obj) %#ok<MANU>
            % Subclasses may override.
        end

        function stopDrag(obj)
            if ~obj.IsDragging
                obj.releaseDragLock();
                return;
            end
            try
                obj.doStopDrag();
            catch ME
                obj.logCaught(ME, 'ControllerBase:stopDrag');
            end
            obj.releaseDragLock();
        end

        function doStopDrag(obj) %#ok<MANU>
            % Subclasses may override.
        end

        function state = captureState(obj) %#ok<MANU>
            state = struct();
        end

        function [tf, target] = hitTest(obj, point)
            tf = false;
            target = [];
            try
                point = double(point);
                if numel(point) < 2 || any(~isfinite(point(1:2)))
                    return;
                end
                point = point(1:2);
                if isprop(obj, 'Axes') && ~isempty(obj.Axes)
                    axesList = obj.Axes;
                    for k = 1:numel(axesList)
                        ax = axesList(k);
                        if obj.inAxes(ax, point)
                            tf = true;
                            target = ax;
                            return;
                        end
                    end
                end
            catch ME
                obj.logCaught(ME, 'ControllerBase:hitTest');
                tf = false;
                target = [];
            end
        end

        function tf = inAxes(~, ax, point)
            tf = false;
            try
                if isempty(ax) || ~isvalid(ax) || numel(point) < 2
                    return;
                end
                pos = getpixelposition(ax, true);
                tf = point(1) >= pos(1) && point(1) <= pos(1) + pos(3) && ...
                    point(2) >= pos(2) && point(2) <= pos(2) + pos(4);
            catch
                tf = false;
            end
        end

        function pt = getCurrentMousePoint(obj)
            pt = [0 0];
            try
                if isempty(obj.Dashboard) || ~isvalid(obj.Dashboard) || ...
                        ~isprop(obj.Dashboard, 'UIFigure') || isempty(obj.Dashboard.UIFigure) || ...
                        ~isvalid(obj.Dashboard.UIFigure)
                    return;
                end
                cp = obj.Dashboard.UIFigure.CurrentPoint;
                if numel(cp) >= 2
                    pt = double(cp(1:2));
                end
            catch
                pt = [0 0];
            end
        end

        function addListener(obj, src, eventName, callback)
            try
                if isempty(src) || ~isvalid(src)
                    return;
                end
                obj.trackListener(addlistener(src, eventName, callback));
            catch ME
                obj.logCaught(ME, 'ControllerBase:addListener');
            end
        end

        function addSessionListener(obj, source, eventName, callback)
            try
                L = flightdash.event.SessionScopedListener(obj.SessionId, source, eventName, callback);
                obj.SessionListeners{end+1} = L;
            catch ME
                obj.logCaught(ME, 'ControllerBase:addSessionListener');
            end
        end

        function trackListener(obj, listenerHandle)
            if isempty(listenerHandle)
                return;
            end
            obj.Listeners{end+1} = listenerHandle;
        end

        function cleanup(obj)
            obj.IsDragging = false;
            obj.releaseDragLock();
            for k = 1:numel(obj.Listeners)
                try
                    if ~isempty(obj.Listeners{k}) && isvalid(obj.Listeners{k})
                        delete(obj.Listeners{k});
                    end
                catch
                end
            end
            obj.Listeners = {};
            for k = 1:numel(obj.SessionListeners)
                try
                    if ~isempty(obj.SessionListeners{k}) && isvalid(obj.SessionListeners{k})
                        delete(obj.SessionListeners{k});
                    end
                catch
                end
            end
            obj.SessionListeners = {};
            obj.onCleanup();
        end

        function onCleanup(obj) %#ok<MANU>
            % Subclasses may override.
        end

        function delete(obj)
            try, obj.cleanup(); catch, end
        end
    end

    methods (Access = protected)
        function tf = canInteract(obj)
            tf = false;
            try
                if isempty(obj.Dashboard) || ~isvalid(obj.Dashboard)
                    return;
                end
                if isprop(obj.Dashboard, 'IsDeleting') && obj.Dashboard.IsDeleting
                    return;
                end
                tf = obj.isActiveSession();
            catch
                tf = false;
            end
        end

        function logCaught(obj, ME, tag)
            try
                if ~isempty(obj.Adapter) && ismethod(obj.Adapter, 'logCaught')
                    obj.Adapter.logCaught(ME, tag);
                    return;
                end
                if ~isempty(obj.Dashboard) && isvalid(obj.Dashboard) && ismethod(obj.Dashboard, 'logCaught')
                    obj.Dashboard.logCaught(ME, tag);
                else
                    flightdash.util.ErrorLog.log(ME, tag, false);
                end
            catch
            end
        end
    end
end
