classdef CounterCommand < flightdash.command.Command
    %COUNTERCOMMAND Minimal undoable command used by stabilization tests.

    properties
        Target
        OldValue double = 0
        NewValue double = 0
    end

    methods
        function obj = CounterCommand(sessionId, target, oldValue, newValue, description)
            obj@flightdash.command.Command(sessionId, description);
            obj.Target = target;
            obj.OldValue = oldValue;
            obj.NewValue = newValue;
        end

        function execute(obj)
            if ~isempty(obj.Target) && isvalid(obj.Target)
                obj.Target.Value = obj.NewValue;
            end
        end

        function undo(obj)
            if ~isempty(obj.Target) && isvalid(obj.Target)
                obj.Target.Value = obj.OldValue;
            end
        end
    end
end
