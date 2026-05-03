classdef FrameCacheModel < handle
    % flightdash.model.FrameCacheModel
    % - 비행경로별 프레임 이미지 캐시 (가중 LRU + 메모리 예산)
    % - 기존 FlightDataDashboard.cacheGetFrame/cacheStoreFrame/evictByScore 통합
    % - score = (hits * recency) / bytes
    %   → 자주 + 최근에 액세스된 작은 frame 보호
    %
    % 사용 예:
    %   cm = flightdash.model.FrameCacheModel(30);   % 30 MB 예산
    %   cm.recomputeLimit(1920, 1080);               % 영상 해상도 등록
    %   cm.store(frameNo, img);
    %   img = cm.get(frameNo);                       % miss 시 [] 반환
    %   tf  = cm.has(frameNo);
    %   cm.invalidate();                              % 동기 재설정 시 호출
    %
    % 단일 채널(fIdx) 책임. 배열로 [1xN] 사용.
    
    properties (Constant, Access = private)
        MAX_CACHE_FRAMES  = 200    % 절대 상한
        MIN_CACHE_FRAMES  = 5      % 절대 하한
    end
    
    properties (Access = private)
        Cache       cell    = {}
        Keys        double  = []
        Hits        double  = []
        BytesArr    double  = []     % [PERF] frame별 바이트 (cellfun 회피)
        LastUse     uint64  = uint64([])
        BytesUsed   double  = 0
        UseCounter  uint64  = uint64(0)
        % 외부에서 clamp 보호용 (초기 0이면 보호 비활성)
        TotalFrames double  = 0
        % [PERF] 영상 해상도 기반 frame 크기 캐시 (whos 호출 회피)
        % - 같은 영상 내에서 width*height*3은 불변 → recomputeLimit 시 1회 산정
        BytesPerFrame double = 0
    end
    
    properties (Access = public)
        BudgetMB    double  = 30
        FrameLimit  double  = 50    % 동적 계산된 max frames (DynamicCacheLimit 대체)
        DebugMode   logical = false
    end
    
    methods
        function obj = FrameCacheModel(budgetMB)
            if nargin >= 1 && ~isempty(budgetMB) && budgetMB > 0
                obj.BudgetMB = budgetMB;
            end
        end
        
        function setTotalFrames(obj, total)
            % VideoModel과 동기화 — clamp 보호용
            obj.TotalFrames = max(0, round(total));
        end
        
        function img = get(obj, frameNo)
            % miss 시 [] 반환. hit 시 LRU/hits 갱신.
            img = [];
            try
                if obj.TotalFrames >= 1
                    frameNo = max(1, min(round(frameNo), obj.TotalFrames));
                end
                if isempty(obj.Keys), return; end
                foundIdx = find(obj.Keys == frameNo, 1);
                if isempty(foundIdx), return; end
                
                img = obj.Cache{foundIdx};
                
                % 사용 카운터 단조 증가 + lastUse 갱신
                obj.UseCounter = obj.UseCounter + 1;
                obj.syncLengths_();
                obj.LastUse(foundIdx) = obj.UseCounter;
                obj.Hits(foundIdx)    = obj.Hits(foundIdx) + 1;
            catch ME_silent
                flightdash.util.ErrorLog.log(ME_silent, 'cacheGet');
                img = [];
            end
        end
        
        function store(obj, frameNo, img)
            try
                obj.syncLengths_();
                obj.UseCounter = obj.UseCounter + 1;
                useNow = obj.UseCounter;
                
                foundIdx = find(obj.Keys == frameNo, 1);
                newBytes = obj.frameBytes_(img);
                if ~isempty(foundIdx)
                    % 이미 존재 → in-place 갱신
                    obj.BytesUsed = obj.BytesUsed - obj.BytesArr(foundIdx) + newBytes;
                    obj.Cache{foundIdx}    = img;
                    obj.LastUse(foundIdx)  = useNow;
                    obj.BytesArr(foundIdx) = newBytes;
                else
                    obj.Keys(end+1)     = frameNo;
                    obj.Cache{end+1}    = img;
                    obj.Hits(end+1)     = 1;
                    obj.LastUse(end+1)  = useNow;
                    obj.BytesArr(end+1) = newBytes;
                    obj.BytesUsed = obj.BytesUsed + newBytes;
                end
                
                % frame 수 한도 초과 시 가중 evict
                limit = obj.FrameLimit;
                if limit < obj.MIN_CACHE_FRAMES, limit = obj.MIN_CACHE_FRAMES; end
                if limit > obj.MAX_CACHE_FRAMES, limit = obj.MAX_CACHE_FRAMES; end
                obj.evictByScore_(limit, false);
                
                % 절대 메모리 hard limit
                hardLimitBytes = obj.BudgetMB * 1024 * 1024;
                obj.evictByScore_(hardLimitBytes, true);
            catch e
                if obj.DebugMode
                    fprintf('[Cache] store failed: %s\n', e.message);
                end
                flightdash.util.ErrorLog.log(e, 'cacheStore');
            end
        end
        
        function tf = has(obj, frameNo)
            try
                if obj.TotalFrames >= 1
                    frameNo = max(1, min(round(frameNo), obj.TotalFrames));
                end
                tf = ~isempty(find(obj.Keys == frameNo, 1));
            catch
                tf = false;
            end
        end
        
        function invalidate(obj)
            obj.Cache     = {};
            obj.Keys      = [];
            obj.Hits      = [];
            obj.LastUse   = uint64([]);
            obj.BytesArr  = [];
            obj.BytesUsed = 0;
            obj.BytesPerFrame = 0;
        end
        
        function recomputeLimit(obj, width, height)
            % 영상 해상도와 사용자 예산을 바탕으로 FrameLimit 재계산
            try
                bytesPerFrame = width * height * 3;
                if bytesPerFrame <= 0 || ~isfinite(bytesPerFrame)
                    obj.BytesPerFrame = 0;
                    obj.FrameLimit = obj.MAX_CACHE_FRAMES;
                    return;
                end
                % [PERF] frameBytes_의 whos 호출 제거를 위해 영상 해상도 기준값 캐시
                obj.BytesPerFrame = bytesPerFrame;
                budgetBytes = obj.BudgetMB * 1024 * 1024;
                maxFrames = floor(budgetBytes / bytesPerFrame);
                maxFrames = max(obj.MIN_CACHE_FRAMES, min(maxFrames, obj.MAX_CACHE_FRAMES));
                obj.FrameLimit = maxFrames;
                
                if obj.DebugMode
                    fprintf('[Cache] %dx%d, budget=%dMB, limit=%d frames\n', ...
                        width, height, obj.BudgetMB, maxFrames);
                end
                
                % 현재 캐시가 한도 초과 시 즉시 evict
                obj.syncLengths_();
                if length(obj.Keys) > maxFrames
                    obj.evictByScore_(maxFrames, false);
                end
            catch ME_silent
                flightdash.util.ErrorLog.log(ME_silent, 'cacheRecomputeLimit');
                obj.FrameLimit = 50;
            end
        end
        
        function setBudgetMB(obj, mb)
            % 예산 변경 후 호출자가 recomputeLimit를 명시적으로 부르도록 책임 분리
            if mb > 0
                obj.BudgetMB = mb;
            end
        end
        
        function s = stats(obj)
            % 디버그용 요약
            s = struct( ...
                'frameCount',  numel(obj.Keys), ...
                'frameLimit',  obj.FrameLimit, ...
                'bytesUsed',   obj.BytesUsed, ...
                'budgetBytes', obj.BudgetMB * 1024 * 1024, ...
                'useCounter',  obj.UseCounter);
        end
    end
    
    methods (Access = private)
        function syncLengths_(obj)
            % hits/lastUse/bytesArr 길이를 keys와 양방향 보정 (방어적)
            nKeys = length(obj.Keys);
            if length(obj.Hits) < nKeys
                obj.Hits(end+1:nKeys) = 1;
            elseif length(obj.Hits) > nKeys
                obj.Hits = obj.Hits(1:nKeys);
            end
            if length(obj.LastUse) < nKeys
                obj.LastUse(end+1:nKeys) = uint64(0);
            elseif length(obj.LastUse) > nKeys
                obj.LastUse = obj.LastUse(1:nKeys);
            end
            if length(obj.BytesArr) < nKeys
                % 보정 시 cell의 실제 바이트로 채움 (드물게 호출)
                for k = (length(obj.BytesArr)+1):nKeys
                    obj.BytesArr(k) = obj.frameBytes_(obj.Cache{k});
                end
            elseif length(obj.BytesArr) > nKeys
                obj.BytesArr = obj.BytesArr(1:nKeys);
            end
        end
        
        function evictByScore_(obj, limit, byBytes)
            % 가중 evict 통합 헬퍼
            % - byBytes=false: limit는 frame 개수
            % - byBytes=true : limit는 누적 바이트 (최신 1프레임만 보호)
            % - score = (hits * recency) / bytes
            % [PERF] BytesArr 사용으로 cellfun 호출 제거 (매 iteration O(N) → O(1))
            if byBytes
                minKeep = 1;   % hard byte limit: keep only the newest frame if necessary
            else
                minKeep = obj.MIN_CACHE_FRAMES;
            end
            while length(obj.Keys) > minKeep
                if byBytes
                    if obj.BytesUsed <= limit, break; end
                else
                    if length(obj.Keys) <= limit, break; end
                end
                useNow = double(obj.UseCounter);
                if useNow <= 0, useNow = 1; end
                recency = double(obj.LastUse) ./ useNow;
                recency = max(recency, 0.01);
                scores = (double(obj.Hits) .* recency) ./ max(obj.BytesArr, 1);
                
                if numel(scores) <= 1
                    break;
                end
                % 최신(가장 마지막에 추가된) 항목은 score 평가에서 제외 (보호)
                [~, evictIdx] = min(scores(1:end-1));
                obj.BytesUsed = obj.BytesUsed - obj.BytesArr(evictIdx);
                obj.Keys(evictIdx)     = [];
                obj.Cache(evictIdx)    = [];
                obj.Hits(evictIdx)     = [];
                obj.LastUse(evictIdx)  = [];
                obj.BytesArr(evictIdx) = [];
            end
        end
        
        function bytes = frameBytes_(obj, img)
            % [PERF] 같은 영상 내에서 width*height*3 불변 → 캐시값 재사용
            % - whos 호출은 심볼테이블 검색으로 비용이 크므로 핫패스에서 회피
            % - 캐시 미설정/비 uint8/해상도 변경 시에만 whos 폴백
            if obj.BytesPerFrame > 0 && isa(img, 'uint8') && numel(img) == obj.BytesPerFrame
                bytes = obj.BytesPerFrame;
            else
                info = whos('img');
                bytes = info.bytes;
            end
        end
    end
end
