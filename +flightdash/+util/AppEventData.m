classdef AppEventData < event.EventData
    % flightdash.util.AppEventData
    % - EventBus를 통해 전달될 데이터 페이로드 객체
    % - ChannelIdx: 채널 인덱스 (1 또는 2, 비채널 이벤트는 0)
    % - Payload: 임의 데이터 (matlab event struct, scalar, struct 등)
    
    properties
        ChannelIdx
        Payload
    end
    
    methods
        function obj = AppEventData(fIdx, payloadData)
            if nargin < 1, fIdx = 0; end
            if nargin < 2, payloadData = []; end
            obj.ChannelIdx = fIdx;
            obj.Payload = payloadData;
        end
    end
end
