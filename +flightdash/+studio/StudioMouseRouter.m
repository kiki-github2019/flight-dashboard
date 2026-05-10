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
        IsAttached       logical = false
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
            obj.UIFigure.WindowButtonMotionFcn = @(~,~) obj.onMouseMotion();
            obj.UIFigure.WindowButtonUpFcn     = @(~,~) obj.onMouseUp();
            obj.IsAttached = true;
        end

        function detach(obj)
            try
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                    obj.UIFigure.WindowButtonMotionFcn = '';
                    obj.UIFigure.WindowButtonUpFcn     = '';
                end
            catch
            end
            obj.IsAttached = false;
            obj.ActiveController = [];
            obj.ActiveSessionId  = '';
        end

        function tf = requestDragLock(obj, sessionId, controller)
            % Returns true if the lock was granted (active session
            % matches workspace's currently selected tab AND no other
            % drag is in progress). Callers should fall through silently
            % when false — the click was on a stale tab.
            tf = false;
            sessionId = char(sessionId);
            try
                if ~isempty(obj.ActiveController) && isvalid(obj.ActiveController)
                    return;  % another drag still owns the lock
                end
                activeId = '';
                if ~isempty(obj.Workspace) && (~isa(obj.Workspace, 'handle') || isvalid(obj.Workspace))
                    activeId = char(obj.Workspace.activeSessionId());
                end
                if isempty(activeId) || strcmp(activeId, 'standalone') || ...
                        ~strcmp(activeId, sessionId)
                    return;  % requesting session is not the visible tab
                end
                obj.ActiveSessionId  = sessionId;
                obj.ActiveController = controller;
                if isprop(obj.UIFigure, 'Pointer')
                    try, obj.UIFigure.Pointer = 'left-right'; catch, end
                end
                tf = true;
            catch
            end
        end

        function releaseDragLock(obj)
            obj.ActiveController = [];
            obj.ActiveSessionId  = '';
            try
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure) ...
                        && isprop(obj.UIFigure, 'Pointer')
                    obj.UIFigure.Pointer = 'arrow';
                end
            catch
            end
        end

        function cancelSession(obj, sessionId)
            sessionId = char(sessionId);
            try
                if isempty(sessionId) || isempty(obj.ActiveSessionId) || ...
                        ~strcmp(obj.ActiveSessionId, sessionId)
                    return;
                end
                ctrl = obj.ActiveController;
                if ~isempty(ctrl) && isvalid(ctrl) && ismethod(ctrl, 'stopDrag')
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
            tf = ~isempty(obj.ActiveController) && isvalid(obj.ActiveController) ...
                && strcmp(obj.ActiveSessionId, char(sessionId));
        end

        function delete(obj)
            obj.detach();
        end
    end

    methods (Access = private)
        function onMouseMotion(obj)
            if isempty(obj.ActiveController) || ~isvalid(obj.ActiveController)
                obj.releaseDragLock();
                return;
            end
            % If the user switched tabs while the drag was in progress
            % the active session changed; suppress motion until either
            % the drag is released or focus returns.
            try
                activeNow = '';
                if ~isempty(obj.Workspace) && isvalid(obj.Workspace)
                    activeNow = char(obj.Workspace.activeSessionId());
                end
                if ~isempty(activeNow) && ~strcmp(activeNow, obj.ActiveSessionId)
                    return;
                end
            catch
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
            if isempty(ctrl) || ~isvalid(ctrl)
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
    end
end
