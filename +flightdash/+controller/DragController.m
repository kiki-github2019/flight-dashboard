classdef DragController < flightdash.controller.ControllerBase
    % flightdash.controller.DragController
    % - SplitterDragStarted 이벤트 구독
    %
    % [Phase 4 stabilization] Inherits from ControllerBase. EventBus
    % subscriptions go through trackListener so cleanup releases them
    % automatically. Splitter start verbs still escape-hatch through
    % obj.app() — they are dense UI mutators with no adapter API.

    properties
        HitThreshold double = 8
    end

    methods
        function obj = DragController(adapterOrApp)
            obj@flightdash.controller.ControllerBase( ...
                flightdash.controller.ControllerBase.normalizeAdapterInput( ...
                    adapterOrApp, 'DragController'));
            obj.subscribeEvents();
        end

        function subscribeEvents(obj)
            appHandle = obj.app();
            if isempty(appHandle), return; end
            EB = @(eventName, callback) ...
                flightdash.util.EventBus.subscribeForApp(appHandle, eventName, callback);
            obj.trackListener(EB('PanelSplitterDragStarted', @(~,d) obj.onPanelSplitterStart(d)));
            obj.trackListener(EB('SplitterDragStarted',     @(~,d) obj.onSplitterStart(d)));
        end

        function onPanelSplitterStart(obj, d)
            a = obj.app();
            if isempty(a) || ~a.isActiveSession(d), return; end
            a.startPanelSplitterDrag(d.ChannelIdx, d.Payload);
        end
        function onSplitterStart(obj, d)
            a = obj.app();
            if isempty(a) || ~a.isActiveSession(d), return; end
            a.startHISplitterDrag(d.ChannelIdx);
        end

        % 호환 wrapper
        function startSplitter(obj, fIdx)
            a = obj.app(); if ~isempty(a), a.startHISplitterDrag(fIdx); end
        end

        function [tf, target] = hitTest(obj, point)
            % Splitter-specific override of ControllerBase.hitTest.
            tf = false;
            target = [];
            try
                a = obj.app();
                if isempty(a) || ~isvalid(a) || ~a.isActiveSession()
                    return;
                end
                point = double(point);
                if numel(point) < 2 || any(~isfinite(point(1:2))) || ...
                        ~isprop(a, 'UI') || isempty(a.UI)
                    return;
                end
                point = point(1:2);

                for fIdx = 1:min(2, numel(a.UI))
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
                obj.logCaught(ME, 'SplitterHitTest');
                tf = false;
                target = [];
            end
        end

        function onButtonDown(obj, target, ~)
            % Splitter button-down — overrides ControllerBase.onButtonDown.
            try
                if isempty(target) || ~isstruct(target) || ~isfield(target, 'ChannelIdx')
                    return;
                end
                a = obj.app();
                if isfield(target, 'IsPanel') && target.IsPanel
                    a.startPanelSplitterDrag(target.ChannelIdx, target.Kind);
                else
                    a.startHISplitterDrag(target.ChannelIdx);
                end
            catch ME
                obj.logCaught(ME, 'SplitterHitTest:buttonDown');
            end
        end
    end

    methods (Access = private)
        function candidates = splitterCandidates(obj, fIdx)
            candidates = {};
            try
                a = obj.app();
                ui = a.UI(fIdx);
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
