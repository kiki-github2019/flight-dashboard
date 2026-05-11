classdef DragController < handle
    % flightdash.controller.DragController
    % - SplitterDragStarted 이벤트 구독
    
    properties (Access = private)
        App
        Listeners cell = {}
    end

    properties
        HitThreshold double = 8
    end
    
    methods
        function obj = DragController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @(eventName, callback) flightdash.util.EventBus.subscribeForApp(obj.App, eventName, callback);
            obj.Listeners{end+1} = EB('PanelSplitterDragStarted', @(~,d) obj.onPanelSplitterStart(d));
            obj.Listeners{end+1} = EB('SplitterDragStarted', @(~,d) obj.onSplitterStart(d));
        end
        
        function onPanelSplitterStart(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.startPanelSplitterDrag(d.ChannelIdx, d.Payload);
        end
        function onSplitterStart(obj, d)
            if ~obj.App.isActiveSession(d), return; end
            obj.App.startHISplitterDrag(d.ChannelIdx);
        end
        
        % 호환 wrapper
        function startSplitter(obj, fIdx), obj.App.startHISplitterDrag(fIdx); end

        function [tf, target] = hitTest(obj, point)
            tf = false;
            target = [];
            try
                app = obj.App;
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
                try, obj.App.logCaught(ME, 'SplitterHitTest'); catch, end
                tf = false;
                target = [];
            end
        end

        function onButtonDown(obj, target, ~)
            try
                if isempty(target) || ~isstruct(target) || ~isfield(target, 'ChannelIdx')
                    return;
                end
                if isfield(target, 'IsPanel') && target.IsPanel
                    obj.App.startPanelSplitterDrag(target.ChannelIdx, target.Kind);
                else
                    obj.App.startHISplitterDrag(target.ChannelIdx);
                end
            catch ME
                try, obj.App.logCaught(ME, 'SplitterHitTest:buttonDown'); catch, end
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
                ui = obj.App.UI(fIdx);
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
