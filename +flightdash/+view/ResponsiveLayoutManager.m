classdef ResponsiveLayoutManager < handle
    % flightdash.view.ResponsiveLayoutManager
    % Owns figure sizing, responsive grid profiles, panel rails, and summaries.

    methods
        function applyLayout(obj, app, reason) %#ok<INUSD>
            if nargin < 3, reason = ''; end %#ok<NASGU>
            if app.InResponsiveLayout, return; end
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end

            app.InResponsiveLayout = true;
            cleanup_ = onCleanup(@() obj.finishResponsiveLayout(app)); %#ok<NASGU>
            try
                [figW, figH] = obj.currentFigureSizePx(app);
                profile = flightdash.util.UIScale.profileForSize(figW, figH);
                app.LayoutProfile = profile;
                app.LastLayoutSize = [figW, figH];
                obj.applyResponsiveShellLayout(app, profile, figH);

                if isempty(app.UI), return; end
                nChannels = min(2, numel(app.UI));
                for fIdx = 1:nChannels
                    obj.applyResponsiveChannelLayout(app, fIdx, profile);
                    try, app.updatePlotRowHeights(fIdx); catch, end
                end
            catch ME
                app.logCaught(ME, 'Layout:responsive');
            end
        end

        function finishResponsiveLayout(~, app)
            app.InResponsiveLayout = false;
        end

        function pos = initialFigurePosition(obj, app)
            mon = obj.primaryMonitorRect();
            pos = obj.figurePositionForMonitor(mon, false);
        end

        function pos = fitFigurePosition(obj, app)
            mon = obj.currentMonitorRect(app);
            pos = obj.figurePositionForMonitor(mon, true);
        end

        function [figW, figH] = currentFigureSizePx(~, app)
            % [PHASE 3b/3c] In embedded mode, the dashboard occupies the
            % parent uitab/uipanel — NOT the whole Studio figure. Using
            % the figure size here would size every channel panel to the
            % Studio's full width, pushing plot/map panels off the right
            % edge of the tab. Measure the RootContainer instead.
            figW = NaN;
            figH = NaN;

            target = [];
            try
                if isprop(app, 'IsEmbedded') && app.IsEmbedded ...
                        && isprop(app, 'RootContainer') ...
                        && ~isempty(app.RootContainer) && isvalid(app.RootContainer)
                    target = app.RootContainer;
                end
            catch
            end
            if isempty(target)
                target = app.UIFigure;
            end

            try
                pos = getpixelposition(target);
                if numel(pos) >= 4 && all(isfinite(pos(3:4))) && pos(3) > 0 && pos(4) > 0
                    figW = pos(3);
                    figH = pos(4);
                    return;
                end
            catch
            end

            try
                oldUnits = app.UIFigure.Units;
                app.UIFigure.Units = 'pixels';
                pos = app.UIFigure.Position;
                app.UIFigure.Units = oldUnits;
                if numel(pos) >= 4 && all(isfinite(pos(3:4))) && pos(3) > 0 && pos(4) > 0
                    figW = pos(3);
                    figH = pos(4);
                    return;
                end
            catch
            end

            [figW, figH] = flightdash.util.UIScale.screenSize();
        end

        function mon = primaryMonitorRect(~)
            try
                monitors = get(groot, 'MonitorPositions');
                if ~isempty(monitors) && size(monitors, 2) >= 4
                    mon = monitors(1, 1:4);
                    return;
                end
            catch
            end
            [screenW, screenH] = flightdash.util.UIScale.screenSize();
            mon = [1, 1, screenW, screenH];
        end

        function mon = currentMonitorRect(obj, app)
            try
                monitors = get(groot, 'MonitorPositions');
                if isempty(monitors) || size(monitors, 2) < 4
                    mon = obj.primaryMonitorRect();
                    return;
                end

                oldUnits = app.UIFigure.Units;
                app.UIFigure.Units = 'pixels';
                figPos = app.UIFigure.Position;
                app.UIFigure.Units = oldUnits;
                figCenter = [figPos(1) + figPos(3)/2, figPos(2) + figPos(4)/2];

                for k = 1:size(monitors, 1)
                    r = monitors(k, 1:4);
                    if figCenter(1) >= r(1) && figCenter(1) <= r(1) + r(3) && ...
                            figCenter(2) >= r(2) && figCenter(2) <= r(2) + r(4)
                        mon = r;
                        return;
                    end
                end

                centers = [monitors(:,1) + monitors(:,3)/2, monitors(:,2) + monitors(:,4)/2];
                dist2 = (centers(:,1) - figCenter(1)).^2 + (centers(:,2) - figCenter(2)).^2;
                [~, idx] = min(dist2);
                mon = monitors(idx, 1:4);
            catch
                mon = obj.primaryMonitorRect();
            end
        end

        function pos = figurePositionForMonitor(~, mon, fitToScreen)
            marginX = min(flightdash.util.AppConstants.FIGURE_MARGIN_X, max(8, floor(mon(3) * 0.04)));
            marginY = min(flightdash.util.AppConstants.FIGURE_MARGIN_Y, max(16, floor(mon(4) * 0.08)));
            availW = max(360, mon(3) - 2 * marginX);
            availH = max(360, mon(4) - 2 * marginY);

            if fitToScreen
                w = availW;
                h = availH;
            else
                w = min(flightdash.util.AppConstants.FIGURE_INITIAL_W, availW);
                h = min(flightdash.util.AppConstants.FIGURE_INITIAL_H, availH);
                if availW >= flightdash.util.AppConstants.FIGURE_MIN_W
                    w = max(w, flightdash.util.AppConstants.FIGURE_MIN_W);
                end
                if availH >= flightdash.util.AppConstants.FIGURE_MIN_H
                    h = max(h, flightdash.util.AppConstants.FIGURE_MIN_H);
                end
            end

            x = mon(1) + max(4, floor((mon(3) - w) / 2));
            y = mon(2) + max(24, floor((mon(4) - h) / 2));
            pos = [x, y, max(360, round(w)), max(360, round(h))];
        end

        function applyResponsiveShellLayout(obj, app, profile, figH)
            try
                obj.applyResponsiveHeaderLayout(app, profile);
            catch ME
                app.logCaught(ME, 'Layout:header');
            end
            try
                obj.applyResponsiveBodyLayout(app, profile, figH);
            catch ME
                app.logCaught(ME, 'Layout:body');
            end
        end

        function applyResponsiveHeaderLayout(obj, app, profile)
            if ~isfield(app.LayoutHandles, 'header'), return; end
            h = app.LayoutHandles.header;
            if ~isfield(h, 'HeaderGrid') || isempty(h.HeaderGrid) || ~isvalid(h.HeaderGrid), return; end

            profile = flightdash.util.UIScale.normalizeProfile(profile);
            UIScale = flightdash.util.UIScale;
            isNarrow = strcmp(profile, flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW);
            isCompact = strcmp(profile, flightdash.util.AppConstants.LAYOUT_PROFILE_COMPACT);

            g = h.HeaderGrid;
            if isNarrow
                g.RowHeight = {UIScale.pxForProfile(32, profile), UIScale.pxForProfile(32, profile), UIScale.pxForProfile(32, profile)};
                obj.placeGridItem(h.Flight1Button, 1, 1);
                obj.placeGridItem(h.Flight2Button, 1, 2);
                obj.placeGridItem(h.CoastButton, 1, 3);
                obj.placeGridItem(h.FitScreenButton, 1, 4);
                obj.placeGridItem(h.ExportConfigButton, 2, 1);
                obj.placeGridItem(h.ImportConfigButton, 2, 2);
                obj.placeGridItem(h.ChannelViewDropDown, 2, 3);
                obj.placeGridItem(h.DebugBox, 2, 4);
                obj.placeGridItem(h.SyncInput, 3, [1 2]);
                obj.placeGridItem(h.SyncBtn, 3, [3 4]);
                obj.setHandleVisible(h.HeaderSpacer, false);

                g.ColumnWidth = {'1x', '1x', '1x', UIScale.pxForProfile(42, profile)};
                g.Padding = [3 3 3 3];
                g.ColumnSpacing = 3;
                g.RowSpacing = 3;
            else
                if isCompact
                    fileW = 96; coastW = 80; cfgW = 92; viewW = 88; fitW = 38; debugW = 70; inputW = 120; syncW = 120;
                else
                    fileW = 104; coastW = 88; cfgW = 100; viewW = 92; fitW = 42; debugW = 80; inputW = 145; syncW = 145;
                end

                g.ColumnWidth = { ...
                    UIScale.pxForProfile(fileW, profile), ...
                    UIScale.pxForProfile(coastW, profile), ...
                    UIScale.pxForProfile(cfgW, profile), ...
                    UIScale.pxForProfile(viewW, profile), ...
                    '1x', ...
                    UIScale.pxForProfile(fitW, profile), ...
                    UIScale.pxForProfile(debugW, profile), ...
                    UIScale.pxForProfile(inputW, profile), ...
                    UIScale.pxForProfile(syncW, profile)};
                g.Padding = [5 5 5 5];
                g.ColumnSpacing = 5;
                g.RowSpacing = 3;

                obj.placeGridItem(h.Flight1Button, 1, 1);
                obj.placeGridItem(h.Flight2Button, 1, 2);
                obj.placeGridItem(h.CoastButton, 1, 3);
                obj.placeGridItem(h.ExportConfigButton, 1, 4);
                obj.placeGridItem(h.ImportConfigButton, 1, 5);
                obj.placeGridItem(h.ChannelViewDropDown, 1, 6);
                obj.placeGridItem(h.HeaderSpacer, 1, 7);
                obj.placeGridItem(h.FitScreenButton, 1, 8);
                obj.placeGridItem(h.DebugBox, 1, 9);
                obj.placeGridItem(h.SyncInput, 1, 10);
                obj.placeGridItem(h.SyncBtn, 1, 11);
                obj.setHandleVisible(h.HeaderSpacer, true);
                g.RowHeight = {'fit'};
            end
            app.updateMaximizeButtonState();
        end

        function applyResponsiveBodyLayout(obj, app, profile, figH)
            if ~isfield(app.LayoutHandles, 'bodyGrid'), return; end
            bodyGrid = app.LayoutHandles.bodyGrid;
            if isempty(bodyGrid) || ~isvalid(bodyGrid), return; end

            profile = flightdash.util.UIScale.normalizeProfile(profile);
            switch lower(char(app.ChannelViewMode))
                case 'flight1'
                    bodyGrid.RowHeight = {'1x', 0};
                    obj.setChannelRootVisible(app, 1, true);
                    obj.setChannelRootVisible(app, 2, false);
                    try, bodyGrid.Scrollable = 'on'; catch, end
                    return;
                case 'flight2'
                    bodyGrid.RowHeight = {0, '1x'};
                    obj.setChannelRootVisible(app, 1, false);
                    obj.setChannelRootVisible(app, 2, true);
                    try, bodyGrid.Scrollable = 'on'; catch, end
                    return;
                otherwise
                    obj.setChannelRootVisible(app, 1, true);
                    obj.setChannelRootVisible(app, 2, true);
            end
            isShort = ~isfinite(figH) || figH < flightdash.util.AppConstants.LAYOUT_SHORT_VIEW_H || ...
                strcmp(profile, flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW);
            if isShort
                rowH = flightdash.util.UIScale.pxForProfile(obj.channelMinHeightForProfile(profile), profile);
                bodyGrid.RowHeight = {rowH, rowH};
            else
                bodyGrid.RowHeight = {'1x', '1x'};
            end
            try, bodyGrid.Scrollable = 'on'; catch, end
        end

        function setChannelRootVisible(obj, app, fIdx, tf)
            try
                if fIdx <= numel(app.UI) && isfield(app.UI(fIdx), 'rootPanel') && ...
                        ~isempty(app.UI(fIdx).rootPanel) && isvalid(app.UI(fIdx).rootPanel)
                    app.UI(fIdx).rootPanel.Visible = obj.visibleState(tf);
                elseif fIdx <= numel(app.UI) && isfield(app.UI(fIdx), 'channelPanel') && ...
                        ~isempty(app.UI(fIdx).channelPanel) && isvalid(app.UI(fIdx).channelPanel)
                    app.UI(fIdx).channelPanel.Visible = obj.visibleState(tf);
                elseif fIdx <= numel(app.UI) && isfield(app.UI(fIdx), 'panel') && ...
                        ~isempty(app.UI(fIdx).panel) && isvalid(app.UI(fIdx).panel)
                    app.UI(fIdx).panel.Visible = obj.visibleState(tf);
                end
            catch
            end
        end

        function rowH = channelMinHeightForProfile(~, profile)
            profile = flightdash.util.UIScale.normalizeProfile(profile);
            switch profile
                case flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW
                    rowH = flightdash.util.AppConstants.LAYOUT_CHANNEL_MIN_H_NARROW;
                case flightdash.util.AppConstants.LAYOUT_PROFILE_COMPACT
                    rowH = flightdash.util.AppConstants.LAYOUT_CHANNEL_MIN_H_COMPACT;
                case flightdash.util.AppConstants.LAYOUT_PROFILE_MEDIUM
                    rowH = flightdash.util.AppConstants.LAYOUT_CHANNEL_MIN_H_MEDIUM;
                otherwise
                    rowH = flightdash.util.AppConstants.LAYOUT_CHANNEL_MIN_H_WIDE;
            end
        end

        function placeGridItem(~, h, row, col)
            try
                if isempty(h) || ~isvalid(h), return; end
                h.Layout.Row = row;
                h.Layout.Column = col;
            catch
            end
        end

        function applyResponsiveChannelLayout(obj, app, fIdx, profile)
            try
                if fIdx < 1 || fIdx > numel(app.UI), return; end
                if ~isfield(app.UI(fIdx), 'dataGrid'), return; end
                dg = app.UI(fIdx).dataGrid;
                if isempty(dg) || ~isvalid(dg), return; end

                gridW = NaN;
                try
                    gridPos = getpixelposition(dg, true);
                    if numel(gridPos) >= 4 && isfinite(gridPos(3)) && gridPos(3) > 0
                        gridW = gridPos(3);
                    end
                catch
                end
                if ~isfinite(gridW) || gridW <= 0
                    gridW = app.LastLayoutSize(1);
                end

                widths = obj.computeResponsiveColumnWidths(app, fIdx, profile, gridW, dg);
                if isempty(widths), return; end
                dg.ColumnWidth = widths;

                try
                    if isfield(app.UI(fIdx), 'attMapSplitter')
                        obj.setHandleVisible(app.UI(fIdx).attMapSplitter, isnumeric(widths{2}) && widths{2} > 0);
                    end
                    if isfield(app.UI(fIdx), 'mapInfoSplitter')
                        obj.setHandleVisible(app.UI(fIdx).mapInfoSplitter, isnumeric(widths{4}) && widths{4} > 0);
                    end
                    if isfield(app.UI(fIdx), 'infoPlotSplitter')
                        obj.setHandleVisible(app.UI(fIdx).infoPlotSplitter, isnumeric(widths{6}) && widths{6} > 0);
                    end
                    if isfield(app.UI(fIdx), 'hiSplitter')
                        obj.setHandleVisible(app.UI(fIdx).hiSplitter, isnumeric(widths{8}) && widths{8} > 0);
                    end
                catch
                end
                obj.applyResponsiveRailStates(app, fIdx, widths, profile);
                obj.updatePanelRailSummaries(app, fIdx);
            catch ME
                app.logCaught(ME, 'Layout:channel');
            end
        end

        function widths = computeResponsiveColumnWidths(obj, app, fIdx, profile, gridW, dg)
            profile = flightdash.util.UIScale.normalizeProfile(profile);
            [attD, mapD, infoD, videoD, hMinD] = obj.layoutDesignWidths(profile);

            attW   = flightdash.util.UIScale.pxForProfile(attD, profile);
            mapW   = flightdash.util.UIScale.pxForProfile(mapD, profile);
            infoW  = flightdash.util.UIScale.pxForProfile(infoD, profile);
            videoW = flightdash.util.UIScale.pxForProfile(videoD, profile);
            splitW = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_SPLITTER_W, profile);
            hMinW  = flightdash.util.UIScale.pxForProfile(hMinD, profile);

            if ~obj.isPanelVisibleForLayout(app, fIdx, 'attitude'), attW = 0; end
            if ~obj.isPanelVisibleForLayout(app, fIdx, 'map'),      mapW = 0; end
            if obj.isPanelVisibleForLayout(app, fIdx, 'attitude')
                attW = obj.resolveManualPanelWidth(app, fIdx, 'attitude', attW, profile);
            end
            if obj.isPanelVisibleForLayout(app, fIdx, 'map')
                mapW = obj.resolveManualPanelWidth(app, fIdx, 'map', mapW, profile);
            end
            if obj.isPanelVisibleForLayout(app, fIdx, 'info')
                infoW = obj.resolveManualPanelWidth(app, fIdx, 'info', infoW, profile);
            end
            if obj.isSplitterRestrictedForProfile(profile), splitW = 0; end
            if ~obj.isPanelVisibleForLayout(app, fIdx, 'video')
                videoW = 0;
            end

            if videoW > 0
                videoW = obj.resolvePreferredVideoWidth(app, fIdx, profile, videoW, dg);
            end

            splitAM = splitW;
            splitMI = splitW;
            splitIH = splitW;
            splitHI = splitW;
            if attW <= 0 || mapW <= 0, splitAM = 0; end
            if mapW <= 0 || infoW <= 0, splitMI = 0; end
            if infoW <= 0, splitIH = 0; end
            if videoW <= 0, splitHI = 0; end

            spacing = 0;
            try, spacing = dg.ColumnSpacing * 8; catch, end
            fixedW = attW + splitAM + mapW + splitMI + infoW + splitIH + splitHI + videoW + spacing;
            deficit = fixedW + hMinW - gridW;
            if isfinite(deficit) && deficit > 0
                minAtt   = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_ATT_RAIL, profile);
                minInfo  = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_INFO_RAIL, profile);
                minVideo = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_VIDEO_RAIL, profile);
                minMap   = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_MAP_RAIL, profile);

                [videoW, deficit] = obj.shrinkWidth(videoW, minVideo, deficit);
                [mapW,   deficit] = obj.shrinkWidth(mapW,   minMap,   deficit);
                [infoW,  deficit] = obj.shrinkWidth(infoW,  minInfo,  deficit);
                [attW,   deficit] = obj.shrinkWidth(attW,   minAtt,   deficit);
            end

            widths = {max(0, round(attW)), max(0, round(splitAM)), ...
                      max(0, round(mapW)), max(0, round(splitMI)), ...
                      max(0, round(infoW)), max(0, round(splitIH)), ...
                      '1x', max(0, round(splitHI)), max(0, round(videoW))};
        end

        function [attD, mapD, infoD, videoD, hMinD] = layoutDesignWidths(~, profile)
            switch profile
                case flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW
                    attD   = flightdash.util.AppConstants.LAYOUT_ATT_RAIL;
                    mapD   = flightdash.util.AppConstants.LAYOUT_MAP_COMPACT;
                    infoD  = flightdash.util.AppConstants.LAYOUT_INFO_RAIL;
                    videoD = flightdash.util.AppConstants.LAYOUT_VIDEO_RAIL;
                    hMinD  = flightdash.util.AppConstants.LAYOUT_H_MIN_NARROW;
                case flightdash.util.AppConstants.LAYOUT_PROFILE_COMPACT
                    attD   = flightdash.util.AppConstants.LAYOUT_ATT_MEDIUM;
                    mapD   = flightdash.util.AppConstants.LAYOUT_MAP_COMPACT;
                    infoD  = flightdash.util.AppConstants.LAYOUT_INFO_MEDIUM;
                    videoD = flightdash.util.AppConstants.LAYOUT_VIDEO_COMPACT;
                    hMinD  = flightdash.util.AppConstants.LAYOUT_H_MIN_COMPACT;
                case flightdash.util.AppConstants.LAYOUT_PROFILE_MEDIUM
                    attD   = flightdash.util.AppConstants.LAYOUT_ATT_MEDIUM;
                    mapD   = flightdash.util.AppConstants.LAYOUT_MAP_MEDIUM;
                    infoD  = flightdash.util.AppConstants.LAYOUT_INFO_MEDIUM;
                    videoD = flightdash.util.AppConstants.LAYOUT_VIDEO_MEDIUM;
                    hMinD  = flightdash.util.AppConstants.LAYOUT_H_MIN_MEDIUM;
                otherwise
                    attD   = flightdash.util.AppConstants.LAYOUT_ATT_WIDE;
                    mapD   = flightdash.util.AppConstants.LAYOUT_MAP_WIDE;
                    infoD  = flightdash.util.AppConstants.LAYOUT_INFO_WIDE;
                    videoD = flightdash.util.AppConstants.LAYOUT_VIDEO_WIDE;
                    hMinD  = flightdash.util.AppConstants.LAYOUT_H_MIN_WIDE;
            end
        end

        function videoW = resolvePreferredVideoWidth(~, app, fIdx, profile, videoW, dg)
            try
                if app.VideoUserResized(fIdx)
                    manualW = app.ManualVideoWidth(fIdx);
                    if isfinite(manualW) && manualW >= 0
                        videoW = manualW;
                    else
                        cw = dg.ColumnWidth;
                        if numel(cw) >= 9 && isnumeric(cw{9}) && isfinite(cw{9}) && cw{9} > 0
                            videoW = cw{9};
                        end
                    end
                    return;
                end

                prefW = app.PreferredVideoWidth(fIdx);
                if ~isfinite(prefW) || prefW <= 0, return; end

                if strcmp(profile, flightdash.util.AppConstants.LAYOUT_PROFILE_WIDE)
                    capW = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_VIDEO_WIDE_MAX, profile);
                    videoW = min(max(videoW, prefW), capW);
                else
                    videoW = min(videoW, prefW);
                end
            catch
            end
        end

        function setManualPanelWidth(obj, app, fIdx, panelName, widthVal, profile, gridW)
            try
                widthVal = double(widthVal);
                if ~isfinite(widthVal), return; end
                minW = obj.minimumPanelWidth(panelName, profile);
                maxW = max(minW, gridW * 0.70);
                widthVal = min(max(widthVal, minW), maxW);
                m = app.ManualPanelWidths{fIdx};
                m.(panelName) = round(widthVal);
                app.ManualPanelWidths{fIdx} = m;
            catch ME
                app.logCaught(ME, 'PanelSplitter:setManual');
            end
        end

        function widthVal = resolveManualPanelWidth(obj, app, fIdx, panelName, defaultW, profile)
            widthVal = defaultW;
            try
                if fIdx < 1 || fIdx > numel(app.ManualPanelWidths), return; end
                m = app.ManualPanelWidths{fIdx};
                if isstruct(m) && isfield(m, panelName)
                    candidate = double(m.(panelName));
                    if isfinite(candidate) && candidate >= obj.minimumPanelWidth(panelName, profile)
                        widthVal = candidate;
                    end
                end
            catch
                widthVal = defaultW;
            end
        end

        function minW = minimumPanelWidth(~, panelName, profile)
            switch char(panelName)
                case 'attitude'
                    minD = flightdash.util.AppConstants.LAYOUT_ATT_RAIL;
                case 'map'
                    minD = flightdash.util.AppConstants.LAYOUT_MAP_RAIL;
                case 'info'
                    minD = flightdash.util.AppConstants.LAYOUT_INFO_RAIL;
                otherwise
                    minD = 80;
            end
            minW = flightdash.util.UIScale.pxForProfile(minD, profile);
        end

        function tf = isSplitterRestricted(obj, app)
            try
                [figW, figH] = obj.currentFigureSizePx(app);
                profile = flightdash.util.UIScale.profileForSize(figW, figH);
                tf = obj.isSplitterRestrictedForProfile(profile);
            catch
                tf = false;
            end
        end

        function tf = isSplitterRestrictedForProfile(~, profile)
            profile = flightdash.util.UIScale.normalizeProfile(profile);
            tf = strcmp(profile, flightdash.util.AppConstants.LAYOUT_PROFILE_NARROW);
        end

        function tf = isPanelVisibleForLayout(~, app, fIdx, pnlName)
            tf = true;
            try
                if isfield(app.UI(fIdx), 'PanelVisible') && isfield(app.UI(fIdx).PanelVisible, pnlName)
                    tf = logical(app.UI(fIdx).PanelVisible.(pnlName));
                end
            catch
                tf = true;
            end
        end

        function [val, deficit] = shrinkWidth(~, val, minVal, deficit)
            if deficit <= 0 || val <= 0, return; end
            reducible = max(0, val - minVal);
            take = min(deficit, reducible);
            val = val - take;
            deficit = deficit - take;
        end

        function setHandleVisible(obj, h, isVisible)
            if isempty(h), return; end
            try
                if ~all(isvalid(h)), return; end
                h.Visible = obj.visibleState(isVisible);
            catch
            end
        end

        function applyResponsiveRailStates(obj, app, fIdx, widths, profile)
            try
                if isempty(widths) || numel(widths) < 9, return; end

                % [PHASE 3c] When the dashboard is embedded inside a
                % Studio workspace tab the measured width can fall
                % below the rail thresholds even though the user wants
                % full content. Rails would replace map / info / video
                % with single-line text summaries. Force rails OFF in
                % embedded mode so the panels keep their full UI.
                forceFullPanels = false;
                try
                    if isprop(app, 'IsEmbedded') && app.IsEmbedded
                        forceFullPanels = true;
                    end
                catch
                end

                if forceFullPanels
                    attRail   = false;
                    mapRail   = false;
                    infoRail  = false;
                    videoRail = false;
                else
                    attRail   = obj.isRailColumn(widths{1}, flightdash.util.AppConstants.LAYOUT_ATT_RAIL,   profile);
                    mapRail   = obj.isRailColumn(widths{3}, flightdash.util.AppConstants.LAYOUT_MAP_RAIL,   profile);
                    infoRail  = obj.isRailColumn(widths{5}, flightdash.util.AppConstants.LAYOUT_INFO_RAIL,  profile);
                    videoRail = obj.isRailColumn(widths{9}, flightdash.util.AppConstants.LAYOUT_VIDEO_RAIL, profile);
                end

                obj.setContentRailMode(app, fIdx, 'attitudeContent', 'attitudeRail', attRail);
                obj.setContentRailMode(app, fIdx, 'mapAltContent',   'mapAltRail',   mapRail);
                obj.setContentRailMode(app, fIdx, 'infoContent',     'infoRail',     infoRail);
                obj.setContentRailMode(app, fIdx, 'videoContent',    'videoRail',    videoRail);
            catch ME
                app.logCaught(ME, 'Layout:railState');
            end
        end

        function tf = isRailColumn(~, widthVal, railDesignWidth, profile)
            tf = false;
            if ~isnumeric(widthVal) || isempty(widthVal) || ~isfinite(widthVal) || widthVal <= 0
                return;
            end
            railMax = flightdash.util.UIScale.pxForProfile(railDesignWidth + 16, profile);
            tf = widthVal <= railMax;
        end

        function setContentRailMode(obj, app, fIdx, contentField, railField, useRail)
            if fIdx < 1 || fIdx > numel(app.UI), return; end
            if isfield(app.UI(fIdx), contentField)
                obj.setHandleVisible(app.UI(fIdx).(contentField), ~useRail);
            end
            if isfield(app.UI(fIdx), railField)
                obj.setHandleVisible(app.UI(fIdx).(railField), useRail);
            end
        end

        function updatePanelRailSummaries(~, app, fIdx)
            flightdash.view.RailSummaryView.update(app, fIdx);
        end
    end

    methods (Access = private)
        function state = visibleState(~, tf)
            if tf
                state = 'on';
            else
                state = 'off';
            end
        end
    end
end
