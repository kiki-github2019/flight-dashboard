classdef SessionScopedListener < handle
    %SESSIONSCOPEDLISTENER Auto-cleaning listener with SessionId filtering.

    properties
        SessionId char = ''
        Listener = []
    end

    methods
        function obj = SessionScopedListener(sessionId, source, eventName, callback)
            if nargin < 1, sessionId = ''; end
            if nargin < 2, source = []; end
            if nargin < 3, eventName = ''; end
            if nargin < 4, callback = []; end

            obj.SessionId = char(sessionId);
            if isempty(callback) || isempty(eventName)
                return;
            end

            eventName = char(eventName);
            if isempty(source)
                obj.Listener = flightdash.util.EventBus.subscribe(eventName, callback, obj.SessionId);
            else
                obj.Listener = addlistener(source, eventName, ...
                    @(src, evt) obj.safeCallback(src, evt, callback));
            end
        end

        function safeCallback(obj, src, evt, callback)
            try
                if isempty(obj) || ~isvalid(obj)
                    return;
                end
                if ~flightdash.util.EventBus.acceptsSession(obj.SessionId, obj.eventSessionId(evt))
                    return;
                end
                callback(src, evt);
            catch ME
                flightdash.util.ErrorLog.log(ME, 'SessionScopedListener', false);
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.Listener) && isvalid(obj.Listener)
                    delete(obj.Listener);
                end
            catch
            end
            obj.Listener = [];
        end
    end

    methods (Access = private)
        function sessionId = eventSessionId(~, evt)
            sessionId = '';
            try
                if isa(evt, 'flightdash.util.AppEventData') || ...
                        (isobject(evt) && isprop(evt, 'SessionId'))
                    sessionId = char(evt.SessionId);
                elseif isstruct(evt) && isfield(evt, 'SessionId')
                    sessionId = char(evt.SessionId);
                end
            catch
                sessionId = '';
            end
        end
    end
end
