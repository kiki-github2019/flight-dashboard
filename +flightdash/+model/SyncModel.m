classdef SyncModel < handle
    % flightdash.model.SyncModel
    % - 비디오/비행데이터 동기 anchor + Frame ↔ Time 변환
    % - VideoModel 의존성 없음 (TotalFrames/VideoFps만 외부에서 주입)
    %
    % [V3.23 sub-frame] AnchorOffset 도입
    % - AnchorFrame은 정수 frame (UI uispinner 입력값)
    % - AnchorOffset은 [-0.5, 0.5] 범위의 sub-frame 분수 보정
    % - 실효 anchor = AnchorFrame + AnchorOffset (분수 정밀도)
    % - 긴 영상에서 anchor 정수화로 인한 누적 오차 제거
    
    properties (Access = public)
        IsSynced     logical = false
        AnchorFrame  double  = 0     % 정수 frame
        AnchorOffset double  = 0     % [-0.5, 0.5] sub-frame 보정
        AnchorTime   double  = 0
        DataFps      double  = 50
    end
    
    methods
        function setAnchor(obj, frameNo, timeVal, offset)
            obj.AnchorFrame  = frameNo;
            obj.AnchorTime   = timeVal;
            if nargin >= 4 && ~isempty(offset)
                obj.AnchorOffset = max(-0.5, min(0.5, offset));
            else
                obj.AnchorOffset = 0;
            end
            obj.IsSynced = true;
        end
        
        function clear(obj)
            obj.IsSynced     = false;
            obj.AnchorFrame  = 0;
            obj.AnchorOffset = 0;
            obj.AnchorTime   = 0;
        end
        
        function timeVal = frameToTime(obj, frameNo, videoFps, anchorFrame, anchorTime, anchorOffset)
            if nargin < 4, anchorFrame = obj.AnchorFrame; end
            if nargin < 5, anchorTime  = obj.AnchorTime;  end
            if nargin < 6, anchorOffset = obj.AnchorOffset; end
            if videoFps <= 0
                timeVal = anchorTime; return;
            end
            % 실효 anchor = anchorFrame + anchorOffset
            timeVal = anchorTime + (frameNo - (anchorFrame + anchorOffset)) / videoFps;
        end
        
        function frameNo = timeToFrame(obj, timeVal, videoFps, totalFrames, anchorFrame, anchorTime, anchorOffset)
            if nargin < 5, anchorFrame = obj.AnchorFrame; end
            if nargin < 6, anchorTime  = obj.AnchorTime;  end
            if nargin < 7, anchorOffset = obj.AnchorOffset; end
            if isnan(anchorFrame), anchorFrame = 1; end
            if isnan(anchorOffset), anchorOffset = 0; end
            if isnan(anchorTime), anchorTime = 0; end
            if videoFps <= 0 || isnan(videoFps) || isnan(timeVal)
                frameNo = max(1, round(anchorFrame + anchorOffset)); return;
            end
            if isnan(totalFrames) || totalFrames < 1, totalFrames = 1; end
            % [JITTER GUARD] ±0.5 경계의 부동소수점 미세 오차로 ±1 frame 점프 방지
            % - timeVal이 매우 미세하게 진동할 때 round() 결과가 floor↔ceil 토글되는 현상 차단
            % - 1e-9 정밀도로 사전 절삭하여 round() 입력을 결정적으로 만듦
            rawFrame = (anchorFrame + anchorOffset) + (timeVal - anchorTime) * videoFps;
            rawFrame = round(rawFrame * 1e9) / 1e9;
            frameNo = round(rawFrame);
            if isnan(frameNo), frameNo = anchorFrame; end
            frameNo = max(1, min(frameNo, totalFrames));
        end
    end
end
