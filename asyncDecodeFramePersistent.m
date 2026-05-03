function img = asyncDecodeFramePersistent(filePath, frameNo, fps, maxSlots)
    % parfeval worker용 비동기 디코딩 - persistent VideoReader LRU 캐시
    % - 매 호출 VR 재생성(50ms) → persistent 재사용(3ms)
    % - 파일 경로 변경 시에만 VR 재생성
    % - maxSlots: 호출처에서 전달 (기본 4) - 채널별 VR 독립 보유
    % - filePath == '__CLEANUP__' 호출 시 모든 슬롯 VR delete + persistent clear
    persistent cache useCounter   % cache: .path, .vr, .lastUse(counter)
    img = [];
    if nargin < 4 || isempty(maxSlots) || maxSlots < 1
        maxSlots = 4;
    end
    maxSlots = min(maxSlots, 2);  % one worker can keep at most the active channel readers
    if isempty(useCounter), useCounter = uint64(0); end
    
    % cleanup 분기
    if (ischar(filePath) || isstring(filePath)) && strcmp(char(filePath), '__CLEANUP__')
        if ~isempty(cache)
            for k = 1:numel(cache)
                try
                    if ~isempty(cache(k).vr) && isvalid(cache(k).vr)
                        delete(cache(k).vr);
                    end
                catch
                end
            end
        end
        cache = [];
        useCounter = uint64(0);
        return;
    end
    if isstring(filePath), filePath = char(filePath); end
    
    try
        if isempty(cache), cache = struct('path',{},'vr',{},'lastUse',{}); end

        % 슬롯 탐색
        idx = 0;
        for k = 1:numel(cache)
            if strcmp(cache(k).path, filePath) && ~isempty(cache(k).vr) && isvalid(cache(k).vr)
                idx = k; break;
            end
        end

        if idx == 0
            % LRU 축출 (꽉 찬 경우 가장 오래된 슬롯 delete)
            if numel(cache) >= maxSlots
                ages = zeros(1, numel(cache));
                for k = 1:numel(cache)
                    if cache(k).lastUse ~= 0
                        ages(k) = double(useCounter - cache(k).lastUse);
                    else
                        ages(k) = inf;
                    end
                end
                [~, victim] = max(ages);
                try, delete(cache(victim).vr); catch, end
                cache(victim) = [];
            end
            newSlot = struct('path', filePath, 'vr', VideoReader(filePath), 'lastUse', uint64(0));
            cache(end+1) = newSlot;
            idx = numel(cache);
        end
        useCounter = useCounter + 1;
        cache(idx).lastUse = useCounter;
        vr = cache(idx).vr;

        % [FIX] 사용 직전 isvalid 재확인 - 슬롯 매칭 후 VR 무효화 케이스 방어
        % (worker 자체 cleanup, 메모리 압박 등으로 invalidate 가능)
        if isempty(vr) || ~isvalid(vr)
            try, cache(idx) = []; catch, end
            try
                vr = VideoReader(filePath);
                useCounter = useCounter + 1;
                cache(end+1) = struct('path', filePath, 'vr', vr, 'lastUse', useCounter);
            catch
                img = []; return;
            end
        end

        try
            img = read(vr, frameNo);
        catch
            relTime = (frameNo - 1) / max(1, fps);
            relTime = max(0, min(relTime, vr.Duration - 0.05));
            vr.CurrentTime = relTime;
            if hasFrame(vr), img = readFrame(vr); end
        end
    catch
        img = [];
    end
end
