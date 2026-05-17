classdef SharedDecodeService < handle
    % Shared decode scheduler prototype for Phase 10.

    properties
        Cache = []
        ActiveSessionId char = ''
        ExecutionMode char = 'timer-cooperative'
        AsyncInterval double = 0.01
        AsyncBatchSize double = 1
    end

    properties (Access = private)
        Queue
        AsyncTimer = []
        AsyncBusy logical = false
        RequestCounter uint64 = uint64(0)
        SessionGeneration
        CompletedCount double = 0
        DiscardedCount double = 0
        CancelledCount double = 0
        AsyncErrorCount double = 0
        LastError char = ''
    end

    methods
        function obj = SharedDecodeService(cache)
            if nargin < 1 || isempty(cache)
                cache = flightdash.services.SharedCacheService();
            end
            obj.Cache = cache;
            obj.SessionGeneration = containers.Map('KeyType', 'char', 'ValueType', 'double');
            obj.Queue = obj.emptyQueue();
        end

        function delete(obj)
            obj.stopAsync();
        end

        function setActiveSession(obj, sessionId)
            obj.ActiveSessionId = char(sessionId);
        end

        function reply = requestFrame(obj, sessionId, channelIdx, videoPath, frameNo, decoderFcn, completionFcn)
            if nargin < 6 || isempty(decoderFcn)
                decoderFcn = @flightdash.services.SharedDecodeService.defaultDecoder;
            end
            if nargin < 7
                completionFcn = [];
            end

            [hit, frame] = obj.Cache.get(sessionId, channelIdx, videoPath, frameNo);
            if hit
                reply = obj.reply('cache-hit', '', frame);
                obj.invokeCompletion(completionFcn, reply, frame);
                return;
            end

            req = obj.makeRequest(sessionId, channelIdx, videoPath, frameNo, ...
                decoderFcn, completionFcn);

            obj.coalesceStream(req);
            obj.Queue(end+1) = req;
            reply = obj.reply('queued', req.RequestId, []);
        end

        function reply = requestFrameAsync(obj, sessionId, channelIdx, videoPath, frameNo, decoderFcn, completionFcn)
            if nargin < 6 || isempty(decoderFcn)
                decoderFcn = @flightdash.services.SharedDecodeService.defaultDecoder;
            end
            if nargin < 7
                completionFcn = [];
            end
            reply = obj.requestFrame(sessionId, channelIdx, videoPath, frameNo, ...
                decoderFcn, completionFcn);
            if strcmp(reply.Status, 'queued')
                obj.startAsync();
            end
        end

        function [result, frame] = decodeNow(obj, sessionId, channelIdx, videoPath, frameNo, decoderFcn)
            frame = [];
            if nargin < 6 || isempty(decoderFcn)
                decoderFcn = @flightdash.services.SharedDecodeService.defaultDecoder;
            end

            [hit, frame] = obj.Cache.get(sessionId, channelIdx, videoPath, frameNo);
            if hit
                result = obj.reply('cache-hit', '', frame);
                return;
            end

            req = obj.makeRequest(sessionId, channelIdx, videoPath, frameNo, decoderFcn, []);
            [result, frame] = obj.decodeRequest(req);
        end

        function n = queueLength(obj)
            n = numel(obj.Queue);
        end

        function n = cancelSession(obj, sessionId)
            obj.advanceSessionGeneration(sessionId);
            before = numel(obj.Queue);
            obj.Queue = obj.Queue(~strcmp({obj.Queue.SessionId}, char(sessionId)));
            n = before - numel(obj.Queue);
            obj.CancelledCount = obj.CancelledCount + n;
        end

        function setExecutionMode(obj, mode)
            mode = char(mode);
            allowed = {'sync', 'timer', 'timer-cooperative'};
            if ~any(strcmp(mode, allowed))
                error('SharedDecodeService:InvalidExecutionMode', ...
                    'Invalid execution mode: %s', mode);
            end
            obj.ExecutionMode = mode;
        end

        function gen = advanceSessionGeneration(obj, sessionId)
            key = char(sessionId);
            gen = obj.generation(key) + 1;
            obj.SessionGeneration(key) = gen;
        end

        function [result, frame] = runNext(obj)
            frame = [];
            if isempty(obj.Queue)
                result = obj.reply('idle', '', []);
                return;
            end

            idx = obj.nextQueueIndex();
            [result, frame] = obj.runQueueIndex(idx);
        end

        function [result, frame] = runRequest(obj, requestId)
            frame = [];
            if isempty(obj.Queue)
                result = obj.reply('idle', char(requestId), []);
                return;
            end
            idx = find(strcmp({obj.Queue.RequestId}, char(requestId)), 1);
            if isempty(idx)
                result = obj.reply('missing', char(requestId), []);
                return;
            end
            [result, frame] = obj.runQueueIndex(idx);
        end

        function [results, frames] = runAll(obj)
            results = struct('Status', {}, 'RequestId', {}, 'Frame', {});
            frames = {};
            while obj.queueLength() > 0
                [result, frame] = obj.runNext();
                results(end+1) = result; %#ok<AGROW>
                frames{end+1} = frame; %#ok<AGROW>
            end
        end

        function startAsync(obj, interval)
            if nargin >= 2 && ~isempty(interval) && isfinite(interval)
                obj.AsyncInterval = max(0.001, double(interval));
            end
            if obj.queueLength() == 0 || obj.isAsyncRunning()
                return;
            end

            obj.stopAsync();
            try
                obj.AsyncTimer = timer( ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period', max(0.001, obj.AsyncInterval), ...
                    'BusyMode', 'drop', ...
                    'Name', 'FlightDashSharedDecode', ...
                    'TimerFcn', @(~,~) obj.onAsyncTimer(), ...
                    'ErrorFcn', @(~,evt) obj.onAsyncTimerError(evt));
                start(obj.AsyncTimer);
            catch ME
                obj.AsyncErrorCount = obj.AsyncErrorCount + 1;
                obj.LastError = ME.message;
                obj.stopAsync();
            end
        end

        function stopAsync(obj)
            timerHandle = obj.AsyncTimer;
            obj.AsyncTimer = [];
            obj.AsyncBusy = false;
            try
                if ~isempty(timerHandle) && isvalid(timerHandle)
                    stop(timerHandle);
                    delete(timerHandle);
                end
            catch ME
                obj.AsyncErrorCount = obj.AsyncErrorCount + 1;
                obj.LastError = ME.message;
            end
        end

        function tf = isAsyncRunning(obj)
            tf = false;
            try
                tf = ~isempty(obj.AsyncTimer) && isvalid(obj.AsyncTimer) && ...
                    strcmp(obj.AsyncTimer.Running, 'on');
            catch
                tf = false;
            end
        end

        function s = stats(obj)
            cacheStats = obj.Cache.stats();
            s = struct( ...
                'Queued', numel(obj.Queue), ...
                'Completed', obj.CompletedCount, ...
                'Discarded', obj.DiscardedCount, ...
                'Cancelled', obj.CancelledCount, ...
                'AsyncRunning', obj.isAsyncRunning(), ...
                'AsyncErrors', obj.AsyncErrorCount, ...
                'ExecutionMode', obj.ExecutionMode, ...
                'IsPrototype', true, ...
                'ActiveSessionId', obj.ActiveSessionId, ...
                'LastError', obj.LastError, ...
                'Cache', cacheStats);
        end
    end

    methods (Access = private)
        function [result, frame] = runQueueIndex(obj, idx)
            frame = [];
            req = obj.Queue(idx);
            obj.Queue(idx) = [];
            [result, frame] = obj.decodeRequest(req);
            obj.invokeCompletion(req.CompletionFcn, result, frame);
        end

        function [result, frame] = decodeRequest(obj, req)
            frame = [];
            if req.Generation ~= obj.generation(req.SessionId)
                obj.DiscardedCount = obj.DiscardedCount + 1;
                result = obj.reply('stale-discard', req.RequestId, []);
                return;
            end

            try
                decoder = req.DecoderFcn;
                frame = decoder(req);
                obj.Cache.store(req.SessionId, req.ChannelIdx, req.VideoPath, req.FrameNo, frame);
                obj.CompletedCount = obj.CompletedCount + 1;
                result = obj.reply('completed', req.RequestId, frame);
            catch ME
                obj.LastError = ME.message;
                result = obj.reply('error', req.RequestId, []);
            end
        end

        function req = makeRequest(obj, sessionId, channelIdx, videoPath, frameNo, decoderFcn, completionFcn)
            obj.RequestCounter = obj.RequestCounter + 1;
            req = struct( ...
                'RequestId', char(sprintf('D%06d', double(obj.RequestCounter))), ...
                'SessionId', char(sessionId), ...
                'ChannelIdx', double(channelIdx), ...
                'VideoPath', char(videoPath), ...
                'FrameNo', double(frameNo), ...
                'Generation', obj.generation(sessionId), ...
                'Priority', obj.priorityFor(sessionId), ...
                'Sequence', double(obj.RequestCounter), ...
                'DecoderFcn', decoderFcn, ...
                'CompletionFcn', completionFcn);
        end

        function q = emptyQueue(~)
            q = struct( ...
                'RequestId', {}, ...
                'SessionId', {}, ...
                'ChannelIdx', {}, ...
                'VideoPath', {}, ...
                'FrameNo', {}, ...
                'Generation', {}, ...
                'Priority', {}, ...
                'Sequence', {}, ...
                'DecoderFcn', {}, ...
                'CompletionFcn', {});
        end

        function gen = generation(obj, sessionId)
            key = char(sessionId);
            if ~isKey(obj.SessionGeneration, key)
                obj.SessionGeneration(key) = 0;
            end
            gen = obj.SessionGeneration(key);
        end

        function priority = priorityFor(obj, sessionId)
            if ~isempty(obj.ActiveSessionId) && strcmp(char(sessionId), obj.ActiveSessionId)
                priority = 0;
            else
                priority = 10;
            end
        end

        function coalesceStream(obj, req)
            if isempty(obj.Queue), return; end
            keep = true(1, numel(obj.Queue));
            for k = 1:numel(obj.Queue)
                old = obj.Queue(k);
                if strcmp(old.SessionId, req.SessionId) && ...
                        old.ChannelIdx == req.ChannelIdx && ...
                        strcmp(old.VideoPath, req.VideoPath)
                    keep(k) = false;
                end
            end
            obj.Queue = obj.Queue(keep);
        end

        function idx = nextQueueIndex(obj)
            priorities = [obj.Queue.Priority];
            sequences = [obj.Queue.Sequence];
            [~, order] = sortrows([priorities(:), sequences(:)], [1 2]);
            idx = order(1);
        end

        function r = reply(~, status, requestId, frame)
            r = struct('Status', char(status), 'RequestId', char(requestId), 'Frame', frame);
        end

        function onAsyncTimer(obj)
            if obj.AsyncBusy
                return;
            end
            obj.AsyncBusy = true;
            cleanup = onCleanup(@() obj.clearAsyncBusy()); %#ok<NASGU>

            if obj.queueLength() == 0
                obj.stopAsync();
                return;
            end

            batchSize = max(1, round(obj.AsyncBatchSize));
            for k = 1:batchSize
                if obj.queueLength() == 0
                    break;
                end
                obj.runNext();
            end

            if obj.queueLength() == 0
                obj.stopAsync();
            end
        end

        function onAsyncTimerError(obj, evt)
            obj.AsyncErrorCount = obj.AsyncErrorCount + 1;
            try
                obj.LastError = evt.Data.message;
            catch
                obj.LastError = 'Shared decode async timer failed.';
            end
            obj.stopAsync();
        end

        function clearAsyncBusy(obj)
            obj.AsyncBusy = false;
        end

        function invokeCompletion(obj, completionFcn, result, frame)
            if isempty(completionFcn)
                return;
            end
            try
                completionFcn(result, frame);
            catch ME
                obj.AsyncErrorCount = obj.AsyncErrorCount + 1;
                obj.LastError = ME.message;
            end
        end
    end

    methods (Static)
        function frame = defaultDecoder(req)
            %DEFAULTDECODER Backward-compatible mock decoder.
            % This is intentionally not a production VideoReader decoder.
            % Production callers should inject a decoder function handle.
            frame = flightdash.services.SharedDecodeService.mockDecoder(req);
        end

        function frame = mockDecoder(req)
            seed = mod(round(req.FrameNo) + numel(req.SessionId) + req.ChannelIdx, 255);
            frame = repmat(uint8(seed), [4 4 3]);
        end
    end
end
