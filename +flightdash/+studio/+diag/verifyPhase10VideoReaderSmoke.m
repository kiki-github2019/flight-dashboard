function results = verifyPhase10VideoReaderSmoke()
%VERIFYPHASE10VIDEOREADERSMOKE Verify injected VideoReader decode path.

    fprintf('\n=== Phase 10 VideoReader smoke diagnostic ===\n\n');

    tests = {
        'P10VR-1', @checkCreateTinyAvi
        'P10VR-2', @checkDecodeNowVideoReader
        'P10VR-3', @checkCacheHit
        'P10VR-4', @checkAsyncCompletion
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});
    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};
        try
            [status, msg] = fn();
        catch ME
            status = 'FAIL';
            msg = sprintf('%s: %s', ME.identifier, ME.message);
        end
        fprintf('[%s] %s - %s\n', tc, status, msg);
        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);
end

function [status, msg] = checkCreateTinyAvi()
    [ok, why] = videoApisAvailable();
    if ~ok
        status = 'SKIP';
        msg = why;
        return;
    end

    try
        [videoPath, cleanup] = makeTinyAvi(); %#ok<ASGLU>
    catch ME
        status = 'SKIP';
        msg = sprintf('Tiny AVI creation unavailable: %s', ME.message);
        return;
    end
    vr = VideoReader(videoPath);
    ok = hasFrame(vr);
    if ok
        status = 'PASS';
        msg = 'Tiny AVI created and opened with VideoReader.';
    else
        status = 'FAIL';
        msg = 'Tiny AVI opened but has no readable frame.';
    end
end

function [status, msg] = checkDecodeNowVideoReader()
    [ok, why] = videoApisAvailable();
    if ~ok
        status = 'SKIP';
        msg = why;
        return;
    end

    try
        [videoPath, cleanup] = makeTinyAvi(); %#ok<ASGLU>
    catch ME
        status = 'SKIP';
        msg = sprintf('Tiny AVI creation unavailable: %s', ME.message);
        return;
    end
    cache = flightdash.services.SharedCacheService(4);
    svc = flightdash.services.SharedDecodeService(cache);
    decoder = @(req) localReadFrame(videoPath, req.FrameNo);
    [result, frame] = svc.decodeNow('S1', 1, videoPath, 3, decoder);
    hit = cache.has('S1', 1, videoPath, 3);

    if strcmp(result.Status, 'completed') && ~isempty(frame) && hit
        status = 'PASS';
        msg = 'decodeNow decoded a real VideoReader frame and cached it.';
    else
        status = 'FAIL';
        msg = sprintf('decodeNow failed. status=%s cacheHit=%d', result.Status, hit);
    end
end

function [status, msg] = checkCacheHit()
    [ok, why] = videoApisAvailable();
    if ~ok
        status = 'SKIP';
        msg = why;
        return;
    end

    try
        [videoPath, cleanup] = makeTinyAvi(); %#ok<ASGLU>
    catch ME
        status = 'SKIP';
        msg = sprintf('Tiny AVI creation unavailable: %s', ME.message);
        return;
    end
    svc = flightdash.services.SharedDecodeService(flightdash.services.SharedCacheService(4));
    decoder = @(req) localReadFrame(videoPath, req.FrameNo);
    svc.decodeNow('S1', 1, videoPath, 2, decoder);
    [result, frame] = svc.decodeNow('S1', 1, videoPath, 2, decoder);

    if strcmp(result.Status, 'cache-hit') && ~isempty(frame)
        status = 'PASS';
        msg = 'Repeated decodeNow returns cache-hit.';
    else
        status = 'FAIL';
        msg = sprintf('Expected cache-hit, got %s.', result.Status);
    end
end

function [status, msg] = checkAsyncCompletion()
    [ok, why] = videoApisAvailable();
    if ~ok
        status = 'SKIP';
        msg = why;
        return;
    end

    try
        [videoPath, cleanupFile] = makeTinyAvi(); %#ok<ASGLU>
    catch ME
        status = 'SKIP';
        msg = sprintf('Tiny AVI creation unavailable: %s', ME.message);
        return;
    end
    svc = flightdash.services.SharedDecodeService(flightdash.services.SharedCacheService(4));
    cleanupSvc = onCleanup(@() svc.stopAsync()); %#ok<NASGU>
    callbackStatus = '';
    callbackFrame = [];
    decoder = @(req) localReadFrame(videoPath, req.FrameNo);

    try
        reply = svc.requestFrameAsync('S1', 1, videoPath, 4, decoder, @captureResult);
    catch ME
        status = 'SKIP';
        msg = sprintf('Timer-based async unavailable: %s', ME.message);
        return;
    end

    deadline = tic;
    hit = false;
    while toc(deadline) < 2.0
        pause(0.02);
        hit = svc.Cache.has('S1', 1, videoPath, 4);
        if hit
            break;
        end
    end

    if strcmp(reply.Status, 'queued') && hit && strcmp(callbackStatus, 'completed') ...
            && ~isempty(callbackFrame)
        status = 'PASS';
        msg = 'requestFrameAsync completed via timer and callback.';
    else
        stats = svc.stats();
        if stats.AsyncErrors > 0
            status = 'WARN';
            msg = sprintf('Async timer reported %d error(s): %s', ...
                stats.AsyncErrors, stats.LastError);
        else
            status = 'FAIL';
            msg = 'Async request did not complete within timeout.';
        end
    end

    function captureResult(result, frame)
        callbackStatus = result.Status;
        callbackFrame = frame;
    end
end

function [videoPath, cleanup] = makeTinyAvi()
    videoPath = [tempname() '.avi'];
    vw = VideoWriter(videoPath, 'Motion JPEG AVI');
    vw.FrameRate = 5;
    open(vw);
    cleaner = onCleanup(@() closeWriter(vw));
    for k = 1:5
        frame = repmat(uint8(k * 32), [16 16 3]);
        writeVideo(vw, frame);
    end
    close(vw);
    clear cleaner;
    cleanup = onCleanup(@() deleteIfExists(videoPath));
end

function frame = localReadFrame(videoPath, frameNo)
    vr = VideoReader(videoPath);
    idx = max(1, round(double(frameNo)));
    try
        frame = read(vr, idx);
    catch
        fps = max(1, double(vr.FrameRate));
        vr.CurrentTime = min(max(0, (idx - 1) / fps), max(0, vr.Duration - 1 / fps));
        if hasFrame(vr)
            frame = readFrame(vr);
        else
            frame = [];
        end
    end
end

function [ok, msg] = videoApisAvailable()
    hasWriter = exist('VideoWriter', 'class') == 8 || exist('VideoWriter', 'file') == 2;
    hasReader = exist('VideoReader', 'class') == 8 || exist('VideoReader', 'file') == 2;
    ok = hasWriter && hasReader;
    if ok
        msg = '';
    else
        msg = 'VideoWriter or VideoReader is unavailable.';
    end
end

function closeWriter(vw)
    try
        close(vw);
    catch
    end
end

function deleteIfExists(pathValue)
    try
        if isfile(pathValue)
            delete(pathValue);
        end
    catch
    end
end

function printResults(results)
    tc = string({results.TC})';
    status = string({results.Result})';
    msg = string({results.Message})';
    disp(table(tc, status, msg, 'VariableNames', {'TC', 'Result', 'Message'}));
end
