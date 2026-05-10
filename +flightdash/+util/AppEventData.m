classdef AppEventData < event.EventData
    % flightdash.util.AppEventData
    % EventBus payload wrapper.
    %
    % ChannelIdx:
    %   1 or 2 for channel-specific events, 0 for non-channel events.
    %
    % Payload:
    %   Arbitrary event payload such as MATLAB UI event data, scalar values,
    %   strings, or structs.
    %
    % SessionId:
    %   Empty means legacy broadcast. In Studio mode, EventBus.publish()
    %   fills an empty SessionId from SessionScope when an active workspace
    %   session exists.

    properties
        ChannelIdx
        Payload
        SessionId
    end

    methods
        function obj = AppEventData(fIdx, payloadData, sessionId)
            if nargin < 1, fIdx = 0; end
            if nargin < 2, payloadData = []; end
            if nargin < 3, sessionId = ''; end
            obj.ChannelIdx = fIdx;
            obj.Payload    = payloadData;
            obj.SessionId  = char(sessionId);
        end
    end
end
