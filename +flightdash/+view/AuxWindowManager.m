classdef AuxWindowManager < handle
    % flightdash.view.AuxWindowManager
    % Owns auxiliary figures (plot manager, ROI manager, statistics).

    properties (Access = private)
        AuxFigures = struct()
        Listeners cell = {}
    end

    methods
        function obj = AuxWindowManager(app)
            if nargin > 0 && ~isempty(app)
                EB = @flightdash.util.EventBus.subscribe;
                obj.Listeners{end+1} = EB('DetailsToggleRequested', @(~,d) obj.onDetailsToggle(app, d));
            end
        end

        function onDetailsToggle(obj, app, d)
            try
                obj.toggleDetailsFigure(app, d.ChannelIdx);
            catch ME
                app.logCaught(ME, 'AuxFigure:detailsToggle');
            end
        end

        function toggleDetailsFigure(obj, app, fIdx)
            fig = obj.getExistingAuxFigure('Details', fIdx);
            if isempty(fig)
                obj.openDetailsFigure(app, fIdx);
                return;
            end
            if strcmpi(fig.Visible, 'on')
                fig.Visible = 'off';
            else
                obj.refreshDetailsFigure(app, fIdx);
                fig.Visible = 'on';
            end
        end

        function openDetailsFigure(obj, app, fIdx)
            try
                fig = obj.getAuxFigure(app, 'Details', fIdx, ...
                    sprintf('Details, Plots, and Flight Modes - Flight %d', fIdx), [220 120 430 620]);
                if isempty(fig), return; end
                if isempty(fig.Children)
                    obj.buildDetailsFigure(app, fig, fIdx);
                end
                obj.refreshDetailsFigure(app, fIdx);
                fig.Visible = 'on';
            catch ME
                app.logCaught(ME, 'AuxFigure:details');
            end
        end

        function refreshDetailsFigure(obj, app, fIdx)
            try
                fig = obj.getExistingAuxFigure('Details', fIdx);
                if isempty(fig), return; end
                app.refreshPlotManager(fIdx);
                app.refreshPlotDetails(fIdx);
                app.refreshRoiTable(fIdx);
                app.updateFlightModeBands(fIdx);
            catch ME
                app.logCaught(ME, 'AuxFigure:detailsRefresh');
            end
        end

        function openPlotManagerFigure(obj, app, fIdx)
            try
                fig = obj.getAuxFigure(app, 'Manager', fIdx, sprintf('Plot Manager - Flight %d', fIdx), [100 100 560 360]);
                if isempty(fig), return; end
                if isempty(fig.Children)
                    grid = uigridlayout(fig, [2 1]);
                    grid.RowHeight = {'1x', 34};
                    grid.Padding = [8 8 8 8];
                    tbl = uitable(grid, 'Data', cell(0, 3), ...
                        'ColumnName', {'Show', 'Plot', 'Y'}, ...
                        'ColumnEditable', [true false false], ...
                        'ColumnFormat', {'logical', 'char', 'char'}, ...
                        'RowName', [], 'CellEditCallback', @(~,event) app.onPlotVisibilityChanged(fIdx, event), ...
                        'CellSelectionCallback', @(~,event) app.onPlotManagerSelected(fIdx, event));
                    tbl.Tag = 'PlotManagerFigureTable';
                    btnGrid = uigridlayout(grid, [1 3]);
                    btnGrid.RowHeight = {'1x'};
                    btnGrid.ColumnWidth = {100, 100, '1x'};
                    btnGrid.Padding = [0 0 0 0];
                    uibutton(btnGrid, 'Text', 'Refresh', 'ButtonPushedFcn', @(~,~) obj.refreshPlotManagerFigure(app, fIdx));
                    uibutton(btnGrid, 'Text', 'Details', 'ButtonPushedFcn', @(~,~) app.togglePlotDetails(fIdx));
                    uilabel(btnGrid, 'Text', sprintf('Flight %d current tab plots', fIdx), 'HorizontalAlignment', 'right');
                end
                obj.refreshPlotManagerFigure(app, fIdx);
                fig.Visible = 'on';
            catch ME
                app.logCaught(ME, 'AuxFigure:manager');
            end
        end

        function refreshPlotManagerFigure(obj, app, fIdx)
            try
                fig = obj.getExistingAuxFigure('Manager', fIdx);
                if isempty(fig), return; end
                tbl = findobj(fig, 'Tag', 'PlotManagerFigureTable');
                if isempty(tbl), return; end
                if isfield(app.UI(fIdx), 'plotManagerTable') && ~isempty(app.UI(fIdx).plotManagerTable) && isvalid(app.UI(fIdx).plotManagerTable)
                    tbl.Data = app.UI(fIdx).plotManagerTable.Data;
                end
            catch ME
                app.logCaught(ME, 'AuxFigure:managerRefresh');
            end
        end

        function openRoiFigure(obj, app, fIdx)
            try
                fig = obj.getAuxFigure(app, 'ROI', fIdx, sprintf('ROI Manager - Flight %d', fIdx), [140 140 620 340]);
                if isempty(fig), return; end
                if isempty(fig.Children)
                    grid = uigridlayout(fig, [2 1]);
                    grid.RowHeight = {'1x', 34};
                    grid.Padding = [8 8 8 8];
                    tbl = uitable(grid, 'Data', cell(0, 5), ...
                        'ColumnName', {'Start', 'End', 'Signal', 'Mean', 'RMSE/Std'}, ...
                        'RowName', [], 'CellSelectionCallback', @(~,event) app.onRoiSelectionChanged(fIdx, event));
                    tbl.Tag = 'RoiFigureTable';
                    btnGrid = uigridlayout(grid, [1 5]);
                    btnGrid.RowHeight = {'1x'};
                    btnGrid.ColumnWidth = {84, 120, 84, 92, '1x'};
                    btnGrid.Padding = [0 0 0 0];
                    uibutton(btnGrid, 'Text', '+ ROI', 'ButtonPushedFcn', @(~,~) app.addCurrentRoi(fIdx));
                    uibutton(btnGrid, 'Text', 'Delete Selected', 'ButtonPushedFcn', @(~,~) app.deleteSelectedRoi(fIdx));
                    uibutton(btnGrid, 'Text', 'Clear', 'ButtonPushedFcn', @(~,~) app.clearRois(fIdx));
                    uibutton(btnGrid, 'Text', 'Analyze', 'ButtonPushedFcn', @(~,~) app.computeRoiAnalysis(fIdx));
                    uilabel(btnGrid, 'Text', sprintf('Flight %d ROI ranges', fIdx), 'HorizontalAlignment', 'right');
                end
                obj.refreshRoiFigure(app, fIdx);
                fig.Visible = 'on';
            catch ME
                app.logCaught(ME, 'AuxFigure:roi');
            end
        end

        function refreshRoiFigure(obj, app, fIdx)
            try
                fig = obj.getExistingAuxFigure('ROI', fIdx);
                if isempty(fig), return; end
                tbl = findobj(fig, 'Tag', 'RoiFigureTable');
                if isempty(tbl), return; end
                if isfield(app.UI(fIdx), 'roiRows')
                    tbl.Data = app.UI(fIdx).roiRows;
                else
                    tbl.Data = cell(0, 5);
                end
            catch ME
                app.logCaught(ME, 'AuxFigure:roiRefresh');
            end
        end

        function openStatsFigure(obj, app, fIdx)
            try
                fig = obj.getAuxFigure(app, 'Stats', fIdx, sprintf('Range Statistics - Flight %d', fIdx), [180 180 720 360]);
                if isempty(fig), return; end
                if isempty(fig.Children)
                    grid = uigridlayout(fig, [2 1]);
                    grid.RowHeight = {'1x', 34};
                    grid.Padding = [8 8 8 8];
                    tbl = uitable(grid, 'Data', cell(0, 8), ...
                        'ColumnName', {'Flight', 'Tab', 'Signal', 'From', 'To', 'Mean', 'Std', 'Min/Max'}, ...
                        'RowName', []);
                    tbl.Tag = 'StatsFigureTable';
                    btnGrid = uigridlayout(grid, [1 2]);
                    btnGrid.RowHeight = {'1x'};
                    btnGrid.ColumnWidth = {100, '1x'};
                    btnGrid.Padding = [0 0 0 0];
                    uibutton(btnGrid, 'Text', 'Refresh', 'ButtonPushedFcn', @(~,~) obj.refreshStatsFigure(app, fIdx));
                    uilabel(btnGrid, 'Text', 'Statistics use the current H-panel visible time range.', 'HorizontalAlignment', 'right');
                end
                obj.refreshStatsFigure(app, fIdx);
                fig.Visible = 'on';
            catch ME
                app.logCaught(ME, 'AuxFigure:stats');
            end
        end

        function refreshStatsFigure(obj, app, fIdx)
            try
                fig = obj.getExistingAuxFigure('Stats', fIdx);
                if isempty(fig), return; end
                tbl = findobj(fig, 'Tag', 'StatsFigureTable');
                if isempty(tbl), return; end
                tbl.Data = app.statsRowsForCurrentRange(fIdx);
            catch ME
                app.logCaught(ME, 'AuxFigure:statsRefresh');
            end
        end

        function fig = getAuxFigure(obj, app, kind, fIdx, titleText, pos)
            fig = obj.getExistingAuxFigure(kind, fIdx);
            if ~isempty(fig), return; end
            key = obj.auxFigureKey(kind, fIdx);
            fig = uifigure('Name', titleText, 'Position', pos);
            fig.CloseRequestFcn = @(src,~) obj.hideAuxFigure(src);
            obj.AuxFigures.(key) = fig;
        end

        function fig = getExistingAuxFigure(obj, kind, fIdx)
            fig = [];
            try
                key = obj.auxFigureKey(kind, fIdx);
                if isfield(obj.AuxFigures, key)
                    h = obj.AuxFigures.(key);
                    if ~isempty(h) && isvalid(h)
                        fig = h;
                    end
                end
            catch
                fig = [];
            end
        end

        function closeAllAuxFigures(obj)
            try
                if isempty(obj.AuxFigures) || ~isstruct(obj.AuxFigures), return; end
                fields = fieldnames(obj.AuxFigures);
                for k = 1:numel(fields)
                    try
                        h = obj.AuxFigures.(fields{k});
                        if ~isempty(h) && isvalid(h)
                            delete(h);
                        end
                    catch
                    end
                end
                obj.AuxFigures = struct();
            catch
            end
        end

        function delete(obj)
            obj.closeAllAuxFigures();
            for k = 1:numel(obj.Listeners)
                try
                    if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end
                catch
                end
            end
            obj.Listeners = {};
        end
    end

    methods (Access = private)
        function buildDetailsFigure(~, app, fig, fIdx)
            UIScale = flightdash.util.UIScale;
            grid = uigridlayout(fig, [3 1]);
            grid.RowHeight = {'1x', UIScale.px(292), UIScale.px(126)};
            grid.Padding = [8 8 8 8];
            grid.RowSpacing = 6;

            plotsPanel = uipanel(grid, 'Title', 'Plots', ...
                'BackgroundColor', [0.98 0.98 0.98], 'FontWeight', 'bold');
            plotsGrid = uigridlayout(plotsPanel, [1 1]);
            plotsGrid.Padding = [2 2 2 2];
            app.UI(fIdx).plotManagerTable = uitable(plotsGrid, ...
                'Data', cell(0, 3), ...
                'ColumnName', {'Show', 'Plot', 'Y'}, ...
                'ColumnEditable', [true false false], ...
                'ColumnFormat', {'logical', 'char', 'char'}, ...
                'RowName', [], ...
                'FontSize', 11, ...
                'CellEditCallback', @(~,event) app.onPlotVisibilityChanged(fIdx, event), ...
                'CellSelectionCallback', @(~,event) app.onPlotManagerSelected(fIdx, event));

            detailsPanel = uipanel(grid, 'Title', 'Details / Annotation', ...
                'BackgroundColor', [0.98 0.98 0.98], 'FontWeight', 'bold');
            detailGrid = uigridlayout(detailsPanel, [12 2]);
            detailGrid.RowHeight = {UIScale.px(22), UIScale.px(26), UIScale.px(22), UIScale.px(24), ...
                UIScale.px(24), UIScale.px(26), UIScale.px(24), UIScale.px(26), ...
                UIScale.px(26), UIScale.px(64), UIScale.px(26), '1x'};
            detailGrid.ColumnWidth = {UIScale.px(68), '1x'};
            detailGrid.Padding = [4 4 4 4];
            detailGrid.RowSpacing = 3;

            uilabel(detailGrid, 'Text', 'Plot', 'FontWeight', 'bold');
            app.UI(fIdx).detailName = uieditfield(detailGrid, 'text', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotDetailChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'Name', 'Value', src.Value))));
            app.UI(fIdx).detailName.Layout.Row = 1;
            app.UI(fIdx).detailName.Layout.Column = 2;

            uilabel(detailGrid, 'Text', 'Y Label', 'FontWeight', 'bold');
            app.UI(fIdx).detailYLabel = uieditfield(detailGrid, 'text', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotDetailChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YLabel', 'Value', src.Value))));
            app.UI(fIdx).detailYLabel.Layout.Row = 2;
            app.UI(fIdx).detailYLabel.Layout.Column = 2;

            app.UI(fIdx).detailLegend = uicheckbox(detailGrid, 'Text', 'Legend', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotDetailChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'Legend', 'Value', src.Value))));
            app.UI(fIdx).detailLegend.Layout.Row = 3;
            app.UI(fIdx).detailLegend.Layout.Column = [1 2];

            app.UI(fIdx).detailSignalLabel = uilabel(detailGrid, 'Text', 'No plot selected', ...
                'FontAngle', 'italic', 'FontColor', [0.25 0.25 0.25]);
            app.UI(fIdx).detailSignalLabel.Layout.Row = 4;
            app.UI(fIdx).detailSignalLabel.Layout.Column = [1 2];

            app.UI(fIdx).detailXAuto = uicheckbox(detailGrid, 'Text', 'Auto X', 'Value', true, ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'XAuto', 'Value', src.Value))));
            app.UI(fIdx).detailXAuto.Layout.Row = 5;
            app.UI(fIdx).detailXAuto.Layout.Column = [1 2];

            xLimGrid = uigridlayout(detailGrid, [1 4]);
            xLimGrid.Layout.Row = 6;
            xLimGrid.Layout.Column = [1 2];
            xLimGrid.ColumnWidth = {UIScale.px(28), '1x', UIScale.px(32), '1x'};
            xLimGrid.RowHeight = {'1x'};
            xLimGrid.Padding = [0 0 0 0];
            xLimGrid.ColumnSpacing = 2;
            uilabel(xLimGrid, 'Text', 'Min', 'HorizontalAlignment', 'right');
            app.UI(fIdx).detailXMin = uieditfield(xLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'XMin', 'Value', src.Value))));
            uilabel(xLimGrid, 'Text', 'Max', 'HorizontalAlignment', 'right');
            app.UI(fIdx).detailXMax = uieditfield(xLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'XMax', 'Value', src.Value))));

            app.UI(fIdx).detailYAuto = uicheckbox(detailGrid, 'Text', 'Auto Y', 'Value', true, ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YAuto', 'Value', src.Value))));
            app.UI(fIdx).detailYAuto.Layout.Row = 7;
            app.UI(fIdx).detailYAuto.Layout.Column = [1 2];

            yLimGrid = uigridlayout(detailGrid, [1 4]);
            yLimGrid.Layout.Row = 8;
            yLimGrid.Layout.Column = [1 2];
            yLimGrid.ColumnWidth = {UIScale.px(28), '1x', UIScale.px(32), '1x'};
            yLimGrid.RowHeight = {'1x'};
            yLimGrid.Padding = [0 0 0 0];
            yLimGrid.ColumnSpacing = 2;
            uilabel(yLimGrid, 'Text', 'Min', 'HorizontalAlignment', 'right');
            app.UI(fIdx).detailYMin = uieditfield(yLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YMin', 'Value', src.Value))));
            uilabel(yLimGrid, 'Text', 'Max', 'HorizontalAlignment', 'right');
            app.UI(fIdx).detailYMax = uieditfield(yLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YMax', 'Value', src.Value))));

            app.UI(fIdx).roiTable = uitable(detailGrid, ...
                'Data', cell(0, 5), ...
                'ColumnName', {'Start', 'End', 'Signal', 'Mean', 'RMSE/Std'}, ...
                'RowName', [], ...
                'FontSize', 10, ...
                'CellSelectionCallback', @(~,event) app.onRoiSelectionChanged(fIdx, event));
            app.UI(fIdx).roiTable.Layout.Row = [9 10];
            app.UI(fIdx).roiTable.Layout.Column = [1 2];

            app.UI(fIdx).deleteRoiButton = uibutton(detailGrid, 'Text', 'Delete Selected', ...
                'ButtonPushedFcn', @(~,~) app.deleteSelectedRoi(fIdx));
            app.UI(fIdx).deleteRoiButton.Layout.Row = 11;
            app.UI(fIdx).deleteRoiButton.Layout.Column = 1;

            app.UI(fIdx).clearRoiButton = uibutton(detailGrid, 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(~,~) app.clearRois(fIdx));
            app.UI(fIdx).clearRoiButton.Layout.Row = 11;
            app.UI(fIdx).clearRoiButton.Layout.Column = 2;

            app.UI(fIdx).detailHelp = uilabel(detailGrid, ...
                'Text', 'Click a plot row, edit name/label, add ROI, then Analyze.', ...
                'WordWrap', 'on', 'FontSize', 10, 'FontColor', [0.2 0.2 0.2]);
            app.UI(fIdx).detailHelp.Layout.Row = 12;
            app.UI(fIdx).detailHelp.Layout.Column = [1 2];

            modePanel = uipanel(grid, 'Title', 'Flight Modes', ...
                'BackgroundColor', 'w', 'FontWeight', 'bold');
            modeGrid = uigridlayout(modePanel, [1 1]);
            modeGrid.Padding = [0 0 0 0];
            app.UI(fIdx).flightModeTable = uitable(modeGrid, ...
                'Data', cell(0, 4), ...
                'ColumnName', {'Start', 'End', 'Mode', 'Color'}, ...
                'RowName', [], ...
                'FontSize', 10);
        end

        function key = auxFigureKey(~, kind, fIdx)
            key = sprintf('%s%d', char(kind), fIdx);
        end

        function hideAuxFigure(~, fig)
            try
                fig.Visible = 'off';
            catch
            end
        end
    end
end
