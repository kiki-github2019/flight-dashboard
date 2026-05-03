classdef VideoModel < handle
    % flightdash.model.VideoModel
    % - VideoReader 라이프사이클 관리 + TotalFrames 계산 + 첫 프레임 로드
    % - 디코딩 자체는 호출자가 담당(decode 결과 cache는 FrameCacheModel)
    %
    % [V3.24 events] 변경 통지:
    %   VideoLoaded   - Reader가 새로 부착되었을 때 (해상도 결정 시점)
    %   VideoCleared  - cleanup으로 Reader가 해제되었을 때
    
    events
        VideoLoaded
        VideoCleared
    end
    
    properties (Access = public)
        Reader              = []
        ImageHandle         = []
        StartTime    double = 0
        FilePath     char   = ''
        TotalFrames  double = 0
        VideoFps     double = 70
        CurrentFrame double = 1
    end
    
    methods
        function attachReader(obj, vr, filePath, imageHandle)
            % Reader 부착 + (옵션) 메타 동기 set + VideoLoaded notify
            if nargin < 2 || isempty(vr) || ~isvalid(vr)
                return;
            end
            try
                if ~isempty(obj.Reader) && isvalid(obj.Reader) && ~isequal(obj.Reader, vr)
                    delete(obj.Reader);
                end
            catch ME
                flightdash.util.ErrorLog.log(ME, 'VideoModel:replaceReader');
            end
            obj.Reader = vr;
            if nargin >= 3 && ~isempty(filePath), obj.FilePath = filePath; end
            if nargin >= 4 && ~isempty(imageHandle), obj.ImageHandle = imageHandle; end
            notify(obj, 'VideoLoaded');
        end
        
        function tf = isReady(obj)
            tf = false;
            try
                tf = ~isempty(obj.Reader) && isvalid(obj.Reader) && ...
                     ~isempty(obj.ImageHandle) && isvalid(obj.ImageHandle);
            catch
            end
        end
        
        function totalFrames = computeTotalFrames(obj, debugMode, vrOverride)
            % NumFrames 우선 → Duration*FrameRate 폴백 → 0
            % vrOverride: 호출자가 별도 VideoReader 핸들 보유 시 (호환용)
            if nargin < 2, debugMode = false; end
            totalFrames = 0;
            if nargin >= 3 && ~isempty(vrOverride)
                vr = vrOverride;
            else
                vr = obj.Reader;
            end
            if isempty(vr) || ~isvalid(vr), return; end
            try
                if isprop(vr, 'NumFrames') && ~isempty(vr.NumFrames) && vr.NumFrames > 0
                    totalFrames = double(vr.NumFrames);
                end
            catch ME
                flightdash.util.ErrorLog.log(ME, 'VideoModel:NumFrames', debugMode);
                totalFrames = 0;
            end
            estFrames = 0;
            try
                if vr.FrameRate > 0
                    estFrames = floor(vr.Duration * vr.FrameRate);
                end
            catch ME
                flightdash.util.ErrorLog.log(ME, 'VideoModel:Duration', debugMode);
            end
            if totalFrames < 1
                totalFrames = estFrames;
            elseif totalFrames <= 1 && estFrames > 1
                % 일부 codec/버전에서 NumFrames가 1로 고정되는 경우 slider range가 1에 갇힌다.
                totalFrames = estFrames;
            end
            % VFR/MP4 mismatch 경고 (디버그 시만)
            if debugMode && totalFrames > 0
                try
                    if estFrames > 0 && abs(totalFrames - estFrames) > 2
                        fprintf('[VideoModel] TotalFrames mismatch: chosen=%d, est=%d (VFR/codec metadata check)\n', ...
                            totalFrames, estFrames);
                    end
                catch
                end
            end
        end
        
        function img = loadFirstFrame(obj)
            % 첫 프레임 디코딩 + 이미지 핸들 갱신 + axes XLim/YLim/AspectRatio 보정
            % - axes는 외부에서 별도 보정 (View 책임)
            img = [];
            try
                img = read(obj.Reader, 1);
            catch
                try
                    obj.Reader.CurrentTime = 0;
                    if hasFrame(obj.Reader)
                        img = readFrame(obj.Reader);
                    end
                catch ME_silent, flightdash.util.ErrorLog.log(ME_silent, 'silent'); end
            end
            if ~isempty(img) && ~isempty(obj.ImageHandle) && isvalid(obj.ImageHandle)
                set(obj.ImageHandle, 'CData', img);
            end
        end
        
        function cleanup(obj)
            % VideoReader 명시적 해제 (파일락 즉시 반환)
            try
                if ~isempty(obj.Reader) && isvalid(obj.Reader)
                    delete(obj.Reader);
                end
            catch ME, flightdash.util.ErrorLog.log(ME, 'silent'); end
            obj.Reader       = [];
            obj.StartTime    = 0;
            obj.FilePath     = '';
            obj.TotalFrames  = 0;
            obj.CurrentFrame = 1;
            notify(obj, 'VideoCleared');
        end
    end
end
