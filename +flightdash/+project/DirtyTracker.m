classdef DirtyTracker
    % flightdash.project.DirtyTracker
    % Phase 8b dependency graph for ReviewResultModel metadata.
    %
    % Scope:
    %   - build reverse dependencies from ReviewResultModel.DependsOn
    %   - propagate source/result changes to downstream results
    %   - return result ids in topological recalculation order
    %
    % It intentionally does not run computations or manage background work.

    methods (Static)
        function [project, dirtyResultIds, dirtyNodeIds] = markDirty(project, changedNodeIds)
            mustBeA(project, 'flightdash.project.ProjectModel');
            changedNodeIds = flightdash.project.DirtyTracker.toCell(changedNodeIds);
            dirtyResultIds = {};
            dirtyNodeIds = {};
            if isempty(changedNodeIds) || isempty(project.Results)
                return;
            end

            graph = flightdash.project.DirtyTracker.buildGraph(project);
            affected = flightdash.project.DirtyTracker.collectDownstream(graph, changedNodeIds);
            dirtyNodeIds = flightdash.project.DirtyTracker.topologicalNodeOrder(project, affected);

            for k = 1:numel(dirtyNodeIds)
                nodeId = dirtyNodeIds{k};
                idx = graph.NodeToIndex(nodeId);
                result = project.Results(idx).markDirty();
                project.Results(idx) = result;
                dirtyResultIds{end+1} = char(result.ResultId); %#ok<AGROW>
            end

            if ~isempty(dirtyResultIds)
                project = project.touch();
            end
        end

        function [resultIds, nodeIds] = topologicalOrder(project, targets)
            mustBeA(project, 'flightdash.project.ProjectModel');
            if nargin < 2 || isempty(targets)
                nodeIds = flightdash.project.DirtyTracker.allResultNodeIds(project);
            else
                nodeIds = flightdash.project.DirtyTracker.resolveTargetNodes(project, targets);
            end
            nodeIds = flightdash.project.DirtyTracker.includeUpstreamResultDependencies(project, nodeIds);
            nodeIds = flightdash.project.DirtyTracker.topologicalNodeOrder(project, nodeIds);
            resultIds = flightdash.project.DirtyTracker.resultIdsFromNodeIds(project, nodeIds);
        end

        function validateAcyclic(project)
            flightdash.project.DirtyTracker.topologicalOrder(project);
        end

        function nid = resultNodeId(result)
            mustBeA(result, 'flightdash.project.ReviewResultModel');
            nid = result.nodeId();
        end

        function sourceId = roiSourceNodeId(sessionId, channelIdx, roiIndex)
            sourceId = sprintf('session:%s:channel:%d:roi:%d', ...
                char(sessionId), double(channelIdx), double(roiIndex));
        end
    end

    methods (Static, Access = private)
        function graph = buildGraph(project)
            graph = struct();
            graph.NodeIds = flightdash.project.DirtyTracker.allResultNodeIds(project);
            graph.NodeToIndex = containers.Map('KeyType', 'char', 'ValueType', 'double');
            graph.ResultIdToNode = containers.Map('KeyType', 'char', 'ValueType', 'char');
            graph.Dependents = containers.Map('KeyType', 'char', 'ValueType', 'any');

            for k = 1:numel(project.Results)
                result = project.Results(k);
                nodeId = flightdash.project.DirtyTracker.resultNodeId(result);
                graph.NodeToIndex(nodeId) = k;
                graph.ResultIdToNode(char(result.ResultId)) = nodeId;
            end

            for k = 1:numel(project.Results)
                result = project.Results(k);
                nodeId = flightdash.project.DirtyTracker.resultNodeId(result);
                deps = flightdash.project.DirtyTracker.toCell(result.DependsOn);
                for d = 1:numel(deps)
                    depId = char(deps{d});
                    if isempty(depId), continue; end
                    if graph.Dependents.isKey(depId)
                        list = graph.Dependents(depId);
                    else
                        list = {};
                    end
                    if ~any(strcmp(list, nodeId))
                        list{end+1} = nodeId; %#ok<AGROW>
                    end
                    graph.Dependents(depId) = list;
                end
            end
        end

        function affected = collectDownstream(graph, changedNodeIds)
            affectedMap = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            queue = flightdash.project.DirtyTracker.toCell(changedNodeIds);
            head = 1;
            while head <= numel(queue)
                nodeId = char(queue{head});
                head = head + 1;
                if isempty(nodeId) || ~graph.Dependents.isKey(nodeId)
                    continue;
                end
                children = graph.Dependents(nodeId);
                for k = 1:numel(children)
                    child = char(children{k});
                    if ~affectedMap.isKey(child)
                        affectedMap(child) = true;
                        queue{end+1} = child; %#ok<AGROW>
                    end
                end
            end
            affected = affectedMap.keys;
        end

        function ordered = topologicalNodeOrder(project, targetNodeIds)
            targetNodeIds = flightdash.project.DirtyTracker.toCell(targetNodeIds);
            graph = flightdash.project.DirtyTracker.buildGraph(project);
            targets = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            for k = 1:numel(targetNodeIds)
                nodeId = char(targetNodeIds{k});
                if graph.NodeToIndex.isKey(nodeId)
                    targets(nodeId) = true;
                end
            end

            ordered = {};
            if targets.Count == 0
                return;
            end

            indegree = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for k = 1:numel(graph.NodeIds)
                nodeId = graph.NodeIds{k};
                if targets.isKey(nodeId)
                    indegree(nodeId) = 0;
                end
            end

            for k = 1:numel(graph.NodeIds)
                nodeId = graph.NodeIds{k};
                if ~targets.isKey(nodeId), continue; end
                idx = graph.NodeToIndex(nodeId);
                deps = flightdash.project.DirtyTracker.toCell(project.Results(idx).DependsOn);
                for d = 1:numel(deps)
                    depId = char(deps{d});
                    if targets.isKey(depId)
                        indegree(nodeId) = indegree(nodeId) + 1;
                    end
                end
            end

            done = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            while numel(ordered) < targets.Count
                progressed = false;
                for k = 1:numel(graph.NodeIds)
                    nodeId = graph.NodeIds{k};
                    if ~targets.isKey(nodeId) || done.isKey(nodeId)
                        continue;
                    end
                    if indegree(nodeId) ~= 0
                        continue;
                    end

                    ordered{end+1} = nodeId; %#ok<AGROW>
                    done(nodeId) = true;
                    progressed = true;

                    if graph.Dependents.isKey(nodeId)
                        children = graph.Dependents(nodeId);
                        for c = 1:numel(children)
                            child = char(children{c});
                            if targets.isKey(child)
                                indegree(child) = indegree(child) - 1;
                            end
                        end
                    end
                end
                if ~progressed
                    error('DirtyTracker:CycleDetected', ...
                        'Result dependency graph contains a cycle.');
                end
            end
        end

        function nodeIds = resolveTargetNodes(project, targets)
            targets = flightdash.project.DirtyTracker.toCell(targets);
            graph = flightdash.project.DirtyTracker.buildGraph(project);
            nodeIds = {};
            for k = 1:numel(targets)
                target = char(targets{k});
                if graph.NodeToIndex.isKey(target)
                    nodeIds{end+1} = target; %#ok<AGROW>
                elseif graph.ResultIdToNode.isKey(target)
                    nodeIds{end+1} = graph.ResultIdToNode(target); %#ok<AGROW>
                end
            end
            nodeIds = flightdash.project.DirtyTracker.uniqueStable(nodeIds);
        end

        function nodeIds = includeUpstreamResultDependencies(project, nodeIds)
            graph = flightdash.project.DirtyTracker.buildGraph(project);
            nodeIds = flightdash.project.DirtyTracker.uniqueStable(nodeIds);
            seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            for k = 1:numel(nodeIds)
                seen(nodeIds{k}) = true;
            end

            head = 1;
            while head <= numel(nodeIds)
                nodeId = char(nodeIds{head});
                head = head + 1;
                if ~graph.NodeToIndex.isKey(nodeId), continue; end

                result = project.Results(graph.NodeToIndex(nodeId));
                deps = flightdash.project.DirtyTracker.toCell(result.DependsOn);
                for d = 1:numel(deps)
                    depId = char(deps{d});
                    if graph.NodeToIndex.isKey(depId) && ~seen.isKey(depId)
                        nodeIds{end+1} = depId; %#ok<AGROW>
                        seen(depId) = true;
                    end
                end
            end
        end

        function resultIds = resultIdsFromNodeIds(project, nodeIds)
            nodeIds = flightdash.project.DirtyTracker.toCell(nodeIds);
            graph = flightdash.project.DirtyTracker.buildGraph(project);
            resultIds = {};
            for k = 1:numel(nodeIds)
                nodeId = char(nodeIds{k});
                if graph.NodeToIndex.isKey(nodeId)
                    resultIds{end+1} = char(project.Results(graph.NodeToIndex(nodeId)).ResultId); %#ok<AGROW>
                end
            end
        end

        function ids = allResultNodeIds(project)
            ids = cell(1, numel(project.Results));
            for k = 1:numel(project.Results)
                ids{k} = flightdash.project.DirtyTracker.resultNodeId(project.Results(k));
            end
        end

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

        function out = uniqueStable(in)
            out = {};
            for k = 1:numel(in)
                item = char(in{k});
                if isempty(item), continue; end
                if ~any(strcmp(out, item))
                    out{end+1} = item; %#ok<AGROW>
                end
            end
        end
    end
end
