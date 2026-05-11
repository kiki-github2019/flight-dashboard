classdef MoveROICommand < flightdash.command.Command
    % flightdash.command.MoveROICommand
    % Undoable movement for either graphics ROI objects or table-backed ROI rows.

    properties
        Mode char = 'object'
        ROI = []
        OldPosition double = []
        NewPosition double = []
        App = []
        ChannelIdx double = 0
        RoiIndex double = 0
        OldRow cell = {}
        NewRow cell = {}
    end

    methods
        function obj = MoveROICommand(sessionId, target, varargin)
            description = 'Move ROI';
            isRowCommand = numel(varargin) >= 5 && isnumeric(varargin{1}) && isnumeric(varargin{2}) && ...
                    iscell(varargin{3}) && iscell(varargin{4});
            if isRowCommand
                description = varargin{5};
            elseif numel(varargin) >= 3 && ~isempty(varargin{3})
                description = varargin{3};
            end

            obj@flightdash.command.Command(sessionId, description);

            if isRowCommand
                obj.Mode = 'row';
                obj.App = target;
                obj.ChannelIdx = double(varargin{1});
                obj.RoiIndex = double(varargin{2});
                obj.OldRow = varargin{3};
                obj.NewRow = varargin{4};
            else
                obj.Mode = 'object';
                obj.ROI = target;
                if numel(varargin) >= 1, obj.OldPosition = varargin{1}; end
                if numel(varargin) >= 2 && ~isempty(varargin{2})
                    obj.NewPosition = varargin{2};
                else
                    obj.NewPosition = flightdash.command.MoveROICommand.readPosition(target);
                end
            end
        end

        function execute(obj)
            if strcmp(obj.Mode, 'row')
                obj.applyRow(obj.NewRow);
            else
                obj.applyPosition(obj.NewPosition);
            end
        end

        function undo(obj)
            if strcmp(obj.Mode, 'row')
                obj.applyRow(obj.OldRow);
            else
                obj.applyPosition(obj.OldPosition);
            end
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
