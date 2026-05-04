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

        function out = pxForProfile(val, profile)
            % Layout profile별 DPI 상한을 적용한 픽셀 변환.
            s = flightdash.util.UIScale.factorForProfile(profile);
            out = round(val * s);
        end

        function out = pxForSize(val, widthPx, heightPx)
            % 현재 figure 크기로 profile을 판정한 뒤 픽셀 변환.
            if nargin < 3
                heightPx = [];
            end
            profile = flightdash.util.UIScale.profileForSize(widthPx, heightPx);
            out = flightdash.util.UIScale.pxForProfile(val, profile);
        end

        function s = factor()
            % 현재 화면 DPI 기반 스케일 비율 (96 DPI = 1.0)
            persistent cachedScale
            if isempty(cachedScale)
                cachedScale = min(flightdash.util.UIScale.rawFactor(), ...
                    flightdash.util.AppConstants.LAYOUT_SCALE_MAX_WIDE);
            end
            s = cachedScale;
        end

        function s = factorForProfile(profile)
            % Wide는 기존 DPI 보정을 유지하고, 작은 화면 profile은 폭 확대를 제한한다.
            baseScale = flightdash.util.UIScale.factor();
            profile = flightdash.util.UIScale.normalizeProfile(profile);

            switch profile
                case flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW
                    maxScale = flightdash.util.AppConstants.LAYOUT_SCALE_MAX_NARROW;
                case flightdash.util.AppConstants.LAYOUT_PROFILE_COMPACT
                    maxScale = flightdash.util.AppConstants.LAYOUT_SCALE_MAX_COMPACT;
                case flightdash.util.AppConstants.LAYOUT_PROFILE_MEDIUM
                    maxScale = flightdash.util.AppConstants.LAYOUT_SCALE_MAX_MEDIUM;
                otherwise
                    maxScale = flightdash.util.AppConstants.LAYOUT_SCALE_MAX_WIDE;
            end
            s = min(baseScale, maxScale);
        end

        function profile = profileForSize(widthPx, heightPx)
            % Figure/viewport 크기를 responsive layout profile로 변환.
            if nargin < 1 || isempty(widthPx) || ~isfinite(widthPx) || widthPx <= 0
                [widthPx, fallbackH] = flightdash.util.UIScale.screenSize();
            else
                fallbackH = [];
            end

            if nargin < 2 || isempty(heightPx) || ~isfinite(heightPx) || heightPx <= 0
                if isempty(fallbackH)
                    [~, heightPx] = flightdash.util.UIScale.screenSize();
                else
                    heightPx = fallbackH;
                end
            end

            if widthPx >= flightdash.util.AppConstants.LAYOUT_WIDE_MIN_W && ...
                    heightPx >= flightdash.util.AppConstants.LAYOUT_USABLE_MIN_H
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_WIDE;
            elseif widthPx >= flightdash.util.AppConstants.LAYOUT_MEDIUM_MIN_W
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_MEDIUM;
            elseif widthPx >= flightdash.util.AppConstants.LAYOUT_COMPACT_MIN_W
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_COMPACT;
            else
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW;
            end
        end

        function profile = normalizeProfile(profile)
            if nargin < 1 || isempty(profile)
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_WIDE;
                return;
            end

            profile = lower(char(profile));
            knownProfiles = {flightdash.util.AppConstants.LAYOUT_PROFILE_WIDE, ...
                flightdash.util.AppConstants.LAYOUT_PROFILE_MEDIUM, ...
                flightdash.util.AppConstants.LAYOUT_PROFILE_COMPACT, ...
                flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW};
            if ~any(strcmp(profile, knownProfiles))
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_WIDE;
            end
        end

        function s = rawFactor()
            try
                dpi = get(groot, 'ScreenPixelsPerInch');
                if isempty(dpi) || ~isfinite(dpi) || dpi <= 0
                    s = 1;
                else
                    s = dpi / 96;
                end
            catch
                s = 1;
            end
        end

        function [widthPx, heightPx] = screenSize()
            try
                scr = get(groot, 'ScreenSize');
                if numel(scr) >= 4 && all(isfinite(scr(3:4))) && scr(3) > 0 && scr(4) > 0
                    widthPx = scr(3);
                    heightPx = scr(4);
                    return;
                end
            catch
            end
            widthPx = 1920;
            heightPx = 1080;
        end
    end
end
