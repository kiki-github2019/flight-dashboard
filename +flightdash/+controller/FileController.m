classdef FileController < handle
    % flightdash.controller.FileController
    % - 파일 로드 이벤트 구독: FlightFileRequested, AviFileRequested, CoastFileRequested
    %
    % [REFACTOR R5+6] Migrated to DashboardAppAdapter. Pure event-relay
    % controller — every callback forwards to an app verb
    % (handleFlightFile / loadAviFile / handleCoastFile /
    % exportConfigInteractive / importConfigInteractive) that has no
    % adapter API yet. Bodies uniformly escape-hatch via
    % obj.Adapter.app().

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
        Listeners cell = {}
    end

    methods
        function obj = FileController(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('FileController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            app = obj.Adapter.app();
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(app, eventName, callback);
            obj.Listeners{end+1} = EB('FlightFileRequested',   @(~,d) obj.onFlightFile(d));
            obj.Listeners{end+1} = EB('AviFileRequested',      @(~,d) obj.onAviFile(d));
            obj.Listeners{end+1} = EB('CoastFileRequested',    @(~,~) obj.onCoastFile());
            obj.Listeners{end+1} = EB('ConfigExportRequested', @(~,~) obj.onConfigExport());
            obj.Listeners{end+1} = EB('ConfigImportRequested', @(~,~) obj.onConfigImport());
        end

        function onFlightFile(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.handleFlightFile(d.ChannelIdx);
        end
        function onAviFile(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.loadAviFile(d.ChannelIdx);
        end
        function onCoastFile(obj)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            app.handleCoastFile();
        end
        function onConfigExport(obj)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            app.exportConfigInteractive();
        end
        function onConfigImport(obj)
            app = obj.Adapter.app();
            if ~app.isActiveSession(), return; end
            app.importConfigInteractive();
        end

        % 호환 wrapper (기존 직접 호출 호환)
        function loadAvi(obj, fIdx),    obj.Adapter.app().loadAviFile(fIdx); end
        function loadFlight(obj, fIdx), obj.Adapter.app().handleFlightFile(fIdx); end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end
end
