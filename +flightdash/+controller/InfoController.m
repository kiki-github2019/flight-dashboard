classdef InfoController < handle
    % flightdash.controller.InfoController
    % Owns current-info table interactions: row reorder, drag-to-reorder.
    %
    % [REFACTOR R5+1] Migrated from full-app dependency to
    % DashboardAppAdapter. Adapter routes the calls the controller
    % actually needs (logCaught / session / uiFigure); write paths to
    % app.Models(fIdx).displayMeta and app.updateCurrentInfoTable still
    % use the adapter.app() escape hatch — these are the future
    % migration candidates the R5 brief flagged.

    properties (Access = private)
        Adapter  % flightdash.runtime.DashboardAppAdapter
    end

    properties (SetAccess = private)
        IsDraggingInfoRow logical = false
        InfoDragFIdx      double  = 0
        InfoDragSourceRow double  = 0
    end

    methods
        function obj = InfoController(adapterOrApp)
            % Accept either the adapter (new path) or the app handle
            % (legacy path) so external test code constructing the
            % controller directly is unaffected during the transition.
            if isa(adapterOrApp, 'flightdash.runtime.DashboardAppAdapter')
                obj.Adapter = adapterOrApp;
            elseif isa(adapterOrApp, 'flightdash.FlightDataDashboard')
                obj.Adapter = adapterOrApp.getAdapter();
            else
                error('InfoController:BadInput', ...
                    'Expected DashboardAppAdapter or FlightDataDashboard, got %s.', ...
                    class(adapterOrApp));
            end
        end

        function handleTableSelection(obj, fIdx, event)
            app = obj.Adapter.app();
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
                if ~obj.bindMouseUp()
                    obj.clearState();
                end
            catch ME
                obj.Adapter.logCaught(ME, 'InfoDrag:select');
            end
        end

        function moveSelectedRow(obj, fIdx, direction)
            app = obj.Adapter.app();
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
                obj.Adapter.logCaught(ME, 'InfoOrder:move');
            end
        end

        function moveRowTo(obj, fIdx, fromRow, toRow)
            app = obj.Adapter.app();
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
                obj.Adapter.logCaught(ME, 'InfoOrder:moveTo');
            end
        end

        function stopRowDrag(obj)
            try
                obj.IsDraggingInfoRow = false;
                obj.InfoDragFIdx = 0;
                obj.InfoDragSourceRow = 0;
                session = obj.Adapter.session();
                if ~isempty(session) && session.IsEmbedded
                    router = obj.lookupRouter();
                    if ~isempty(router) && isvalid(router) && ...
                            ismethod(router, 'isLockHeldBy') && ...
                            router.isLockHeldBy(session.ActiveSessionId)
                        router.releaseDragLock();
                    end
                else
                    fig = obj.Adapter.uiFigure();
                    if ~isempty(fig) && isvalid(fig)
                        fig.WindowButtonUpFcn = '';
                    end
                end
            catch ME
                obj.Adapter.logCaught(ME, 'InfoDrag:stop');
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

        function tf = bindMouseUp(obj)
            tf = false;
            try
                session = obj.Adapter.session();
                if ~isempty(session) && session.IsEmbedded
                    router = obj.lookupRouter();
                    if isempty(router) || ~isvalid(router)
                        ME = MException('FlightDash:NoStudioMouseRouter', ...
                            'Embedded info row drag requires StudioMouseRouter.');
                        obj.Adapter.logCaught(ME, 'InfoDrag:router');
                        return;
                    end
                    tf = router.requestDragLock(session.ActiveSessionId, obj);
                    return;
                end
                fig = obj.Adapter.uiFigure();
                if ~isempty(fig) && isvalid(fig)
                    fig.WindowButtonUpFcn = @(~,~) obj.stopRowDrag();
                    tf = true;
                end
            catch ME
                obj.Adapter.logCaught(ME, 'InfoDrag:bind');
            end
        end

        function router = lookupRouter(obj)
            router = [];
            try
                fig = obj.Adapter.uiFigure();
                if ~isempty(fig) && isvalid(fig) ...
                        && isappdata(fig, 'StudioMouseRouter')
                    router = getappdata(fig, 'StudioMouseRouter');
                end
            catch
            end
        end
    end
end
