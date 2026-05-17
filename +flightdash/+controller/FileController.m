classdef FileController < flightdash.controller.ControllerBase
    % flightdash.controller.FileController
    % - 파일 로드 이벤트 구독: FlightFileRequested, AviFileRequested, CoastFileRequested
    %
    % [Phase 4 stabilization] Inherits from ControllerBase so listener
    % tracking + cleanup use the shared `trackListener` / `cleanup`
    % surface. EventBus subscriptions are tracked so dashboard
    % teardown reliably deletes them.

    methods
        function obj = FileController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.ControllerBase.normalizeAdapterInput( ...
                    adapterOrApp, 'FileController'));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            appHandle = obj.app();
            if isempty(appHandle), return; end
            EB = @(eventName, callback) ...
                flightdash.util.EventBus.subscribeForApp(appHandle, eventName, callback);
            obj.trackListener(EB('FlightFileRequested',   @(~,d) obj.onFlightFile(d)));
            obj.trackListener(EB('AviFileRequested',      @(~,d) obj.onAviFile(d)));
            obj.trackListener(EB('CoastFileRequested',    @(~,~) obj.onCoastFile()));
            obj.trackListener(EB('ConfigExportRequested', @(~,~) obj.onConfigExport()));
            obj.trackListener(EB('ConfigImportRequested', @(~,~) obj.onConfigImport()));
        end

        function onFlightFile(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.handleFlightFile(d.ChannelIdx);
        end
        function onAviFile(obj, d)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(d), return; end
            app.loadAviFile(d.ChannelIdx);
        end
        function onCoastFile(obj)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            app.handleCoastFile();
        end
        function onConfigExport(obj)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            app.exportConfigInteractive();
        end
        function onConfigImport(obj)
            app = obj.app();
            if isempty(app) || ~app.isActiveSession(), return; end
            app.importConfigInteractive();
        end

        % 호환 wrapper (기존 직접 호출 호환)
        function loadAvi(obj, fIdx),    appHandle = obj.app(); if ~isempty(appHandle), appHandle.loadAviFile(fIdx); end, end
        function loadFlight(obj, fIdx), appHandle = obj.app(); if ~isempty(appHandle), appHandle.handleFlightFile(fIdx); end, end
    end

end
