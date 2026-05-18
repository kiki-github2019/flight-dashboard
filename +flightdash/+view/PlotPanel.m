classdef PlotPanel
    % flightdash.view.PlotPanel
    % H data view with plot tabs, manager, details, panner, modes, and ROI.

    methods (Static)
        function ui = build(dataGrid, fIdx)
            MAX_TABS = flightdash.util.AppConstants.MAX_TABS;
            UIScale = flightdash.util.UIScale;
            ui = struct();

            hPnl = uipanel(dataGrid, 'Title', '데이터 보기 (Data View)', ...
                'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', 'w');
            hPnl.Layout.Column = 7;
            ui.plotPanel = hPnl;

            shell = uigridlayout(hPnl, [3 3]);
            shell.RowHeight = {UIScale.px(32), '1x', 0};
            shell.ColumnWidth = {0, '1x', 0};
            shell.Padding = [2 2 2 2];
            shell.RowSpacing = 3;
            shell.ColumnSpacing = 3;
            ui.plotShellGrid = shell;
            ui.PlotManagerVisible = false;
            ui.PlotDetailsVisible = false;
            ui.PannerVisible = false;

            btnGrid = uigridlayout(shell, [1 8]);
            btnGrid.Layout.Row = 1;
            btnGrid.Layout.Column = [1 3];
            btnGrid.ColumnWidth = {UIScale.px(76), UIScale.px(76), UIScale.px(82), UIScale.px(82), UIScale.px(72), UIScale.px(82), UIScale.px(76), '1x'};
            btnGrid.RowHeight = {'1x'};
            btnGrid.Padding = [0 0 0 0];
            btnGrid.ColumnSpacing = 3;

            uibutton(btnGrid, 'Text', '+ Tab', ...
                'Tooltip', 'Add plot tab', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PlotTabAddRequested', flightdash.util.AppEventData(fIdx)));
            uibutton(btnGrid, 'Text', 'Clear', ...
                'Tooltip', 'Clear current tab', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PlotTabClearRequested', flightdash.util.AppEventData(fIdx)));
            uibutton(btnGrid, 'Text', 'Manager', ...
                'Tooltip', 'Show or hide plot manager', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PlotManagerToggled', flightdash.util.AppEventData(fIdx)));
            uibutton(btnGrid, 'Text', 'Details', ...
                'Tooltip', 'Show details, plot list, ROI, and flight modes in a popup', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('DetailsToggleRequested', flightdash.util.AppEventData(fIdx)));
            uibutton(btnGrid, 'Text', '+ ROI', ...
                'Tooltip', 'Add current visible time range as ROI', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('RoiAddRequested', flightdash.util.AppEventData(fIdx)));
            uibutton(btnGrid, 'Text', 'Analyze', ...
                'Tooltip', 'Compute basic ROI statistics', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('AnalysisComputeRequested', flightdash.util.AppEventData(fIdx)));
            uibutton(btnGrid, 'Text', 'Range', ...
                'Tooltip', 'Show or hide time range bar', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PannerToggled', flightdash.util.AppEventData(fIdx)));

            ui.plotManagerPanel = uipanel(shell, 'Title', 'Plots', ...
                'BackgroundColor', [0.98 0.98 0.98], 'FontWeight', 'bold');
            ui.plotManagerPanel.Layout.Row = 2;
            ui.plotManagerPanel.Layout.Column = 1;
            ui.plotManagerPanel.Visible = 'off';
            managerGrid = uigridlayout(ui.plotManagerPanel, [2 1]);
            managerGrid.RowHeight = {'1x', UIScale.px(118)};
            managerGrid.Padding = [2 2 2 2];
            managerGrid.RowSpacing = 3;

            ui.plotManagerTable = uitable(managerGrid, ...
                'Data', cell(0, 3), ...
                'ColumnName', {'Show', 'Plot', 'Y'}, ...
                'ColumnEditable', [true false false], ...
                'ColumnFormat', {'logical', 'char', 'char'}, ...
                'RowName', [], ...
                'FontSize', 11, ...
                'CellEditCallback', @(~,event) flightdash.util.EventBus.publish('PlotVisibilityChanged', flightdash.util.AppEventData(fIdx, event)), ...
                'CellSelectionCallback', @(~,event) flightdash.util.EventBus.publish('PlotManagerSelected', flightdash.util.AppEventData(fIdx, event)));

            modePanel = uipanel(managerGrid, 'Title', 'Flight Modes', ...
                'BackgroundColor', 'w', 'FontWeight', 'bold');
            modeGrid = uigridlayout(modePanel, [1 1]);
            modeGrid.Padding = [0 0 0 0];
            ui.flightModeTable = uitable(modeGrid, ...
                'Data', cell(0, 4), ...
                'ColumnName', {'Start', 'End', 'Mode', 'Color'}, ...
                'RowName', [], ...
                'FontSize', 10);

            ui.tabGroup = uitabgroup(shell);
            ui.tabGroup.Layout.Row = 2;
            ui.tabGroup.Layout.Column = 2;
            ui.tabGroup.SelectionChangedFcn = @(~,~) flightdash.util.EventBus.publish('TabChanged', flightdash.util.AppEventData(fIdx));

            ui.plotDetailsPanel = uipanel(shell, 'Title', 'Details / Annotation', ...
                'BackgroundColor', [0.98 0.98 0.98], 'FontWeight', 'bold');
            ui.plotDetailsPanel.Layout.Row = 2;
            ui.plotDetailsPanel.Layout.Column = 3;
            ui.plotDetailsPanel.Visible = 'off';
            detailGrid = uigridlayout(ui.plotDetailsPanel, [12 2]);
            detailGrid.RowHeight = {UIScale.px(22), UIScale.px(26), UIScale.px(22), UIScale.px(24), ...
                UIScale.px(24), UIScale.px(26), UIScale.px(24), UIScale.px(26), ...
                UIScale.px(26), UIScale.px(64), UIScale.px(26), '1x'};
            detailGrid.ColumnWidth = {UIScale.px(68), '1x'};
            detailGrid.Padding = [4 4 4 4];
            detailGrid.RowSpacing = 3;

            uilabel(detailGrid, 'Text', 'Plot', 'FontWeight', 'bold');
            ui.detailName = uieditfield(detailGrid, 'text', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotDetailChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'Name', 'Value', src.Value))));
            ui.detailName.Layout.Row = 1;
            ui.detailName.Layout.Column = 2;

            uilabel(detailGrid, 'Text', 'Y Label', 'FontWeight', 'bold');
            ui.detailYLabel = uieditfield(detailGrid, 'text', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotDetailChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YLabel', 'Value', src.Value))));
            ui.detailYLabel.Layout.Row = 2;
            ui.detailYLabel.Layout.Column = 2;

            ui.detailLegend = uicheckbox(detailGrid, 'Text', 'Legend', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotDetailChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'Legend', 'Value', src.Value))));
            ui.detailLegend.Layout.Row = 3;
            ui.detailLegend.Layout.Column = [1 2];

            ui.detailSignalLabel = uilabel(detailGrid, 'Text', 'No plot selected', ...
                'FontAngle', 'italic', 'FontColor', [0.25 0.25 0.25]);
            ui.detailSignalLabel.Layout.Row = 4;
            ui.detailSignalLabel.Layout.Column = [1 2];

            ui.detailXAuto = uicheckbox(detailGrid, 'Text', 'Auto X', 'Value', true, ...
                'Tooltip', 'Use automatic visible X range for this plot', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'XAuto', 'Value', src.Value))));
            ui.detailXAuto.Layout.Row = 5;
            ui.detailXAuto.Layout.Column = [1 2];

            xLimGrid = uigridlayout(detailGrid, [1 4]);
            xLimGrid.Layout.Row = 6;
            xLimGrid.Layout.Column = [1 2];
            xLimGrid.ColumnWidth = {UIScale.px(28), '1x', UIScale.px(32), '1x'};
            xLimGrid.RowHeight = {'1x'};
            xLimGrid.Padding = [0 0 0 0];
            xLimGrid.ColumnSpacing = 2;
            uilabel(xLimGrid, 'Text', 'Min', 'HorizontalAlignment', 'right');
            ui.detailXMin = uieditfield(xLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'XMin', 'Value', src.Value))));
            uilabel(xLimGrid, 'Text', 'Max', 'HorizontalAlignment', 'right');
            ui.detailXMax = uieditfield(xLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'XMax', 'Value', src.Value))));

            ui.detailYAuto = uicheckbox(detailGrid, 'Text', 'Auto Y', 'Value', true, ...
                'Tooltip', 'Use automatic Y limits for this plot', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YAuto', 'Value', src.Value))));
            ui.detailYAuto.Layout.Row = 7;
            ui.detailYAuto.Layout.Column = [1 2];

            yLimGrid = uigridlayout(detailGrid, [1 4]);
            yLimGrid.Layout.Row = 8;
            yLimGrid.Layout.Column = [1 2];
            yLimGrid.ColumnWidth = {UIScale.px(28), '1x', UIScale.px(32), '1x'};
            yLimGrid.RowHeight = {'1x'};
            yLimGrid.Padding = [0 0 0 0];
            yLimGrid.ColumnSpacing = 2;
            uilabel(yLimGrid, 'Text', 'Min', 'HorizontalAlignment', 'right');
            ui.detailYMin = uieditfield(yLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YMin', 'Value', src.Value))));
            uilabel(yLimGrid, 'Text', 'Max', 'HorizontalAlignment', 'right');
            ui.detailYMax = uieditfield(yLimGrid, 'numeric', 'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PlotAxisChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'YMax', 'Value', src.Value))));

            ui.roiTable = uitable(detailGrid, ...
                'Data', cell(0, 5), ...
                'ColumnName', {'Start', 'End', 'Signal', 'Mean', 'RMSE/Std'}, ...
                'RowName', [], ...
                'FontSize', 10, ...
                'CellSelectionCallback', @(~,event) flightdash.util.EventBus.publish('RoiSelectionChanged', flightdash.util.AppEventData(fIdx, event)));
            ui.roiTable.Layout.Row = [9 10];
            ui.roiTable.Layout.Column = [1 2];

            ui.deleteRoiButton = uibutton(detailGrid, 'Text', 'Delete Selected', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('RoiDeleteSelectedRequested', flightdash.util.AppEventData(fIdx)));
            ui.deleteRoiButton.Layout.Row = 11;
            ui.deleteRoiButton.Layout.Column = 1;

            ui.clearRoiButton = uibutton(detailGrid, 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('RoiClearRequested', flightdash.util.AppEventData(fIdx)));
            ui.clearRoiButton.Layout.Row = 11;
            ui.clearRoiButton.Layout.Column = 2;

            ui.detailHelp = uilabel(detailGrid, ...
                'Text', 'Click a plot row, edit name/label, add ROI, then Analyze.', ...
                'WordWrap', 'on', 'FontSize', 10, 'FontColor', [0.2 0.2 0.2]);
            ui.detailHelp.Layout.Row = 12;
            ui.detailHelp.Layout.Column = [1 2];

            pannerPanel = uipanel(shell, 'Title', 'Range', ...
                'BackgroundColor', [0.96 0.96 0.96], 'FontWeight', 'bold');
            pannerPanel.Layout.Row = 3;
            pannerPanel.Layout.Column = [1 3];
            pannerPanel.Visible = 'off';
            ui.pannerPanel = pannerPanel;

            pannerGrid = uigridlayout(pannerPanel, [1 6]);
            pannerGrid.RowHeight = {'1x'};
            pannerGrid.ColumnWidth = {'1x', UIScale.px(36), UIScale.px(78), UIScale.px(22), UIScale.px(78), UIScale.px(92)};
            pannerGrid.Padding = [4 2 4 2];
            pannerGrid.RowSpacing = 0;
            pannerGrid.ColumnSpacing = 4;

            ui.pannerAxes = uiaxes(pannerGrid);
            ui.pannerAxes.Layout.Row = 1;
            ui.pannerAxes.Layout.Column = 1;
            ui.pannerAxes.Toolbar.Visible = 'off';
            ui.pannerAxes.Interactions = [];
            ui.pannerAxes.XGrid = 'off';
            ui.pannerAxes.YTick = [];
            ui.pannerAxes.XTick = [];
            ui.pannerAxes.Box = 'on';
            ui.pannerAxes.ButtonDownFcn = @(~,~) flightdash.util.EventBus.publish('PannerClicked', flightdash.util.AppEventData(fIdx));

            ui.modeAxes = gobjects(0);

            uilabel(pannerGrid, 'Text', 'From', 'HorizontalAlignment', 'right');
            ui.pannerFrom = uieditfield(pannerGrid, 'numeric', ...
                'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PannerRangeChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'From', 'Value', src.Value))));
            uilabel(pannerGrid, 'Text', 'To', 'HorizontalAlignment', 'right');
            ui.pannerTo = uieditfield(pannerGrid, 'numeric', ...
                'Limits', [-Inf Inf], ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('PannerRangeChanged', ...
                    flightdash.util.AppEventData(fIdx, struct('Field', 'To', 'Value', src.Value))));
            ui.pannerReset = uibutton(pannerGrid, 'Text', 'Reset Limits', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PannerResetRequested', flightdash.util.AppEventData(fIdx)));

            ui.plotTabs = [];
            ui.plotLayouts = {};
            ui.plotAxes      = cell(1, MAX_TABS);
            ui.timeLines     = cell(1, MAX_TABS);
            ui.timeMarkers   = cell(1, MAX_TABS);
            ui.plotValueLabels = cell(1, MAX_TABS);
            ui.plotData      = cell(1, MAX_TABS);
            ui.plotMeta      = cell(1, MAX_TABS);
            ui.xLimListeners = cell(1, MAX_TABS);
            ui.selectedPlotIdx = 0;
            ui.roiRows = cell(0, 5);
            ui.selectedRoiIdx = 0;
            ui.flightModeBands = struct('Start', {}, 'End', {}, 'Mode', {}, 'Color', {});
        end
    end
end
