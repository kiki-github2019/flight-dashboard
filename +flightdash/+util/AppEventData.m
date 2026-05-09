classdef AppEventData < event.EventData
    % flightdash.util.AppEventData
    % - EventBus를 통해 전달될 데이터 페이로드 객체
    % - ChannelIdx: 채널 인덱스 (1 또는 2, 비채널 이벤트는 0)
    % - Payload:    임의 데이터 (matlab event struct, scalar, struct 등)
    % - SessionId:  [PHASE 4 review] 발행 세션 식별자.
    %               '' 이면 broadcast (legacy / standalone) — 모든 listener 처리.
    %               'SESS_xxx' 이면 해당 세션의 controller만 처리.
    %               View publish 시점에 publisher가 자기 dashboard의
    %               ActiveSessionId 를 채워 broadcast 누수를 방지한다.

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
