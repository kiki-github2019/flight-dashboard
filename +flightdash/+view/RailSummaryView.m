classdef RailSummaryView < handle
    % flightdash.view.RailSummaryView
    % Renders the collapsed-rail summary text for each panel column.

    methods (Static)
        function update(app, fIdx)
            try
                if fIdx < 1 || fIdx > numel(app.UI), return; end

                hasData = ~isempty(app.Models(fIdx).rawData) && height(app.Models(fIdx).rawData) > 0;
                if hasData
                    nRows = height(app.Models(fIdx).rawData);
                    idx = max(1, min(nRows, app.Models(fIdx).currentIndex));
                    currTime = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Time', idx, NaN);
                    pitch = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Pitch', idx, NaN);
                    roll  = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Roll', idx, NaN);
                    hdg   = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Heading', idx, NaN);
                    lat   = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Lat', idx, NaN);
                    lon   = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Lon', idx, NaN);
                    alt   = flightdash.view.RailSummaryView.modelValueAt(app, fIdx, 'Alt', idx, NaN);
                else
                    nRows = 0; idx = 0; currTime = NaN;
                    pitch = NaN; roll = NaN; hdg = NaN; lat = NaN; lon = NaN; alt = NaN;
                end

                fmt = @flightdash.view.RailSummaryView.formatNumber;

                if isfield(app.UI(fIdx), 'attitudeRail') && ~isempty(app.UI(fIdx).attitudeRail) && isvalid(app.UI(fIdx).attitudeRail)
                    app.UI(fIdx).attitudeRail.Text = sprintf('ATT\nP %s\nR %s\nH %s', ...
                        fmt('%+.0f', pitch, '--'), ...
                        fmt('%+.0f', roll, '--'), ...
                        fmt('%.0f', hdg, '--'));
                end

                if isfield(app.UI(fIdx), 'mapAltRail') && ~isempty(app.UI(fIdx).mapAltRail) && isvalid(app.UI(fIdx).mapAltRail)
                    app.UI(fIdx).mapAltRail.Text = sprintf('MAP\nLat %s\nLon %s\nAlt %s', ...
                        fmt('%.4f', lat, '--'), ...
                        fmt('%.4f', lon, '--'), ...
                        fmt('%.0f', alt, '--'));
                end

                if isfield(app.UI(fIdx), 'infoRail') && ~isempty(app.UI(fIdx).infoRail) && isvalid(app.UI(fIdx).infoRail)
                    if hasData
                        app.UI(fIdx).infoRail.Text = sprintf('INFO\n%s\nRow %d/%d', ...
                            fmt('%.2fs', currTime, '--'), idx, nRows);
                    else
                        app.UI(fIdx).infoRail.Text = sprintf('INFO\nNo data');
                    end
                end

                if isfield(app.UI(fIdx), 'videoRail') && ~isempty(app.UI(fIdx).videoRail) && isvalid(app.UI(fIdx).videoRail)
                    total = app.VideoSyncState(fIdx).TotalFrames;
                    cur = app.VideoSyncState(fIdx).CurrentFrame;
                    if total > 0
                        if app.VideoSyncState(fIdx).IsSynced
                            syncTxt = 'SYNC';
                        else
                            syncTxt = 'FREE';
                        end
                        app.UI(fIdx).videoRail.Text = sprintf('VID\n%d/%d\n%s', cur, total, syncTxt);
                    else
                        app.UI(fIdx).videoRail.Text = sprintf('VID\nNo AVI');
                    end
                end
            catch ME
                app.logCaught(ME, 'RailSummary:update');
            end
        end

        function val = modelValueAt(app, fIdx, keyName, idx, defaultVal)
            val = defaultVal;
            try
                if isempty(app.Models(fIdx).rawData) || ~isfield(app.Models(fIdx).mappedCols, keyName)
                    return;
                end
                colName = app.Models(fIdx).mappedCols.(keyName);
                if ~ismember(colName, app.Models(fIdx).rawData.Properties.VariableNames)
                    return;
                end
                arr = app.Models(fIdx).rawData.(colName);
                if idx >= 1 && idx <= numel(arr)
                    val = arr(idx);
                end
            catch
                val = defaultVal;
            end
        end

        function txt = formatNumber(fmt, val, fallback)
            if isnumeric(val) && isscalar(val) && isfinite(val)
                txt = sprintf(fmt, val);
            else
                txt = fallback;
            end
        end
    end
end
