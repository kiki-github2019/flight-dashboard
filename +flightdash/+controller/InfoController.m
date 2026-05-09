classdef InfoController < handle
    % flightdash.controller.InfoController
    % Owns current-info table interactions: row reorder, drag-to-reorder.

    properties (Access = private)
        App
    end

    properties (SetAccess = private)
        IsDraggingInfoRow logical = false
        InfoDragFIdx      double  = 0
        InfoDragSourceRow double  = 0
    end

    methods
        function obj = InfoController(app)
            obj.App = app;
        end

        function handleTableSelection(obj, fIdx, event)
            app = obj.App;
            try
                if isempty(event) || isempty(event.Indices), return; end
                row = event.Indices(1, 1);
                app.Models(fIdx).selectedRow = row;

                if obj.IsDraggingInfoRow && obj.InfoDragFIdx == fIdx
                    if row ~= obj.InfoDragSourceRow && obj.InfoDragSourceRow >= 1
                        obj.moveRowTo(fIdx, obj.InfoDragSourceRow, row);
                        obj.InfoDragSourceRow = row;
                    end
                    return;
                end

                obj.IsDraggingInfoRow = true;
                obj.InfoDragFIdx = fIdx;
                obj.InfoDragSourceRow = row;
                if ~obj.bindMouseUp(app)
                    obj.clearState();
                end
            catch ME
                app.logCaught(ME, 'InfoDrag:select');
            end
        end

        function moveSelectedRow(obj, fIdx, direction)
            app = obj.App;
            try
                meta = app.Models(fIdx).displayMeta;
                if isempty(meta), return; end
                row = app.Models(fIdx).selectedRow;
                if isempty(row) || row < 1 || row > numel(meta), return; end
                if strcmpi(char(direction), 'up')
                    target = row - 1;
                else
                    target = row + 1;
                end
                if target < 1 || target > numel(meta), return; end
                obj.moveRowTo(fIdx, row, target);
            catch ME
                app.logCaught(ME, 'InfoOrder:move');
            end
        end

        function moveRowTo(obj, fIdx, fromRow, toRow)
            app = obj.App;
            try
                meta = app.Models(fIdx).displayMeta;
                if isempty(meta), return; end
                n = numel(meta);
                fromRow = round(double(fromRow));
                toRow = round(double(toRow));
                if fromRow < 1 || fromRow > n || toRow < 1 || toRow > n || fromRow == toRow
                    return;
                end

                moved = meta(fromRow);
                meta(fromRow) = [];
                insertBefore = toRow;
                meta = [meta(1:insertBefore-1), moved, meta(insertBefore:end)];
                for k = 1:numel(meta)
                    if isfield(meta(k), 'order'), meta(k).order = k; end
                end
                app.Models(fIdx).displayMeta = meta;
                app.Models(fIdx).selectedRow = toRow;
                app.updateCurrentInfoTable(fIdx, app.Models(fIdx).currentIndex);
                try
                    app.UI(fIdx).dataTable.Selection = [toRow 1];
                catch
                end
            catch ME
                app.logCaught(ME, 'InfoOrder:moveTo');
            end
        end

        function stopRowDrag(obj)
            app = obj.App;
            try
                obj.IsDraggingInfoRow = false;
                obj.InfoDragFIdx = 0;
                obj.InfoDragSourceRow = 0;
                if app.IsEmbedded
                    router = obj.lookupRouter(app);
                    if ~isempty(router) && isvalid(router)
                        router.releaseDragLock();
                    end
                elseif ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonUpFcn = '';
                end
            catch ME
                app.logCaught(ME, 'InfoDrag:stop');
            end
        end

        function handleDragMotion(~)
            % Info row drag is selection-driven; mouse motion is not needed.
        end

        function stopDrag(obj)
            obj.stopRowDrag();
        end

        function clearState(obj)
            obj.IsDraggingInfoRow = false;
            obj.InfoDragFIdx = 0;
            obj.InfoDragSourceRow = 0;
        end

        function tf = bindMouseUp(obj, app)
            tf = false;
            try
                if app.IsEmbedded
                    router = obj.lookupRouter(app);
                    if isempty(router) || ~isvalid(router)
                        ME = MException('FlightDash:NoStudioMouseRouter', ...
                            'Embedded info row drag requires StudioMouseRouter.');
                        app.logCaught(ME, 'InfoDrag:router');
                        return;
                    end
                    tf = router.requestDragLock(app.ActiveSessionId, obj);
                    return;
                end
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.WindowButtonUpFcn = @(~,~) obj.stopRowDrag();
                    tf = true;
                end
            catch ME
                app.logCaught(ME, 'InfoDrag:bind');
            end
        end

        function router = lookupRouter(~, app)
            router = [];
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure) ...
                        && isappdata(app.UIFigure, 'StudioMouseRouter')
                    router = getappdata(app.UIFigure, 'StudioMouseRouter');
                end
            catch
            end
        end
    end
end
