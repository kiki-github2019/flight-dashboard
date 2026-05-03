classdef PanelToggleController < handle
    % flightdash.controller.PanelToggleController
    % - 패널 토글 + DebugMode + SyncToggle 이벤트 구독
    
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = PanelToggleController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('PanelToggled',      @(~,d) obj.onPanelToggled(d));
            obj.Listeners{end+1} = EB('DebugModeToggled',  @(~,d) obj.onDebugToggled(d));
            obj.Listeners{end+1} = EB('SyncToggled',       @(~,~) obj.onSyncToggled());
        end
        
        function onPanelToggled(obj, d)
            obj.App.togglePanel(d.ChannelIdx, d.Payload);
        end
        function onDebugToggled(obj, d)
            obj.App.toggleDebugMode(d.Payload);
        end
        function onSyncToggled(obj)
            obj.App.toggleSync();
        end
        
        % 호환 wrapper
        function toggle(obj, fIdx, pnlName), obj.App.togglePanel(fIdx, pnlName); end
        
        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
