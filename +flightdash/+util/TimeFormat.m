classdef TimeFormat
    % flightdash.util.TimeFormat
    % - 프레임/초 ↔ HH:MM:SS.mmm 문자열 변환 (정적 메서드만)
    %
    % 사용 예:
    %   s = flightdash.util.TimeFormat.frameToHMSms(frameNo, fps)
    %       → 'HH:MM:SS.mmm' 문자열
    %   s = flightdash.util.TimeFormat.secondsToHMSms(tSec)
    %       → 'HH:MM:SS.mmm' 문자열
    %   [hh, mm, ss, ms] = flightdash.util.TimeFormat.decompose(tSec)
    %       → 분리된 정수 값들
    %
    % floor + 0.5 방식으로 부동소수점 오차 보정 (기존 동작 보존).
    
    methods (Static)
        function s = frameToHMSms(frameNo, fps)
            if nargin < 2 || isempty(fps) || fps <= 0
                fps = 70;   % 기존 폴백값 유지
            end
            tSec = (frameNo - 1) / fps;
            s = flightdash.util.TimeFormat.secondsToHMSms(tSec);
        end
        
        function s = secondsToHMSms(tSec)
            [hh, mm, ss, ms] = flightdash.util.TimeFormat.decompose(tSec);
            s = sprintf('%02d:%02d:%02d.%03d', hh, mm, ss, ms);
        end
        
        function [hh, mm, ss, ms] = decompose(tSec)
            if isnan(tSec) || isinf(tSec) || tSec < 0
                hh = 0; mm = 0; ss = 0; ms = 0; return;
            end
            hh = floor(tSec / 3600);
            mm = floor(mod(tSec, 3600) / 60);
            ss = floor(mod(tSec, 60));
            % floor + 0.5 방식으로 부동소수점 오차 보정 (기존 코드 line 858)
            ms = floor(mod(tSec, 1) * 1000 + 0.5);
            % 반올림으로 1000이 되면 초 단위로 캐리오버
            if ms >= 1000
                ms = 0; ss = ss + 1;
                if ss >= 60, ss = 0; mm = mm + 1; end
                if mm >= 60, mm = 0; hh = hh + 1; end
            end
        end
    end
end
