classdef RouterTestController < handle
    %ROUTERTESTCONTROLLER Minimal controller double for router diagnostics.

    properties
        MotionCount double = 0
        StopCount double = 0
        ThrowOnMotion logical = false
    end

    methods
        function handleDragMotion(obj)
            obj.MotionCount = obj.MotionCount + 1;
            if obj.ThrowOnMotion
                error('flightdash:RouterTestController:Motion', 'Synthetic motion failure');
            end
        end

        function stopDrag(obj)
            obj.StopCount = obj.StopCount + 1;
        end
    end
end
