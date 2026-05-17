classdef RibbonIconFactory
    %RIBBONICONFACTORY  Programmatic 24x24 RGB icons for ribbon buttons.
    %
    %   Static API. Generates uint8(sz,sz,3) icon matrices suitable for
    %   uibutton's Icon property. No external image files required, no
    %   Image Processing Toolbox dependency.
    %
    %   Three styles:
    %     - text(label, bg)   : 1-2 character white text on category bg
    %     - symbol(name, bg)  : pictographic shape (play/stop/prev/etc.)
    %     - forCommand(cmdId) : dispatches to text/symbol based on cmdId
    %
    %   Memoized via persistent containers.Map so repeated requests for
    %   the same icon hit a cache.

    properties (Constant, Access = public)
        DefaultSize     = 24
        % Category palette (RGB triplets 0..255).
        ColorHome       = [ 50 110 200]    % blue
        ColorData       = [ 60 160  80]    % green
        ColorSync       = [140  70 180]    % purple
        ColorPlayback   = [230 130  40]    % orange
        ColorReview     = [200  60  60]    % red
        ColorPlot       = [ 50 150 170]    % teal
        ColorEdit       = [110 110 130]    % steel
        ColorPref       = [ 90  90 100]    % gray
        ColorHelp       = [120 130 140]    % cool gray
        ColorDefault    = [ 90  90  90]
    end

    methods (Static, Access = public)

        function rgb = forCommand(cmdId, varargin)
            % Resolve cmdId -> icon. Cached.
            cmdId = char(cmdId);
            cache = flightdash.ui.RibbonIconFactory.cacheMap();
            key = cmdId;
            if cache.isKey(key)
                rgb = cache(key);
                return;
            end
            spec = flightdash.ui.RibbonIconFactory.specForCommand(cmdId);
            switch spec.style
                case 'symbol'
                    rgb = flightdash.ui.RibbonIconFactory.symbol(spec.name, spec.color);
                otherwise
                    rgb = flightdash.ui.RibbonIconFactory.text(spec.text, spec.color);
            end
            cache(key) = rgb;
        end

        function rgb = text(label, bgColor, sz)
            if nargin < 3, sz = flightdash.ui.RibbonIconFactory.DefaultSize; end
            if nargin < 2 || isempty(bgColor)
                bgColor = flightdash.ui.RibbonIconFactory.ColorDefault;
            end
            label = char(label);
            if numel(label) > 2, label = label(1:2); end
            rgb = flightdash.ui.RibbonIconFactory.renderText(label, bgColor, sz);
        end

        function rgb = symbol(name, bgColor, sz)
            if nargin < 3, sz = flightdash.ui.RibbonIconFactory.DefaultSize; end
            if nargin < 2 || isempty(bgColor)
                bgColor = flightdash.ui.RibbonIconFactory.ColorDefault;
            end
            rgb = flightdash.ui.RibbonIconFactory.renderSymbol(char(name), bgColor, sz);
        end

        function color = categoryColor(prefix)
            % Map a command prefix ('File:'/'Toolbar:'/etc.) to category color.
            switch lower(char(prefix))
                case {'file','toolbar:new','toolbar:open','toolbar:save'}
                    color = flightdash.ui.RibbonIconFactory.ColorHome;
                case {'data','toolbar:loaddata','toolbar:loadvideo','video'}
                    color = flightdash.ui.RibbonIconFactory.ColorData;
                case {'sync','toolbar:sync','toolbar:syncquality'}
                    color = flightdash.ui.RibbonIconFactory.ColorSync;
                case {'toolbar:play','toolbar:stop','toolbar:prev','toolbar:next'}
                    color = flightdash.ui.RibbonIconFactory.ColorPlayback;
                case {'review','toolbar:roi','toolbar:marker','analysis','toolbar:analyze','toolbar:recalc'}
                    color = flightdash.ui.RibbonIconFactory.ColorReview;
                case {'plot','window'}
                    color = flightdash.ui.RibbonIconFactory.ColorPlot;
                case {'edit','toolbar:addsession'}
                    color = flightdash.ui.RibbonIconFactory.ColorEdit;
                case {'pref','preferences','toolbar:toggleexplorer','toolbar:togglerightdock'}
                    color = flightdash.ui.RibbonIconFactory.ColorPref;
                case 'help'
                    color = flightdash.ui.RibbonIconFactory.ColorHelp;
                otherwise
                    color = flightdash.ui.RibbonIconFactory.ColorDefault;
            end
        end

        function clearCache()
            cache = flightdash.ui.RibbonIconFactory.cacheMap();
            cache.remove(cache.keys);
        end
    end

    methods (Static, Access = private)

        function map = cacheMap()
            persistent cache
            if isempty(cache)
                cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            map = cache;
        end

        function spec = specForCommand(cmdId)
            spec = struct('style', 'text', 'text', '', 'name', '', 'color', []);
            lower_ = lower(cmdId);
            % Symbol routing for transport-control verbs.
            switch lower_
                case 'toolbar:play'
                    spec.style = 'symbol'; spec.name = 'play';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorPlayback; return;
                case 'toolbar:stop'
                    spec.style = 'symbol'; spec.name = 'stop';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorPlayback; return;
                case 'toolbar:prev'
                    spec.style = 'symbol'; spec.name = 'prev';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorPlayback; return;
                case 'toolbar:next'
                    spec.style = 'symbol'; spec.name = 'next';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorPlayback; return;
                case 'edit:undo'
                    spec.style = 'symbol'; spec.name = 'undo';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorEdit; return;
                case 'edit:redo'
                    spec.style = 'symbol'; spec.name = 'redo';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorEdit; return;
                case 'toolbar:addsession'
                    spec.style = 'symbol'; spec.name = 'plus';
                    spec.color = flightdash.ui.RibbonIconFactory.ColorEdit; return;
            end
            % Text fallback: first 1-2 chars after the colon, prefix-colored.
            spec.text = flightdash.ui.RibbonIconFactory.textForCommand(cmdId);
            spec.color = flightdash.ui.RibbonIconFactory.categoryColor( ...
                flightdash.ui.RibbonIconFactory.prefixOf(cmdId));
        end

        function prefix = prefixOf(cmdId)
            cmdId = char(cmdId);
            idx = find(cmdId == ':', 1);
            if isempty(idx)
                prefix = cmdId;
            else
                prefix = cmdId(1:idx-1);
            end
        end

        function txt = textForCommand(cmdId)
            cmdId = char(cmdId);
            idx = find(cmdId == ':', 1);
            if isempty(idx)
                tail = cmdId;
            else
                tail = cmdId(idx+1:end);
            end
            tail = regexprep(tail, '^Toolbar', '');
            tail = regexprep(tail, '[^A-Za-z0-9]', '');
            if isempty(tail)
                txt = '?';
            elseif numel(tail) == 1
                txt = upper(tail);
            else
                txt = [upper(tail(1)), lower(tail(2))];
            end
        end

        function rgb = renderText(label, bgColor, sz)
            rgb = flightdash.ui.RibbonIconFactory.fillBackground(bgColor, sz);
            try
                fig = figure('Visible', 'off', 'Units', 'pixels', ...
                    'Position', [0 0 sz sz], 'Color', double(bgColor)/255, ...
                    'MenuBar', 'none', 'ToolBar', 'none', 'DockControls', 'off');
                cleanupF = onCleanup(@() delete(fig)); %#ok<NASGU>
                ax = axes(fig, 'Units', 'normalized', 'Position', [0 0 1 1], ...
                    'XLim', [0 1], 'YLim', [0 1], 'Color', double(bgColor)/255, ...
                    'XColor', 'none', 'YColor', 'none');
                fontSize = max(8, round(sz * 0.55));
                text(ax, 0.5, 0.5, label, 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', 'Color', 'w', ...
                    'FontWeight', 'bold', 'FontSize', fontSize, ...
                    'FontName', 'Arial');
                drawnow;
                frame = getframe(ax);
                cdata = frame.cdata;
                if ~isempty(cdata)
                    cdata = imresize8(cdata, sz);
                    if size(cdata, 1) == sz && size(cdata, 2) == sz
                        rgb = uint8(cdata);
                    end
                end
            catch
                % Fall back to solid color block + 1-letter marker via direct pixel write.
                rgb = flightdash.ui.RibbonIconFactory.fallbackText(label, bgColor, sz);
            end
        end

        function rgb = renderSymbol(name, bgColor, sz)
            rgb = flightdash.ui.RibbonIconFactory.fillBackground(bgColor, sz);
            fg = uint8([255 255 255]);
            switch lower(name)
                case 'play'
                    rgb = flightdash.ui.RibbonIconFactory.drawTriangleRight(rgb, fg);
                case 'stop'
                    rgb = flightdash.ui.RibbonIconFactory.drawSquare(rgb, fg);
                case 'prev'
                    rgb = flightdash.ui.RibbonIconFactory.drawTriangleLeft(rgb, fg);
                    rgb = flightdash.ui.RibbonIconFactory.drawBar(rgb, fg, 'left');
                case 'next'
                    rgb = flightdash.ui.RibbonIconFactory.drawTriangleRight(rgb, fg, 'shifted');
                    rgb = flightdash.ui.RibbonIconFactory.drawBar(rgb, fg, 'right');
                case 'undo'
                    rgb = flightdash.ui.RibbonIconFactory.drawArrow(rgb, fg, 'left');
                case 'redo'
                    rgb = flightdash.ui.RibbonIconFactory.drawArrow(rgb, fg, 'right');
                case 'plus'
                    rgb = flightdash.ui.RibbonIconFactory.drawPlus(rgb, fg);
                otherwise
                    rgb = flightdash.ui.RibbonIconFactory.fallbackText('?', bgColor, sz);
            end
        end

        function rgb = fillBackground(bgColor, sz)
            rgb = zeros(sz, sz, 3, 'uint8');
            rgb(:,:,1) = bgColor(1);
            rgb(:,:,2) = bgColor(2);
            rgb(:,:,3) = bgColor(3);
        end

        function rgb = fallbackText(label, bgColor, sz)
            rgb = flightdash.ui.RibbonIconFactory.fillBackground(bgColor, sz);
            % Draw a centered white block representing the letter mass —
            % deterministic and dependency-free.
            pad = round(sz * 0.30);
            rgb(pad+1:end-pad, pad+1:end-pad, :) = 255;
            % Mark by punching a small black square in one quadrant whose
            % position depends on the first character — so different
            % labels produce visually different fallbacks.
            ch = upper(label(1));
            offset = double(ch) - double('A');
            q = mod(offset, 4);
            qr = floor(sz * 0.15) + 1;
            qc = floor(sz * 0.15) + 1;
            switch q
                case 0
                    rgb(pad+1:pad+qr, pad+1:pad+qc, :) = 0;
                case 1
                    rgb(pad+1:pad+qr, end-pad-qc+1:end-pad, :) = 0;
                case 2
                    rgb(end-pad-qr+1:end-pad, pad+1:pad+qc, :) = 0;
                case 3
                    rgb(end-pad-qr+1:end-pad, end-pad-qc+1:end-pad, :) = 0;
            end
        end

        function rgb = drawTriangleRight(rgb, fg, mode)
            if nargin < 3, mode = 'centered'; end
            sz = size(rgb, 1);
            pad = round(sz * 0.25);
            if strcmp(mode, 'shifted'), pad = round(sz * 0.35); end
            for r = pad+1:sz-pad
                halfH = (sz - 2*pad) / 2;
                d = abs(r - (sz/2 + 0.5));
                cMax = sz - pad - round((d / halfH) * (sz/2 - pad));
                cMin = pad + 1;
                if strcmp(mode, 'shifted')
                    cMin = pad + 1;
                end
                cMax = max(cMin, min(sz, cMax));
                rgb(r, cMin:cMax, 1) = fg(1);
                rgb(r, cMin:cMax, 2) = fg(2);
                rgb(r, cMin:cMax, 3) = fg(3);
            end
        end

        function rgb = drawTriangleLeft(rgb, fg)
            sz = size(rgb, 1);
            pad = round(sz * 0.25);
            for r = pad+1:sz-pad
                halfH = (sz - 2*pad) / 2;
                d = abs(r - (sz/2 + 0.5));
                cMin = pad + 1 + round((d / halfH) * (sz/2 - pad));
                cMax = sz - pad;
                cMin = max(1, min(cMax, cMin));
                rgb(r, cMin:cMax, 1) = fg(1);
                rgb(r, cMin:cMax, 2) = fg(2);
                rgb(r, cMin:cMax, 3) = fg(3);
            end
        end

        function rgb = drawSquare(rgb, fg)
            sz = size(rgb, 1);
            pad = round(sz * 0.30);
            rgb(pad+1:end-pad, pad+1:end-pad, 1) = fg(1);
            rgb(pad+1:end-pad, pad+1:end-pad, 2) = fg(2);
            rgb(pad+1:end-pad, pad+1:end-pad, 3) = fg(3);
        end

        function rgb = drawBar(rgb, fg, side)
            sz = size(rgb, 1);
            barW = max(1, round(sz * 0.10));
            pad = round(sz * 0.25);
            switch side
                case 'left'
                    rgb(pad+1:sz-pad, pad+1:pad+barW, 1) = fg(1);
                    rgb(pad+1:sz-pad, pad+1:pad+barW, 2) = fg(2);
                    rgb(pad+1:sz-pad, pad+1:pad+barW, 3) = fg(3);
                case 'right'
                    rgb(pad+1:sz-pad, sz-pad-barW+1:sz-pad, 1) = fg(1);
                    rgb(pad+1:sz-pad, sz-pad-barW+1:sz-pad, 2) = fg(2);
                    rgb(pad+1:sz-pad, sz-pad-barW+1:sz-pad, 3) = fg(3);
            end
        end

        function rgb = drawArrow(rgb, fg, direction)
            sz = size(rgb, 1);
            mid = round(sz / 2);
            % Horizontal shaft.
            rgb(mid-1:mid+1, round(sz*0.25):round(sz*0.75), 1) = fg(1);
            rgb(mid-1:mid+1, round(sz*0.25):round(sz*0.75), 2) = fg(2);
            rgb(mid-1:mid+1, round(sz*0.25):round(sz*0.75), 3) = fg(3);
            % Head as a small triangle.
            tipPad = round(sz * 0.20);
            switch direction
                case 'left'
                    rgb = flightdash.ui.RibbonIconFactory.paintTriangleHead(rgb, fg, tipPad, mid, 'left');
                case 'right'
                    rgb = flightdash.ui.RibbonIconFactory.paintTriangleHead(rgb, fg, tipPad, mid, 'right');
            end
        end

        function rgb = paintTriangleHead(rgb, fg, tipPad, mid, direction)
            sz = size(rgb, 1);
            for k = 0:tipPad
                if strcmp(direction, 'left')
                    cBase = tipPad - k + 1;
                else
                    cBase = sz - tipPad + k;
                end
                r1 = max(1, mid - k);
                r2 = min(sz, mid + k);
                cBase = max(1, min(sz, cBase));
                rgb(r1:r2, cBase, 1) = fg(1);
                rgb(r1:r2, cBase, 2) = fg(2);
                rgb(r1:r2, cBase, 3) = fg(3);
            end
        end

        function rgb = drawPlus(rgb, fg)
            sz = size(rgb, 1);
            mid = round(sz / 2);
            barW = max(2, round(sz * 0.18));
            pad = round(sz * 0.20);
            % Vertical bar.
            rgb(pad+1:sz-pad, mid-floor(barW/2):mid-floor(barW/2)+barW-1, 1) = fg(1);
            rgb(pad+1:sz-pad, mid-floor(barW/2):mid-floor(barW/2)+barW-1, 2) = fg(2);
            rgb(pad+1:sz-pad, mid-floor(barW/2):mid-floor(barW/2)+barW-1, 3) = fg(3);
            % Horizontal bar.
            rgb(mid-floor(barW/2):mid-floor(barW/2)+barW-1, pad+1:sz-pad, 1) = fg(1);
            rgb(mid-floor(barW/2):mid-floor(barW/2)+barW-1, pad+1:sz-pad, 2) = fg(2);
            rgb(mid-floor(barW/2):mid-floor(barW/2)+barW-1, pad+1:sz-pad, 3) = fg(3);
        end
    end
end

function out = imresize8(cdata, sz)
    % Lightweight nearest-neighbor resize so we do not require Image
    % Processing Toolbox. Returns uint8 sz x sz x 3.
    [h, w, c] = size(cdata);
    if c < 3, cdata = repmat(cdata(:,:,1), [1 1 3]); c = 3; end
    rowIdx = max(1, min(h, round(linspace(1, h, sz))));
    colIdx = max(1, min(w, round(linspace(1, w, sz))));
    out = uint8(zeros(sz, sz, 3));
    for k = 1:3
        out(:,:,k) = cdata(rowIdx, colIdx, k);
    end
end
