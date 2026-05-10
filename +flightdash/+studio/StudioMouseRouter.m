classdef StudioMouseRouter < handle
    %STUDIOMOUSEROUTER  Mediator for figure-level mouse drag callbacks.
    %
    %   Phase 3.5 — built atop the Phase 4 isActiveSession() guards.
    %   Phase 4 ensured controllers IGNORE drags from inactive tabs.
    %   Phase 3.5 goes further: the Studio uifigure's
    %   WindowButtonMotionFcn / WindowButtonUpFcn are owned by ONE
    %   router. Per-session controllers do not write to those callback
    %   slots at all in embedded mode; instead they request a "drag
    %   lock" from the router. The router validates that the requesting
    %   session is the active workspace tab and, while the lock is
    %   held, dispatches motion / up events back to the controller's
    %   handleDragMotion() / stopDrag() methods.
    %
    %   Invariants the router upholds:
    %     - Only one drag is active at a time across all sessions.
    %     - If the active workspace tab changes mid-drag, motion is
    %       silently suppressed (the controller's handleDragMotion is
    %       not called) so the inactive session's state never updates.
    %     - releaseDragLock is always idempotent and safe to call from
    %       a stopDrag handler that may itself error.
    %
    %   Standalone dashboards continue to write WindowButton callbacks
    %   directly on their own uifigure; no router is involved there.

    properties (Access = private)
        UIFigure
        Workspace          % flightdash.studio.WorkspaceManager
        ActiveController = []
        ActiveSessionId  = ''
        ActiveGesture    = ''
        CurrentPointer   = 'arrow'
        IsAttached       logical = false
    end

    properties (Access = public)
        DebugMode logical = false
        HitTestEnabled logical = false
    end

    methods
        function obj = StudioMouseRouter(uifig, workspace)
            obj.UIFigure  = uifig;
            obj.Workspace = workspace;
            obj.attach();
        end

        function attach(obj)
            if obj.IsAttached, return; end
            if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure), return; end
            obj.UIFigure.WindowButtonDownFcn   = @(~,~) obj.onButtonDown();
            obj.UIFigure.WindowButtonMotionFcn = @(~,~) obj.onMouseMotion();
            obj.UIFigure.WindowButtonUpFcn     = @(~,~) obj.onMouseUp();
            obj.IsAttached = true;
        end

        function detach(obj)
            obj.releaseDragLock();
            try
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                    obj.UIFigure.WindowButtonDownFcn   = '';
                    obj.UIFigure.WindowButtonMotionFcn = '';
                    obj.UIFigure.WindowButtonUpFcn     = '';
                end
            catch
            end
            obj.IsAttached = false;
            obj.ActiveController = [];
            obj.ActiveSessionId  = '';
            obj.ActiveGesture = '';
        end

        function tf = requestDragLock(obj, sessionId, controller, pointerType, gesture)
            % Returns true if the lock was granted (active session
            % matches workspace's currently selected tab AND no other
            % drag is in progress). Callers should fall through silently
            % when false — the click was on a stale tab.
            if nargin < 4 || isempty(pointerType), pointerType = 'fleur'; end
            if nargin < 5 || isempty(gesture), gesture = 'drag'; end
            tf = false;
            sessionId = char(sessionId);
            try
                if isempty(sessionId) || isempty(controller) || ...
                        ~isa(controller, 'handle') || ~isvalid(controller)
                    return;
                end
                if obj.hasActiveLock()
                    return;  % another drag still owns the lock
                end
                if ~obj.isSessionActive(sessionId)
                    return;  % requesting session is not the visible tab
                end
                obj.ActiveSessionId  = sessionId;
                obj.ActiveController = controller;
                obj.ActiveGesture = char(gesture);
                obj.setPointerSafe(pointerType);
                if obj.DebugMode
                    fprintf('StudioMouseRouter: lock granted to %s [%s]\n', ...
                        obj.ActiveSessionId, obj.ActiveGesture);
                end
                tf = true;
            catch
            end
        end

        function releaseDragLock(obj)
            if obj.DebugMode && obj.hasActiveLock()
                fprintf('StudioMouseRouter: lock released from %s\n', obj.ActiveSessionId);
            end
            obj.ActiveController = [];
            obj.ActiveSessionId  = '';
            obj.ActiveGesture = '';
            obj.setPointerSafe('arrow');
        end

        function cancelSession(obj, sessionId)
            sessionId = char(sessionId);
            try
                if isempty(sessionId) || isempty(obj.ActiveSessionId) || ...
                        ~strcmp(obj.ActiveSessionId, sessionId)
                    return;
                end
                ctrl = obj.ActiveController;
                if ~isempty(ctrl) && isa(ctrl, 'handle') && isvalid(ctrl) && ismethod(ctrl, 'stopDrag')
                    try
                        ctrl.stopDrag();
                    catch ME
                        try
                            flightdash.util.ErrorLog.log(ME, 'StudioMouseRouter:CancelSession', false);
                        catch
                        end
                    end
                end
            catch
            end
            obj.releaseDragLock();
        end

        function tf = isLockHeldBy(obj, sessionId)
            tf = obj.hasActiveLock() && strcmp(obj.ActiveSessionId, char(sessionId));
        end

        function tf = hasActiveLock(obj)
            tf = ~isempty(obj.ActiveController) && isa(obj.ActiveController, 'handle') && ...
                isvalid(obj.ActiveController);
        end

        function sessionId = lockedSessionId(obj)
            sessionId = obj.ActiveSessionId;
        end

        function gesture = activeGesture(obj)
            gesture = obj.ActiveGesture;
        end

        function tf = isSessionActive(obj, sessionId)
            tf = false;
            try
                sessionId = char(sessionId);
                if isempty(sessionId) || isempty(obj.Workspace) || ...
                        (isa(obj.Workspace, 'handle') && ~isvalid(obj.Workspace))
                    return;
                end
                activeId = char(obj.Workspace.activeSessionId());
                tf = ~isempty(activeId) && ~strcmp(activeId, 'standalone') && ...
                    strcmp(activeId, sessionId);
            catch
                tf = false;
            end
        end

        function setPointer(obj, pointerType)
            obj.setPointerSafe(pointerType);
        end

        function tf = startGesture(obj, sessionId, controller, gestureType, pointerType)
            if nargin < 5 || isempty(pointerType)
                pointerType = obj.gestureToPointer(gestureType);
            end
            tf = obj.requestDragLock(sessionId, controller, pointerType, gestureType);
        end

        function pointerType = gestureToPointer(~, gestureType)
            switch lower(char(gestureType))
                case 'pan'
                    pointerType = 'hand';
                case 'split'
                    pointerType = 'fleur';
                case {'zoom', 'draw'}
                    pointerType = 'crosshair';
                otherwise
                    pointerType = 'fleur';
            end
        end

        function hitInfo = performHitTest(obj, point)
            hitInfo = obj.emptyHitInfo();
            try
                if ~obj.HitTestEnabled || isempty(obj.UIFigure) || ~isvalid(obj.UIFigure)
                    return;
                end
                point = double(point);
                if numel(point) < 2 || any(~isfinite(point(1:2)))
                    return;
                end
                point = point(1:2);

                entry = obj.getActiveDashboardEntry();
                if isempty(entry) || ~isstruct(entry) || ~isfield(entry, 'Dashboard') || ...
                        isempty(entry.Dashboard) || ~isvalid(entry.Dashboard)
                    return;
                end

                if isfield(entry, 'SessionId')
                    hitInfo.SessionId = char(entry.SessionId);
                else
                    hitInfo.SessionId = char(entry.Dashboard.ActiveSessionId);
                end

                tests = {
                    'MarkerDragCtrl', 'marker',   100
                    'DragCtrl',       'splitter',  95
                    'PannerCtrl',     'panner',    90
                    'RoiCtrl',        'roi',       85
                    'PlotCtrl',       'axes',      50
                    };

                for k = 1:size(tests, 1)
                    candidate = obj.testControllerHit(entry.Dashboard, point, ...
                        tests{k, 1}, tests{k, 2}, tests{k, 3});
                    if candidate.Hit && candidate.Priority > hitInfo.Priority
                        hitInfo = candidate;
                        if hitInfo.Priority >= 90
                            break;
                        end
                    end
                end
            catch
                hitInfo = obj.emptyHitInfo();
            end
        end

        function activeEntry = getActiveDashboardEntry(obj)
            activeEntry = [];
            try
                if isempty(obj.Workspace) || ...
                        (isa(obj.Workspace, 'handle') && ~isvalid(obj.Workspace)) || ...
                        ~isprop(obj.Workspace, 'DashboardEntries')
                    return;
                end
                sessionId = char(obj.Workspace.activeSessionId());
                entries = obj.Workspace.DashboardEntries;
                if isempty(sessionId) || isempty(entries) || ~entries.isKey(sessionId)
                    return;
                end
                activeEntry = entries(sessionId);
            catch
                activeEntry = [];
            end
        end

        function delete(obj)
            obj.detach();
        end
    end

    methods (Access = private)
        function onButtonDown(obj)
            if ~obj.HitTestEnabled || obj.hasActiveLock()
                return;
            end
            try
                if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure)
                    return;
                end
                hitInfo = obj.performHitTest(obj.UIFigure.CurrentPoint(1:2));
                if ~hitInfo.Hit || isempty(hitInfo.Controller) || ...
                        ~isa(hitInfo.Controller, 'handle') || ~isvalid(hitInfo.Controller) || ...
                        ~ismethod(hitInfo.Controller, 'onButtonDown')
                    return;
                end
                evt = struct('IntersectionPoint', hitInfo.Point, ...
                    'HitTarget', hitInfo.Target, ...
                    'HitType', hitInfo.Type);
                hitInfo.Controller.onButtonDown(hitInfo.Target, evt);
            catch ME
                try
                    flightdash.util.ErrorLog.log(ME, 'StudioMouseRouter:ButtonDown', false);
                catch
                end
            end
        end

        function onMouseMotion(obj)
            if ~obj.hasActiveLock()
                obj.releaseDragLock();
                return;
            end
            % If the user switched tabs while the drag was in progress
            % the active session changed; suppress motion until either
            % the drag is released or focus returns.
            if ~obj.isSessionActive(obj.ActiveSessionId)
                obj.releaseDragLock();
                return;
            end

            try
                obj.ActiveController.handleDragMotion();
            catch ME
                try
                    flightdash.util.ErrorLog.log(ME, 'StudioMouseRouter:Motion', false);
                catch, end
            end
        end

        function onMouseUp(obj)
            ctrl = obj.ActiveController;
            if isempty(ctrl) || ~isa(ctrl, 'handle') || ~isvalid(ctrl)
                obj.releaseDragLock();
                return;
            end
            try
                ctrl.stopDrag();
            catch ME
                try
                    flightdash.util.ErrorLog.log(ME, 'StudioMouseRouter:Up', false);
                catch, end
            end
            obj.releaseDragLock();
        end

        function setPointerSafe(obj, pointerType)
            try
                if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure) || ...
                        ~isprop(obj.UIFigure, 'Pointer')
                    return;
                end
                ptr = char(pointerType);
                if isempty(ptr), ptr = 'arrow'; end
                if strcmp(ptr, 'left-right')
                    ptr = 'fleur';
                end
                try
                    obj.UIFigure.Pointer = ptr;
                    obj.CurrentPointer = ptr;
                catch
                    try
                        obj.UIFigure.Pointer = 'arrow';
                        obj.CurrentPointer = 'arrow';
                    catch
                    end
                end
            catch
            end
        end

        function hitInfo = testControllerHit(obj, dashboard, point, ctrlName, hitType, priority)
            hitInfo = obj.emptyHitInfo();
            try
                if isempty(dashboard) || ~isvalid(dashboard) || ~isprop(dashboard, ctrlName)
                    return;
                end
                ctrl = dashboard.(ctrlName);
                if isempty(ctrl) || ~isobject(ctrl)
                    return;
                end
                for n = 1:numel(ctrl)
                    c = ctrl(n);
                    if ~isa(c, 'handle') || ~isvalid(c) || ~ismethod(c, 'hitTest')
                        continue;
                    end
                    [hit, target] = c.hitTest(point);
                    if hit
                        hitInfo.Hit = true;
                        hitInfo.SessionId = char(dashboard.ActiveSessionId);
                        hitInfo.Controller = c;
                        hitInfo.Target = target;
                        hitInfo.Type = char(hitType);
                        hitInfo.Priority = double(priority);
                        hitInfo.Point = point;
                        return;
                    end
                end
            catch
                hitInfo = obj.emptyHitInfo();
            end
        end

        function hitInfo = emptyHitInfo(~)
            hitInfo = struct('Hit', false, ...
                'SessionId', '', ...
                'Controller', [], ...
                'Target', [], ...
                'Type', '', ...
                'Priority', 0, ...
                'Point', [NaN NaN]);
        end
    end
end
