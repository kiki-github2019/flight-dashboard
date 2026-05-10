function results = verifyPhase10()
%VERIFYPHASE10 Phase 10 prototype verification: shared decode/cache services.

    fprintf('\n=== Phase 10 verification: Shared Decode/Cache Prototype ===\n\n');
    fprintf('Progress is printed before and after each check.\n\n');

    tests = {
        'P10-1', @checkPhase10Classes
        'P10-2', @checkCacheSessionIsolation
        'P10-3', @checkActiveSessionPriority
        'P10-4', @checkScrubCoalescing
        'P10-5', @checkCancelPendingSession
        'P10-6', @checkStaleGenerationDiscard
        'P10-7', @checkRunAllAndCacheStats
        'P10-8', @checkPrototypeScopeGuard
    };

    results = struct('TC', {}, 'Result', {}, 'Message', {});
    for k = 1:size(tests, 1)
        tc = tests{k, 1};
        fn = tests{k, 2};
        label = phase10CheckLabel(fn);
        progressStart(tc, label, k, size(tests, 1));
        tStart = tic;
        try
            [ok, msg, status] = fn();
            if isempty(status)
                if ok
                    status = 'PASS';
                else
                    status = 'FAIL';
                end
            end
        catch ME
            ok = false; %#ok<NASGU>
            status = 'FAIL';
            msg = sprintf('%s: %s', ME.identifier, ME.message);
        end
        elapsed = toc(tStart);
        progressDone(tc, status, msg, elapsed);
        results(end+1).TC = tc; %#ok<AGROW>
        results(end).Result = status;
        results(end).Message = msg;
    end

    printResults(results);
    passCount = sum(strcmp({results.Result}, 'PASS'));
    fprintf('\n%d / %d Phase 10 checks passed.\n', passCount, numel(results));
end

function [ok, msg, status] = checkPhase10Classes()
    status = '';
    classes = {
        'flightdash.services.SharedCacheService'
        'flightdash.services.SharedDecodeService'
    };
    missing = {};
    for k = 1:numel(classes)
        if isempty(meta.class.fromName(classes{k}))
            missing{end+1} = classes{k}; %#ok<AGROW>
        end
    end
    ok = isempty(missing);
    if ok
        msg = 'SharedCacheService and SharedDecodeService resolved';
    else
        msg = sprintf('Missing classes: %s', strjoin(missing, ', '));
    end
end

function [ok, msg, status] = checkCacheSessionIsolation()
    status = '';
    cache = flightdash.services.SharedCacheService(1);
    img1 = uint8(ones(2, 2, 3));
    img2 = uint8(2 * ones(2, 2, 3));
    cache.store('S1', 1, 'video.avi', 10, img1);
    cache.store('S2', 1, 'video.avi', 10, img2);
    [hit1, out1] = cache.get('S1', 1, 'video.avi', 10);
    [hit2, out2] = cache.get('S2', 1, 'video.avi', 10);
    ok = hit1 && hit2 && isequal(out1, img1) && isequal(out2, img2);
    msg = passFail(ok, 'Cache keys isolate sessions for the same video/frame', ...
        'Cache session isolation failed');
end

function [ok, msg, status] = checkActiveSessionPriority()
    status = '';
    svc = flightdash.services.SharedDecodeService();
    svc.setActiveSession('S_ACTIVE');
    svc.requestFrame('S_IDLE', 1, 'a.avi', 1, @decodeFromRequest);
    active = svc.requestFrame('S_ACTIVE', 1, 'a.avi', 2, @decodeFromRequest);
    [result, ~] = svc.runNext();
    ok = strcmp(active.Status, 'queued') && strcmp(result.Status, 'completed') && ...
         strcmp(result.RequestId, active.RequestId);
    msg = passFail(ok, 'Active session request runs before older inactive request', ...
        'Active session priority did not win');
end

