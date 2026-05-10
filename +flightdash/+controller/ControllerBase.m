classdef ControllerBase < handle
    %CONTROLLERBASE Optional base for future Studio-aware controllers.
    %
    % Existing controllers are not forced to inherit from this class. It
    % provides a small, safe contract for new drag/click controllers:
    % session identity, optional StudioMouseRouter locking, listener
    % tracking, and idempotent cleanup.

    properties
        Dashboard = []
        Router = []
        SessionId char = ''
        IsDragging logical = false
        IsEnabled logical = false
    end

    properties (Access = protected)
        StartPoint double = [0 0]
        OriginalState = []
        Listeners cell = {}
    end

    methods
        function obj = ControllerBase(dashboard)
            if nargin < 1
                dashboard = [];
            end
            obj.Dashboard = dashboard;
            try
                if ~isempty(dashboard) && isprop(dashboard, 'ActiveSessionId')
                    obj.SessionId = char(dashboard.ActiveSessionId);
                end
                if ~isempty(dashboard) && isprop(dashboard, 'UIFigure') && ...
                        ~isempty(dashboard.UIFigure) && isvalid(dashboard.UIFigure) && ...
                        isappdata(dashboard.UIFigure, 'StudioMouseRouter')
                    obj.Router = getappdata(dashboard.UIFigure, 'StudioMouseRouter');
                end
            catch ME
                obj.logCaught(ME, 'ControllerBase:ctor');
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

        function tf = isActiveSession(obj)
            tf = true;
            try
                if isempty(obj.Dashboard) || ~isvalid(obj.Dashboard)
                    tf = false;
                    return;
                end
                if ismethod(obj.Dashboard, 'isActiveSession')
                    tf = obj.Dashboard.isActiveSession();
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
