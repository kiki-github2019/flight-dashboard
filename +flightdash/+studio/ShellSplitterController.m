classdef ShellSplitterController < handle
    %SHELLSPLITTERCONTROLLER  Drag handler for Studio shell column splitters.
    %
    %   Integrates with StudioMouseRouter via the 'shell' lock path so the
    %   ProjectExplorer | Workspace | RightDock column widths can be
    %   resized by dragging the thin splitter panels between them.
    %
    %   Construction:
    %       ctrl = ShellSplitterController(app, bodyGrid, router);
    %       ctrl.attach(leftSplitterPanel,  1);   % between cols 1↔3
    %       ctrl.attach(rightSplitterPanel, 2);   % between cols 3↔5
    %
    %   BodyGrid layout (5 columns):
    %       [explorer | splitter1 | workspace | splitter2 | rightdock]
    %
    %   Memory: one controller per Studio shell; no per-frame allocation.
    %   Exception: every public path swallows errors and releases the lock.

    properties (Access = public)
        App
        Router
        BodyGrid
        DebugMode logical = false
    end

    properties (Access = private)
        ActiveIdx       = 0     % 1 = left splitter, 2 = right splitter, 0 = idle
        StartFigX       = 0     % figure CurrentPoint X at mouse-down (pixels)
        StartLeftPx     = 0     % left-column pixel width at mouse-down
        StartRightPx    = 0     % right-column pixel width at mouse-down
        MinLeftPx       = 120   % minimum pixel width for left-column panel
        MinRightPx      = 120   % minimum pixel width for right-column panel
    end

    methods
        function obj = ShellSplitterController(app, bodyGrid, router)
            obj.App      = app;
            obj.BodyGrid = bodyGrid;
            obj.Router   = router;
        end

        function attach(obj, splitterPanel, splitterIdx)
            % Wire ButtonDownFcn so clicking the splitter starts a drag.
            try
                if isempty(splitterPanel) || ~isvalid(splitterPanel), return; end
                splitterPanel.ButtonDownFcn = @(src,~) obj.onButtonDown(src, splitterIdx);
                splitterPanel.Tooltip = 'Drag to resize';
            catch
            end
        end

        function handleDragMotion(obj)
            % Called by StudioMouseRouter while a shell drag lock is held.
            if obj.ActiveIdx == 0, return; end
            try
                fig = obj.App.UIFigure;
                if isempty(fig) || ~isvalid(fig), return; end
                if isempty(obj.BodyGrid) || ~isvalid(obj.BodyGrid), return; end

                curX = fig.CurrentPoint(1);
                dx   = curX - obj.StartFigX;

                if obj.ActiveIdx == 1
                    % Dragging the left splitter: explorer (col 1) grows,
                    % workspace (col 3) absorbs the loss via '1x'.
                    newW = max(obj.MinLeftPx, obj.StartLeftPx + dx);
                    obj.setColumnPx(1, newW);
                else
                    % Dragging the right splitter: rightdock (col 5)
                    % grows as the user drags LEFT (negative dx).
                    newW = max(obj.MinRightPx, obj.StartRightPx - dx);
                    obj.setColumnPx(5, newW);
                end
            catch
            end
        end

        function stopDrag(obj)
            % Called by StudioMouseRouter on mouse-up.
            obj.ActiveIdx    = 0;
            obj.StartFigX    = 0;
            obj.StartLeftPx  = 0;
            obj.StartRightPx = 0;
            try
                % Trigger one final layout refresh on the active dashboard
                % so its responsive profile recomputes against the new
                % workspace width (avoids rail-mode lag on release).
                if ~isempty(obj.App) && isvalid(obj.App) ...
                        && ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace)
                    obj.App.Workspace.refreshActiveLayout('shellSplitter');
                end
            catch
            end
        end
    end

    methods (Access = private)
        function onButtonDown(obj, splitterPanel, splitterIdx) %#ok<INUSL>
            try
                if isempty(obj.Router) || ~isvalid(obj.Router), return; end
                fig = obj.App.UIFigure;
                if isempty(fig) || ~isvalid(fig), return; end

                obj.ActiveIdx = splitterIdx;
                obj.StartFigX = fig.CurrentPoint(1);
                widths = obj.currentColumnPixels();
                if numel(widths) >= 5
                    obj.StartLeftPx  = widths(1);
                    obj.StartRightPx = widths(5);
                end

                if ~obj.Router.requestShellDragLock(obj, 'fleur', 'shellSplitter')
                    obj.ActiveIdx = 0;
                end
            catch
                obj.ActiveIdx = 0;
            end
        end

        function setColumnPx(obj, colIdx, px)
            try
                cw = obj.BodyGrid.ColumnWidth;
                if numel(cw) < colIdx, return; end
                cw{colIdx} = round(px);
                obj.BodyGrid.ColumnWidth = cw;
            catch
            end
        end

        function widths = currentColumnPixels(obj)
            % Resolve grid ColumnWidth entries to actual pixels. '1x' and
            % 'fit' entries are derived from the grid's pixel position.
            widths = zeros(1, 0);
            try
                cw = obj.BodyGrid.ColumnWidth;
                gridPos = getpixelposition(obj.BodyGrid);
                totalW = gridPos(3);
                fixedSum = 0;
                flexCount = 0;
                resolved = zeros(1, numel(cw));
                for k = 1:numel(cw)
                    v = cw{k};
                    if isnumeric(v)
                        resolved(k) = v;
                        fixedSum = fixedSum + v;
                    else
                        resolved(k) = -1;
                        flexCount = flexCount + 1;
                    end
                end
                if flexCount > 0
                    flexShare = max(0, (totalW - fixedSum) / flexCount);
                    resolved(resolved < 0) = flexShare;
                end
                widths = resolved;
            catch
            end
        end
    end
end
