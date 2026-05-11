classdef MoveMarkerCommand < flightdash.command.Command
    % flightdash.command.MoveMarkerCommand
    % Undoable movement for graphics objects exposing Position.

    properties
        Marker
        OldPosition double = []
        NewPosition double = []
    end

    methods
        function obj = MoveMarkerCommand(sessionId, marker, oldPos, newPos, description)
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
        end

        function execute(obj)
            obj.applyPosition(obj.NewPosition);
        end

        function undo(obj)
            obj.applyPosition(obj.OldPosition);
        end
    end

    methods (Access = private)
        function applyPosition(obj, pos)
            if isempty(pos) || ~flightdash.command.MoveMarkerCommand.isValidHandle(obj.Marker)
                return;
            end
            try
                cur = obj.Marker.Position;
                n = min(numel(cur), numel(pos));
                cur(1:n) = pos(1:n);
                obj.Marker.Position = cur;
            catch
            end
        end
    end

    methods (Static, Access = private)
        function pos = readPosition(marker)
            pos = [];
            try
                if flightdash.command.MoveMarkerCommand.isValidHandle(marker) && isprop(marker, 'Position')
                    pos = marker.Position;
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
