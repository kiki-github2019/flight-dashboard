classdef FileController < handle
    % flightdash.controller.FileController
    % - 파일 로드 이벤트 구독: FlightFileRequested, AviFileRequested, CoastFileRequested
    
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = FileController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(obj.App, eventName, callback);
            obj.Listeners{end+1} = EB('FlightFileRequested', @(~,d) obj.onFlightFile(d));
            obj.Listeners{end+1} = EB('AviFileRequested',    @(~,d) obj.onAviFile(d));
            obj.Listeners{end+1} = EB('CoastFileRequested',  @(~,~) obj.onCoastFile());
            obj.Listeners{end+1} = EB('ConfigExportRequested', @(~,~) obj.onConfigExport());
            obj.Listeners{end+1} = EB('ConfigImportRequested', @(~,~) obj.onConfigImport());
        end
        
        function onFlightFile(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.handleFlightFile(d.ChannelIdx);
        end
        function onAviFile(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.loadAviFile(d.ChannelIdx);
        end
        function onCoastFile(obj)
            if ~obj.App.isActiveSession(), return; end
            obj.App.handleCoastFile();
        end
        function onConfigExport(obj)
            if ~obj.App.isActiveSession(), return; end
            obj.App.exportConfigInteractive();
        end
        function onConfigImport(obj)
            if ~obj.App.isActiveSession(), return; end
            obj.App.importConfigInteractive();
        end
        
        % 호환 wrapper (기존 직접 호출 호환)
        function loadAvi(obj, fIdx),    obj.App.loadAviFile(fIdx); end
        function loadFlight(obj, fIdx), obj.App.handleFlightFile(fIdx); end
        
        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
