classdef MarkerDragController < flightdash.controller.ControllerBase
    % flightdash.controller.MarkerDragController
    % Owns plot marker / video frame drag lifecycle and per-drag state.
    %
    % [Phase 4 stabilization] Inherits from ControllerBase. Drag state
    % is custom (uses figure-level WindowButton callbacks rather than
    % the base's router-based lock) so the existing handlers are kept;
    % the base still provides logCaught + session/uiFigure routing.

    properties (SetAccess = private)
        IsDraggingMarker logical = false
        DraggedMarker            = []
        DraggedFIdx      double  = 0
        DraggedFromVideo logical = false
        OriginalMarkerPosition double = []
        OriginalMarkerIndex double = NaN
        VideoThrottleDyn double  = 0.05
        LastDragTime     cell    = {uint64(0), uint64(0)}
    end

    methods
        function obj = MarkerDragController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.MarkerDragController.normalizeInput(adapterOrApp));
        end

        function startPlotMarkerDrag(obj, fIdx, ~, src, event)
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            app = obj.Adapter.app();
            if event.Button ~= 1, return; end
            if isempty(app.Models(fIdx).rawData), return; end
            if app.SyncState.IsSynced && fIdx == 2, return; end

            obj.IsDraggingMarker = true;
            obj.DraggedMarker = src;
            obj.DraggedFIdx = fIdx;
            obj.DraggedFromVideo = false;
            obj.OriginalMarkerPosition = obj.readMarkerPosition(src);
            obj.OriginalMarkerIndex = obj.readCurrentIndex(fIdx);
            obj.VideoThrottleDyn = 0.05;
            obj.LastDragTime{fIdx} = tic;
            try
                app.throttleReset('MapPathDragUpdate', fIdx);
                app.throttleReset('PlotDragTimelineUpdate', fIdx);
            catch ME, obj.Adapter.logCaught(ME, 'silent'); end
            app.State = 'DRAGGING';
            src.HitTest = 'off';

            try
                ax = src.Parent;
                if isvalid(ax) && isprop(ax, 'Interactions')
                    obj.DraggedMarker.UserData = ax.Interactions;
                    ax.Interactions = [];
                end
            catch ME, obj.Adapter.logCaught(ME, 'silent'); end

            app.setXLimListenersEnabled(fIdx, false);

            try
                for tIdx = 1:length(app.UI(fIdx).timeLines)
                    tlArr = app.UI(fIdx).timeLines{tIdx};
                    for k = 1:length(tlArr)
                        if ~isempty(tlArr{k}) && isvalid(tlArr{k})
                            tlArr{k}.Alpha = 1.0;
                        end
                    end
                end
                if isfield(app.UI(fIdx), 'timeLine') && ~isempty(app.UI(fIdx).timeLine) && isvalid(app.UI(fIdx).timeLine)
                    app.UI(fIdx).timeLine.Alpha = 1.0;
                end
            catch ME, obj.Adapter.logCaught(ME, 'silent'); end

            if ~obj.bindFigureCallbacks()
                obj.stopDrag();
            end
        end

        function startVideoFrameDrag(obj, fIdx, src, event)
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            app = obj.Adapter.app();
            if event.Button ~= 1, return; end
            if isempty(app.VideoState(fIdx).videoReader), return; end

            obj.IsDraggingMarker = true;
            obj.DraggedMarker = src;
            obj.DraggedFIdx = fIdx;
            obj.DraggedFromVideo = true;
            obj.OriginalMarkerPosition = obj.readMarkerPosition(src);
            obj.OriginalMarkerIndex = obj.readCurrentIndex(fIdx);
            obj.VideoThrottleDyn = 0.05;
            obj.LastDragTime{fIdx} = tic;
            app.State = 'DRAGGING';
            src.HitTest = 'off';

            try
                ax = src.Parent;
                if isvalid(ax) && isprop(ax, 'Interactions')
                    obj.DraggedMarker.UserData = ax.Interactions;
                    ax.Interactions = [];
                end
            catch ME, obj.Adapter.logCaught(ME, 'silent'); end

            app.setXLimListenersEnabled(fIdx, false);

            if ~obj.bindFigureCallbacks()
                obj.stopDrag();
            end
        end

        function tf = bindFigureCallbacks(obj)
            % [PHASE 3.5] Standalone keeps writing the figure callback
            % directly. Embedded mode hands the lock to the Studio's
            % StudioMouseRouter so a single owner dispatches motion +
            % up events for every session sharing the host figure.
            tf = false;
            if obj.Adapter.isEmbedded()
                router = obj.lookupRouter();
                if ~isempty(router) && isvalid(router)
                    if router.requestDragLock(obj.Adapter.activeSessionId(), obj)
                        tf = true;
                        return;  % router will dispatch handleDragMotion / stopDrag
                    end
                end
                obj.logEmbeddedRouterIssue();
                return;
            end
            fig = obj.Adapter.uiFigure();
            if isempty(fig) || ~isvalid(fig), return; end
            fig.WindowButtonMotionFcn = @(~,~) flightdash.controller.MarkerDragController.safeHandleDragMotion(obj);
            fig.WindowButtonUpFcn    = @(~,~) flightdash.controller.MarkerDragController.safeStopDrag(obj);
            tf = true;
        end

        function handleDragMotion(obj)
            % [PHASE 3.5] Unified motion entry: dispatch based on
            % whether the active drag was started from a plot marker
            % or a video frame slider.
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            if ~obj.IsDraggingMarker, return; end
            if obj.DraggedFromVideo
                obj.videoFrameDragMotion(obj.DraggedFIdx);
            else
                obj.plotMarkerDragMotion(obj.DraggedFIdx);
            end
        end

        function router = lookupRouter(obj)
            router = [];
            try
                fig = obj.Adapter.uiFigure();
                if ~isempty(fig) && isvalid(fig) ...
                        && isappdata(fig, 'StudioMouseRouter')
                    router = getappdata(fig, 'StudioMouseRouter');
                end
            catch
            end
        end

        function logEmbeddedRouterIssue(obj)
            try
                ME = MException('FlightDash:NoStudioMouseRouter', ...
                    'Embedded marker drag requires StudioMouseRouter.');
                obj.Adapter.logCaught(ME, 'Drag:router');
            catch
            end
        end

        function plotMarkerDragMotion(obj, fIdx)
            app = obj.Adapter.app();
            if ~obj.IsDraggingMarker, return; end
            % [PHASE 4 review] Figure-level WindowButtonMotionFcn is a
            % single slot. If the user switched workspace tabs after the
            % drag started, this controller's motion fcn keeps firing
            % for the new tab's mouse events. Guard against acting on
            % the wrong session.
            if ~app.isActiveSession(), return; end
            try
                if isempty(obj.DraggedMarker) || ~isvalid(obj.DraggedMarker), return; end
                ax = obj.DraggedMarker.Parent;
                if isempty(ax) || ~isvalid(ax), return; end
                pt = ax.CurrentPoint;
                if isempty(pt) || any(isnan(pt(:))) || any(~isfinite(pt(:))), return; end
                targetTime = pt(1, 1);
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isempty(times), return; end
                targetTime = max(min(targetTime, times(end)), times(1));
                idx = app.findClosestIndexByTime(times, targetTime);
                if isequal(app.Models(fIdx).currentIndex, idx), return; end
                app.updateMarkersOnly(fIdx, idx);
            catch ME_silent, obj.Adapter.logCaught(ME_silent, 'silent'); end
        end

        function videoFrameDragMotion(obj, fIdx)
            app = obj.Adapter.app();
            if ~obj.IsDraggingMarker, return; end
            if ~app.isActiveSession(), return; end
            try
                if isempty(obj.DraggedMarker) || ~isvalid(obj.DraggedMarker), return; end
                ax = obj.DraggedMarker.Parent;
                if isempty(ax) || ~isvalid(ax), return; end
                pt = ax.CurrentPoint;
                if isempty(pt) || any(isnan(pt(:))) || any(~isfinite(pt(:))), return; end
                targetFrame = round(pt(1, 1));
                totalFrames = app.VideoSyncState(fIdx).TotalFrames;
                if totalFrames < 1, return; end
                app.updateDragVelocity(fIdx, targetFrame);
                app.goToFrame(fIdx, targetFrame, 'drag');
                drawnow limitrate;
            catch ME_silent, obj.Adapter.logCaught(ME_silent, 'silent'); end
        end

        function computeDynamicVideoThrottle(obj)
            try
                fIdx = obj.DraggedFIdx;
                if fIdx < 1 || fIdx > 2, return; end
                if obj.LastDragTime{fIdx} == 0, obj.LastDragTime{fIdx} = tic; return; end
                dt = toc(obj.LastDragTime{fIdx});
                obj.LastDragTime{fIdx} = tic;
                if dt <= 0, return; end
                if dt < 0.025
                    target = 0.20;
                elseif dt < 0.06
                    target = 0.10;
                else
                    target = 0.05;
                end
                obj.VideoThrottleDyn = 0.7 * obj.VideoThrottleDyn + 0.3 * target;
            catch ME_silent, obj.Adapter.logCaught(ME_silent, 'silent'); end
        end

        function stopDrag(obj)
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            app = obj.Adapter.app();
            wasDraggingFIdx = obj.DraggedFIdx;
            draggedMarker = obj.DraggedMarker;
            oldPosition = obj.OriginalMarkerPosition;
            newPosition = obj.readMarkerPosition(draggedMarker);
            oldIndex = obj.OriginalMarkerIndex;
            newIndex = obj.readCurrentIndex(wasDraggingFIdx);
            obj.IsDraggingMarker = false;
            app.State = 'IDLE';

            % [PHASE 3.5] Only clear figure callbacks in standalone
            % mode. In embedded mode the StudioMouseRouter owns those
            % slots — clearing them would break drag for every other
            % session in the Studio. The router calls releaseDragLock
            % itself after stopDrag returns.
            try
                fig = obj.Adapter.uiFigure();
                if ~obj.Adapter.isEmbedded() && ~isempty(fig) && isvalid(fig)
                    fig.WindowButtonMotionFcn = '';
                    fig.WindowButtonUpFcn = '';
                end
            catch ME, obj.Adapter.logCaught(ME, 'silent'); end

            try
                if ~isempty(obj.DraggedMarker) && isvalid(obj.DraggedMarker)
                    obj.DraggedMarker.HitTest = 'on';
                    ax = obj.DraggedMarker.Parent;
                    if isvalid(ax) && isprop(ax, 'Interactions') && ~isempty(obj.DraggedMarker.UserData)
                        ax.Interactions = obj.DraggedMarker.UserData;
                    end
                end
            catch ME, obj.Adapter.logCaught(ME, 'silent'); end

            obj.DraggedMarker = [];
            obj.DraggedFIdx = 0;
            obj.DraggedFromVideo = false;
            obj.OriginalMarkerPosition = [];
            obj.OriginalMarkerIndex = NaN;
            obj.VideoThrottleDyn = 0.05;

            obj.pushMoveMarkerCommand(wasDraggingFIdx, draggedMarker, oldPosition, newPosition, oldIndex, newIndex);

            for fIdx = 1:2
                try
                    for tIdx = 1:length(app.UI(fIdx).timeLines)
                        tlArr = app.UI(fIdx).timeLines{tIdx};
                        for k = 1:length(tlArr)
                            if ~isempty(tlArr{k}) && isvalid(tlArr{k})
                                tlArr{k}.Alpha = 0.5;
                            end
                        end
                    end
                    if isfield(app.UI(fIdx), 'timeLine') && ~isempty(app.UI(fIdx).timeLine) && isvalid(app.UI(fIdx).timeLine)
                        app.UI(fIdx).timeLine.Alpha = 0.5;
                    end
                catch ME, obj.Adapter.logCaught(ME, 'silent'); end
            end

            if wasDraggingFIdx >= 1 && wasDraggingFIdx <= 2
                app.setXLimListenersEnabled(wasDraggingFIdx, true);
            end

            for fIdx = 1:2
                if ~isvalid(app), break; end
                if ~isempty(app.Models(fIdx).rawData)
                    idx = app.Models(fIdx).currentIndex;
                    app.setStateUpdating(fIdx, true);
                    cleanup_ = onCleanup(@() flightdash.controller.MarkerDragController.safeClearUpdating(app, fIdx)); %#ok<NASGU>
                    try
                        app.updateDashboard(fIdx, idx);
                    catch e
                        if isvalid(app), obj.Adapter.logCaught(e, 'stopPlotMarkerDrag:sync'); end
                    end
                    clear cleanup_;
                    if isvalid(app), app.prefetchAdjacentFrames(fIdx); end
                end
            end
        end

        function setDraggedFromVideo(obj, tf)
            obj.DraggedFromVideo = logical(tf);
        end

        function clearDraggedMarker(obj)
            obj.DraggedMarker = [];
        end

        function pos = readMarkerPosition(~, marker)
            pos = [];
            try
                if isempty(marker) || ~isvalid(marker)
                    return;
                end
                if isprop(marker, 'Position')
                    pos = marker.Position;
                elseif isprop(marker, 'Value')
                    pos = marker.Value;
                elseif isprop(marker, 'XData') && isprop(marker, 'YData')
                    x = marker.XData;
                    y = marker.YData;
                    if ~isempty(x) && ~isempty(y)
                        pos = [x(1), y(1)];
                    end
                end
            catch
                pos = [];
            end
        end

        function idx = readCurrentIndex(obj, fIdx)
            idx = NaN;
            try
                app = obj.Adapter.app();
                if fIdx >= 1 && fIdx <= numel(app.Models)
                    idx = app.Models(fIdx).currentIndex;
                end
            catch
                idx = NaN;
            end
        end

        function pushMoveMarkerCommand(obj, fIdx, marker, oldPosition, newPosition, oldIndex, newIndex)
            try
                app = obj.Adapter.app();
                markerMoved = ~(isempty(oldPosition) || isempty(newPosition) || isequal(oldPosition, newPosition));
                indexMoved = ~(isempty(oldIndex) || isempty(newIndex) || isnan(oldIndex) || isnan(newIndex) || oldIndex == newIndex);
                if ~markerMoved && ~indexMoved
                    return;
                end
                if isempty(marker) || ~isvalid(marker), return; end
                undoSvc = obj.Adapter.undoService();
                if isempty(app) || ~isvalid(app) || isempty(undoSvc)
                    return;
                end
                cmd = flightdash.command.MoveMarkerCommand(obj.Adapter.activeSessionId(), marker, ...
                    oldPosition, newPosition, 'Move Marker', app, fIdx, oldIndex, newIndex);
                undoSvc.push(cmd);
            catch ME
                obj.Adapter.logCaught(ME, 'MarkerDrag:undoPush');
            end
        end
    end

    methods (Static)
        function safeClearUpdating(app, fIdx)
            % Defensive onCleanup target: app may be deleted by the time
            % this fires (e.g. modal dialog tore down the dashboard mid-drag).
            try
                if isa(app, 'handle') && isvalid(app)
                    app.setStateUpdating(fIdx, false);
                end
            catch
            end
        end

        function safeHandleDragMotion(controller)
            try
                if ~flightdash.controller.MarkerDragController.isUsable(controller), return; end
                controller.handleDragMotion();
            catch ME
                try
                    flightdash.util.ErrorLog.log(ME, 'MarkerDrag:motionCallback', false);
                catch
                end
            end
        end

        function safeStopDrag(controller)
            try
                if ~flightdash.controller.MarkerDragController.isUsable(controller), return; end
                controller.stopDrag();
            catch ME
                try
                    flightdash.util.ErrorLog.log(ME, 'MarkerDrag:upCallback', false);
                catch
                end
            end
        end

        function tf = isUsable(controller)
            tf = false;
            try
                tf = ~isempty(controller) && isvalid(controller);
            catch
                tf = false;
            end
        end

        function input = normalizeInput(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter') || ...
                    isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                input = adapterOrApp;
            else
                error('MarkerDragController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
        end
    end
end
