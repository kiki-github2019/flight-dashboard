classdef ErrorLog < handle
    % flightdash.util.ErrorLog
    % - 사일런트/논사일런트 캐치 모두 ring buffer에 보관
    % - 사후 조사용 dump 메서드 제공
    % - 싱글톤 instance 패턴 (전역 단일 로그)
    %
    % 사용 예:
    %   flightdash.util.ErrorLog.log(ME, 'tag')      % 인스턴스 자동
    %   flightdash.util.ErrorLog.log(ME, 'tag', dbg) % DebugMode 명시
    %   flightdash.util.ErrorLog.dump()              % 전체
    %   flightdash.util.ErrorLog.dump(20)            % 최근 20건
    %   flightdash.util.ErrorLog.dump(20, 'Async')   % 태그 필터
    %   flightdash.util.ErrorLog.clear()             % 비우기
    
    properties (Access = private)
        Entries    = struct('time', {}, 'tag', {}, 'identifier', {}, 'message', {}, 'stack', {}, 'report', {})
        Capacity   = 200
        DebugMode  logical = false
    end
    
    methods (Access = private)
        function obj = ErrorLog()
            % private constructor (싱글톤)
        end
    end
    
    methods (Static)
        function inst = instance()
            persistent singleton
            if isempty(singleton) || ~isvalid(singleton)
                singleton = flightdash.util.ErrorLog();
            end
            inst = singleton;
        end
        
        function setDebugMode(tf)
            flightdash.util.ErrorLog.instance().DebugMode = logical(tf);
        end
        
        function setCapacity(n)
            obj = flightdash.util.ErrorLog.instance();
            obj.Capacity = max(10, round(n));
            if numel(obj.Entries) > obj.Capacity
                obj.Entries = obj.Entries(end-obj.Capacity+1:end);
            end
        end
        
        function log(ME, tag, debugOverride)
            % ring buffer에 항상 적재; debug 모드일 때만 콘솔 출력
            % - silent 태그는 buffer만 남기고 콘솔에는 안 찍음 (기존 동작 보존)
            if nargin < 2, tag = 'unknown'; end
            obj = flightdash.util.ErrorLog.instance();
            
            try
                stackCell = {[]};
                try, stackCell = {ME.stack}; catch, end
                reportStr = '';
                try, reportStr = getReport(ME, 'extended', 'hyperlinks', 'off'); catch, end
                entry = struct( ...
                    'time',       datetime('now'), ...
                    'tag',        char(tag), ...
                    'identifier', char(ME.identifier), ...
                    'message',    char(ME.message), ...
                    'stack',      stackCell, ...
                    'report',     reportStr);
                if isempty(obj.Entries)
                    obj.Entries = entry;
                else
                    obj.Entries(end+1) = entry;
                    if numel(obj.Entries) > obj.Capacity
                        obj.Entries = obj.Entries(end-obj.Capacity+1:end);
                    end
                end
            catch
                % ring buffer 자체가 실패해도 절대 throw 안 함
            end
            
            % 콘솔 출력 게이팅
            dbg = obj.DebugMode;
            if nargin >= 3 && ~isempty(debugOverride)
                dbg = logical(debugOverride);
            end
            if ~dbg, return; end
            if strcmpi(tag, 'silent'), return; end
            fprintf('[%s] %s: %s\n', tag, ME.identifier, ME.message);
        end
        
        function dump(n, filterTag)
            obj = flightdash.util.ErrorLog.instance();
            if isempty(obj.Entries)
                fprintf('[ErrorLog] (empty)\n'); return;
            end
            log = obj.Entries;
            if nargin >= 2 && ~isempty(filterTag)
                keep = arrayfun(@(e) contains(e.tag, filterTag, 'IgnoreCase', true), log);
                log = log(keep);
            end
            if nargin >= 1 && ~isempty(n) && n > 0 && numel(log) > n
                log = log(end-n+1:end);
            end
            fprintf('[ErrorLog] %d entries:\n', numel(log));
            for k = 1:numel(log)
                tstr = '';
                try
                    tstr = char(datetime(log(k).time, 'Format', 'HH:mm:ss.SSS'));
                catch
                    try, tstr = datestr(log(k).time, 'HH:MM:SS.FFF'); catch, tstr = ''; end %#ok<DATST>
                end
                fprintf('  [%s] [%s] %s: %s\n', tstr, ...
                    log(k).tag, log(k).identifier, log(k).message);
            end
        end
        
        function clear()
            obj = flightdash.util.ErrorLog.instance();
            obj.Entries = struct('time', {}, 'tag', {}, 'identifier', {}, 'message', {}, 'stack', {}, 'report', {});
        end
        
        function n = count()
            obj = flightdash.util.ErrorLog.instance();
            n = numel(obj.Entries);
        end
    end
end
