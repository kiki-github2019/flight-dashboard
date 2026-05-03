function cleanupAsyncDecodeCache()
    % 워커 persistent 캐시 정리 - asyncDecodeFramePersistent의 __CLEANUP__ 분기 호출
    % parfevalOnAll(pool, @cleanupAsyncDecodeCache, 0)으로 모든 워커에 전파
    try
        asyncDecodeFramePersistent('__CLEANUP__', 0, 0);
    catch
    end
    pause(0.1);  % VideoReader delete/file-lock release propagation
    try
        clear asyncDecodeFramePersistent
    catch
    end
end
