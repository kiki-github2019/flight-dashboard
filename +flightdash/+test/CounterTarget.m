classdef CounterTarget < handle
    %COUNTERTARGET Small mutable target used by undo/redo tests.

    properties
        Value double = 0
    end

    methods
        function obj = CounterTarget(value)
            if nargin >= 1
                obj.Value = value;
            end
        end
    end
end
