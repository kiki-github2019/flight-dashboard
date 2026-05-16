function cleanupAsyncDecodeCache()
    % 워커 persistent 캐시 정리 - asyncDecodeFramePersistent의 __CLEANUP__ 분기 호출
    % parfevalOnAll(pool, @cleanupAsyncDecodeCache, 0)으로 모든 워커에 전파
    try
        asyncDecodeFramePersistent('__CLEANUP__', 0, 0);
    catch ME
        logCleanupFailure(ME, 'AsyncDecode:cleanupPersistent');
    end
    pause(0.1);  % VideoReader delete/file-lock release propagation
    try
        clear asyncDecodeFramePersistent
    catch ME
        logCleanupFailure(ME, 'AsyncDecode:clearPersistent');
    end
end

function logCleanupFailure(ME, tag)
    try
        flightdash.util.ErrorLog.log(ME, tag, false);
    catch logME
        warning('AsyncDecode:CleanupLogFailed', '%s', logME.message);
    end
end
