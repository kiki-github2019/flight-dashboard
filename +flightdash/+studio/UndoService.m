classdef UndoService < handle
    % flightdash.studio.UndoService
    % Per-session undo/redo stack manager.

    properties
        SessionId char = ''
        UndoStack cell = {}
        RedoStack cell = {}
        MaxDepth double = 100
        LastCommand = []
        StatusCallback = []
    end

    events
        StateChanged
    end

    methods
        function obj = UndoService(sessionId)
            if nargin >= 1 && ~isempty(sessionId)
                obj.SessionId = char(sessionId);
            end
        end

        function push(obj, command, executeNow)
            if nargin < 3 || isempty(executeNow)
                executeNow = false;
            end
            if ~obj.accepts(command)
                return;
            end
            try
                if executeNow
                    command.execute();
                end
                obj.UndoStack{end+1} = command;
                obj.trimUndoStack();
                obj.RedoStack = {};
                obj.LastCommand = command;
                obj.notifyStateChanged('push', command);
            catch ME
                flightdash.util.ErrorLog.log(ME, 'UndoService:push', false);
            end
        end

        function command = undo(obj)
            command = [];
            if ~obj.canUndo()
                obj.notifyStateChanged('undo-empty', []);
                return;
            end
            command = obj.UndoStack{end};
            obj.UndoStack(end) = [];
            try
                command.undo();
                obj.RedoStack{end+1} = command;
                obj.LastCommand = command;
            catch ME
                flightdash.util.ErrorLog.log(ME, 'UndoService:undo', false);
            end
            obj.notifyStateChanged('undo', command);
        end

        function command = redo(obj)
            command = [];
            if ~obj.canRedo()
                obj.notifyStateChanged('redo-empty', []);
                return;
            end
            command = obj.RedoStack{end};
            obj.RedoStack(end) = [];
            try
                command.redo();
                obj.UndoStack{end+1} = command;
                obj.LastCommand = command;
            catch ME
                flightdash.util.ErrorLog.log(ME, 'UndoService:redo', false);
            end
            obj.notifyStateChanged('redo', command);
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
            obj.LastCommand = [];
            obj.notifyStateChanged('clear', []);
        end
    end

    methods (Access = private)
        function tf = accepts(obj, command)
            tf = false;
            try
                tf = ~isempty(command) && isa(command, 'flightdash.command.Command') && ...
                    (isempty(obj.SessionId) || command.belongsToSession(obj.SessionId));
            catch
                tf = false;
            end
        end

        function trimUndoStack(obj)
            if isempty(obj.MaxDepth) || obj.MaxDepth <= 0
                return;
            end
            overflow = numel(obj.UndoStack) - obj.MaxDepth;
            if overflow > 0
                obj.UndoStack(1:overflow) = [];
            end
        end

        function notifyStateChanged(obj, action, command)
            undoDesc = obj.topDescription(obj.UndoStack);
            redoDesc = obj.topDescription(obj.RedoStack);
            data = flightdash.studio.UndoStateChangedData( ...
                obj.SessionId, action, command, obj.canUndo(), obj.canRedo(), undoDesc, redoDesc);
            try
                notify(obj, 'StateChanged', data);
            catch
            end
            obj.publishEventBusState(action, command, undoDesc, redoDesc);
            obj.updateStatus(action, command);
        end

        function publishEventBusState(obj, action, command, undoDesc, redoDesc)
            try
                payload = struct('SessionId', obj.SessionId, ...
                    'Action', char(action), ...
                    'Command', command, ...
                    'CanUndo', obj.canUndo(), ...
                    'CanRedo', obj.canRedo(), ...
                    'UndoDescription', char(undoDesc), ...
                    'RedoDescription', char(redoDesc));
                flightdash.util.EventBus.publish('UndoStateChanged', ...
                    flightdash.util.AppEventData(0, payload, obj.SessionId), obj.SessionId);
            catch
            end
        end

        function updateStatus(obj, action, command)
            try
                if isempty(obj.StatusCallback) || ~isa(obj.StatusCallback, 'function_handle')
                    return;
                end
                switch char(action)
                    case 'push'
                        prefix = 'Undo available';
                    case 'undo'
                        prefix = 'Undo';
                    case 'redo'
                        prefix = 'Redo';
                    otherwise
                        return;
                end
                desc = '';
                if ~isempty(command) && isprop(command, 'Description')
                    desc = char(command.Description);
                end
                if isempty(desc)
                    msg = prefix;
                else
                    msg = sprintf('%s: %s', prefix, desc);
                end
                obj.StatusCallback(msg, 2.5);
            catch
            end
        end

        function desc = topDescription(~, stack)
            desc = '';
            try
                if ~isempty(stack)
                    cmd = stack{end};
                    if ~isempty(cmd) && isprop(cmd, 'Description')
                        desc = char(cmd.Description);
                    end
                end
            catch
                desc = '';
            end
        end
    end
end
