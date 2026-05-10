classdef MoveROICommand < flightdash.command.Command
    %MOVEROICOMMAND Undoable edit for the dashboard's ROI row model.

    properties
        App = []
        ChannelIdx double = 0
        RoiIndex double = 0
        OldRow cell = {}
        NewRow cell = {}
    end

    methods
        function obj = MoveROICommand(sessionId, app, channelIdx, roiIndex, oldRow, newRow, description)
            if nargin < 7 || isempty(description)
                description = 'Move ROI';
            end
            obj@flightdash.command.Command(sessionId, description);
            if nargin >= 2, obj.App = app; end
            if nargin >= 3, obj.ChannelIdx = double(channelIdx); end
            if nargin >= 4, obj.RoiIndex = double(roiIndex); end
            if nargin >= 5, obj.OldRow = oldRow; end
            if nargin >= 6, obj.NewRow = newRow; end
        end

        function execute(obj)
            obj.applyRow(obj.NewRow);
        end

        function undo(obj)
            obj.applyRow(obj.OldRow);
        end
    end

    methods (Access = private)
        function applyRow(obj, row)
            if isempty(row) || isempty(obj.App) || ~isa(obj.App, 'handle') || ~isvalid(obj.App)
                return;
            end
            app = obj.App;
            fIdx = obj.ChannelIdx;
            roiIdx = obj.RoiIndex;
            try
                if fIdx < 1 || fIdx > numel(app.UI) || ...
                        ~isfield(app.UI(fIdx), 'roiRows') || ...
                        roiIdx < 1 || roiIdx > size(app.UI(fIdx).roiRows, 1)
                    return;
                end
                app.UI(fIdx).roiRows(roiIdx, :) = row;
                app.UI(fIdx).selectedRoiIdx = roiIdx;
                if ~isempty(app.RoiCtrl) && isvalid(app.RoiCtrl)
                    app.RoiCtrl.refreshTable(fIdx);
                    app.RoiCtrl.drawBands(fIdx);
                end
            catch ME
                try, app.logCaught(ME, 'Undo:MoveROI'); catch, end
            end
        end
    end
end
