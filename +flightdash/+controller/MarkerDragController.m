classdef MarkerDragController < handle
    % flightdash.controller.MarkerDragController
    % Owns plot marker / video frame drag lifecycle and per-drag state.

    properties (Access = private)
        App
    end

    properties (SetAccess = private)
        IsDraggingMarker logical = false
        DraggedMarker            = []
        DraggedFIdx      double  = 0
        DraggedFromVideo logical = false
        VideoThrottleDyn double  = 0.05
        LastDragTime     cell    = {uint64(0), uint64(0)}
    end

    methods
        function obj = MarkerDragController(app)
            obj.App = app;
        end

        function startPlotMarkerDrag(obj, fIdx, ~, src, event)
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            app = obj.App;
            if event.Button ~= 1, return; end
            if isempty(app.Models(fIdx).rawData), return; end
            if app.SyncState.IsSynced && fIdx == 2, return; end

            obj.IsDraggingMarker = true;
            obj.DraggedMarker = src;
            obj.DraggedFIdx = fIdx;
            obj.DraggedFromVideo = false;
            obj.VideoThrottleDyn = 0.05;
            obj.LastDragTime{fIdx} = tic;
            try
                app.throttleReset('MapPathDragUpdate', fIdx);
                app.throttleReset('PlotDragTimelineUpdate', fIdx);
            catch ME, app.logCaught(ME, 'silent'); end
            app.State = 'DRAGGING';
            src.HitTest = 'off';

            try
                ax = src.Parent;
                if isvalid(ax) && isprop(ax, 'Interactions')
                    obj.DraggedMarker.UserData = ax.Interactions;
                    ax.Interactions = [];
                end
            catch ME, app.logCaught(ME, 'silent'); end

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
            catch ME, app.logCaught(ME, 'silent'); end

            obj.bindFigureCallbacks(app);
        end

        function startVideoFrameDrag(obj, fIdx, src, event)
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            app = obj.App;
            if event.Button ~= 1, return; end
            if isempty(app.VideoState(fIdx).videoReader), return; end

            obj.IsDraggingMarker = true;
            obj.DraggedMarker = src;
            obj.DraggedFIdx = fIdx;
            obj.DraggedFromVideo = true;
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
            catch ME, app.logCaught(ME, 'silent'); end

            app.setXLimListenersEnabled(fIdx, false);

            obj.bindFigureCallbacks(app);
        end

        function bindFigureCallbacks(obj, app)
            % [PHASE 3.5] Standalone keeps writing the figure callback
            % directly. Embedded mode hands the lock to the Studio's
            % StudioMouseRouter so a single owner dispatches motion +
            % up events for every session sharing the host figure.
            if app.IsEmbedded
                router = obj.lookupRouter(app);
                if ~isempty(router) && isvalid(router)
                    if router.requestDragLock(app.ActiveSessionId, obj)
                        return;  % router will dispatch handleDragMotion / stopDrag
                    end
                end
                % Fallback: router unavailable or refused. Direct
                % callback assignment is still safer than no callback;
                % the Phase 4 isActiveSession guards inside the motion
                % methods keep cross-tab leaks impossible.
            end
            app.UIFigure.WindowButtonMotionFcn = @(~,~) flightdash.controller.MarkerDragController.safeHandleDragMotion(obj);
            app.UIFigure.WindowButtonUpFcn    = @(~,~) flightdash.controller.MarkerDragController.safeStopDrag(obj);
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

        function router = lookupRouter(~, app)
            router = [];
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure) ...
                        && isappdata(app.UIFigure, 'StudioMouseRouter')
                    router = getappdata(app.UIFigure, 'StudioMouseRouter');
                end
            catch
            end
        end

        function plotMarkerDragMotion(obj, fIdx)
            app = obj.App;
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
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function videoFrameDragMotion(obj, fIdx)
            app = obj.App;
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
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function computeDynamicVideoThrottle(obj)
            app = obj.App;
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
            catch ME_silent, app.logCaught(ME_silent, 'silent'); end
        end

        function stopDrag(obj)
            if ~flightdash.controller.MarkerDragController.isUsable(obj), return; end
            app = obj.App;
            wasDraggingFIdx = obj.DraggedFIdx;
            obj.IsDraggingMarker = false;
            app.State = 'IDLE';

            % [PHASE 3.5] Only clear figure callbacks in standalone
            % mode. In embedded mode the StudioMouseRouter owns those
            % slots — clearing them would break drag for every other
            % session in the Studio. The router calls releaseDragLock
            % itself after stopDrag returns.
            try
                if ~app.IsEmbedded && ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = '';
                    app.UIFigure.WindowButtonUpFcn = '';
                end
            catch ME, app.logCaught(ME, 'silent'); end

            try
                if ~isempty(obj.DraggedMarker) && isvalid(obj.DraggedMarker)
                    obj.DraggedMarker.HitTest = 'on';
                    ax = obj.DraggedMarker.Parent;
                    if isvalid(ax) && isprop(ax, 'Interactions') && ~isempty(obj.DraggedMarker.UserData)
                        ax.Interactions = obj.DraggedMarker.UserData;
                    end
                end
            catch ME, app.logCaught(ME, 'silent'); end

            obj.DraggedMarker = [];
            obj.DraggedFIdx = 0;
            obj.DraggedFromVideo = false;
            obj.VideoThrottleDyn = 0.05;

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
                catch ME, app.logCaught(ME, 'silent'); end
            end

            if wasDraggingFIdx >= 1 && wasDraggingFIdx <= 2
                app.setXLimListenersEnabled(wasDraggingFIdx, true);
            end

            for fIdx = 1:2
                if ~isempty(app.Models(fIdx).rawData)
                    idx = app.Models(fIdx).currentIndex;
                    app.setStateUpdating(fIdx, true);
                    cleanup_ = onCleanup(@() app.setStateUpdating(fIdx, false)); %#ok<NASGU>
                    try
                        app.updateDashboard(fIdx, idx);
                    catch e
                        app.logCaught(e, 'stopPlotMarkerDrag:sync');
                    end
                    clear cleanup_;
                    app.prefetchAdjacentFrames(fIdx);
                end
            end
        end

        function setDraggedFromVideo(obj, tf)
            obj.DraggedFromVideo = logical(tf);
        end

        function clearDraggedMarker(obj)
            obj.DraggedMarker = [];
        end
    end

    methods (Static)
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
    end
end
