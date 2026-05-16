classdef ScrubBench
    %SCRUBBENCH  Debug-only counters for the slider scrub hot path.
    %
    %   Activated only when FlightDataDashboard.DebugMode is true. Each
    %   scrubTick increment is added to a tiny shared struct parked on
    %   setappdata(0, AppDataKey, ...) so multiple dashboards aggregate
    %   into one process-wide counter. Snapshot() reads the counters,
    %   prints a single one-line summary, and clears the slot.
    %
    %   Usage:
    %       app.DebugMode = true;
    %       % … drag the slider for 5 seconds …
    %       flightdash.util.ScrubBench.snapshot();
    %
    %   Counters tracked:
    %       Ticks         — scrubTick invocations
    %       CacheHits     — frame served from CacheModel
    %       SyncDecodes   — frame served via decodeFrameSync
    %       Previews      — previewSyncedMarkersOnly invocations
    %       SkipsNoFrame  — ticks where pending == lastRendered
    %       SkipsNotReady — ticks where isVideoReady was false
    %
    %   This is debug instrumentation only — no production code path
    %   imports it directly. FlightDataDashboard reads ismethod()
    %   before calling so the absence of this class is harmless.

    properties (Constant, Access = private)
        AppDataKey = 'FlightdashScrubStats'
    end

    methods (Static)
        function tick(field)
            % Increment one named counter. Caller must guard on
            % app.DebugMode (we do NOT check here — keeping the call
            % site to a single setappdata cycle).
            try
                key = flightdash.util.ScrubBench.AppDataKey;
                if isappdata(0, key)
                    s = getappdata(0, key);
                else
                    s = flightdash.util.ScrubBench.emptyStats();
                end
                if ~isstruct(s) || ~isfield(s, char(field))
                    s = flightdash.util.ScrubBench.emptyStats();
                end
                s.(char(field)) = s.(char(field)) + 1;
                setappdata(0, key, s);
            catch
            end
        end

        function s = snapshot()
            % Read + print + clear. Returns the snapshot struct so
            % automated benchmarks can verify counts.
            s = flightdash.util.ScrubBench.emptyStats();
            try
                key = flightdash.util.ScrubBench.AppDataKey;
                if isappdata(0, key)
                    s = getappdata(0, key);
                    rmappdata(0, key);
                end
            catch
            end
            try
                fprintf(['[ScrubBench] Ticks=%d  CacheHits=%d  SyncDecodes=%d ' ...
                    ' Previews=%d  SkipsNoFrame=%d  SkipsNotReady=%d\n'], ...
                    s.Ticks, s.CacheHits, s.SyncDecodes, s.Previews, ...
                    s.SkipsNoFrame, s.SkipsNotReady);
            catch
            end
        end

        function reset()
            try
                key = flightdash.util.ScrubBench.AppDataKey;
                if isappdata(0, key)
                    rmappdata(0, key);
                end
            catch
            end
        end
    end

    methods (Static, Access = private)
        function s = emptyStats()
            s = struct( ...
                'Ticks',         0, ...
                'CacheHits',     0, ...
                'SyncDecodes',   0, ...
                'Previews',      0, ...
                'SkipsNoFrame',  0, ...
                'SkipsNotReady', 0);
        end
    end
end
