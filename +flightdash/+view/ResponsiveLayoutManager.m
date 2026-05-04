classdef ResponsiveLayoutManager < handle
    % flightdash.view.ResponsiveLayoutManager
    % Pure sizing helpers for responsive layout. The app still applies handles.

    methods
        function [figW, figH] = currentFigureSizePx(~, app)
            figW = NaN;
            figH = NaN;
            try
                pos = getpixelposition(app.UIFigure);
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

        function widths = computeResponsiveColumnWidths(obj, app, fIdx, profile, gridW, dg)
            profile = flightdash.util.UIScale.normalizeProfile(profile);
            [attD, mapD, infoD, videoD, hMinD] = obj.layoutDesignWidths(profile);

            attW   = flightdash.util.UIScale.pxForProfile(attD, profile);
            mapW   = flightdash.util.UIScale.pxForProfile(mapD, profile);
            infoW  = flightdash.util.UIScale.pxForProfile(infoD, profile);
            videoW = flightdash.util.UIScale.pxForProfile(videoD, profile);
            splitW = flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_SPLITTER_W, profile);
            hMinW  = flightdash.util.UIScale.pxForProfile(hMinD, profile);

            if ~app.isPanelVisibleForLayout(fIdx, 'attitude'), attW = 0; end
            if ~app.isPanelVisibleForLayout(fIdx, 'map'),      mapW = 0; end
            if app.isPanelVisibleForLayout(fIdx, 'attitude')
                attW = app.resolveManualPanelWidth(fIdx, 'attitude', attW, profile);
            end
            if app.isPanelVisibleForLayout(fIdx, 'map')
                mapW = app.resolveManualPanelWidth(fIdx, 'map', mapW, profile);
            end
            if app.isPanelVisibleForLayout(fIdx, 'info')
                infoW = app.resolveManualPanelWidth(fIdx, 'info', infoW, profile);
            end
            if app.isSplitterRestrictedForProfile(profile), splitW = 0; end
            if ~app.isPanelVisibleForLayout(fIdx, 'video')
                videoW = 0;
            end

            if videoW > 0
                videoW = app.resolvePreferredVideoWidth(fIdx, profile, videoW, dg);
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

                [videoW, deficit] = app.shrinkWidth(videoW, minVideo, deficit);
                [mapW,   deficit] = app.shrinkWidth(mapW,   minMap,   deficit);
                [infoW,  deficit] = app.shrinkWidth(infoW,  minInfo,  deficit);
                [attW,   deficit] = app.shrinkWidth(attW,   minAtt,   deficit);
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
    end
end
