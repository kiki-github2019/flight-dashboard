classdef (Abstract) Command < handle
    % flightdash.command.Command
    % Base class for undoable per-session operations.

    properties
        SessionId char = ''
        Description char = 'Command'
        CreatedAt = []
        Timestamp = []
    end

    methods
        function obj = Command(sessionId, description)
            if nargin >= 1 && ~isempty(sessionId)
                obj.SessionId = char(sessionId);
            end
            if nargin >= 2 && ~isempty(description)
                obj.Description = char(description);
            end
            try
                obj.CreatedAt = datetime('now');
                obj.Timestamp = obj.CreatedAt;
            catch
                obj.CreatedAt = [];
                obj.Timestamp = [];
            end
        end

        function tf = belongsToSession(obj, sessionId)
            tf = strcmp(char(obj.SessionId), char(sessionId));
        end

        function redo(obj)
            obj.execute();
        end
    end

    methods (Abstract)
        execute(obj)
        undo(obj)
    end
end
