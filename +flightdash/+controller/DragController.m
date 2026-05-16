classdef DragController < handle
    % flightdash.controller.DragController
    % - SplitterDragStarted 이벤트 구독
    %
    % [REFACTOR R5+4] Migrated to DashboardAppAdapter. Splitter
    % start/stop verbs (app.startPanelSplitterDrag,
    % app.startHISplitterDrag) still escape-hatch through
    % obj.Adapter.app() — they are dense UI-state mutators that have
    % no adapter API yet.

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
        Listeners cell = {}
    end

    properties
        HitThreshold double = 8
    end

    methods
        function obj = DragController(adapterOrApp)
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('DragController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            app = obj.Adapter.app();
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(app, eventName, callback);
            obj.Listeners{end+1} = EB('PanelSplitterDragStarted', @(~,d) obj.onPanelSplitterStart(d));
            obj.Listeners{end+1} = EB('SplitterDragStarted', @(~,d) obj.onSplitterStart(d));
        end

        function onPanelSplitterStart(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.startPanelSplitterDrag(d.ChannelIdx, d.Payload);
        end
        function onSplitterStart(obj, d)
            app = obj.Adapter.app();
            if ~app.isActiveSession(d), return; end
            app.startHISplitterDrag(d.ChannelIdx);
        end

        % 호환 wrapper
        function startSplitter(obj, fIdx)
            obj.Adapter.app().startHISplitterDrag(fIdx);
        end

        function [tf, target] = hitTest(obj, point)
            tf = false;
            target = [];
            try
                app = obj.Adapter.app();
                if isempty(app) || ~isvalid(app) || ~app.isActiveSession()
                    return;
                end
                point = double(point);
                if numel(point) < 2 || any(~isfinite(point(1:2))) || ...
                        ~isprop(app, 'UI') || isempty(app.UI)
                    return;
                end
                point = point(1:2);

                for fIdx = 1:min(2, numel(app.UI))
                    candidates = obj.splitterCandidates(fIdx);
                    for k = 1:numel(candidates)
                        c = candidates{k};
                        h = c.Handle;
                        if isempty(h) || ~isvalid(h) || ~obj.isVisible(h)
                            continue;
                        end
                        pos = obj.safePixelPosition(h);
                        if pos(3) <= 0 || pos(4) <= 0
                            continue;
                        end
                        hitArea = obj.expandHitArea(pos);
                        if point(1) >= hitArea(1) && point(1) <= hitArea(1) + hitArea(3) && ...
                                point(2) >= hitArea(2) && point(2) <= hitArea(2) + hitArea(4)
                            tf = true;
                            target = c;
                            target.Position = pos;
                            return;
                        end
                    end
                end
            catch ME
                obj.Adapter.logCaught(ME, 'SplitterHitTest');
                tf = false;
                target = [];
            end
        end

        function onButtonDown(obj, target, ~)
            try
                if isempty(target) || ~isstruct(target) || ~isfield(target, 'ChannelIdx')
                    return;
                end
                app = obj.Adapter.app();
                if isfield(target, 'IsPanel') && target.IsPanel
                    app.startPanelSplitterDrag(target.ChannelIdx, target.Kind);
                else
                    app.startHISplitterDrag(target.ChannelIdx);
                end
            catch ME
                obj.Adapter.logCaught(ME, 'SplitterHitTest:buttonDown');
            end
        end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
            obj.Listeners = {};
        end
    end

    methods (Access = private)
        function candidates = splitterCandidates(obj, fIdx)
            candidates = {};
            try
                app = obj.Adapter.app();
                ui = app.UI(fIdx);
                candidates = obj.addCandidate(candidates, ui, 'attMapSplitter', fIdx, 'att-map', true);
                candidates = obj.addCandidate(candidates, ui, 'mapInfoSplitter', fIdx, 'map-info', true);
                candidates = obj.addCandidate(candidates, ui, 'infoPlotSplitter', fIdx, 'info-plot', true);
                candidates = obj.addCandidate(candidates, ui, 'hiSplitter', fIdx, 'hi', false);
            catch
                candidates = {};
            end
        end

        function candidates = addCandidate(~, candidates, ui, fieldName, fIdx, kind, isPanel)
            try
                if isfield(ui, fieldName)
                    candidates{end+1} = struct( ...
                        'Handle', ui.(fieldName), ...
                        'ChannelIdx', fIdx, ...
                        'Kind', char(kind), ...
                        'IsPanel', logical(isPanel)); %#ok<AGROW>
                end
            catch
            end
        end

        function pos = safePixelPosition(~, h)
            pos = [0 0 0 0];
            try
                pos = getpixelposition(h, true);
            catch
                try
                    if isprop(h, 'Position')
                        pos = h.Position;
                    end
                catch
                end
            end
        end

        function hitArea = expandHitArea(obj, pos)
            pad = max(0, double(obj.HitThreshold));
            hitArea = [pos(1) - pad, pos(2) - pad, pos(3) + 2 * pad, pos(4) + 2 * pad];
        end

        function tf = isVisible(~, h)
            tf = true;
            try
                if isprop(h, 'Visible')
                    tf = strcmpi(char(h.Visible), 'on');
                end
            catch
                tf = true;
            end
        end
    end
end
