classdef RoiAnalyzer
    % flightdash.model.RoiAnalyzer
    % Pure ROI statistics calculation: Mean, RMSE (vs. target), or Std.

    methods (Static)
        function rows = computeStats(times, rawData, rows)
            % rows: cell array {Start, End, Signal, Mean, RMSE/Std}
            % rawData: MATLAB table with signal columns
            % times: time series matching rawData rows
            vars = rawData.Properties.VariableNames;
            for r = 1:size(rows, 1)
                signalName = rows{r, 3};
                if ~ismember(signalName, vars)
                    rows{r, 4} = '--';
                    rows{r, 5} = '--';
                    continue;
                end
                idx = times >= rows{r, 1} & times <= rows{r, 2};
                y = rawData.(signalName);
                if ~any(idx)
                    rows{r, 4} = '--';
                    rows{r, 5} = '--';
                    continue;
                end
                rows{r, 4} = sprintf('%.5g', mean(y(idx), 'omitnan'));
                targetCol = flightdash.model.RoiAnalyzer.matchTargetColumn(vars, signalName);
                if ~isempty(targetCol)
                    target = rawData.(targetCol);
                    err = y(idx) - target(idx);
                    rows{r, 5} = sprintf('RMSE %.5g', sqrt(mean(err.^2, 'omitnan')));
                else
                    rows{r, 5} = sprintf('STD %.5g', std(y(idx), 'omitnan'));
                end
            end
        end

        function targetCol = matchTargetColumn(vars, signalName)
            targetCol = '';
            candidates = {[signalName 'Target'], [signalName '_Target']};
            switch char(signalName)
                case {'Roll', 'roll'}
                    candidates{end+1} = 'RollTarget';
                case {'Pitch', 'pitch'}
                    candidates{end+1} = 'PitchTarget';
                case {'Yaw', 'Heading', 'hdg_deg'}
                    candidates{end+1} = 'YawTarget';
            end
            for k = 1:numel(candidates)
                if ismember(candidates{k}, vars)
                    targetCol = candidates{k};
                    return;
                end
            end
        end
    end
end
