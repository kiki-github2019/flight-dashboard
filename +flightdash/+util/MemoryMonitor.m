classdef MemoryMonitor
    %MEMORYMONITOR  Debug-only memory-usage logger (Phase 11 §11).
    %
    %   Diagnostic utility. No production code path imports this class —
    %   start it manually when investigating memory leaks during long
    %   slider-scrub / multi-session sessions.
    %
    %   Usage:
    %       flightdash.util.MemoryMonitor.log('after addSession');
    %       flightdash.util.MemoryMonitor.startMonitoring(3);   % 3 s interval
    %       flightdash.util.MemoryMonitor.stopMonitoring();
    %
    %   The timer handle is parked on setappdata(0, ...) instead of the
    %   base workspace so unit tests do not pollute their callers.
    %   `memory()` is Windows-only; on MATLAB Online / Linux / macOS the
    %   call is caught and the line falls back to `(memory() failed)`.

    properties (Constant, Access = private)
        AppDataKey = 'FlightdashMemoryMonitorTimer'
        TimerName  = 'FlightdashMemoryMonitor'
    end

    methods (Static)
        function path = logPath()
            % Always write into tempdir — current working directory is
            % not necessarily writable and pollutes user paths.
            path = fullfile(tempdir, 'flightdash_memory_log.txt');
        end

        function log(msg, detailed)
            if nargin < 1, msg = '(no tag)'; end
            if nargin < 2, detailed = false; end
            try
                m = memory;
                usedMB  = m.MemUsedMATLAB / 1024^2;
                availMB = m.MemAvailableAllArrays / 1024^2;
                tsLine  = datestr(now, 'yyyy-mm-dd HH:MM:SS.fff');
                line = sprintf('%s | %s | Used: %7.1f MB | Available: %7.1f MB', ...
                    tsLine, char(msg), usedMB, availMB);
                if detailed
                    line = sprintf('%s | MaxPossible: %.1f MB', ...
                        line, m.MaxPossibleArrayBytes / 1024^2);
                end
            catch
                line = sprintf('%s | %s | (memory() failed)', ...
                    datestr(now, 'yyyy-mm-dd HH:MM:SS.fff'), char(msg));
            end

            fprintf('[Memory] %s\n', line);

            try
                fid = fopen(flightdash.util.MemoryMonitor.logPath(), 'a');
                if fid ~= -1
                    fprintf(fid, '%s\n', line);
                    fclose(fid);
                end
            catch
            end
        end

        function startMonitoring(intervalSec)
            if nargin < 1 || isempty(intervalSec) || ~isnumeric(intervalSec) || intervalSec <= 0
                intervalSec = 3;
            end
            % Stop any pre-existing instance before creating a new one.
            flightdash.util.MemoryMonitor.stopMonitoring();
            t = timer( ...
                'Name', flightdash.util.MemoryMonitor.TimerName, ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', double(intervalSec), ...
                'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) flightdash.util.MemoryMonitor.log('Periodic Check'));
            try
                setappdata(0, flightdash.util.MemoryMonitor.AppDataKey, t);
                start(t);
            catch ME
                try, delete(t); catch, end
                warning('FlightdashMemoryMonitor:StartFailed', '%s', ME.message);
            end
        end

        function stopMonitoring()
            try
                key = flightdash.util.MemoryMonitor.AppDataKey;
                if isappdata(0, key)
                    t = getappdata(0, key);
                    rmappdata(0, key);
                    if isa(t, 'timer') && isvalid(t)
                        if strcmp(t.Running, 'on')
                            stop(t);
                        end
                        delete(t);
                    end
                end
            catch
            end
            % Belt-and-suspenders: kill any orphan timer matching our name
            % (e.g. created before the appdata slot existed).
            try
                stray = timerfindall('Name', flightdash.util.MemoryMonitor.TimerName);
                for k = 1:numel(stray)
                    try
                        if strcmp(stray(k).Running, 'on'), stop(stray(k)); end
                    catch, end
                    try, delete(stray(k)); catch, end
                end
            catch
            end
        end

        function tf = isRunning()
            tf = false;
            try
                key = flightdash.util.MemoryMonitor.AppDataKey;
                if ~isappdata(0, key), return; end
                t = getappdata(0, key);
                tf = isa(t, 'timer') && isvalid(t) && strcmp(t.Running, 'on');
            catch
                tf = false;
            end
        end
    end
end
