classdef (Abstract) Command < handle
    %COMMAND Base class for undoable, session-scoped actions.

    properties
        SessionId char = ''
        Description char = 'Action'
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
                obj.Timestamp = datetime('now');
            catch
                obj.Timestamp = [];
            end
        end

        function tf = belongsToSession(obj, sessionId)
            tf = strcmp(obj.SessionId, char(sessionId));
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
