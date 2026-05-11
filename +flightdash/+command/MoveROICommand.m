classdef MoveROICommand < flightdash.command.Command
    % flightdash.command.MoveROICommand
    % Undoable movement for ROI objects exposing Position.

    properties
        ROI
        OldPosition double = []
        NewPosition double = []
    end

    methods
        function obj = MoveROICommand(sessionId, roi, oldPos, newPos, description)
            if nargin < 5 || isempty(description)
                description = 'Move ROI';
            end
            obj@flightdash.command.Command(sessionId, description);
            obj.ROI = roi;
            obj.OldPosition = oldPos;
            if nargin >= 4 && ~isempty(newPos)
                obj.NewPosition = newPos;
            else
                obj.NewPosition = flightdash.command.MoveROICommand.readPosition(roi);
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
            if isempty(pos) || ~flightdash.command.MoveROICommand.isValidHandle(obj.ROI)
                return;
            end
            try
                obj.ROI.Position = pos;
            catch
            end
        end
    end

    methods (Static, Access = private)
        function pos = readPosition(roi)
            pos = [];
            try
                if flightdash.command.MoveROICommand.isValidHandle(roi) && isprop(roi, 'Position')
                    pos = roi.Position;
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
