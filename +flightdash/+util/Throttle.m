classdef Throttle < handle
    % flightdash.util.Throttle
    % - 시간 기반 hit 게이트 (이름표 + 채널별 슬롯)
    % - 기존 throttleHit과 100% 호환되는 입력/출력
    %
    % 사용 예:
    %   t = flightdash.util.Throttle();
    %   if t.hit('slider', fIdx, 0.03), return; end   % 30ms 이내 재진입 차단
    %
    % 또는 싱글톤 인스턴스로 전역 사용:
    %   if flightdash.util.Throttle.instance().hit('video', 1, 0.05), return; end
    %
    % 슬롯은 (slotName, fIdx) 키 조합으로 자동 생성/재사용됩니다.
    
    properties (Access = private)
        % slotName -> {tic_handle_per_channel}
        Slots   containers.Map
    end
    
    methods
        function obj = Throttle()
            obj.Slots = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end
        
        function tf = hit(obj, slotName, fIdx, limitS)
            % true 반환 = throttle 발생, 호출자는 즉시 return
            % false 반환 = 통과, slot에 현재 시각 기록
            if ~obj.Slots.isKey(slotName)
                obj.Slots(slotName) = {uint64(0), uint64(0)};
            end
            slot = obj.Slots(slotName);
            % 채널 수 확장 보호 - 중간 인덱스도 모두 uint64(0)로 명시 초기화
            if numel(slot) < fIdx
                for k = (numel(slot)+1):fIdx
                    slot{k} = uint64(0);
                end
            end
            t0 = slot{fIdx};
            if t0 ~= 0 && toc(t0) < limitS
                tf = true; return;
            end
            slot{fIdx} = tic;
            obj.Slots(slotName) = slot;
            tf = false;
        end
        
        function reset(obj, slotName, fIdx)
            % 특정 슬롯/채널 reset (선택사항)
            if nargin < 2 || isempty(slotName)
                obj.Slots = containers.Map('KeyType', 'char', 'ValueType', 'any');
                return;
            end
            if ~obj.Slots.isKey(slotName), return; end
            if nargin < 3
                obj.Slots.remove(slotName);
                return;
            end
            slot = obj.Slots(slotName);
            if numel(slot) >= fIdx
                slot{fIdx} = uint64(0);
                obj.Slots(slotName) = slot;
            end
        end
    end
    
    methods (Static)
        function inst = instance()
            persistent singleton
            if isempty(singleton) || ~isvalid(singleton)
                singleton = flightdash.util.Throttle();
            end
            inst = singleton;
        end
    end
end
