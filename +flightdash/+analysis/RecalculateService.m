classdef RecalculateService
    % flightdash.analysis.RecalculateService
    % Phase 8a/8b MVP for Manual/Auto/Frozen recalculation metadata.
    %
    % Phase 8a manages one persisted ReviewResultModel at a time. Phase 8b
    % delegates dependency propagation and topological ordering to
    % flightdash.project.DirtyTracker. Phase 8c adds a conservative debounce
    % queue through flightdash.analysis.RecalculateQueue.

    properties (Constant)
        ValidModes = {'Manual', 'Auto', 'Frozen'}
    end

    methods (Static)
        function mode = normalizeMode(modeName)
            mode = char(modeName);
            matches = strcmpi(mode, flightdash.analysis.RecalculateService.ValidModes);
            if ~any(matches)
                error('RecalculateService:InvalidMode', ...
                    'Recalculate mode must be one of: %s', ...
                    strjoin(flightdash.analysis.RecalculateService.ValidModes, ', '));
            end
            mode = flightdash.analysis.RecalculateService.ValidModes{find(matches, 1)};
        end

        function result = setMode(result, modeName)
            mustBeA(result, 'flightdash.project.ReviewResultModel');
            result = result.setRecalculateMode( ...
                flightdash.analysis.RecalculateService.normalizeMode(modeName));
        end

        function [result, changed] = markIfSourceChanged(result, sourceDataHash, syncStateHash)
            mustBeA(result, 'flightdash.project.ReviewResultModel');
            if nargin < 2, sourceDataHash = ''; end
            if nargin < 3, syncStateHash = ''; end

            changed = false;
            if ~isempty(sourceDataHash) && ~strcmp(char(result.SourceDataHash), char(sourceDataHash))
                changed = true;
            end
            if ~isempty(syncStateHash) && ~strcmp(char(result.SyncStateHash), char(syncStateHash))
                changed = true;
            end

            if changed
                result = result.markDirty();
            end
        end

        function [project, dirtyIds] = markSessionResultsDirty(project, sessionId, sourceDataHash, syncStateHash)
            mustBeA(project, 'flightdash.project.ProjectModel');
            sessionId = char(sessionId);
            dirtyIds = {};
            if isempty(project.Results), return; end

            for k = 1:numel(project.Results)
                result = project.Results(k);
                if ~strcmp(char(result.SessionId), sessionId)
                    continue;
                end
                [updated, changed] = flightdash.analysis.RecalculateService.markIfSourceChanged( ...
                    result, sourceDataHash, syncStateHash);
                if changed
                    project.Results(k) = updated;
                    dirtyIds{end+1} = char(updated.ResultId); %#ok<AGROW>
                end
            end

            if ~isempty(dirtyIds)
                project = project.touch();
            end
        end

        function [project, dirtyResultIds, dirtyNodeIds] = markDependenciesDirty(project, changedNodeIds)
            [project, dirtyResultIds, dirtyNodeIds] = ...
                flightdash.project.DirtyTracker.markDirty(project, changedNodeIds);
        end

        function [resultIds, nodeIds] = recalculationOrder(project, targets)
            if nargin < 2
                [resultIds, nodeIds] = flightdash.project.DirtyTracker.topologicalOrder(project);
            else
                [resultIds, nodeIds] = flightdash.project.DirtyTracker.topologicalOrder(project, targets);
            end
        end

        function queue = createQueue(project, debounceSeconds, autoStart)
            if nargin < 2, debounceSeconds = 0.1; end
            if nargin < 3, autoStart = false; end
            queue = flightdash.analysis.RecalculateQueue(project, debounceSeconds, autoStart);
        end

        function [result, analysisResult] = recalculateRoiResult(result, request, force)
            mustBeA(result, 'flightdash.project.ReviewResultModel');
            if nargin < 3 || isempty(force), force = false; end
            analysisResult = struct();

            if strcmp(result.RecalculateMode, 'Frozen') && ~force
                result = result.markDirty();
                return;
            end
            if ~strcmp(result.ResultType, 'ROI')
                error('RecalculateService:UnsupportedResult', ...
                    'Only ROI ReviewResultModel recalculation is supported in Phase 8a.');
            end

            result = result.markComputing();
            try
                analysisResult = flightdash.analysis.AnalysisService.run(request);
                updated = flightdash.analysis.AnalysisService.toReviewResultModel(analysisResult);

                updated.ResultId = result.ResultId;
                updated.CreatedAt = result.CreatedAt;
                updated.UserComment = result.UserComment;
                updated.LinkedFigureId = result.LinkedFigureId;
                updated.RecalculateMode = result.RecalculateMode;

                result = updated;
                result.LastError = [];
                result.DirtyState = 'clean';
                result.DirtyFlag = false;
                if isempty(result.LastCalculatedAt)
                    result.LastCalculatedAt = flightdash.project.ProjectModel.nowIso();
                end
            catch ME
                result = result.markError(ME);
                rethrow(ME);
            end
        end

        function [project, result, analysisResult] = recalculateProjectResult(project, resultId, request, force)
            mustBeA(project, 'flightdash.project.ProjectModel');
            if nargin < 4 || isempty(force), force = false; end

            idx = flightdash.analysis.RecalculateService.findResultIndex(project, resultId);
            if idx == 0
                error('RecalculateService:UnknownResult', ...
                    'Result id "%s" was not found.', char(resultId));
            end

            [result, analysisResult] = flightdash.analysis.RecalculateService.recalculateRoiResult( ...
                project.Results(idx), request, force);
            project.Results(idx) = result;
            project = project.touch();
        end
    end

    methods (Static, Access = private)
        function idx = findResultIndex(project, resultId)
            idx = 0;
            if isempty(project.Results), return; end
            resultId = char(resultId);
            for k = 1:numel(project.Results)
                if strcmp(char(project.Results(k).ResultId), resultId)
                    idx = k;
                    return;
                end
            end
        end
    end
end
