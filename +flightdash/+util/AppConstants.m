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

        % --- Responsive layout profiles ---
        LAYOUT_PROFILE_WIDE    = 'wide'
        LAYOUT_PROFILE_MEDIUM  = 'medium'
        LAYOUT_PROFILE_COMPACT = 'compact'
        LAYOUT_PROFILE_NARROW  = 'narrow'

        % Figure width breakpoints in effective pixels.
        LAYOUT_WIDE_MIN_W      = 1700
        LAYOUT_MEDIUM_MIN_W    = 1450
        LAYOUT_COMPACT_MIN_W   = 1120
        LAYOUT_USABLE_MIN_H    = 640

        % DPI scale caps by profile. Small MATLAB Online viewports should
        % not inflate fixed panel widths just because browser/OS scaling is high.
        LAYOUT_SCALE_MAX_WIDE    = 1.25
        LAYOUT_SCALE_MAX_MEDIUM  = 1.10
        LAYOUT_SCALE_MAX_COMPACT = 1.00
        LAYOUT_SCALE_MAX_NARROW  = 0.90

        % Design widths for the responsive allocator used by later stages.
        LAYOUT_ATT_WIDE      = 200
        LAYOUT_ATT_MEDIUM    = 170
        LAYOUT_ATT_RAIL      = 56
        LAYOUT_MAP_WIDE      = 500
        LAYOUT_MAP_MEDIUM    = 380
        LAYOUT_MAP_COMPACT   = 320
        LAYOUT_MAP_RAIL      = 220
        LAYOUT_INFO_WIDE     = 250
        LAYOUT_INFO_MEDIUM   = 210
        LAYOUT_INFO_RAIL     = 64
        LAYOUT_VIDEO_WIDE    = 500
        LAYOUT_VIDEO_WIDE_MAX = 900
        LAYOUT_VIDEO_MEDIUM  = 380
        LAYOUT_VIDEO_COMPACT = 320
        LAYOUT_VIDEO_RAIL    = 72
        LAYOUT_SPLITTER_W    = 8
        LAYOUT_H_MIN_WIDE    = 320
        LAYOUT_H_MIN_MEDIUM  = 300
        LAYOUT_H_MIN_COMPACT = 260
        LAYOUT_H_MIN_NARROW  = 220
        LAYOUT_SHORT_VIEW_H  = 760
        LAYOUT_CHANNEL_MIN_H_WIDE    = 380
        LAYOUT_CHANNEL_MIN_H_MEDIUM  = 350
        LAYOUT_CHANNEL_MIN_H_COMPACT = 320
        LAYOUT_CHANNEL_MIN_H_NARROW  = 300

        % Initial and fit-to-screen figure sizing.
        FIGURE_INITIAL_W = 1320
        FIGURE_INITIAL_H = 820
        FIGURE_MIN_W     = 980
        FIGURE_MIN_H     = 620
        FIGURE_MARGIN_X  = 48
        FIGURE_MARGIN_Y  = 88

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

        % --- Column severity split (Commit 1) ---
        REQ_KEYS_CRITICAL = {'Time', 'Lat', 'Lon', 'Alt'}
        REQ_KEYS_OPTIONAL = {'Roll', 'Pitch', 'Heading'}
    end

    methods (Static)
        function aliases = columnAliases()
            % Central alias source for tolerant CSV header → required-key
            % mapping. Match is performed on normalized (lower + alnum only)
            % forms in FlightDataLoader.normalizeHeaderName.
            aliases = struct();
            aliases.Time    = {'time','time_s','timestamp','t','sec','seconds','elapsedtime','elapsed_time'};
            aliases.Roll    = {'roll','rollangle','phi','bank','roll_deg','rolldeg','flight_roll'};
            aliases.Pitch   = {'pitch','pitchangle','theta','pitch_deg','pitchdeg','flight_pitch'};
            aliases.Heading = {'heading','yaw','course','track','hdg','psi','headingangle','flight_heading','course_angle','courseangle'};
            aliases.Alt     = {'alt','altitude','height','alt_ft','altitude_ft','altitude_m','flight_alt','pressaltitude','press_altitude','baro_altitude'};
            aliases.Lat     = {'lat','latitude','lat_deg','flight_lat','gps_lat','gpslatitude'};
            aliases.Lon     = {'lon','longitude','long','lon_deg','flight_lon','lng','gps_lon','gpslongitude'};
        end
    end
end
