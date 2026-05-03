classdef AppConstants
    % flightdash.util.AppConstants
    % - View/Controller가 공유하는 상수 (매직 넘버 중앙화)
    % - 본체 FlightDataDashboard.m의 private 상수와 분리하여
    %   외부 패키지(view, controller)에서 직접 접근 가능
    %
    % 사용:
    %   import flightdash.util.AppConstants
    %   if dt < AppConstants.SLIDER_THROTTLE_S, return; end

    properties (Constant)
        % --- 탭/플롯 ---
        MAX_TABS              = 10
        MAX_PLOTS_PER_TAB     = 12
        PLOT_ROW_HEIGHT       = 150     % H영역 내 각 플롯 패널 높이(px)
        MOCK_STEP_COUNT       = 200     % 모의 데이터 스텝 수
        REQ_KEYS              = {'Time', 'Roll', 'Pitch', 'Heading', 'Alt', 'Lat', 'Lon'}

        % --- Throttle (초) ---
        VIDEO_THROTTLE_S         = 0.05    % 비디오 프레임 갱신 (~20fps)
        SLIDER_THROTTLE_S        = 0.03    % 슬라이더 갱신 (~33fps)
        PLOT_DRAG_THROTTLE_S     = 0.04    % drag-time plot marker (~25fps)
        MAP_PATH_DRAG_THROTTLE_S = 0.08    % drag-time map path (~12fps)

        % --- Cache 한도 ---
        MAX_CACHE_FRAMES      = 200
        MIN_CACHE_FRAMES      = 5

        % --- Async/Worker ---
        ASYNC_WORKER_COUNT    = 2
        WORKER_VR_CACHE_SLOTS = 4
        MAX_SEQ_READ_STEP     = 4
        MAX_PENDING_ITERS     = 10
    end
end
