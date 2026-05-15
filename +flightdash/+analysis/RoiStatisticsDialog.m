classdef RoiStatisticsDialog < flightdash.analysis.AnalysisDialog
    %ROISTATISTICSDIALOG  ROI statistics dialog (Phase 7).
    %
    %   Interactive front-end that picks a variable + [T0, T1] time range
    %   on the active session's flight data table, then routes the
    %   request through the existing AnalysisService.runRoiStatistics
    %   so the heavy stats calculation stays in one place.
    %
    %   Saves the result as a ReviewResultModel via
    %   AnalysisService.toReviewResultModel + Project.addResult.

    properties (Access = private)
        VariableDropdown
        T0Field
        T1Field
        ChannelField
    end

    methods
        function obj = RoiStatisticsDialog(app, sessionId, channelIdx)
            obj@flightdash.analysis.AnalysisDialog(app, sessionId, channelIdx);
            obj.AnalysisType = flightdash.analysis.AnalysisService.RoiStatsType;
            obj.DialogTitle  = 'ROI Statistics';
        end
    end

    methods (Access = protected)
        function buildBody(obj, parent)
            UIScale = flightdash.util.UIScale;
            grid = uigridlayout(parent, [5 2], ...
                'ColumnWidth', {UIScale.px(120), '1x'}, ...
                'RowHeight', repmat({UIScale.px(28)}, 1, 5), ...
                'RowSpacing', 4, 'Padding', [4 4 4 4]);

            uilabel(grid, 'Text', 'Channel (Flight #)', 'FontWeight', 'bold');
            obj.ChannelField = uispinner(grid, 'Limits', [1 2], ...
                'Step', 1, 'Value', obj.ChannelIdx);

            uilabel(grid, 'Text', 'Variable', 'FontWeight', 'bold');
            vars = obj.availableVariables();
            if isempty(vars), vars = {''}; end
            obj.VariableDropdown = uidropdown(grid, ...
                'Items', vars, 'Value', obj.defaultVariable(vars));

            uilabel(grid, 'Text', 'T0 (s)', 'FontWeight', 'bold');
            obj.T0Field = uieditfield(grid, 'numeric', 'Value', 0);

            uilabel(grid, 'Text', 'T1 (s)', 'FontWeight', 'bold');
            obj.T1Field = uieditfield(grid, 'numeric', 'Value', 0);

            uilabel(grid, 'Text', 'Output', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'Mean / Std / Min / Max / N -> ReviewResult', ...
                'FontColor', [0.35 0.35 0.35]);

            obj.prefillTimeRange();
        end

        function s = readInputs(obj)
            s = struct();
            s.ChannelIdx = double(obj.ChannelField.Value);
            s.Variable   = char(obj.VariableDropdown.Value);
            s.T0         = double(obj.T0Field.Value);
            s.T1         = double(obj.T1Field.Value);
        end

        function out = compute(obj, settings)
            out = struct('Mean', NaN, 'Std', NaN, 'Min', NaN, 'Max', NaN, ...
                'N', 0, 'T0', settings.T0, 'T1', settings.T1, ...
                'Variable', settings.Variable);
            dash = obj.activeDashboard();
            if isempty(dash) || ~isvalid(dash), return; end
            fIdx = max(1, min(2, settings.ChannelIdx));
            if isempty(dash.Models(fIdx).rawData), return; end
            tbl = dash.Models(fIdx).rawData;
            mc  = dash.Models(fIdx).mappedCols;
            if ~isfield(mc, 'Time') || isempty(mc.Time), return; end
            tcol  = mc.Time;
            vname = settings.Variable;
            if ~ismember(tcol, tbl.Properties.VariableNames), return; end
            if ~ismember(vname, tbl.Properties.VariableNames), return; end
            t = tbl.(tcol);
            v = tbl.(vname);
            mask = isfinite(t) & isfinite(v) & t >= settings.T0 & t <= settings.T1;
            if ~any(mask), return; end
            vm = v(mask);
            out.Mean = mean(vm);
            out.Std  = std(vm);
            out.Min  = min(vm);
            out.Max  = max(vm);
            out.N    = sum(mask);
        end
    end

    methods (Access = private)
        function names = availableVariables(obj)
            names = {};
            try
                dash = obj.activeDashboard();
                if isempty(dash) || ~isvalid(dash), return; end
                fIdx = max(1, min(2, obj.ChannelIdx));
                if isempty(dash.Models(fIdx).rawData), return; end
                names = dash.Models(fIdx).rawData.Properties.VariableNames;
            catch
            end
        end

        function v = defaultVariable(obj, names)
            v = '';
            if isempty(names), return; end
            preferred = {'Alt', 'Altitude', 'Roll', 'Pitch'};
            try
                dash = obj.activeDashboard();
                if ~isempty(dash) && isvalid(dash) ...
                        && obj.ChannelIdx <= numel(dash.Models) ...
                        && isstruct(dash.Models(obj.ChannelIdx).mappedCols)
                    mc = dash.Models(obj.ChannelIdx).mappedCols;
                    for k = 1:numel(preferred)
                        if isfield(mc, preferred{k}) && ~isempty(mc.(preferred{k})) ...
                                && ismember(mc.(preferred{k}), names)
                            v = mc.(preferred{k});
                            return;
                        end
                    end
                end
            catch
            end
            if isempty(v), v = names{1}; end
        end

        function prefillTimeRange(obj)
            try
                dash = obj.activeDashboard();
                if isempty(dash) || ~isvalid(dash), return; end
                fIdx = max(1, min(2, obj.ChannelIdx));
                if isempty(dash.Models(fIdx).rawData), return; end
                mc = dash.Models(fIdx).mappedCols;
                if ~isfield(mc, 'Time') || isempty(mc.Time), return; end
                t = dash.Models(fIdx).rawData.(mc.Time);
                t = t(isfinite(t));
                if isempty(t), return; end
                obj.T0Field.Value = double(min(t));
                obj.T1Field.Value = double(max(t));
            catch
            end
        end

        function dash = activeDashboard(obj)
            dash = [];
            try
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                if ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace) ...
                        && ismethod(obj.App.Workspace, 'activeDashboard')
                    dash = obj.App.Workspace.activeDashboard();
                end
            catch
            end
        end
    end
end
