classdef RoiController < handle
    % flightdash.controller.RoiController
    % Owns ROI events, ROI table state updates, and ROI statistics commands.

    properties (Access = private)
        App
        Listeners cell = {}
    end

    methods
        function obj = RoiController(app)
            obj.App = app;
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            % [PHASE 4] Each handler bails when this controller's app
            % is not the active Studio session.
            obj.Listeners{end+1} = EB('RoiAddRequested',            @(~,d) obj.gated(@(d_) obj.addCurrentRoi(d_.ChannelIdx), d));
            obj.Listeners{end+1} = EB('RoiSelectionChanged',        @(~,d) obj.gated(@(d_) obj.onSelectionChanged(d_.ChannelIdx, d_.Payload), d));
            obj.Listeners{end+1} = EB('RoiDeleteSelectedRequested', @(~,d) obj.gated(@(d_) obj.deleteSelectedRoi(d_.ChannelIdx), d));
            obj.Listeners{end+1} = EB('RoiClearRequested',          @(~,d) obj.gated(@(d_) obj.clearRois(d_.ChannelIdx), d));
            obj.Listeners{end+1} = EB('AnalysisComputeRequested',   @(~,d) obj.gated(@(d_) obj.computeAnalysis(d_.ChannelIdx), d));
        end

        function gated(obj, fn, d)
            if ~obj.App.isActiveSession(d), return; end
            fn(d);
        end

        function addCurrentRoi(obj, fIdx)
            app = obj.App;
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
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows)
                    app.UI(fIdx).roiRows = row;
                else
                    app.UI(fIdx).roiRows(end+1, :) = row;
                end
                app.UI(fIdx).selectedRoiIdx = size(app.UI(fIdx).roiRows, 1);
                obj.refreshTable(fIdx);
                obj.drawBands(fIdx);
                app.AuxWindowMgr.openRoiFigure(app, fIdx);
            catch ME
                app.logCaught(ME, 'ROI:add');
            end
        end

        function onSelectionChanged(obj, fIdx, event)
            app = obj.App;
            try
                app.UI(fIdx).selectedRoiIdx = 0;
                if isempty(event) || isempty(event.Indices), return; end
                row = event.Indices(1, 1);
                if row >= 1 && isfield(app.UI(fIdx), 'roiRows') && row <= size(app.UI(fIdx).roiRows, 1)
                    app.UI(fIdx).selectedRoiIdx = row;
                end
            catch ME
                app.logCaught(ME, 'ROI:select');
            end
        end

        function deleteSelectedRoi(obj, fIdx)
            app = obj.App;
            try
                if ~isfield(app.UI(fIdx), 'roiRows') || isempty(app.UI(fIdx).roiRows), return; end
                row = 0;
                if isfield(app.UI(fIdx), 'selectedRoiIdx'), row = app.UI(fIdx).selectedRoiIdx; end
                if isempty(row) || row < 1 || row > size(app.UI(fIdx).roiRows, 1), return; end
                app.UI(fIdx).roiRows(row, :) = [];
                app.UI(fIdx).selectedRoiIdx = min(row, size(app.UI(fIdx).roiRows, 1));
                obj.refreshTable(fIdx);
                obj.drawBands(fIdx);
                app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
            catch ME
                app.logCaught(ME, 'ROI:deleteSelected');
            end
        end

        function clearRois(obj, fIdx)
            app = obj.App;
            try
                obj.deleteGraphics(fIdx);
                app.UI(fIdx).roiRows = cell(0, 5);
                app.UI(fIdx).selectedRoiIdx = 0;
                obj.refreshTable(fIdx);
                app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
            catch ME
                app.logCaught(ME, 'ROI:clear');
            end
        end

        function refreshTable(obj, fIdx)
            app = obj.App;
            try
                if isfield(app.UI(fIdx), 'roiTable') && ~isempty(app.UI(fIdx).roiTable) && isvalid(app.UI(fIdx).roiTable)
                    app.UI(fIdx).roiTable.Data = app.UI(fIdx).roiRows;
                end
                app.AuxWindowMgr.refreshRoiFigure(app, fIdx);
            catch ME
                app.logCaught(ME, 'ROI:refreshTable');
            end
        end

        function computeAnalysis(obj, fIdx)
            app = obj.App;
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
                app.logCaught(ME, 'ROI:analysis');
            end
        end

        function registerSelectedResult(obj, fIdx, rows, times)
            app = obj.App;
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
                    app.ActiveSessionId, fIdx, roiIdx, rows(roiIdx, :), ...
                    times, app.Models(fIdx).rawData, app.VideoSyncState(fIdx), ...
                    flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId);
                analysisResult = flightdash.analysis.AnalysisService.run(request);
                resultModel = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);
                app.registerReviewResult(resultModel);
            catch ME
                app.logCaught(ME, 'ROI:registerResult');
            end
        end

        function targetCol = matchTargetColumn(obj, fIdx, signalName)
            app = obj.App;
            vars = app.Models(fIdx).rawData.Properties.VariableNames;
            targetCol = flightdash.model.RoiAnalyzer.matchTargetColumn(vars, signalName);
        end

        function drawBands(obj, fIdx)
            app = obj.App;
            try
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
                        app.excludeFromLegend(h);
                        try, uistack(h, 'bottom'); catch, end
                        roiHandles{end+1} = h; %#ok<AGROW>
                    end
                end
                app.UI(fIdx).roiGraphics = roiHandles;
            catch ME
                app.logCaught(ME, 'ROI:draw');
            end
        end

        function deleteGraphics(obj, fIdx)
            app = obj.App;
            try
                if isfield(app.UI(fIdx), 'roiGraphics')
                    app.deleteGraphicsHandles(app.UI(fIdx).roiGraphics);
                end
                app.UI(fIdx).roiGraphics = {};
            catch ME
                app.logCaught(ME, 'ROI:deleteGraphics');
            end
        end

        function delete(obj)
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
