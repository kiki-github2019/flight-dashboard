classdef ChannelUiFacade < handle
    %CHANNELUIFACADE Small per-channel UI write facade for migration.
    %
    %   Wraps narrow, frequently written handles. It reduces direct
    %   app.UI(fIdx) writes without taking ownership of layout creation.

    properties (Access = private)
        App
        FIdx double = 1
    end

    methods
        function obj = ChannelUiFacade(app, fIdx)
            obj.App = app;
            if nargin >= 2 && ~isempty(fIdx) && isnumeric(fIdx)
                obj.FIdx = max(1, round(double(fIdx(1))));
            end
        end

        function setSpinnerValue(obj, value)
            try
                [ok, h] = obj.handle('spinner');
                if ok && abs(h.Value - value) > eps
                    h.Value = value;
                end
            catch ME
                obj.log(ME, 'ChannelUiFacade:setSpinnerValue');
            end
        end

        function setTimelineValue(obj, value)
            try
                [ok, h] = obj.handle('timeLine');
                if ok
                    h.Value = value;
                end
            catch ME
                obj.log(ME, 'ChannelUiFacade:setTimelineValue');
            end
        end

        function setCurrentTimeText(obj, currTime)
            try
                [ok, h] = obj.handle('currentTimeLabel');
                if ok
                    h.Text = sprintf('%.3f s', currTime);
                end
            catch ME
                obj.log(ME, 'ChannelUiFacade:setCurrentTimeText');
            end
        end

        function setAltitudeMarker(obj, currTime, altitude)
            try
                [ok, h] = obj.handle('hAltMarker');
                if ok
                    set(h, 'XData', currTime, 'YData', altitude);
                end
            catch ME
                obj.log(ME, 'ChannelUiFacade:setAltitudeMarker');
            end
        end

        function setMapPath(obj, lon, lat)
            try
                [ok, h] = obj.handle('hMapPath');
                if ok
                    set(h, 'XData', lon, 'YData', lat);
                end
            catch ME
                obj.log(ME, 'ChannelUiFacade:setMapPath');
            end
        end

        function setMapPlaneMatrix(obj, matrixValue)
            try
                [ok, h] = obj.handle('hgMapPlane');
                if ok
                    set(h, 'Matrix', matrixValue);
                end
            catch ME
                obj.log(ME, 'ChannelUiFacade:setMapPlaneMatrix');
            end
        end
    end

    methods (Access = private)
        function [ok, h] = handle(obj, fieldName)
            ok = false;
            h = [];
            try
                if isempty(obj.App) || ~isprop(obj.App, 'UI') || numel(obj.App.UI) < obj.FIdx
                    return;
                end
                ui = obj.App.UI(obj.FIdx);
                if ~isfield(ui, fieldName)
                    return;
                end
                h = ui.(fieldName);
                ok = ~isempty(h) && isvalid(h);
            catch ME
                obj.log(ME, ['ChannelUiFacade:handle:' fieldName]);
            end
        end

        function log(obj, ME, context)
            try
                if ~isempty(obj.App) && ismethod(obj.App, 'logCaught')
                    obj.App.logCaught(ME, context);
                end
            catch
            end
        end
    end
end
