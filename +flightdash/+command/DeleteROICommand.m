classdef DeleteROICommand < flightdash.command.Command
    % flightdash.command.DeleteROICommand
    % Undoable ROI unregistration. This command assumes removeROI does not
    % delete the graphics object; if it does, callers must use a recreating
    % command that stores ROI construction state.

    properties
        ROICtrl
        DeletedROI
        OriginalIndex double = NaN
    end

    methods
        function obj = DeleteROICommand(sessionId, roiCtrl, roiToDelete, description)
            if nargin < 4 || isempty(description)
                description = 'Delete ROI';
            end
            obj@flightdash.command.Command(sessionId, description);
            obj.ROICtrl = roiCtrl;
            obj.DeletedROI = roiToDelete;
            obj.OriginalIndex = obj.lookupIndex(roiToDelete);
        end

        function execute(obj)
            if obj.isUsableROI()
                obj.callController('removeROI', obj.DeletedROI);
            end
        end

        function undo(obj)
            if ~obj.isUsableROI()
                return;
            end
            try
                if ~isempty(obj.ROICtrl) && isvalid(obj.ROICtrl) && ...
                        ismethod(obj.ROICtrl, 'insertROIAt') && ~isnan(obj.OriginalIndex)
                    obj.ROICtrl.insertROIAt(obj.DeletedROI, obj.OriginalIndex);
                else
                    obj.callController('addROI', obj.DeletedROI);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function idx = lookupIndex(obj, roi)
            idx = NaN;
            try
                if ~isempty(obj.ROICtrl) && isvalid(obj.ROICtrl) && ismethod(obj.ROICtrl, 'getROIIndex')
                    idx = obj.ROICtrl.getROIIndex(roi);
                end
            catch
                idx = NaN;
            end
        end

        function tf = isUsableROI(obj)
            tf = flightdash.command.DeleteROICommand.isValidHandle(obj.DeletedROI);
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
