classdef UIScale
    % flightdash.util.UIScale
    % - High-DPI / 텍스트 스케일링 환경에서 픽셀 단위 레이아웃 보정 유틸
    % - 96 DPI를 1.0배 기준점으로 두고 현재 화면 DPI 비율로 가중
    % - 디자인 코드는 1x(96 DPI) 기준으로 작성한 뒤, 런타임에 `UIScale.px(...)`로 변환
    %
    % 사용:
    %   import flightdash.util.UIScale
    %   widths = {UIScale.px(200), UIScale.px(500), UIScale.px(250), '1x', UIScale.px(8), UIScale.px(500)};
    %
    % 캐싱:
    % - 같은 세션 내에서 DPI는 거의 변하지 않으므로 persistent로 1회 산정
    % - DPI 변경(다른 모니터로 이동 등) 시 앱 재시작 권장

    methods (Static)
        function out = px(val)
            % 디자인 픽셀(val) → 실효 픽셀(out)로 변환
            s = flightdash.util.UIScale.factor();
            out = round(val * s);
        end

        function s = factor()
            % 현재 화면 DPI 기반 스케일 비율 (96 DPI = 1.0)
            persistent cachedScale
            if isempty(cachedScale)
                try
                    dpi = get(groot, 'ScreenPixelsPerInch');
                    if isempty(dpi) || ~isfinite(dpi) || dpi <= 0
                        cachedScale = 1;
                    else
                        cachedScale = dpi / 96;
                    end
                catch
                    cachedScale = 1;
                end
            end
            s = cachedScale;
        end
    end
end
