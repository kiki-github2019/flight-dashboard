classdef MoveMarkerCommand < flightdash.command.Command
    % flightdash.command.MoveMarkerCommand
    % Undoable movement for graphics objects exposing Position.

    properties
        Marker
        OldPosition double = []
        NewPosition double = []
        Dashboard = []
        ChannelIdx double = NaN
        OldIndex double = NaN
        NewIndex double = NaN
    end

    methods
        function obj = MoveMarkerCommand(sessionId, marker, oldPos, newPos, description, dashboard, channelIdx, oldIndex, newIndex)
            if nargin < 5 || isempty(description)
                description = 'Move Marker';
            end
            obj@flightdash.command.Command(sessionId, description);
            obj.Marker = marker;
            obj.OldPosition = oldPos;
            if nargin >= 4 && ~isempty(newPos)
                obj.NewPosition = newPos;
            else
                obj.NewPosition = flightdash.command.MoveMarkerCommand.readPosition(marker);
            end
            if nargin >= 6, obj.Dashboard = dashboard; end
            if nargin >= 7 && ~isempty(channelIdx), obj.ChannelIdx = channelIdx; end
            if nargin >= 8 && ~isempty(oldIndex), obj.OldIndex = oldIndex; end
            if nargin >= 9 && ~isempty(newIndex), obj.NewIndex = newIndex; end
        end

        function execute(obj)
            obj.applyState(obj.NewPosition, obj.NewIndex);
        end

        function undo(obj)
            obj.applyState(obj.OldPosition, obj.OldIndex);
        end
    end

    methods (Access = private)
        function applyState(obj, pos, idx)
            if ~obj.applyDashboardIndex(idx)
                obj.applyPosition(pos);
            end
        end

        function tf = applyDashboardIndex(obj, idx)
            tf = false;
            try
                if isempty(idx) || isnan(idx) || isempty(obj.Dashboard) || ~isvalid(obj.Dashboard)
                    return;
                end
                fIdx = obj.ChannelIdx;
                if isempty(fIdx) || isnan(fIdx) || fIdx < 1
                    return;
                end
                idx = round(idx);
                if ismethod(obj.Dashboard, 'updateMarkersOnly')
                    obj.Dashboard.updateMarkersOnly(fIdx, idx);
                    tf = true;
                end
            catch
                tf = false;
            end
        end

        function applyPosition(obj, pos)
            if isempty(pos) || ~flightdash.command.MoveMarkerCommand.isValidHandle(obj.Marker)
                return;
            end
            try
                if isprop(obj.Marker, 'Position')
                    cur = obj.Marker.Position;
                    n = min(numel(cur), numel(pos));
                    cur(1:n) = pos(1:n);
                    obj.Marker.Position = cur;
                elseif isprop(obj.Marker, 'Value')
                    obj.Marker.Value = pos(1);
                elseif isprop(obj.Marker, 'XData') && isprop(obj.Marker, 'YData') && numel(pos) >= 2
                    obj.Marker.XData = pos(1);
                    obj.Marker.YData = pos(2);
                end
            catch
            end
        end
    end

    methods (Static, Access = private)
        function pos = readPosition(marker)
            pos = [];
            try
                if ~flightdash.command.MoveMarkerCommand.isValidHandle(marker)
                    return;
                end
                if isprop(marker, 'Position')
                    pos = marker.Position;
                elseif isprop(marker, 'Value')
                    pos = marker.Value;
                elseif isprop(marker, 'XData') && isprop(marker, 'YData')
                    x = marker.XData;
                    y = marker.YData;
                    if ~isempty(x) && ~isempty(y)
                        pos = [x(1), y(1)];
                    end
                end
            catch
                pos = [];
            end
        end

        function tf = isValidHandle(h)
            tf = false;
            try
                tf = ~isempty(h) && isvalid(h);
            catch
                tf = false;
            end
        end
    end
end
