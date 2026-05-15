classdef SyncQualityDialog < flightdash.analysis.AnalysisDialog
    %SYNCQUALITYDIALOG  Video↔flight-data synchronization quality (Phase 7).
    %
    %   Reports the active session's VideoSyncState and a simple residual
    %   metric: |dataFps - videoFps|/videoFps, anchor offset distance from
    %   half-frame center, total-frames vs data-row consistency.
    %
    %   Saves the result as a ReviewResultModel (ResultType='SyncCheck').

    properties (Access = private)
        ChannelField
        ToleranceField
    end

    methods
        function obj = SyncQualityDialog(app, sessionId, channelIdx)
            obj@flightdash.analysis.AnalysisDialog(app, sessionId, channelIdx);
            obj.AnalysisType = 'SyncCheck';
            obj.DialogTitle  = 'Sync Quality';
        end
    end

    methods (Access = protected)
        function buildBody(obj, parent)
            UIScale = flightdash.util.UIScale;
            grid = uigridlayout(parent, [3 2], ...
                'ColumnWidth', {UIScale.px(160), '1x'}, ...
                'RowHeight', repmat({UIScale.px(28)}, 1, 3), ...
                'RowSpacing', 4, 'Padding', [4 4 4 4]);

            uilabel(grid, 'Text', 'Channel (Flight #)', 'FontWeight', 'bold');
            obj.ChannelField = uispinner(grid, 'Limits', [1 2], ...
                'Step', 1, 'Value', obj.ChannelIdx);

            uilabel(grid, 'Text', 'FPS tolerance (rel.)', 'FontWeight', 'bold');
            obj.ToleranceField = uieditfield(grid, 'numeric', 'Value', 0.02);

            uilabel(grid, 'Text', 'Output', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'IsSynced / FpsResidual / AnchorOffset -> ReviewResult', ...
                'FontColor', [0.35 0.35 0.35]);
        end

        function s = readInputs(obj)
            s = struct();
            s.ChannelIdx = double(obj.ChannelField.Value);
            s.FpsTolerance = max(0, double(obj.ToleranceField.Value));
        end

        function out = compute(obj, settings)
            out = struct('IsSynced', false, 'VideoFps', NaN, 'DataFps', NaN, ...
                'FpsResidual', NaN, 'AnchorFrame', NaN, 'AnchorOffset', NaN, ...
                'TotalFrames', NaN, 'DataRows', NaN, 'Verdict', 'unknown');
            dash = obj.activeDashboard();
            if isempty(dash) || ~isvalid(dash), return; end
            fIdx = max(1, min(2, settings.ChannelIdx));
            if isempty(dash.VideoSyncState) || fIdx > numel(dash.VideoSyncState), return; end
            vs = dash.VideoSyncState(fIdx);
            out.IsSynced     = logical(vs.IsSynced);
            out.VideoFps     = double(vs.VideoFps);
            out.DataFps      = double(vs.DataFps);
            out.AnchorFrame  = double(vs.AnchorFrame);
            out.AnchorOffset = double(vs.AnchorOffset);
            out.TotalFrames  = double(vs.TotalFrames);
            if ~isempty(dash.Models(fIdx).rawData)
                out.DataRows = double(height(dash.Models(fIdx).rawData));
            end
            if out.VideoFps > 0
                out.FpsResidual = abs(out.DataFps - out.VideoFps) / out.VideoFps;
            end
            % Verdict heuristic.
            if ~out.IsSynced
                out.Verdict = 'not-synced';
            elseif isfinite(out.FpsResidual) && out.FpsResidual > settings.FpsTolerance
                out.Verdict = 'fps-mismatch';
            elseif abs(out.AnchorOffset) > 0.5
                out.Verdict = 'anchor-out-of-range';
            else
                out.Verdict = 'ok';
            end
        end
    end

    methods (Access = private)
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
