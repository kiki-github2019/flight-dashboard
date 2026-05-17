classdef RoiController < flightdash.controller.ControllerBase
    % flightdash.controller.RoiController
    % Owns ROI events, ROI table state updates, and ROI statistics commands.
    %
    % [Phase 4 stabilization] Inherits from ControllerBase. EventBus
    % subscriptions go through trackListener; onCleanup() forwards to
    % clearHover so the patch-handle hover state is reset before
    % dashboard teardown.

    properties (Access = private)
        IsDraggingRoi logical = false
        CurrentHitInfo = struct()
        OriginalRoiRow = {}
        DragStartXData double = NaN
        HoveredTarget = struct()
        HoveredHandles cell = {}
    end

    properties
        HitThreshold double = 6
        EdgeThreshold double = 6
        HoverColor double = [1.0 0.58 0.0]
        HoverFaceAlpha double = 0.22
        HoverEdgeAlpha double = 0.18
        HoverLineWidth double = 1.5
    end

    methods
        function obj = RoiController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.ControllerBase.normalizeAdapterInput( ...
                    adapterOrApp, 'RoiController'));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            % [PHASE 4] Each handler bails when this controller's app
            % is not the active Studio session.
            obj.subscribeEvent('RoiAddRequested',            @(~,d) obj.gated(@(d_) obj.addCurrentRoi(d_.ChannelIdx), d));
            obj.subscribeEvent('RoiSelectionChanged',        @(~,d) obj.gated(@(d_) obj.onSelectionChanged(d_.ChannelIdx, d_.Payload), d));
            obj.subscribeEvent('RoiDeleteSelectedRequested', @(~,d) obj.gated(@(d_) obj.deleteSelectedRoi(d_.ChannelIdx), d));
            obj.subscribeEvent('RoiClearRequested',          @(~,d) obj.gated(@(d_) obj.clearRois(d_.ChannelIdx), d));
            obj.subscribeEvent('AnalysisComputeRequested',   @(~,d) obj.gated(@(d_) obj.computeAnalysis(d_.ChannelIdx), d));
        end

        function onCleanup(obj)
            % Clear hover-state patch appearance before listener
            % cleanup so the inherited destructor does not leave
            % visible highlights on the figure.
            try, obj.clearHover(); catch, end
        end

        function gated(obj, fn, d)
            if ~obj.Adapter.app().isActiveSession(d), return; end
            fn(d);
        end

        function addCurrentRoi(obj, fIdx)
            app = obj.Adapter.app();
            try
                if isempty(app.Models(fIdx).rawData), return; end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                xlims = app.currentPlotXLim(fIdx, times);
                tabIdx = app.currentPlotTabIndex(fIdx);
                plotIdx = app.selectedPlotIndex(fIdx);
                signalName = 'time';
                if ~isempty(tabIdx) && plotIdx > 0 && plotIdx <= numel(app.UI(fIdx).plotMeta{tabIdx})
                    signalName = app.UI(fIdx).plotMeta{tabIdx}{plotIdx}.YColumn;
                end
                row = {xlims(1), xlims(2), signalName, '--', '--'};
                rowIdx = obj.insertRoiRow(fIdx, row, Inf);
                obj.pushRoiRowsCommand(fIdx, rowIdx, row, 'create', 'Create ROI');
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:add');
            end
        end

        function onSelectionChanged(obj, fIdx, event)
            app = obj.Adapter.app();
            try
                app.UI(fIdx).selectedRoiIdx = 0;
                if isempty(event) || isempty(event.Indices), return; end
                row = event.Indices(1, 1);
                if row >= 1 && isfield(app.UI(fIdx), 'roiRows') && row <= size(app.UI(fIdx).roiRows, 1)
                    app.UI(fIdx).selectedRoiIdx = row;
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:select');
            end
        end

        function deleteSelectedRoi(obj, fIdx)
            app = obj.Adapter.app();
            try
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows), return; end
                row = 0;
                if isfield(app.UI(fIdx), 'selectedRoiIdx'), row = app.UI(fIdx).selectedRoiIdx; end
                if isempty(row) || row < 1 || row > size(app.UI(fIdx).roiRows, 1), return; end
                rowData = app.UI(fIdx).roiRows(row, :);
                obj.removeRoiRowAt(fIdx, row);
                obj.pushRoiRowsCommand(fIdx, row, rowData, 'delete', 'Delete ROI');
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:deleteSelected');
            end
        end

        function clearRois(obj, fIdx)
            app = obj.Adapter.app();
            try
                obj.deleteGraphics(fIdx);
                app.UI(fIdx).roiRows = cell(0, 5);
                app.UI(fIdx).selectedRoiIdx = 0;
                obj.refreshTable(fIdx);
                app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:clear');
            end
        end

        function refreshTable(obj, fIdx)
            app = obj.Adapter.app();
            try
                if isfield(app.UI(fIdx), 'roiTable') && ~isempty(app.UI(fIdx).roiTable) && isvalid(app.UI(fIdx).roiTable)
                    app.UI(fIdx).roiTable.Data = app.UI(fIdx).roiRows;
                end
                app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:refreshTable');
            end
        end

        function computeAnalysis(obj, fIdx)
            app = obj.Adapter.app();
            try
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows)
                    app.AuxWindowMgr.openStatsFigure(app, fIdx);
                    return;
                end
                timeCol = app.Models(fIdx).mappedCols.Time;
                times = app.Models(fIdx).rawData.(timeCol);
                rows = app.UI(fIdx).roiRows;
                rows = flightdash.model.RoiAnalyzer.computeStats(times, app.Models(fIdx).rawData, rows);
                app.UI(fIdx).roiRows = rows;
                obj.registerSelectedResult(fIdx, rows, times);
                obj.refreshTable(fIdx);
                obj.drawBands(fIdx);
                app.AuxWindowMgr.openStatsFigure(app, fIdx);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:analysis');
            end
        end

        function registerSelectedResult(obj, fIdx, rows, times)
            app = obj.Adapter.app();
            try
                roiIdx = 0;
                if isfield(app.UI(fIdx), 'selectedRoiIdx')
                    roiIdx = app.UI(fIdx).selectedRoiIdx;
                end
                if isempty(roiIdx) || roiIdx < 1 || roiIdx > size(rows, 1)
                    if size(rows, 1) == 1
                        roiIdx = 1;
                    else
                        return;
                    end
                end
                request = flightdash.analysis.AnalysisService.makeRoiStatisticsRequest( ...
                    obj.Adapter.activeSessionId(), fIdx, roiIdx, rows(roiIdx, :), ...
                    times, app.Models(fIdx).rawData, app.VideoSyncState(fIdx), ...
                    flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId);
                analysisResult = flightdash.analysis.AnalysisService.run(request);
                resultModel = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);
                app.registerReviewResult(resultModel);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:registerResult');
            end
        end

        function targetCol = matchTargetColumn(obj, fIdx, signalName)
            app = obj.Adapter.app();
            vars = app.Models(fIdx).rawData.Properties.VariableNames;
            targetCol = flightdash.model.RoiAnalyzer.matchTargetColumn(vars, signalName);
        end

        function drawBands(obj, fIdx)
            app = obj.Adapter.app();
            try
                obj.clearHover();
                obj.deleteGraphics(fIdx);
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows), return; end
                tabIdx = app.currentPlotTabIndex(fIdx);
                if isempty(tabIdx) || isempty(app.UI(fIdx).plotAxes{tabIdx}), return; end
                roiHandles = {};
                for aIdx = 1:numel(app.UI(fIdx).plotAxes{tabIdx})
                    ax = app.UI(fIdx).plotAxes{tabIdx}{aIdx};
                    if isempty(ax) || ~isvalid(ax), continue; end
                    yl = ax.YLim;
                    hold(ax, 'on');
                    for r = 1:size(app.UI(fIdx).roiRows, 1)
                        x0 = app.UI(fIdx).roiRows{r, 1};
                        x1 = app.UI(fIdx).roiRows{r, 2};
                        h = patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], ...
                            [0.96 0.74 0.18], 'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HitTest', 'off');
                        h.UserData = struct('ChannelIdx', fIdx, 'RoiIndex', r, 'AxesIndex', aIdx);
                        app.excludeFromLegend(h);
                        try, uistack(h, 'bottom'); catch, end
                        roiHandles{end+1} = h; %#ok<AGROW>
                    end
                end
                app.UI(fIdx).roiGraphics = roiHandles;
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:draw');
            end
        end

        function deleteGraphics(obj, fIdx)
            app = obj.Adapter.app();
            try
                obj.clearHover();
                if isfield(app.UI(fIdx), 'roiGraphics')
                    app.deleteGraphicsHandles(app.UI(fIdx).roiGraphics);
                end
                app.UI(fIdx).roiGraphics = {};
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:deleteGraphics');
            end
        end

        function [tf, target] = hitTest(obj, point)
            tf = false;
            target = [];
            try
                app = obj.Adapter.app();
                if isempty(app) || ~isvalid(app) || ~app.isActiveSession()
                    return;
                end
                point = double(point);
                if numel(point) < 2 || any(~isfinite(point(1:2))) || ...
                        ~isprop(app, 'UI') || isempty(app.UI)
                    return;
                end
                point = point(1:2);

                for fIdx = 1:min(2, numel(app.UI))
                    if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows)
                        continue;
                    end
                    tabIdx = app.currentPlotTabIndex(fIdx);
                    if isempty(tabIdx) || ~isfield(app.UI(fIdx), 'plotAxes') || ...
                            numel(app.UI(fIdx).plotAxes) < tabIdx || isempty(app.UI(fIdx).plotAxes{tabIdx})
                        continue;
                    end
                    for aIdx = 1:numel(app.UI(fIdx).plotAxes{tabIdx})
                        ax = app.UI(fIdx).plotAxes{tabIdx}{aIdx};
                        if isempty(ax) || ~isvalid(ax) || ~obj.pointInAxes(ax, point)
                            continue;
                        end
                        [roiIdx, hitType, xData, distancePx] = obj.hitRoiRows(app.UI(fIdx).roiRows, ax, point);
                        if roiIdx > 0
                            tf = true;
                            target = struct('ChannelIdx', fIdx, ...
                                'RoiIndex', roiIdx, ...
                                'Axes', ax, ...
                                'AxesIndex', aIdx, ...
                                'HitType', hitType, ...
                                'Distance', distancePx, ...
                                'XData', xData, ...
                                'EdgeSide', obj.edgeSideForHit(app.UI(fIdx).roiRows(roiIdx, :), xData), ...
                                'Row', {app.UI(fIdx).roiRows(roiIdx, :)});
                            return;
                        end
                    end
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:hitTest');
                tf = false;
                target = [];
            end
        end

        function onButtonDown(obj, target, ~)
            try
                if isempty(target) || ~isstruct(target) || ...
                        ~isfield(target, 'ChannelIdx') || ~isfield(target, 'RoiIndex')
                    return;
                end
                fIdx = target.ChannelIdx;
                roiIdx = target.RoiIndex;
                obj.selectRoiTarget(fIdx, roiIdx);
                obj.CurrentHitInfo = target;
                obj.OriginalRoiRow = target.Row;
                obj.DragStartXData = target.XData;
                obj.IsDraggingRoi = false;

                app = obj.Adapter.app();
                router = [];
                try
                    if ismethod(app, 'lookupStudioMouseRouter')
                        router = app.lookupStudioMouseRouter();
                    end
                catch
                end
                if ~isempty(router) && isvalid(router) && ...
                        router.requestDragLock(obj.Adapter.activeSessionId(), obj, 'fleur', 'roi')
                    obj.IsDraggingRoi = true;
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:hitButtonDown');
            end
        end

        function handleHover(obj, point)
            try
                if obj.IsDraggingRoi
                    return;
                end
                [hit, target] = obj.hitTest(point);
                if hit
                    obj.setHoveredTarget(target);
                else
                    obj.clearHover();
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:hover');
            end
        end

        function setHoveredTarget(obj, target)
            try
                if isempty(target) || ~isstruct(target) || ...
                        ~isfield(target, 'ChannelIdx') || ~isfield(target, 'RoiIndex')
                    obj.clearHover();
                    return;
                end
                if obj.sameHoverTarget(target)
                    return;
                end
                obj.clearHover();
                obj.HoveredTarget = target;
                obj.HoveredHandles = obj.roiGraphicHandles(target.ChannelIdx, target.RoiIndex);
                obj.applyHoverAppearance(target);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:setHover');
            end
        end

        function clearHover(obj)
            try
                for k = 1:numel(obj.HoveredHandles)
                    h = obj.HoveredHandles{k};
                    if ~isempty(h) && isvalid(h)
                        h.FaceAlpha = 0.10;
                        h.EdgeColor = 'none';
                        h.LineWidth = 0.5;
                    end
                end
            catch
            end
            obj.HoveredTarget = struct();
            obj.HoveredHandles = {};
        end

        function handleDragMotion(obj)
            if ~obj.IsDraggingRoi
                return;
            end
            try
                app = obj.Adapter.app();
                info = obj.CurrentHitInfo;
                if isempty(app) || ~isvalid(app) || isempty(info) || ~isstruct(info) || ...
                        ~isfield(info, 'ChannelIdx') || ~isfield(info, 'RoiIndex') || ...
                        ~isfield(info, 'Axes') || isempty(info.Axes) || ~isvalid(info.Axes)
                    return;
                end
                fIdx = info.ChannelIdx;
                roiIdx = info.RoiIndex;
                if ~isfield(app.UI(fIdx), 'roiRows') || roiIdx < 1 || roiIdx > size(app.UI(fIdx).roiRows, 1)
                    return;
                end

                fig = obj.Adapter.uiFigure();
                if isempty(fig) || ~isvalid(fig), return; end
                currX = obj.figurePointToAxesX(info.Axes, fig.CurrentPoint(1:2));
                if ~isfinite(currX) || ~isfinite(obj.DragStartXData)
                    return;
                end
                delta = currX - obj.DragStartXData;
                app.UI(fIdx).roiRows(roiIdx, :) = obj.dragRoiRow(obj.OriginalRoiRow, info, delta);
                app.UI(fIdx).selectedRoiIdx = roiIdx;

                if ~app.throttleHit('RoiDragRefresh', fIdx, 0.03)
                    obj.drawBands(fIdx);
                    drawnow limitrate nocallbacks;
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:dragMotion');
            end
        end

        function stopDrag(obj)
            cleanupLock = onCleanup(@() obj.releaseDragLock()); %#ok<NASGU>
            try
                if obj.IsDraggingRoi && ~isempty(obj.CurrentHitInfo) && isstruct(obj.CurrentHitInfo) && ...
                        isfield(obj.CurrentHitInfo, 'ChannelIdx') && isfield(obj.CurrentHitInfo, 'RoiIndex')
                    fIdx = obj.CurrentHitInfo.ChannelIdx;
                    roiIdx = obj.CurrentHitInfo.RoiIndex;
                    obj.pushMoveUndoCommand(fIdx, roiIdx);
                    obj.refreshTable(fIdx);
                    obj.drawBands(fIdx);
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:dragStop');
            end
            obj.IsDraggingRoi = false;
            obj.CurrentHitInfo = struct();
            obj.OriginalRoiRow = {};
            obj.DragStartXData = NaN;
            try
                fig = obj.Adapter.uiFigure();
                if ~isempty(fig) && isvalid(fig)
                    obj.handleHover(fig.CurrentPoint(1:2));
                end
            catch
            end
        end

        function pushMoveUndoCommand(obj, fIdx, roiIdx)
            try
                app = obj.Adapter.app();
                undoSvc = obj.Adapter.undoService();
                if isempty(app) || ~isvalid(app) || isempty(undoSvc) || ...
                        ~isvalid(undoSvc) || isempty(obj.OriginalRoiRow)
                    return;
                end
                if ~isfield(app.UI(fIdx), 'roiRows') || roiIdx < 1 || roiIdx > size(app.UI(fIdx).roiRows, 1)
                    return;
                end
                oldRow = obj.OriginalRoiRow;
                newRow = app.UI(fIdx).roiRows(roiIdx, :);
                if isequaln(oldRow, newRow)
                    return;
                end
                cmd = flightdash.command.MoveROICommand(obj.Adapter.activeSessionId(), app, ...
                    fIdx, roiIdx, oldRow, newRow, sprintf('Move ROI %d', roiIdx));
                undoSvc.push(cmd);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:undoPush');
            end
        end

        function hitInfo = testSingleRoiRow(obj, row, ax, point, roiIndex)
            hitInfo = struct('Hit', false, ...
                'RoiIndex', double(roiIndex), ...
                'HitType', '', ...
                'Distance', inf, ...
                'XData', NaN, ...
                'EdgeSide', '', ...
                'Row', {row});
            try
                pos = getpixelposition(ax, true);
                if isempty(row) || pos(3) <= 0 || numel(point) < 2
                    return;
                end
                xl = double(ax.XLim);
                xData = xl(1) + ((point(1) - pos(1)) / pos(3)) * (xl(2) - xl(1));
                x0 = obj.numericCell(row{1});
                x1 = obj.numericCell(row{2});
                if ~isfinite(x0) || ~isfinite(x1)
                    return;
                end

                lo = min(x0, x1);
                hi = max(x0, x1);
                edgeDistStart = abs(xData - x0);
                edgeDistEnd = abs(xData - x1);
                edgeDistData = min(edgeDistStart, edgeDistEnd);
                dataToPixel = pos(3) / max(abs(xl(2) - xl(1)), eps);
                edgeDistPx = edgeDistData * dataToPixel;

                hitInfo.XData = xData;
                hitInfo.Distance = edgeDistPx;
                if edgeDistPx <= double(obj.EdgeThreshold)
                    hitInfo.Hit = true;
                    hitInfo.HitType = 'edge';
                    if edgeDistStart <= edgeDistEnd
                        hitInfo.EdgeSide = 'start';
                    else
                        hitInfo.EdgeSide = 'end';
                    end
                    return;
                end
                if xData >= lo && xData <= hi
                    hitInfo.Hit = true;
                    hitInfo.HitType = 'body';
                    hitInfo.Distance = 0;
                end
            catch
                hitInfo.Hit = false;
            end
        end

        function rowIdx = insertRoiRow(obj, fIdx, rowData, rowIdx)
            app = obj.Adapter.app();
            if nargin < 4 || isempty(rowIdx) || isnan(rowIdx) || isinf(rowIdx)
                rowIdx = Inf;
            end
            try
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows)
                    app.UI(fIdx).roiRows = cell(0, 5);
                end
                if isempty(rowData)
                    return;
                end
                rowData = rowData(1, :);
                nRows = size(app.UI(fIdx).roiRows, 1);
                rowIdx = max(1, min(rowIdx, nRows + 1));
                if nRows == 0
                    app.UI(fIdx).roiRows = rowData;
                elseif rowIdx > nRows
                    app.UI(fIdx).roiRows(end+1, :) = rowData;
                else
                    app.UI(fIdx).roiRows = [app.UI(fIdx).roiRows(1:rowIdx-1, :); ...
                        rowData; app.UI(fIdx).roiRows(rowIdx:end, :)];
                end
                app.UI(fIdx).selectedRoiIdx = rowIdx;
                obj.refreshTable(fIdx);
                obj.drawBands(fIdx);
                app.AuxWindowMgr.openRoiFigure(app, fIdx);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:insertRow');
            end
        end

        function rowData = removeRoiRowAt(obj, fIdx, rowIdx)
            app = obj.Adapter.app();
            rowData = {};
            try
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows), return; end
                if isempty(rowIdx) || isnan(rowIdx), return; end
                rowIdx = round(rowIdx);
                if rowIdx < 1 || rowIdx > size(app.UI(fIdx).roiRows, 1), return; end
                rowData = app.UI(fIdx).roiRows(rowIdx, :);
                app.UI(fIdx).roiRows(rowIdx, :) = [];
                app.UI(fIdx).selectedRoiIdx = min(rowIdx, size(app.UI(fIdx).roiRows, 1));
                if isempty(app.UI(fIdx).selectedRoiIdx)
                    app.UI(fIdx).selectedRoiIdx = 0;
                end
                obj.refreshTable(fIdx);
                obj.drawBands(fIdx);
                app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:removeRow');
            end
        end


        function pushRoiRowsCommand(obj, fIdx, rowIdx, rowData, operation, description)
            try
                app = obj.Adapter.app();
                undoSvc = obj.Adapter.undoService();
                if isempty(app) || ~isvalid(app) || isempty(undoSvc)
                    return;
                end
                cmd = flightdash.command.RoiRowsCommand(obj.Adapter.activeSessionId(), obj, ...
                    fIdx, rowIdx, rowData, operation, description);
                undoSvc.push(cmd);
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:undoPush');
            end
        end
    end

    methods (Access = private)
        function tf = pointInAxes(~, ax, point)
            tf = false;
            try
                pos = getpixelposition(ax, true);
                tf = point(1) >= pos(1) && point(1) <= pos(1) + pos(3) && ...
                    point(2) >= pos(2) && point(2) <= pos(2) + pos(4);
            catch
                tf = false;
            end
        end

        function [roiIdx, hitType, xData, distancePx] = hitRoiRows(obj, rows, ax, point)
            roiIdx = 0;
            hitType = '';
            xData = NaN;
            distancePx = inf;
            try
                if isempty(rows)
                    return;
                end
                for r = size(rows, 1):-1:1
                    hitInfo = obj.testSingleRoiRow(rows(r, :), ax, point, r);
                    if hitInfo.Hit
                        roiIdx = r;
                        hitType = hitInfo.HitType;
                        xData = hitInfo.XData;
                        distancePx = hitInfo.Distance;
                        return;
                    end
                end
            catch
                roiIdx = 0;
                hitType = '';
                xData = NaN;
                distancePx = inf;
            end
        end

        function value = numericCell(~, value)
            try
                if iscell(value)
                    value = value{1};
                end
                if isstring(value) || ischar(value)
                    value = str2double(value);
                else
                    value = double(value);
                end
            catch
                value = NaN;
            end
        end

        function selectRoiTarget(obj, fIdx, roiIdx)
            app = obj.Adapter.app();
            app.UI(fIdx).selectedRoiIdx = roiIdx;
            obj.refreshTable(fIdx);
            try
                if isfield(app.UI(fIdx), 'roiTable') && ...
                        ~isempty(app.UI(fIdx).roiTable) && isvalid(app.UI(fIdx).roiTable)
                    app.UI(fIdx).roiTable.Selection = [roiIdx 1];
                end
            catch
            end
        end

        function xData = figurePointToAxesX(~, ax, point)
            xData = NaN;
            try
                pos = getpixelposition(ax, true);
                xl = double(ax.XLim);
                if pos(3) > 0
                    xData = xl(1) + ((double(point(1)) - pos(1)) / pos(3)) * (xl(2) - xl(1));
                end
            catch
                xData = NaN;
            end
        end

        function row = dragRoiRow(obj, row, info, delta)
            try
                x0 = obj.numericCell(row{1});
                x1 = obj.numericCell(row{2});
                if ~isfinite(x0) || ~isfinite(x1)
                    return;
                end
                xl = double(info.Axes.XLim);
                minGap = max(abs(diff(xl)) * 0.001, eps);
                switch char(info.HitType)
                    case 'edge'
                        if isfield(info, 'EdgeSide') && strcmp(info.EdgeSide, 'start')
                            x0 = min(max(xl(1), x0 + delta), x1 - minGap);
                        else
                            x1 = max(min(xl(2), x1 + delta), x0 + minGap);
                        end
                    otherwise
                        width = x1 - x0;
                        new0 = x0 + delta;
                        new1 = x1 + delta;
                        if new0 < xl(1)
                            new0 = xl(1);
                            new1 = new0 + width;
                        end
                        if new1 > xl(2)
                            new1 = xl(2);
                            new0 = new1 - width;
                        end
                        x0 = new0;
                        x1 = new1;
                end
                row{1} = x0;
                row{2} = x1;
            catch
            end
        end

        function side = edgeSideForHit(obj, row, xData)
            side = '';
            try
                x0 = obj.numericCell(row{1});
                x1 = obj.numericCell(row{2});
                if abs(xData - x0) <= abs(xData - x1)
                    side = 'start';
                else
                    side = 'end';
                end
            catch
                side = '';
            end
        end

        function handles = roiGraphicHandles(obj, fIdx, roiIdx)
            handles = {};
            try
                app = obj.Adapter.app();
                if ~isfield(app.UI(fIdx), 'roiGraphics')
                    return;
                end
                graphics = app.UI(fIdx).roiGraphics;
                for k = 1:numel(graphics)
                    h = graphics{k};
                    if isempty(h) || ~isvalid(h) || ~isprop(h, 'UserData')
                        continue;
                    end
                    ud = h.UserData;
                    if isstruct(ud) && isfield(ud, 'ChannelIdx') && isfield(ud, 'RoiIndex') && ...
                            ud.ChannelIdx == fIdx && ud.RoiIndex == roiIdx
                        handles{end+1} = h; %#ok<AGROW>
                    end
                end
            catch
                handles = {};
            end
        end

        function applyHoverAppearance(obj, target)
            try
                if isempty(obj.HoveredHandles)
                    return;
                end
                alpha = obj.HoverFaceAlpha;
                lineWidth = obj.HoverLineWidth;
                if isfield(target, 'HitType') && strcmp(target.HitType, 'edge')
                    alpha = obj.HoverEdgeAlpha;
                    lineWidth = obj.HoverLineWidth + 0.5;
                end
                for k = 1:numel(obj.HoveredHandles)
                    h = obj.HoveredHandles{k};
                    if isempty(h) || ~isvalid(h)
                        continue;
                    end
                    h.FaceAlpha = alpha;
                    h.EdgeColor = obj.HoverColor;
                    h.LineWidth = lineWidth;
                end
            catch ME
                obj.Adapter.logCaught(ME, 'ROI:hoverAppearance');
            end
        end

        function tf = sameHoverTarget(obj, target)
            tf = false;
            try
                if isempty(obj.HoveredTarget) || ~isstruct(obj.HoveredTarget)
                    return;
                end
                tf = isfield(obj.HoveredTarget, 'ChannelIdx') && ...
                    isfield(obj.HoveredTarget, 'RoiIndex') && ...
                    isfield(obj.HoveredTarget, 'HitType') && ...
                    obj.HoveredTarget.ChannelIdx == target.ChannelIdx && ...
                    obj.HoveredTarget.RoiIndex == target.RoiIndex && ...
                    strcmp(char(obj.HoveredTarget.HitType), char(target.HitType));
            catch
                tf = false;
            end
        end
    end
end
