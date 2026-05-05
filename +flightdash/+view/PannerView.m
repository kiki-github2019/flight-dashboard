classdef PannerView < handle
    % flightdash.view.PannerView
    % Renders the compact range bar, viewport handles, and mode bands.

    properties (Access = private)
        App
    end

    methods
        function obj = PannerView(app)
            obj.App = app;
        end

        function refresh(obj, fIdx)
            app = obj.App;
            try
                if isempty(app.Models(fIdx).rawData), return; end
                if ~isfield(app.UI(fIdx), 'pannerAxes') || isempty(app.UI(fIdx).pannerAxes) || ~isvalid(app.UI(fIdx).pannerAxes)
                    return;
                end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isempty(times), return; end

                ax = app.UI(fIdx).pannerAxes;
                cla(ax);
                hold(ax, 'on');
                obj.drawModeBands(fIdx, ax, times);
                ax.YLim = [0 1];
                ax.YTick = [];
                ax.XTick = [];
                ax.XLim = [times(1) times(end)];
                grid(ax, 'off');
                obj.drawModeAxes(fIdx);
                obj.updateViewport(fIdx);
            catch ME
                app.logCaught(ME, 'Panner:refresh');
            end
        end

        function drawModeBands(obj, fIdx, ax, times)
            app = obj.App;
            try
                if ~isfield(app.UI(fIdx), 'flightModeBands') || isempty(app.UI(fIdx).flightModeBands)
                    h = patch(ax, [times(1) times(end) times(end) times(1)], [0.18 0.18 0.82 0.82], ...
                        [0.88 0.90 0.94], 'EdgeColor', [0.72 0.74 0.78], 'FaceAlpha', 1.0, 'HitTest', 'off');
                    app.excludeFromLegend(h);
                    return;
                end
                bands = app.UI(fIdx).flightModeBands;
                for k = 1:numel(bands)
                    h = patch(ax, [bands(k).Start bands(k).End bands(k).End bands(k).Start], [0.18 0.18 0.82 0.82], ...
                        bands(k).Color, 'EdgeColor', 'none', 'FaceAlpha', 0.78, 'HitTest', 'off');
                    app.excludeFromLegend(h);
                end
            catch ME
                app.logCaught(ME, 'Panner:modeBands');
            end
        end

        function updateViewport(obj, fIdx)
            app = obj.App;
            try
                if isempty(app.Models(fIdx).rawData), return; end
                if ~isfield(app.UI(fIdx), 'pannerAxes') || isempty(app.UI(fIdx).pannerAxes) || ~isvalid(app.UI(fIdx).pannerAxes)
                    return;
                end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                if isempty(times), return; end
                xlims = app.currentPlotXLim(fIdx, times);
                xlims(1) = max(times(1), min(times(end), xlims(1)));
                xlims(2) = max(times(1), min(times(end), xlims(2)));
                if xlims(2) <= xlims(1), xlims = [times(1), times(end)]; end

                ax = app.UI(fIdx).pannerAxes;
                hold(ax, 'on');
                if ~isfield(app.UI(fIdx), 'pannerViewPatch') || isempty(app.UI(fIdx).pannerViewPatch) || ~isvalid(app.UI(fIdx).pannerViewPatch)
                    app.UI(fIdx).pannerViewPatch = patch(ax, [xlims(1) xlims(2) xlims(2) xlims(1)], [0.08 0.08 0.92 0.92], ...
                        [0.96 0.74 0.18], 'FaceAlpha', 0.22, 'EdgeColor', [0.85 0.45 0.05], 'HitTest', 'off');
                    app.excludeFromLegend(app.UI(fIdx).pannerViewPatch);
                else
                    set(app.UI(fIdx).pannerViewPatch, 'XData', [xlims(1) xlims(2) xlims(2) xlims(1)], 'YData', [0.08 0.08 0.92 0.92]);
                end
                if ~isfield(app.UI(fIdx), 'pannerLeftHandle') || isempty(app.UI(fIdx).pannerLeftHandle) || ~isvalid(app.UI(fIdx).pannerLeftHandle)
                    app.UI(fIdx).pannerLeftHandle = xline(ax, xlims(1), 'Color', [0.85 0.45 0.05], 'LineWidth', 4.0, 'HitTest', 'on');
                    app.UI(fIdx).pannerLeftHandle.ButtonDownFcn = @(~,event) app.startPannerHandleDrag(fIdx, 'left', event);
                    app.excludeFromLegend(app.UI(fIdx).pannerLeftHandle);
                else
                    app.UI(fIdx).pannerLeftHandle.Value = xlims(1);
                end
                if ~isfield(app.UI(fIdx), 'pannerRightHandle') || isempty(app.UI(fIdx).pannerRightHandle) || ~isvalid(app.UI(fIdx).pannerRightHandle)
                    app.UI(fIdx).pannerRightHandle = xline(ax, xlims(2), 'Color', [0.85 0.45 0.05], 'LineWidth', 4.0, 'HitTest', 'on');
                    app.UI(fIdx).pannerRightHandle.ButtonDownFcn = @(~,event) app.startPannerHandleDrag(fIdx, 'right', event);
                    app.excludeFromLegend(app.UI(fIdx).pannerRightHandle);
                else
                    app.UI(fIdx).pannerRightHandle.Value = xlims(2);
                end
                currIdx = max(1, min(numel(times), app.Models(fIdx).currentIndex));
                currTime = times(currIdx);
                if ~isfield(app.UI(fIdx), 'pannerCurrentLine') || isempty(app.UI(fIdx).pannerCurrentLine) || ~isvalid(app.UI(fIdx).pannerCurrentLine)
                    app.UI(fIdx).pannerCurrentLine = xline(ax, currTime, 'r', 'LineWidth', 1.5, 'HitTest', 'off');
                    app.excludeFromLegend(app.UI(fIdx).pannerCurrentLine);
                else
                    app.UI(fIdx).pannerCurrentLine.Value = currTime;
                end
                try, uistack(app.UI(fIdx).pannerViewPatch, 'bottom'); catch, end
                if isfield(app.UI(fIdx), 'pannerFrom') && isvalid(app.UI(fIdx).pannerFrom), app.UI(fIdx).pannerFrom.Value = xlims(1); end
                if isfield(app.UI(fIdx), 'pannerTo') && isvalid(app.UI(fIdx).pannerTo), app.UI(fIdx).pannerTo.Value = xlims(2); end
            catch ME
                app.logCaught(ME, 'Panner:viewport');
            end
        end

        function drawModeAxes(obj, fIdx)
            app = obj.App;
            try
                if ~isfield(app.UI(fIdx), 'modeAxes') || isempty(app.UI(fIdx).modeAxes) || ~isvalid(app.UI(fIdx).modeAxes)
                    return;
                end
                ax = app.UI(fIdx).modeAxes;
                cla(ax);
                hold(ax, 'on');
                if isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                ax.XLim = [times(1), times(end)];
                ax.YLim = [0 1];
                ax.XTick = [];
                ax.YTick = [];
                if ~isfield(app.UI(fIdx), 'flightModeBands'), return; end
                bands = app.UI(fIdx).flightModeBands;
                for k = 1:numel(bands)
                    h = patch(ax, [bands(k).Start bands(k).End bands(k).End bands(k).Start], [0 0 1 1], ...
                        bands(k).Color, 'EdgeColor', 'none', 'FaceAlpha', 0.95, 'HitTest', 'off');
                    app.excludeFromLegend(h);
                end
            catch ME
                app.logCaught(ME, 'FlightModes:draw');
            end
        end
    end
end
