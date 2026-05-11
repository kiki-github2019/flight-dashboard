classdef RoiRowsCommand < flightdash.command.Command
    % flightdash.command.RoiRowsCommand
    % Undoable create/delete operation for table-backed ROI rows.

    properties
        RoiController
        ChannelIdx double = 0
        RowIndex double = NaN
        RowData cell = {}
        Operation char = 'create'
    end

    methods
        function obj = RoiRowsCommand(sessionId, roiController, channelIdx, rowIndex, rowData, operation, description)
            if nargin < 7 || isempty(description)
                description = 'Modify ROI';
            end
            obj@flightdash.command.Command(sessionId, description);
            obj.RoiController = roiController;
            obj.ChannelIdx = channelIdx;
            obj.RowIndex = rowIndex;
            obj.RowData = rowData;
            if nargin >= 6 && ~isempty(operation)
                obj.Operation = char(operation);
            end
        end

        function execute(obj)
            switch char(obj.Operation)
                case 'create'
                    obj.insertRow();
                case 'delete'
                    obj.removeRow();
            end
        end

        function undo(obj)
            switch char(obj.Operation)
                case 'create'
                    obj.removeRow();
                case 'delete'
                    obj.insertRow();
            end
        end
    end

    methods (Access = private)
        function insertRow(obj)
            try
                if obj.hasController()
                    obj.RoiController.insertRoiRow(obj.ChannelIdx, obj.RowData, obj.RowIndex);
                end
            catch
            end
        end

        function removeRow(obj)
            try
                if obj.hasController()
                    obj.RoiController.removeRoiRowAt(obj.ChannelIdx, obj.RowIndex);
                end
            catch
            end
        end

        function tf = hasController(obj)
            tf = false;
            try
                tf = ~isempty(obj.RoiController) && isvalid(obj.RoiController) && ...
                    ismethod(obj.RoiController, 'insertRoiRow') && ...
                    ismethod(obj.RoiController, 'removeRoiRowAt');
            catch
                tf = false;
            end
        end
    end
end
