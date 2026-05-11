classdef PannerController < handle
    % flightdash.controller.PannerController
    % Owns compact range bar commands and handle-drag lifecycle.

    properties (Access = private)
        App
        Listeners cell = {}
        IsDragging logical = false
        DragFIdx double = 0
        DragSide char = ''
    end

    methods
        function obj = PannerController(app)
            obj.App = app;
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(obj.App, eventName, callback);
            % [PHASE 4] Skip event when this dashboard is not the active Studio session.
            obj.Listeners{end+1} = EB('PannerToggled',        @(~,d) obj.gated(@(d_) obj.togglePanner(d_.ChannelIdx), d));
            obj.Listeners{end+1} = EB('PannerClicked',        @(~,d) obj.gated(@(d_) obj.onPannerClicked(d_.ChannelIdx), d));
            obj.Listeners{end+1} = EB('PannerRangeChanged',   @(~,d) obj.gated(@(d_) obj.onRangeChanged(d_.ChannelIdx), d));
            obj.Listeners{end+1} = EB('PannerResetRequested', @(~,d) obj.gated(@(d_) obj.resetRange(d_.ChannelIdx), d));
        end

        function gated(obj, fn, d)
            if ~obj.App.isActiveSession(d), return; end
            fn(d);
        end

        function togglePanner(obj, fIdx)
            app = obj.App;
            try
                if ~isfield(app.UI(fIdx), 'plotShellGrid') || ~isvalid(app.UI(fIdx).plotShellGrid), return; end
                if ~isfield(app.UI(fIdx), 'pannerPanel') || isempty(app.UI(fIdx).pannerPanel) || ~isvalid(app.UI(fIdx).pannerPanel), return; end
                curr = false;
                if isfield(app.UI(fIdx), 'PannerVisible'), curr = logical(app.UI(fIdx).PannerVisible); end
                next = ~curr;
                app.UI(fIdx).PannerVisible = next;
                app.UI(fIdx).pannerPanel.Visible = app.LayoutMgr.visibleState(next);
                rh = app.UI(fIdx).plotShellGrid.RowHeight;
                if next
                    rh{3} = flightdash.util.UIScale.px(58);
                    if ~isempty(app.PannerView), app.PannerView.refresh(fIdx); end
                else
                    rh{3} = 0;
                end
                app.UI(fIdx).plotShellGrid.RowHeight = rh;
            catch ME
                app.logCaught(ME, 'Panner:toggle');
            end
        end

        function onPannerClicked(obj, fIdx)
            app = obj.App;
            try
                ax = app.UI(fIdx).pannerAxes;
                pt = ax.CurrentPoint;
                clickTime = pt(1, 1);
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                xlims = app.currentPlotXLim(fIdx, times);
                minGap = max(eps, (times(end) - times(1)) * 0.001);
                clickTime = max(times(1), min(times(end), clickTime));
                if abs(clickTime - xlims(1)) <= abs(clickTime - xlims(2))
                    clickTime = min(clickTime, xlims(2) - minGap);
                    obj.setCurrentTabXLim(fIdx, clickTime, xlims(2));
                else
                    clickTime = max(clickTime, xlims(1) + minGap);
                    obj.setCurrentTabXLim(fIdx, xlims(1), clickTime);
                end
            catch ME
                app.logCaught(ME, 'Panner:clicked');
            end
        end

        function startHandleDrag(obj, fIdx, side, event)
            app = obj.App;
            try
                if nargin >= 4 && ~isempty(event)
                    try
                        if isprop(event, 'Button') && event.Button ~= 1
                            return;
                        end
                    catch
                    end
                end
                if isempty(app.Models(fIdx).rawData), return; end
                obj.IsDragging = true;
                obj.DragFIdx = fIdx;
                obj.DragSide = char(side);
                if ~obj.bindFigureCallbacks(app)
                    obj.IsDragging = false;
                    obj.DragFIdx = 0;
                    obj.DragSide = '';
                    if ~app.IsEmbedded && isprop(app.UIFigure, 'Pointer')
                        app.UIFigure.Pointer = 'arrow';
                    end
                    return;
                end
                if ~app.IsEmbedded && isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'fleur'; end
            catch ME
                app.logCaught(ME, 'PannerHandle:start');
            end
        end

        function handleDragMotion(obj)
            app = obj.App;
            if ~obj.IsDragging, return; end
            % [PHASE 4 review] Same figure-level callback hazard as
            % MarkerDragController.plotMarkerDragMotion: if the active
            % tab changed mid-drag, ignore motion until the user
            % switches back or releases the mouse.
            if ~app.isActiveSession(), return; end
            try
                fIdx = obj.DragFIdx;
                if fIdx < 1 || fIdx > numel(app.UI), return; end
                ax = app.UI(fIdx).pannerAxes;
                if isempty(ax) || ~isvalid(ax), return; end
                pt = ax.CurrentPoint;
                newTime = pt(1, 1);
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                xlims = app.currentPlotXLim(fIdx, times);
                minGap = max(eps, (times(end) - times(1)) * 0.001);
                newTime = max(times(1), min(times(end), newTime));
                if strcmp(obj.DragSide, 'left')
                    newTime = min(newTime, xlims(2) - minGap);
                    obj.setCurrentTabXLim(fIdx, newTime, xlims(2));
                else
                    newTime = max(newTime, xlims(1) + minGap);
                    obj.setCurrentTabXLim(fIdx, xlims(1), newTime);
                end
                drawnow limitrate nocallbacks;
            catch ME
                app.logCaught(ME, 'PannerHandle:motion');
            end
        end

        function stopHandleDrag(obj)
            app = obj.App;
            try
                obj.IsDragging = false;
                obj.DragFIdx = 0;
                obj.DragSide = '';
                if isempty(app) || ~isvalid(app), return; end
                % [PHASE 3.5] Embedded mode lets StudioMouseRouter
                % manage the WindowButton callbacks; only standalone
                % clears them itself.
                if ~app.IsEmbedded && ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonMotionFcn = '';
                    app.UIFigure.WindowButtonUpFcn = '';
                    if isprop(app.UIFigure, 'Pointer'), app.UIFigure.Pointer = 'arrow'; end
                end
                drawnow limitrate;
            catch ME
                try
                    if ~isempty(app) && isvalid(app)
                        app.logCaught(ME, 'PannerHandle:stop');
                    end
                catch
                end
            end
        end

        function stopDrag(obj)
            % [PHASE 3.5] Unified stop entry — alias used by
            % StudioMouseRouter so MarkerDragController and
            % PannerController share the same contract.
            obj.stopHandleDrag();
        end

        function tf = bindFigureCallbacks(obj, app)
            % [PHASE 3.5] Standalone keeps direct callback assignment.
            % Embedded mode hands off to the central router.
            tf = false;
            if app.IsEmbedded
                router = obj.lookupRouter(app);
                if ~isempty(router) && isvalid(router)
                    if router.requestDragLock(app.ActiveSessionId, obj)
                        tf = true;
                        return;
                    end
                end
                try
                    ME = MException('FlightDash:NoStudioMouseRouter', ...
                        'Embedded panner drag requires StudioMouseRouter.');
                    app.logCaught(ME, 'Panner:router');
                catch
                end
                return;
            end
            app.UIFigure.WindowButtonMotionFcn = @(~,~) obj.handleDragMotion();
            app.UIFigure.WindowButtonUpFcn    = @(~,~) obj.stopHandleDrag();
            tf = true;
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

        function onRangeChanged(obj, fIdx)
            app = obj.App;
            try
                fromVal = app.UI(fIdx).pannerFrom.Value;
                toVal = app.UI(fIdx).pannerTo.Value;
                obj.setCurrentTabXLim(fIdx, fromVal, toVal);
            catch ME
                app.logCaught(ME, 'Panner:range');
            end
        end

        function resetRange(obj, fIdx)
            app = obj.App;
            try
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                obj.setCurrentTabXLim(fIdx, times(1), times(end));
            catch ME
                app.logCaught(ME, 'Panner:reset');
            end
        end

        function setCurrentTabXLim(obj, fIdx, fromVal, toVal)
            app = obj.App;
            try
                if isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isempty(times), return; end
                fromVal = max(times(1), min(times(end), fromVal));
                toVal = max(times(1), min(times(end), toVal));
                if toVal <= fromVal
                    toVal = min(times(end), fromVal + max(eps, (times(end) - times(1)) * 0.05));
                    fromVal = max(times(1), min(fromVal, toVal - eps));
                end
                tabIdx = app.currentPlotTabIndex(fIdx);
                if ~isempty(tabIdx) && ~isempty(app.UI(fIdx).plotAxes{tabIdx})
                    app.IsProgrammaticXLim(fIdx) = true;
                    cleanup_ = onCleanup(@() obj.resetProgrammaticXLim(fIdx)); %#ok<NASGU>
                    for k = 1:numel(app.UI(fIdx).plotAxes{tabIdx})
                        ax = app.UI(fIdx).plotAxes{tabIdx}{k};
                        if ~isempty(ax) && isvalid(ax), ax.XLim = [fromVal, toVal]; end
                    end
                    clear cleanup_;
                end
                app.updatePannerViewport(fIdx);
            catch ME
                app.IsProgrammaticXLim(fIdx) = false;
                app.logCaught(ME, 'Panner:setXLim');
            end
        end

        function resetProgrammaticXLim(obj, fIdx)
            app = obj.App;
            try
                if fIdx >= 1 && fIdx <= numel(app.IsProgrammaticXLim)
                    app.IsProgrammaticXLim(fIdx) = false;
                end
            catch ME
                app.logCaught(ME, 'Panner:resetProgrammaticXLim');
            end
        end

        function delete(obj)
            obj.stopHandleDrag();
            for k = 1:numel(obj.Listeners)
                try
                    if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end
                catch
                end
            end
            obj.Listeners = {};
        end
    end
end
