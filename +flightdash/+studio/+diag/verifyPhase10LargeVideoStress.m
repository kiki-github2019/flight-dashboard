function results = verifyPhase10LargeVideoStress(videoPath)
%VERIFYPHASE10LARGEVIDEOSTRESS Optional user-supplied video stress check.

    fprintf('\n=== Phase 10 large video stress diagnostic ===\n\n');
    results = struct('TC', 'P10STRESS-1', 'Result', 'SKIP', ...
        'Message', 'No video path supplied.');

    if nargin < 1 || isempty(videoPath) || ~isfile(videoPath)
        fprintf('[%s] %s - %s\n', results.TC, results.Result, results.Message);
        printResults(results);
        return;
    end

    videoPath = char(videoPath);
    try
        if exist('VideoReader', 'class') ~= 8 && exist('VideoReader', 'file') ~= 2
            results.Message = 'VideoReader is unavailable.';
            fprintf('[%s] %s - %s\n', results.TC, results.Result, results.Message);
            printResults(results);
            return;
        end

        vr = VideoReader(videoPath);
        frameCount = estimateFrameCount(vr);
        sampleCount = min(100, max(1, frameCount));
        sampleFrames = unique(round(linspace(1, frameCount, sampleCount)));

        cache = flightdash.services.SharedCacheService(256);
        svc = flightdash.services.SharedDecodeService(cache);
        decoder = @(req) localReadFrame(videoPath, req.FrameNo);

        t0 = tic;
        decoded = 0;
        for k = 1:numel(sampleFrames)
            frameNo = sampleFrames(k);
            [result, frame] = svc.decodeNow('STRESS', 1, videoPath, frameNo, decoder);
            if ~(strcmp(result.Status, 'completed') || strcmp(result.Status, 'cache-hit')) ...
                    || isempty(frame)
                results.Result = 'FAIL';
                results.Message = sprintf('Frame %d failed with status=%s.', ...
                    frameNo, result.Status);
                fprintf('[%s] %s - %s\n', results.TC, results.Result, results.Message);
                printResults(results);
                return;
            end
            decoded = decoded + 1;
        end

        elapsed = toc(t0);
        stats = svc.stats();
        if elapsed > 30
            results.Result = 'WARN';
            results.Message = sprintf('Decoded %d frame(s) in %.2fs; cache entries=%d.', ...
                decoded, elapsed, stats.Cache.EntryCount);
        else
            results.Result = 'PASS';
            results.Message = sprintf('Decoded %d frame(s) in %.2fs; cache entries=%d.', ...
                decoded, elapsed, stats.Cache.EntryCount);
        end
    catch ME
        results.Result = 'FAIL';
        results.Message = sprintf('%s: %s', ME.identifier, ME.message);
    end

    fprintf('[%s] %s - %s\n', results.TC, results.Result, results.Message);
    printResults(results);
end

function n = estimateFrameCount(vr)
    n = 1;
    try
        n = max(1, floor(double(vr.Duration) * double(vr.FrameRate)));
    catch
        n = 100;
    end
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

function printResults(results)
    tc = string({results.TC})';
    status = string({results.Result})';
    msg = string({results.Message})';
    disp(table(tc, status, msg, 'VariableNames', {'TC', 'Result', 'Message'}));
end