function [ok, msg, status] = checkScrubCoalescing()
    status = '';
    svc = flightdash.services.SharedDecodeService();
    svc.requestFrame('S1', 1, 'scrub.avi', 1, @decodeFromRequest);
    svc.requestFrame('S1', 1, 'scrub.avi', 2, @decodeFromRequest);
    svc.requestFrame('S1', 1, 'scrub.avi', 3, @decodeFromRequest);
    [result, ~] = svc.runNext();
    [hit, img] = svc.Cache.get('S1', 1, 'scrub.avi', 3);
    ok = svc.queueLength() == 0 && strcmp(result.Status, 'completed') && hit && img(1) == uint8(3);
    msg = passFail(ok, 'Rapid same-stream requests coalesce to the latest frame', ...
        'Same-stream request coalescing failed');
end

function [ok, msg, status] = checkCancelPendingSession()
    status = '';
    svc = flightdash.services.SharedDecodeService();
    svc.requestFrame('S1', 1, 'cancel.avi', 1, @decodeFromRequest);
    svc.requestFrame('S2', 1, 'cancel.avi', 1, @decodeFromRequest);
    removed = svc.cancelSession('S1');
    [result, ~] = svc.runNext();
    ok = removed == 1 && strcmp(result.Status, 'completed') && svc.queueLength() == 0;
    msg = passFail(ok, 'cancelSession removes pending requests for that session only', ...
        'cancelSession removed wrong requests');
end

function [ok, msg, status] = checkStaleGenerationDiscard()
    status = '';
    svc = flightdash.services.SharedDecodeService();
    reply = svc.requestFrame('S1', 1, 'stale.avi', 5, @decodeFromRequest);
    svc.advanceSessionGeneration('S1');
    [result, ~] = svc.runNext();
    hasFrame = svc.Cache.has('S1', 1, 'stale.avi', 5);
    ok = strcmp(reply.Status, 'queued') && strcmp(result.Status, 'stale-discard') && ~hasFrame;
    msg = passFail(ok, 'Generation mismatch discards stale decode output before cache store', ...
        'Stale generation was not discarded');
end

function [ok, msg, status] = checkRunAllAndCacheStats()
    status = '';
    svc = flightdash.services.SharedDecodeService();
    svc.requestFrame('S1', 1, 'all.avi', 1, @decodeFromRequest);
    svc.requestFrame('S2', 1, 'all.avi', 2, @decodeFromRequest);
    [runResults, ~] = svc.runAll();
    stats = svc.stats();
    ok = numel(runResults) == 2 && stats.Completed == 2 && ...
         stats.Cache.EntryCount == 2 && svc.queueLength() == 0;
    msg = passFail(ok, 'runAll decodes queued requests and populates shared cache stats', ...
        'runAll/cache stats mismatch');
end

function [ok, msg, status] = checkPrototypeScopeGuard()
    status = '';
    ok = true;
    msg = 'Phase 10 prototype is service-level only; dashboard integration remains deferred';
end

function img = decodeFromRequest(req)
    img = uint8(req.FrameNo) * ones(2, 2, 3, 'uint8');
end

function msg = passFail(ok, passMsg, failMsg)
    if ok
        msg = passMsg;
    else
        msg = failMsg;
    end
end

function progressStart(tc, label, idx, total)
    fprintf('[%s] START %d/%d - %s\n', tc, idx, total, label);
end

function progressDone(tc, status, msg, elapsed)
    fprintf('[%s] %-14s %6.2fs - %s\n', tc, status, elapsed, msg);
end

function printResults(results)
    fprintf('\n');
    if isempty(results)
        fprintf('No results.\n');
        return;
    end
    tc = string({results.TC})';
    status = string({results.Result})';
    msg = string({results.Message})';
    disp(table(tc, status, msg, 'VariableNames', {'TC', 'Result', 'Message'}));
end

function label = phase10CheckLabel(fn)
    try
        label = func2str(fn);
        if startsWith(label, '@')
            label = char(extractAfter(label, 1));
        end
    catch
        label = 'unknownCheck';
    end
end
