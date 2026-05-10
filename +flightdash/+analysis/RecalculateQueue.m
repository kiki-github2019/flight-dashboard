classdef RecalculateQueue < handle
    % flightdash.analysis.RecalculateQueue
    % Phase 8c MVP debounce queue for Auto recalculation.
    %
    % The queue is deliberately conservative:
    %   - only Auto results are accepted
    %   - repeated enqueue for the same ResultId keeps the latest request
    %   - runDue/runAll process sequentially and isolate per-result errors
    %   - optional timer scheduling is available, but tests can run it
    %     synchronously without parpool/parfeval.

    properties
        Project
        DebounceSeconds double = 0.1
        AutoStart logical = false
        Status char = 'idle'  % idle|scheduled|running|error
        LastError = []
        CompletedIds cell = {}
        FailedIds cell = {}
    end

    properties (Access = private)
        PendingRequests
        PendingSubmittedAt
        PendingOrder cell = {}
        TimerHandle = []
    end

    methods
        function obj = RecalculateQueue(project, debounceSeconds, autoStart)
            if nargin < 1 || isempty(project)
                project = flightdash.project.ProjectModel('Recalculate Queue');
            end
            mustBeA(project, 'flightdash.project.ProjectModel');
            obj.Project = project;

            if nargin >= 2 && ~isempty(debounceSeconds)
                obj.DebounceSeconds = max(0, double(debounceSeconds));
            end
            if nargin >= 3 && ~isempty(autoStart)
                obj.AutoStart = logical(autoStart);
            end

            obj.PendingRequests = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.PendingSubmittedAt = containers.Map('KeyType', 'char', 'ValueType', 'double');
        end

        function delete(obj)
            obj.stopTimer();
        end

        function accepted = enqueue(obj, resultId, request)
            resultId = char(resultId);
            if isempty(resultId)
                error('RecalculateQueue:InvalidResultId', 'ResultId cannot be empty.');
            end

            result = obj.Project.findResult(resultId);
            if isempty(result)
                error('RecalculateQueue:UnknownResult', ...
                    'Result id "%s" was not found.', resultId);
            end

            accepted = strcmp(char(result.RecalculateMode), 'Auto');
            if ~accepted
                return;
            end

            obj.PendingRequests(resultId) = request;
            obj.PendingSubmittedAt(resultId) = now;
            if ~any(strcmp(obj.PendingOrder, resultId))
                obj.PendingOrder{end+1} = resultId;
            end
            obj.Status = 'scheduled';

            if obj.AutoStart
                obj.scheduleTimer();
            end
        end

        function acceptedIds = enqueueMany(obj, resultIds, requestMap)
            resultIds = flightdash.analysis.RecalculateQueue.toCell(resultIds);
            acceptedIds = {};
            for k = 1:numel(resultIds)
                resultId = char(resultIds{k});
                request = obj.requestForId(requestMap, resultId);
                if obj.enqueue(resultId, request)
                    acceptedIds{end+1} = resultId; %#ok<AGROW>
                end
            end
        end

        function cancel(obj, resultId)
            obj.removePending(char(resultId));
            if obj.pendingCount() == 0
                obj.Status = 'idle';
                obj.stopTimer();
            end
        end

        function clear(obj)
            obj.PendingOrder = {};
            obj.PendingRequests = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.PendingSubmittedAt = containers.Map('KeyType', 'char', 'ValueType', 'double');
            obj.Status = 'idle';
            obj.stopTimer();
        end

        function n = pendingCount(obj)
            n = numel(obj.PendingOrder);
        end

        function ids = pendingIds(obj)
            ids = obj.PendingOrder;
        end

        function [project, processedIds, failedIds] = runAll(obj)
            [project, processedIds, failedIds] = obj.runDue(true);
        end

        function [project, processedIds, failedIds] = runDue(obj, force)
            if nargin < 2 || isempty(force), force = false; end
            processedIds = {};
            failedIds = {};

            due = obj.dueIds(force);
            if isempty(due)
                project = obj.Project;
                if obj.pendingCount() > 0
                    obj.Status = 'scheduled';
                else
                    obj.Status = 'idle';
                end
                return;
            end

            obj.Status = 'running';
            for k = 1:numel(due)
                resultId = char(due{k});
                if ~obj.PendingRequests.isKey(resultId)
                    continue;
                end
                request = obj.PendingRequests(resultId);
                obj.removePending(resultId);

                try
                    obj.Project = flightdash.analysis.RecalculateService.recalculateProjectResult( ...
                        obj.Project, resultId, request, false);
                    processedIds{end+1} = resultId; %#ok<AGROW>
                    obj.CompletedIds{end+1} = resultId; %#ok<AGROW>
                catch ME
                    obj.LastError = ME;
                    failedIds{end+1} = resultId; %#ok<AGROW>
                    obj.FailedIds{end+1} = resultId; %#ok<AGROW>
                    obj.markProjectResultError(resultId, ME);
                end
            end

            if ~isempty(failedIds)
                obj.Status = 'error';
            elseif obj.pendingCount() > 0
                obj.Status = 'scheduled';
            else
                obj.Status = 'idle';
            end

            if obj.AutoStart && obj.pendingCount() > 0
                obj.scheduleTimer();
            end
            project = obj.Project;
        end

        function scheduleTimer(obj)
            obj.stopTimer();
            if obj.pendingCount() == 0
                return;
            end
            try
                delay = max(0.001, double(obj.DebounceSeconds));
                obj.TimerHandle = timer( ...
                    'ExecutionMode', 'singleShot', ...
                    'StartDelay', delay, ...
                    'TimerFcn', @(~,~) obj.onTimer(), ...
                    'ErrorFcn', @(~,evt) obj.onTimerError(evt));
                start(obj.TimerHandle);
            catch ME
                obj.LastError = ME;
                obj.Status = 'error';
            end
        end

        function stopTimer(obj)
            try
                if ~isempty(obj.TimerHandle) && isvalid(obj.TimerHandle)
                    stop(obj.TimerHandle);
                    delete(obj.TimerHandle);
                end
            catch
            end
            obj.TimerHandle = [];
        end
    end

    methods (Access = private)
        function ids = dueIds(obj, force)
            ids = {};
            tNow = now;
            for k = 1:numel(obj.PendingOrder)
                resultId = char(obj.PendingOrder{k});
                if ~obj.PendingSubmittedAt.isKey(resultId)
                    continue;
                end
                elapsed = (tNow - obj.PendingSubmittedAt(resultId)) * 86400;
                if force || elapsed >= obj.DebounceSeconds
                    ids{end+1} = resultId; %#ok<AGROW>
                end
            end
        end

        function removePending(obj, resultId)
            if obj.PendingRequests.isKey(resultId)
                remove(obj.PendingRequests, resultId);
            end
            if obj.PendingSubmittedAt.isKey(resultId)
                remove(obj.PendingSubmittedAt, resultId);
            end
            obj.PendingOrder(strcmp(obj.PendingOrder, resultId)) = [];
        end

        function request = requestForId(~, requestMap, resultId)
            request = [];
            if isa(requestMap, 'containers.Map')
                if requestMap.isKey(resultId)
                    request = requestMap(resultId);
                end
            elseif isstruct(requestMap)
                fieldName = matlab.lang.makeValidName(resultId);
                if isfield(requestMap, fieldName)
                    request = requestMap.(fieldName);
                elseif isfield(requestMap, resultId)
                    request = requestMap.(resultId);
                end
            end
        end

        function markProjectResultError(obj, resultId, ME)
            try
                result = obj.Project.findResult(resultId);
                if isempty(result), return; end
                result = result.markError(ME);
                obj.Project = obj.Project.updateResult(result);
            catch
            end
        end

        function onTimer(obj)
            try
                obj.runDue(false);
            catch ME
                obj.LastError = ME;
                obj.Status = 'error';
            end
        end

        function onTimerError(obj, evt)
            try
                obj.LastError = evt.Data;
            catch
                obj.LastError = [];
            end
            obj.Status = 'error';
        end
    end

    methods (Static, Access = private)
        function c = toCell(value)
            if nargin < 1 || isempty(value)
                c = {};
            elseif iscell(value)
                c = value;
            elseif isstring(value)
                c = cellstr(value);
            else
                c = {char(value)};
            end
        end
    end
end
