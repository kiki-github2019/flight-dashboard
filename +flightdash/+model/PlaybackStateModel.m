classdef PlaybackStateModel < handle
    % flightdash.model.PlaybackStateModel
    % Per-channel guards and coalesced frame request state.

    properties (SetAccess = private)
        IsUpdating logical = false
        InGoToFrame logical = false
        IsDecoding logical = false
        PendingFrame double = NaN
        PendingMode char = ''
    end

    methods
        function setUpdating(obj, state)
            obj.IsUpdating = logical(state);
        end

        function setGoToFrame(obj, state)
            obj.InGoToFrame = logical(state);
        end

        function setDecoding(obj, state)
            obj.IsDecoding = logical(state);
        end

        function setPendingRequest(obj, frameNo, mode)
            obj.PendingFrame = double(frameNo);
            if nargin < 3 || isempty(mode)
                mode = '';
            end
            obj.PendingMode = char(mode);
        end

        function [hasPending, frameNo, mode] = peekPendingRequest(obj)
            hasPending = ~isnan(obj.PendingFrame);
            frameNo = obj.PendingFrame;
            mode = obj.PendingMode;
        end

        function [hasPending, frameNo, mode] = consumePendingRequest(obj)
            [hasPending, frameNo, mode] = obj.peekPendingRequest();
            obj.clearPendingRequest();
        end

        function clearPendingRequest(obj)
            obj.PendingFrame = NaN;
            obj.PendingMode = '';
        end

        function reset(obj)
            obj.IsUpdating = false;
            obj.InGoToFrame = false;
            obj.IsDecoding = false;
            obj.clearPendingRequest();
        end
    end
end
