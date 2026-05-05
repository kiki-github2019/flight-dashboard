classdef FlightModeAnalyzer
    % flightdash.model.FlightModeAnalyzer
    % Pure flight-mode band extraction from loaded flight-log tables.

    methods (Static)
        function bands = computeBands(mappedCols, rawData)
            bands = struct('Start', {}, 'End', {}, 'Mode', {}, 'Color', {});
            if isempty(rawData) || ~isfield(mappedCols, 'Time'), return; end
            timeCol = mappedCols.Time;
            if ~ismember(timeCol, rawData.Properties.VariableNames), return; end
            times = rawData.(timeCol);
            times = times(:);
            if numel(times) < 2, return; end

            alt = flightdash.model.FlightModeAnalyzer.seriesByKey(mappedCols, rawData, 'Alt', zeros(size(times)));
            roll = flightdash.model.FlightModeAnalyzer.seriesByKey(mappedCols, rawData, 'Roll', zeros(size(times)));
            alt = flightdash.model.FlightModeAnalyzer.normalizeSeries(alt, numel(times), 0);
            roll = flightdash.model.FlightModeAnalyzer.normalizeSeries(roll, numel(times), 0);
            if max(abs(roll), [], 'omitnan') < 7
                roll = roll * 180 / pi;
            end
            speed = flightdash.model.FlightModeAnalyzer.seriesByCandidates(rawData, ...
                {'GroundSpeed', 'Ground_Speed', 'Speed', 'Airspeed', 'IndicatedAirSpeed'}, zeros(size(times)));
            speed = flightdash.model.FlightModeAnalyzer.normalizeSeries(speed, numel(times), 0);

            labels = flightdash.model.FlightModeAnalyzer.labelsFromData(rawData, numel(times));
            if isempty(labels)
                dtRaw = diff(times);
                dtMed = median(dtRaw(dtRaw > 0 & isfinite(dtRaw)));
                if isempty(dtMed) || ~isfinite(dtMed), dtMed = 1; end
                dt = [dtRaw; dtMed];
                dt(dt <= 0 | ~isfinite(dt)) = dtMed;
                if isempty(dt) || any(~isfinite(dt)), dt = ones(size(times)); end
                vz = [0; diff(alt) ./ dt(1:end-1)];

                labels = repmat({'Cruise'}, numel(times), 1);
                labels(abs(roll) > 12) = {'Turn'};
                labels(speed < 2) = {'Loiter'};
                labels(vz > 0.35) = {'Climb'};
                labels(vz < -0.35) = {'Descent'};
                labels(times < times(1) + 2) = {'Start'};
            end

            startIdx = 1;
            for k = 2:numel(labels)
                if ~strcmp(labels{k}, labels{startIdx})
                    bands(end+1) = flightdash.model.FlightModeAnalyzer.modeBand(times(startIdx), times(k-1), labels{startIdx}); %#ok<AGROW>
                    startIdx = k;
                end
            end
            bands(end+1) = flightdash.model.FlightModeAnalyzer.modeBand(times(startIdx), times(end), labels{startIdx});
        end

        function labels = labelsFromData(rawData, nRows)
            labels = {};
            try
                vars = rawData.Properties.VariableNames;
                candidates = {'FlightMode', 'Flight_Mode', 'VehicleMode', 'Vehicle_Mode', ...
                    'Mode', 'MainState', 'Main_State', 'NavState', 'Nav_State'};
                modeCol = '';
                for k = 1:numel(candidates)
                    idx = find(strcmpi(vars, candidates{k}), 1);
                    if ~isempty(idx)
                        modeCol = vars{idx};
                        break;
                    end
                end
                if isempty(modeCol)
                    lowerVars = lower(vars);
                    idx = find(contains(lowerVars, 'flightmode') | contains(lowerVars, 'flight_mode') | ...
                        contains(lowerVars, 'navstate') | contains(lowerVars, 'mainstate'), 1);
                    if ~isempty(idx), modeCol = vars{idx}; end
                end
                if isempty(modeCol), return; end

                col = rawData.(modeCol);
                if isnumeric(col) || islogical(col)
                    labels = arrayfun(@(v) flightdash.model.FlightModeAnalyzer.codeLabel(v), col(:), 'UniformOutput', false);
                elseif iscategorical(col)
                    labels = cellstr(col(:));
                elseif isstring(col)
                    labels = cellstr(col(:));
                elseif iscell(col)
                    labels = cellfun(@(v) char(string(v)), col(:), 'UniformOutput', false);
                else
                    labels = cellstr(string(col(:)));
                end
                labels = labels(:);
                labels(cellfun(@isempty, labels)) = {'Unknown'};
                if numel(labels) ~= nRows
                    labels = {};
                end
            catch
                labels = {};
            end
        end

        function label = codeLabel(value)
            if isempty(value) || ~isfinite(value)
                label = 'Unknown';
            else
                label = sprintf('Mode %g', value);
            end
        end

        function band = modeBand(t0, t1, modeName)
            band = struct('Start', t0, 'End', t1, 'Mode', modeName, 'Color', [0.55 0.55 0.55]);
            switch char(modeName)
                case 'Start',   band.Color = [0.25 0.55 0.95];
                case 'Climb',   band.Color = [0.15 0.65 0.35];
                case 'Descent', band.Color = [0.90 0.55 0.15];
                case 'Turn',    band.Color = [0.55 0.25 0.75];
                case 'Loiter',  band.Color = [0.20 0.70 0.85];
                otherwise,      band.Color = [0.40 0.55 0.20];
            end
        end
    end

    methods (Static, Access = private)
        function y = seriesByKey(mappedCols, rawData, keyName, defaultVal)
            y = defaultVal(:);
            try
                if isfield(mappedCols, keyName)
                    colName = mappedCols.(keyName);
                    if ismember(colName, rawData.Properties.VariableNames)
                        y = rawData.(colName);
                        if isnumeric(y) || islogical(y)
                            y = double(y(:));
                        else
                            y = defaultVal(:);
                        end
                    end
                end
            catch
                y = defaultVal(:);
            end
        end

        function y = seriesByCandidates(rawData, candidates, defaultVal)
            y = defaultVal(:);
            try
                vars = rawData.Properties.VariableNames;
                for k = 1:numel(candidates)
                    idx = find(strcmpi(vars, candidates{k}), 1);
                    if ~isempty(idx)
                        y = rawData.(vars{idx});
                        if isnumeric(y) || islogical(y)
                            y = double(y(:));
                        else
                            y = defaultVal(:);
                        end
                        return;
                    end
                end
            catch
                y = defaultVal(:);
            end
        end

        function y = normalizeSeries(y, nRows, fillValue)
            if isempty(y) || ~isnumeric(y)
                y = repmat(fillValue, nRows, 1);
                return;
            end
            y = double(y(:));
            if numel(y) ~= nRows
                y = repmat(fillValue, nRows, 1);
            end
        end
    end
end
