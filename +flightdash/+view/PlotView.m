classdef PlotView < handle
    % flightdash.view.PlotView
    % Runtime plot/tab rendering facade for one dashboard channel.

    properties (Access = private)
        App
        FIdx double = 1
    end

    methods
        function obj = PlotView(app, fIdx)
            obj.App = app;
            obj.FIdx = fIdx;
        end

        function addTab(obj)
            app = obj.App;
            fIdx = obj.FIdx;
            nTabs = length(app.UI(fIdx).plotTabs);
            if nTabs >= flightdash.util.AppConstants.MAX_TABS
                errordlg(sprintf('Maximum %d plot tabs can be created.', flightdash.util.AppConstants.MAX_TABS), 'Plot Tabs');
                return;
            end

            newTab = uitab(app.UI(fIdx).tabGroup, 'Title', sprintf('Tab %d', nTabs + 1));
            app.UI(fIdx).plotTabs(end + 1) = newTab;

            plotLayout = uigridlayout(newTab, 'ColumnWidth', {'1x'}, 'RowHeight', {}, ...
                                      'Padding', [5 5 5 5], 'RowSpacing', 5, 'Scrollable', 'on');
            app.UI(fIdx).plotLayouts{end + 1} = plotLayout;
            obj.addEmptyState(plotLayout);

            tabIdx = nTabs + 1;
            app.UI(fIdx).plotAxes{tabIdx} = {};
            app.UI(fIdx).timeLines{tabIdx} = {};
            app.UI(fIdx).timeMarkers{tabIdx} = {};
            app.UI(fIdx).plotValueLabels{tabIdx} = {};
            app.UI(fIdx).plotData{tabIdx} = {};
            app.UI(fIdx).plotMeta{tabIdx} = {};
            app.UI(fIdx).xLimListeners{tabIdx} = {};

            app.UI(fIdx).tabGroup.SelectedTab = newTab;
            app.UI(fIdx).selectedPlotIdx = 0;
            obj.refreshCompanions();
        end

        function clearCurrentTab(obj)
            app = obj.App;
            fIdx = obj.FIdx;
            currTab = app.UI(fIdx).tabGroup.SelectedTab;
            if isempty(currTab), return; end
            tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            if isempty(tabIdx), return; end

            app.deleteListeners(app.UI(fIdx).xLimListeners{tabIdx});
            app.deleteGraphicsHandles(app.UI(fIdx).timeLines{tabIdx});
            app.deleteGraphicsHandles(app.UI(fIdx).timeMarkers{tabIdx});
            app.deleteGraphicsHandles(app.UI(fIdx).plotAxes{tabIdx});

            targetLayout = app.UI(fIdx).plotLayouts{tabIdx};
            try
                if ~isempty(targetLayout) && isvalid(targetLayout)
                    delete(targetLayout.Children);
                    targetLayout.RowHeight = {};
                end
            catch ME
                app.logCaught(ME, 'PlotView:clearCurrentTab');
            end

            app.UI(fIdx).plotAxes{tabIdx} = {};
            app.UI(fIdx).timeLines{tabIdx} = {};
            app.UI(fIdx).timeMarkers{tabIdx} = {};
            app.UI(fIdx).plotValueLabels{tabIdx} = {};
            app.UI(fIdx).plotData{tabIdx} = {};
            app.UI(fIdx).plotMeta{tabIdx} = {};
            app.UI(fIdx).xLimListeners{tabIdx} = {};
            app.UI(fIdx).selectedPlotIdx = 0;
            obj.refreshCompanions();
        end

        function clearAllTabs(obj)
            app = obj.App;
            fIdx = obj.FIdx;
            for i = 1:length(app.UI(fIdx).plotTabs)
                if i <= length(app.UI(fIdx).xLimListeners)
                    app.deleteListeners(app.UI(fIdx).xLimListeners{i});
                end
                try
                    if ~isempty(app.UI(fIdx).plotTabs(i)) && isvalid(app.UI(fIdx).plotTabs(i))
                        delete(app.UI(fIdx).plotTabs(i));
                    end
                catch ME
                    app.logCaught(ME, 'PlotView:clearAllTabs');
                end
            end

            app.UI(fIdx).plotTabs = [];
            app.UI(fIdx).plotLayouts = {};
            app.UI(fIdx).plotAxes = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).timeLines = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).timeMarkers = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).plotValueLabels = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).plotData = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).plotMeta = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).xLimListeners = cell(1, flightdash.util.AppConstants.MAX_TABS);
            app.UI(fIdx).selectedPlotIdx = 0;

            obj.addTab();
            if ~isempty(app.RoiCtrl) && isvalid(app.RoiCtrl)
                app.RoiCtrl.drawBands(fIdx);
            end
        end

        function addSelectedVariable(obj)
            app = obj.App;
            fIdx = obj.FIdx;
            selRow = app.Models(fIdx).selectedRow;
            if isempty(selRow) || selRow < 1, return; end
            if isempty(app.Models(fIdx).rawData), return; end

            currTab = app.UI(fIdx).tabGroup.SelectedTab;
            if isempty(currTab)
                obj.addTab();
                currTab = app.UI(fIdx).tabGroup.SelectedTab;
            end

            tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            if isempty(tabIdx)
                errordlg('Current plot tab is not valid. Add a tab first.', 'Plot Error');
                return;
            end

            numPlots = length(app.UI(fIdx).plotAxes{tabIdx});
            if numPlots >= flightdash.util.AppConstants.MAX_PLOTS_PER_TAB
                errordlg(sprintf('Maximum %d plots can be added to one tab.', flightdash.util.AppConstants.MAX_PLOTS_PER_TAB), 'Plot Limit');
                return;
            end

            if selRow > length(app.Models(fIdx).displayMeta)
                errordlg('Selected row is not valid.', 'Selection Error');
                return;
            end

            meta = app.Models(fIdx).displayMeta(selRow);
            yCol = meta.header;
            yLabelStr = sprintf('%s (%s)', meta.header, meta.unit);
            timeCol = app.Models(fIdx).mappedCols.Time;

            if ~ismember(yCol, app.Models(fIdx).rawData.Properties.VariableNames)
                errordlg(sprintf('Column "%s" was not found.', yCol), 'Data Error');
                return;
            end

            tData = app.Models(fIdx).rawData.(timeCol);
            yData = app.Models(fIdx).rawData.(yCol);
            targetLayout = app.UI(fIdx).plotLayouts{tabIdx};
            if isempty(app.UI(fIdx).plotAxes{tabIdx})
                try
                    delete(targetLayout.Children);
                    targetLayout.RowHeight = {};
                catch
                end
            end
            targetLayout.RowHeight{end + 1} = flightdash.util.AppConstants.PLOT_ROW_HEIGHT;
            newRowIdx = numel(targetLayout.RowHeight);
            app.updatePlotRowHeights(fIdx);

            p = uipanel(targetLayout, 'BorderType', 'line', 'BackgroundColor', 'w');
            p.Layout.Row = newRowIdx;
            p.Layout.Column = 1;

            axGrid = uigridlayout(p, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'}, 'Padding', [5 5 5 5]);
            ax = uiaxes(axGrid);
            ax.Layout.Row = 1;
            ax.Layout.Column = 1;
            ax.Interactions = [panInteraction, zoomInteraction];
            tb = axtoolbar(ax, {'restoreview', 'zoomin', 'zoomout', 'pan'});
            tb.Visible = 'on';

            grid(ax, 'on');
            set(ax, 'XMinorGrid', 'on', 'YMinorGrid', 'on');
            mainLine = plot(ax, tData, yData, 'LineWidth', 1.5, ...
                'Color', [0.15 0.38 0.82], 'DisplayName', meta.header, 'HitTest', 'off');
            title(ax, meta.header, 'Interpreter', 'none', 'FontWeight', 'bold');
            xlabel(ax, 'Time(s)', 'FontWeight', 'bold', 'FontSize', 9);
            ylabel(ax, yLabelStr, 'FontWeight', 'bold', 'FontSize', 10, 'Interpreter', 'none');

            hold(ax, 'on');
            currIdx = app.Models(fIdx).currentIndex;
            currTime = tData(currIdx);
            currY = yData(currIdx);
            tl = xline(ax, currTime, 'r', 'LineWidth', 3.0, 'Alpha', 0.5, 'HitTest', 'on');
            mk = plot(ax, currTime, currY, 'p', 'MarkerFaceColor', [0.98 0.75 0.14], ...
                      'MarkerEdgeColor', [0.71 0.33 0.04], 'MarkerSize', 14, 'HitTest', 'on');
            valueLabel = text(ax, currTime, currY, app.plotValueLabelText(meta.header, currY, meta.format), ...
                'Interpreter', 'none', 'FontSize', 10, 'FontWeight', 'bold', ...
                'Color', [0.12 0.12 0.12], 'BackgroundColor', [1 1 1], ...
                'Margin', 3, 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
                'HitTest', 'off');
            app.excludeFromLegend(tl);
            app.excludeFromLegend(mk);
            app.excludeFromLegend(valueLabel);

            tl.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, tabIdx, src, event);
            mk.ButtonDownFcn = @(src, event) app.MarkerDragCtrl.startPlotMarkerDrag(fIdx, tabIdx, src, event);

            app.UI(fIdx).plotAxes{tabIdx}{end + 1} = ax;
            app.UI(fIdx).timeLines{tabIdx}{end + 1} = tl;
            app.UI(fIdx).timeMarkers{tabIdx}{end + 1} = mk;
            app.UI(fIdx).plotValueLabels{tabIdx}{end + 1} = valueLabel;
            app.UI(fIdx).plotData{tabIdx}{end + 1} = yData;
            plotInfo = struct('Name', meta.header, 'YColumn', yCol, 'YLabel', yLabelStr, ...
                'Unit', meta.unit, 'Format', meta.format, 'MainLine', mainLine, ...
                'Panel', p, 'Visible', true, 'Legend', false, ...
                'XLimMode', 'auto', 'YLimMode', 'auto', 'XLim', ax.XLim, 'YLim', ax.YLim);
            app.UI(fIdx).plotMeta{tabIdx}{end + 1} = plotInfo;

            L = addlistener(ax, 'XLim', 'PostSet', @(~,~) app.handlePlotXLimChange(fIdx, ax));
            app.UI(fIdx).xLimListeners{tabIdx}{end + 1} = L;

            allAxes = [app.UI(fIdx).plotAxes{tabIdx}{:}];
            if numel(allAxes) > 1
                linkaxes(allAxes, 'x');
            end
            app.UI(fIdx).selectedPlotIdx = numel(app.UI(fIdx).plotAxes{tabIdx});
            obj.refreshCompanions();
            app.updateFlightModeBands(fIdx);
            drawnow;
        end

        function addEmptyState(~, plotLayout)
            try
                if isempty(plotLayout) || ~isvalid(plotLayout), return; end
                delete(plotLayout.Children);
                plotLayout.RowHeight = {'1x'};
                lbl = uilabel(plotLayout, ...
                    'Text', '비행 데이터를 불러오거나 +Tab을 눌러 그래프를 추가하세요', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'center', ...
                    'FontAngle', 'italic', ...
                    'FontColor', [0.48 0.52 0.58], ...
                    'WordWrap', 'on');
                lbl.Layout.Row = 1;
                lbl.Layout.Column = 1;
            catch
            end
        end

        function updateTimeIndicators(obj, currIdx, currTime)
            app = obj.App;
            fIdx = obj.FIdx;
            currTab = app.UI(fIdx).tabGroup.SelectedTab;
            if isempty(currTab), return; end

            tabIdx = find(app.UI(fIdx).plotTabs == currTab, 1);
            if isempty(tabIdx), return; end

            if ~isempty(app.UI(fIdx).plotAxes{tabIdx}) && app.currentTabXAutoEnabled(fIdx, tabIdx)
                firstAx = app.UI(fIdx).plotAxes{tabIdx}{1};
                try
                    if isvalid(firstAx)
                        xlims = firstAx.XLim;
                        xMin = xlims(1);
                        xMax = xlims(2);
                        xWidth = xMax - xMin;
                        newLims = [];
                        if currTime > xMax
                            newMin = xMax;
                            newMax = xMax + xWidth;
                            while currTime > newMax
                                newMin = newMax;
                                newMax = newMax + xWidth;
                            end
                            newLims = [newMin, newMax];
                        elseif currTime < xMin
                            newMax = xMin;
                            newMin = xMin - xWidth;
                            while currTime < newMin
                                newMax = newMin;
                                newMin = newMin - xWidth;
                            end
                            newLims = [newMin, newMax];
                        end
                        if ~isempty(newLims)
                            app.setPlotProgrammaticXLim(fIdx, true);
                            firstAx.XLim = newLims;
                            app.setPlotProgrammaticXLim(fIdx, false);
                        end
                    end
                catch ME
                    app.setPlotProgrammaticXLim(fIdx, false);
                    app.logCaught(ME, 'PlotView:autoPage');
                end
            end

            tlArr = app.UI(fIdx).timeLines{tabIdx};
            mkArr = app.UI(fIdx).timeMarkers{tabIdx};
            labelArr = {};
            if isfield(app.UI(fIdx), 'plotValueLabels') && tabIdx <= numel(app.UI(fIdx).plotValueLabels)
                labelArr = app.UI(fIdx).plotValueLabels{tabIdx};
            end
            dataArr = app.UI(fIdx).plotData{tabIdx};
            metaArr = app.UI(fIdx).plotMeta{tabIdx};

            for i = 1:length(tlArr)
                try
                    if ~isempty(tlArr{i}) && isvalid(tlArr{i})
                        set(tlArr{i}, 'Value', currTime);
                    end
                    if ~isempty(mkArr{i}) && isvalid(mkArr{i})
                        yData = dataArr{i};
                        if currIdx >= 1 && currIdx <= numel(yData)
                            set(mkArr{i}, 'XData', currTime, 'YData', yData(currIdx));
                            if i <= numel(labelArr) && ~isempty(labelArr{i}) && isvalid(labelArr{i})
                                labelText = app.plotValueLabelText(metaArr{i}.YColumn, yData(currIdx), metaArr{i}.Format);
                                set(labelArr{i}, 'Position', [currTime yData(currIdx) 0], 'String', labelText);
                            end
                        end
                    end
                catch ME
                    app.logCaught(ME, 'PlotView:updateIndicators');
                end
            end
            app.updatePannerViewport(fIdx);
            if ~isempty(app.AuxWindowMgr) && isvalid(app.AuxWindowMgr)
                app.AuxWindowMgr.refreshStatsFigure(app, fIdx);
            end
        end
    end

    methods (Access = private)
        function refreshCompanions(obj)
            app = obj.App;
            fIdx = obj.FIdx;
            app.refreshPlotManager(fIdx);
            app.refreshPlotDetails(fIdx);
            if ~isempty(app.PannerView), app.PannerView.refresh(fIdx); end
        end
    end
end
