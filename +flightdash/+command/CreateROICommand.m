classdef CreateROICommand < flightdash.command.Command
    % flightdash.command.CreateROICommand
    % Undoable ROI registration. The controller is expected to add/remove
    % without destroying the ROI object.

    properties
        ROICtrl
        NewROI
    end

    methods
        function obj = CreateROICommand(sessionId, roiCtrl, newROI, description)
            if nargin < 4 || isempty(description)
                description = 'Create ROI';
            end
            obj@flightdash.command.Command(sessionId, description);
            obj.ROICtrl = roiCtrl;
            obj.NewROI = newROI;
        end

        function execute(obj)
            if obj.isUsableROI()
                obj.callController('addROI', obj.NewROI);
            end
        end

        function undo(obj)
            if obj.isUsableROI()
                obj.callController('removeROI', obj.NewROI);
            end
        end
    end

    methods (Access = private)
        function tf = isUsableROI(obj)
            tf = flightdash.command.CreateROICommand.isValidHandle(obj.NewROI);
        end

        function callController(obj, methodName, roi)
            try
                if ~isempty(obj.ROICtrl) && isvalid(obj.ROICtrl) && ismethod(obj.ROICtrl, methodName)
                    feval(methodName, obj.ROICtrl, roi);
                end
            catch
            end
        end
    end

    methods (Static, Access = private)
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
