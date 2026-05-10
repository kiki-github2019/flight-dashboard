classdef UndoService < handle
    %UNDOSERVICE Per-session undo/redo stack.

    properties
        SessionId char = ''
        UndoStack cell = {}
        RedoStack cell = {}
        MaxHistory double = 50
    end

    methods
        function obj = UndoService(sessionId)
            if nargin >= 1 && ~isempty(sessionId)
                obj.SessionId = char(sessionId);
            end
        end

        function push(obj, command)
            if isempty(command) || ~isa(command, 'flightdash.command.Command') || ...
                    ~command.belongsToSession(obj.SessionId)
                return;
            end
            obj.UndoStack{end+1} = command;
            obj.RedoStack = {};
            if numel(obj.UndoStack) > obj.MaxHistory
                obj.UndoStack(1) = [];
            end
            obj.notifyStateChanged(command.Description);
        end

        function undo(obj)
            if isempty(obj.UndoStack), return; end
            cmd = obj.UndoStack{end};
            obj.UndoStack(end) = [];
            try
                cmd.undo();
                obj.RedoStack{end+1} = cmd;
            catch ME
                flightdash.util.ErrorLog.log(ME, 'UndoService:undo', false);
            end
            obj.notifyStateChanged('');
        end

        function redo(obj)
            if isempty(obj.RedoStack), return; end
            cmd = obj.RedoStack{end};
            obj.RedoStack(end) = [];
            try
                cmd.redo();
                obj.UndoStack{end+1} = cmd;
            catch ME
                flightdash.util.ErrorLog.log(ME, 'UndoService:redo', false);
            end
            obj.notifyStateChanged('');
        end

        function tf = canUndo(obj)
            tf = ~isempty(obj.UndoStack);
        end

        function tf = canRedo(obj)
            tf = ~isempty(obj.RedoStack);
        end

        function clear(obj)
            obj.UndoStack = {};
            obj.RedoStack = {};
            obj.notifyStateChanged('');
        end

        function notifyStateChanged(obj, lastAction)
            if nargin < 2, lastAction = ''; end
            payload = struct('SessionId', obj.SessionId, ...
                'CanUndo', obj.canUndo(), ...
                'CanRedo', obj.canRedo(), ...
                'LastAction', char(lastAction));
            flightdash.util.EventBus.publish('UndoStateChanged', ...
                flightdash.util.AppEventData(0, payload, obj.SessionId), obj.SessionId);
        end
    end
end
