classdef UndoStateChangedData < event.EventData
    % flightdash.studio.UndoStateChangedData

    properties
        SessionId char = ''
        Action char = ''
        Command = []
        CanUndo logical = false
        CanRedo logical = false
        UndoDescription char = ''
        RedoDescription char = ''
    end

    methods
        function obj = UndoStateChangedData(sessionId, action, command, canUndo, canRedo, undoDescription, redoDescription)
            if nargin >= 1, obj.SessionId = char(sessionId); end
            if nargin >= 2, obj.Action = char(action); end
            if nargin >= 3, obj.Command = command; end
            if nargin >= 4, obj.CanUndo = logical(canUndo); end
            if nargin >= 5, obj.CanRedo = logical(canRedo); end
            if nargin >= 6, obj.UndoDescription = char(undoDescription); end
            if nargin >= 7, obj.RedoDescription = char(redoDescription); end
        end
    end
end
