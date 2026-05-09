classdef AnalysisService
    % flightdash.analysis.AnalysisService
    % Minimal Phase 7 service: ROI request -> analysis result -> project model.

    properties (Constant)
        RoiStatsType = 'RoiStats'
        DefaultRoiStatsThemeId = 'THM_ROI_STATS_DEFAULT'
    end

    methods (Static)
        function theme = defaultRoiStatsTheme()
            theme = flightdash.project.AnalysisThemeModel('ROI Statistics Default', ...
                flightdash.analysis.AnalysisService.RoiStatsType);
            theme.ThemeId = flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId;
            theme.InputDefaults = struct('roiSelection', 'selected', 'variables', {{'SelectedSignal'}});
            theme.Settings = struct('statistics', {{'Mean', 'RMSE_or_STD'}}, 'nanPolicy', 'omitnan');
            theme.OutputOptions = struct('createReviewResult', true, 'updateProjectExplorer', true);
            theme.IsDefault = true;
        end

        function [project, theme] = ensureDefaultThemes(project)
            mustBeA(project, 'flightdash.project.ProjectModel');
            theme = flightdash.analysis.AnalysisService.defaultRoiStatsTheme();
            found = false;
            for k = 1:numel(project.AnalysisThemes)
                t = project.AnalysisThemes(k);
                if strcmp(char(t.AnalysisType), flightdash.analysis.AnalysisService.RoiStatsType) && ...
                        (strcmp(char(t.ThemeId), theme.ThemeId) || t.IsDefault)
                    theme = t;
                    found = true;
                    break;
                end
            end
            if ~found
                project = project.addTheme(theme);
            end
        end

        function request = makeRoiStatisticsRequest(sessionId, channelIdx, roiIndex, roiRow, times, rawData, syncState, themeId)
            if nargin < 7 || isempty(syncState), syncState = struct(); end
            if nargin < 8 || isempty(themeId)
                themeId = flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId;
            end
            request = struct();
            request.AnalysisType = flightdash.analysis.AnalysisService.RoiStatsType;
            request.SessionId = char(sessionId);
            request.ChannelIdx = double(channelIdx);
            request.RoiIndex = double(roiIndex);
            request.RoiRow = roiRow;
            request.Times = times;
            request.RawData = rawData;
            request.SyncState = syncState;
            request.ThemeId = char(themeId);
            request.CreatedAt = flightdash.project.ProjectModel.nowIso();
        end

        function result = run(request)
            type = flightdash.analysis.AnalysisService.fieldChar(request, 'AnalysisType', '');
            switch type
                case flightdash.analysis.AnalysisService.RoiStatsType
                    result = flightdash.analysis.AnalysisService.runRoiStatistics(request);
                otherwise
                    error('AnalysisService:UnsupportedType', 'Unsupported analysis type: %s', type);
            end
        end

        function result = runRoiStatistics(request)
            flightdash.analysis.AnalysisService.validateRoiRequest(request);
            rows = request.RoiRow;
            if isempty(rows)
                rows = cell(0, 5);
            elseif size(rows, 1) ~= 1
                rows = rows(1, :);
            end
            rows = flightdash.analysis.RoiStatisticsAnalyzer.compute(request.Times, request.RawData, rows);

            computed = flightdash.analysis.AnalysisService.computedValuesFromRow(rows(1, :));
            result = struct();
            result.AnalysisType = flightdash.analysis.AnalysisService.RoiStatsType;
            result.Status = 'OK';
            result.Message = 'ROI statistics computed';
            result.SessionId = char(request.SessionId);
            result.ChannelIdx = double(request.ChannelIdx);
            result.RoiIndex = double(request.RoiIndex);
            result.TimeRange = [computed.StartTime, computed.EndTime];
            result.Variables = {computed.SignalName};
            result.Rows = rows;
            result.ComputedValues = computed;
            result.ThemeId = char(request.ThemeId);
            result.SourceDataHash = flightdash.analysis.AnalysisService.sourceHash(request);
            result.SyncStateHash = flightdash.analysis.AnalysisService.structHash(request.SyncState);
            result.InputSnapshot = flightdash.analysis.AnalysisService.inputSnapshot(request);
            result.CalculatedAt = flightdash.project.ProjectModel.nowIso();
        end

        function model = toReviewResultModel(analysisResult)
            sessionId = flightdash.analysis.AnalysisService.fieldChar(analysisResult, 'SessionId', '');
            channelIdx = flightdash.analysis.AnalysisService.fieldNum(analysisResult, 'ChannelIdx', 1);
            model = flightdash.project.ReviewResultModel(sessionId, 'ROI', channelIdx);
            model.TimeRange = flightdash.analysis.AnalysisService.fieldNumPair(analysisResult, 'TimeRange', [NaN NaN]);
            model.Variables = flightdash.analysis.AnalysisService.fieldCell(analysisResult, 'Variables');
            model.AnalysisThemeId = flightdash.analysis.AnalysisService.fieldChar(analysisResult, ...
                'ThemeId', flightdash.analysis.AnalysisService.DefaultRoiStatsThemeId);
            model.SourceDataHash = flightdash.analysis.AnalysisService.fieldChar(analysisResult, 'SourceDataHash', '');
            model.SyncStateHash = flightdash.analysis.AnalysisService.fieldChar(analysisResult, 'SyncStateHash', '');
            if isfield(analysisResult, 'ComputedValues') && isstruct(analysisResult.ComputedValues)
                model = model.setComputedValues(analysisResult.ComputedValues);
            end
            snapshot = struct();
            if isfield(analysisResult, 'InputSnapshot')
                snapshot = analysisResult.InputSnapshot;
            end
            model = model.setComputeFn('RoiAnalyzer', 'computeStats', snapshot);
            model = model.setDependencies({sprintf('session:%s:channel:%d:roi:%d', ...
                sessionId, channelIdx, flightdash.analysis.AnalysisService.fieldNum(analysisResult, 'RoiIndex', 0))});
        end
    end

    methods (Static, Access = private)
        function validateRoiRequest(request)
            required = {'SessionId', 'ChannelIdx', 'RoiIndex', 'RoiRow', 'Times', 'RawData'};
            for k = 1:numel(required)
                if ~isfield(request, required{k})
                    error('AnalysisService:InvalidRequest', 'Missing request field: %s', required{k});
                end
            end
            if ~istable(request.RawData)
                error('AnalysisService:InvalidRequest', 'RawData must be a table.');
            end
            if isempty(request.Times) || numel(request.Times) ~= height(request.RawData)
                error('AnalysisService:InvalidRequest', 'Times must match RawData height.');
            end
            if ~iscell(request.RoiRow) || isempty(request.RoiRow) || size(request.RoiRow, 2) < 3
                error('AnalysisService:InvalidRequest', 'RoiRow must be a cell row with Start, End, and Signal.');
            end
        end

        function computed = computedValuesFromRow(row)
            computed = struct();
            computed.StartTime = flightdash.analysis.AnalysisService.cellNum(row, 1, NaN);
            computed.EndTime = flightdash.analysis.AnalysisService.cellNum(row, 2, NaN);
            computed.SignalName = flightdash.analysis.AnalysisService.cellChar(row, 3, '');
            computed.MeanText = flightdash.analysis.AnalysisService.cellChar(row, 4, '--');
            computed.MetricText = flightdash.analysis.AnalysisService.cellChar(row, 5, '--');
            computed.Mean = flightdash.analysis.AnalysisService.firstNumber(computed.MeanText);
            [computed.MetricName, computed.MetricValue] = ...
                flightdash.analysis.AnalysisService.parseMetric(computed.MetricText);
            computed.RoiRow = row;
        end

        function snapshot = inputSnapshot(request)
            snapshot = struct( ...
                'analysisType', char(request.AnalysisType), ...
                'sessionId', char(request.SessionId), ...
                'channelIdx', double(request.ChannelIdx), ...
                'roiIndex', double(request.RoiIndex), ...
                'roiRow', {request.RoiRow}, ...
                'themeId', char(request.ThemeId));
        end

        function h = sourceHash(request)
            try
                times = request.Times;
                vars = request.RawData.Properties.VariableNames;
                h = sprintf('rows:%d;vars:%d;t0:%.17g;t1:%.17g;roi:%d;%s', ...
                    height(request.RawData), numel(vars), times(1), times(end), ...
                    double(request.RoiIndex), strjoin(vars, ','));
            catch
                h = '';
            end
        end

        function h = structHash(s)
            try
                txt = jsonencode(s);
                h = sprintf('json:%d:%d', strlength(string(txt)), sum(double(char(txt))));
            catch
                h = '';
            end
        end

        function value = cellNum(row, idx, defaultValue)
            value = defaultValue;
            try
                if idx <= numel(row) && ~isempty(row{idx})
                    value = double(row{idx});
                end
            catch
                value = defaultValue;
            end
        end

        function value = cellChar(row, idx, defaultValue)
            value = defaultValue;
            try
                if idx <= numel(row) && ~isempty(row{idx})
                    value = char(row{idx});
                end
            catch
                value = defaultValue;
            end
        end

        function n = firstNumber(text)
            n = NaN;
            try
                token = regexp(char(text), '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match', 'once');
                if ~isempty(token)
                    n = str2double(token);
                end
            catch
                n = NaN;
            end
        end

        function [name, value] = parseMetric(text)
            name = 'Metric';
            value = flightdash.analysis.AnalysisService.firstNumber(text);
            txt = strtrim(char(text));
            if startsWith(txt, 'RMSE', 'IgnoreCase', true)
                name = 'RMSE';
            elseif startsWith(txt, 'STD', 'IgnoreCase', true)
                name = 'STD';
            end
        end

        function value = fieldChar(s, name, defaultValue)
            value = defaultValue;
            try
                if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                    value = char(s.(name));
                end
            catch
                value = defaultValue;
            end
        end

        function value = fieldNum(s, name, defaultValue)
            value = defaultValue;
            try
                if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                    value = double(s.(name));
                end
            catch
                value = defaultValue;
            end
        end

        function value = fieldNumPair(s, name, defaultValue)
            value = defaultValue;
            try
                if isstruct(s) && isfield(s, name) && isnumeric(s.(name)) && numel(s.(name)) >= 2
                    value = double(reshape(s.(name)(1:2), 1, 2));
                end
            catch
                value = defaultValue;
            end
        end

        function value = fieldCell(s, name)
            value = {};
            try
                if ~isstruct(s) || ~isfield(s, name) || isempty(s.(name)), return; end
                raw = s.(name);
                if iscell(raw)
                    value = raw;
                elseif isstring(raw)
                    value = cellstr(raw);
                elseif ischar(raw)
                    value = {raw};
                end
            catch
                value = {};
            end
        end
    end
end
