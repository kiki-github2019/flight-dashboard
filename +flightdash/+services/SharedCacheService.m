classdef SharedCacheService < handle
    % Shared frame cache prototype for Phase 10.

    properties
        BudgetMB double = 128
    end

    properties (Access = private)
        Frames
        LastUse
        Bytes
        BytesUsed double = 0
        UseCounter uint64 = uint64(0)
    end

    methods
        function obj = SharedCacheService(budgetMB)
            if nargin >= 1 && ~isempty(budgetMB) && isfinite(budgetMB) && budgetMB > 0
                obj.BudgetMB = double(budgetMB);
            end
            obj.Frames = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.LastUse = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.Bytes = containers.Map('KeyType', 'char', 'ValueType', 'double');
        end

        function [hit, frame] = get(obj, sessionId, channelIdx, videoPath, frameNo)
            frame = [];
            key = flightdash.services.SharedCacheService.makeKey(sessionId, channelIdx, videoPath, frameNo);
            hit = isKey(obj.Frames, key);
            if ~hit
                return;
            end
            obj.UseCounter = obj.UseCounter + 1;
            obj.LastUse(key) = obj.UseCounter;
            frame = obj.Frames(key);
        end

        function store(obj, sessionId, channelIdx, videoPath, frameNo, frame)
            if isempty(frame)
                return;
            end
            key = flightdash.services.SharedCacheService.makeKey(sessionId, channelIdx, videoPath, frameNo);
            newBytes = flightdash.services.SharedCacheService.frameBytes(frame);
            if isKey(obj.Bytes, key)
                obj.BytesUsed = obj.BytesUsed - obj.Bytes(key);
            end
            obj.UseCounter = obj.UseCounter + 1;
            obj.Frames(key) = frame;
            obj.Bytes(key) = newBytes;
            obj.LastUse(key) = obj.UseCounter;
            obj.BytesUsed = obj.BytesUsed + newBytes;
            obj.evictIfNeeded();
        end

        function tf = has(obj, sessionId, channelIdx, videoPath, frameNo)
            key = flightdash.services.SharedCacheService.makeKey(sessionId, channelIdx, videoPath, frameNo);
            tf = isKey(obj.Frames, key);
        end

        function n = invalidateSession(obj, sessionId)
            prefix = [flightdash.services.SharedCacheService.escapePart(sessionId) '|'];
            n = obj.removeMatching(@(key) startsWith(key, prefix));
        end

        function n = invalidateVideo(obj, videoPath)
            token = ['|' flightdash.services.SharedCacheService.escapePart(videoPath) '|'];
            n = obj.removeMatching(@(key) contains(key, token));
        end

        function clear(obj)
            keys = obj.Frames.keys;
            if ~isempty(keys), remove(obj.Frames, keys); end
            keys = obj.LastUse.keys;
            if ~isempty(keys), remove(obj.LastUse, keys); end
            keys = obj.Bytes.keys;
            if ~isempty(keys), remove(obj.Bytes, keys); end
            obj.BytesUsed = 0;
            obj.UseCounter = uint64(0);
        end

        function s = stats(obj)
            s = struct( ...
                'EntryCount', obj.Frames.Count, ...
                'BytesUsed', obj.BytesUsed, ...
                'BudgetBytes', obj.BudgetMB * 1024 * 1024, ...
                'UseCounter', obj.UseCounter);
        end
    end

    methods (Access = private)
        function evictIfNeeded(obj)
            budgetBytes = obj.BudgetMB * 1024 * 1024;
            while obj.BytesUsed > budgetBytes && obj.Frames.Count > 0
                keys = obj.Frames.keys;
                oldestIdx = 1;
                oldestUse = obj.LastUse(keys{1});
                for k = 2:numel(keys)
                    useValue = obj.LastUse(keys{k});
                    if useValue < oldestUse
                        oldestUse = useValue;
                        oldestIdx = k;
                    end
                end
                obj.removeKey(keys{oldestIdx});
            end
        end

        function n = removeMatching(obj, predicate)
            n = 0;
            keys = obj.Frames.keys;
            for k = 1:numel(keys)
                key = keys{k};
                if predicate(key)
                    obj.removeKey(key);
                    n = n + 1;
                end
            end
        end

        function removeKey(obj, key)
            if isKey(obj.Bytes, key)
                obj.BytesUsed = max(0, obj.BytesUsed - obj.Bytes(key));
                remove(obj.Bytes, key);
            end
            if isKey(obj.Frames, key), remove(obj.Frames, key); end
            if isKey(obj.LastUse, key), remove(obj.LastUse, key); end
        end
    end

    methods (Static)
        function key = makeKey(sessionId, channelIdx, videoPath, frameNo)
            key = sprintf('%s|%d|%s|%d', ...
                flightdash.services.SharedCacheService.escapePart(sessionId), ...
                round(double(channelIdx)), ...
                flightdash.services.SharedCacheService.escapePart(videoPath), ...
                round(double(frameNo)));
        end

        function text = escapePart(value)
            text = char(string(value));
            text = strrep(text, '%', '%25');
            text = strrep(text, '|', '%7C');
        end

        function bytes = frameBytes(frame)
            info = whos('frame');
            bytes = double(info.bytes);
        end
    end
end
