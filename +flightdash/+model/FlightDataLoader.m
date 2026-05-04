classdef FlightDataLoader < handle
    % flightdash.model.FlightDataLoader
    % App-independent parser/preprocessor. Methods return model state instead
    % of mutating FlightDataDashboard directly.

    methods
        function modelState = parseFlightData(obj, fIdx, filepath)
            opts = detectImportOptions(filepath);
            opts.DataLines = [2 Inf];
            opts.VariableNamingRule = 'preserve';

            if ~isempty(opts.VariableNames)
                opts.VariableNames{1} = 'time';
            end

            validTypes = {'double', 'single', 'int8', 'uint8', 'int16', 'uint16', ...
                'int32', 'uint32', 'int64', 'uint64'};
            for k = 1:length(opts.VariableTypes)
                if ismember(opts.VariableTypes{k}, validTypes)
                    opts = setvartype(opts, opts.VariableNames{k}, 'double');
                end
            end

            dataTbl = readtable(filepath, opts);
            modelState = obj.applyOptionFile(fIdx, dataTbl, false);

            if any(ismissing(modelState.rawData), 'all')
                modelState.rawData = fillmissing(modelState.rawData, 'linear', 'DataVariables', @isnumeric);
            end
            modelState.rawData = obj.markInvalidGpsAsNaN(modelState.rawData, modelState.mappedCols);
        end

        function modelState = applyOptionFile(obj, fIdx, dataTbl, isMock)
            csvHeaders = dataTbl.Properties.VariableNames;
            numHeaders = length(csvHeaders);
            optFileName = sprintf('option%d.dat', fIdx);

            reqKeys = flightdash.util.AppConstants.REQ_KEYS;
            mappedCols = struct();
            for i = 1:length(reqKeys)
                mappedCols.(reqKeys{i}) = '';
            end

            displayMeta = struct('header', {}, 'unit', {}, 'format', {}, 'scale', {}, 'order', {});

            if isfile(optFileName)
                lines = readlines(optFileName, 'EmptyLineRule', 'skip');
                section = 0;
                for i = 1:length(lines)
                    lineStr = strtrim(lines(i));
                    if startsWith(lineStr, '#'), section = section + 1; continue; end
                    if section == 1
                        parts = split(lineStr, ':');
                        if length(parts) >= 2
                            k = char(strtrim(parts(1)));
                            v = char(strtrim(parts(2)));
                            if isfield(mappedCols, k) && ismember(v, csvHeaders)
                                mappedCols.(k) = v;
                            end
                        end
                    elseif section == 2
                        parts = split(lineStr, ',');
                        if length(parts) >= 4
                            hdr   = char(strtrim(parts(1)));
                            unit  = char(strtrim(parts(2)));
                            fmt   = char(strtrim(parts(3)));
                            order = str2double(strtrim(parts(4)));
                            if length(parts) >= 5
                                scale = str2double(strtrim(parts(5)));
                            else
                                scale = 1.0;
                            end
                            if ~isnan(order) && ismember(hdr, csvHeaders)
                                displayMeta(end+1) = struct('header', hdr, 'unit', unit, ...
                                    'format', fmt, 'scale', scale, 'order', order); %#ok<AGROW>
                            end
                        end
                    end
                end
            end

            for i = 1:length(reqKeys)
                keyName = reqKeys{i};
                if isempty(mappedCols.(keyName))
                    inferredCol = obj.inferRequiredColumn(keyName, csvHeaders);
                    if ~isempty(inferredCol)
                        mappedCols.(keyName) = inferredCol;
                    end
                end
            end

            if isMock
                for i = 1:length(reqKeys)
                    keyName = reqKeys{i};
                    if isempty(mappedCols.(keyName)) && (i <= numHeaders)
                        mappedCols.(keyName) = csvHeaders{i};
                    end
                end
            else
                obj.validateRequiredColumns(dataTbl, mappedCols, fIdx);
            end

            if isempty(displayMeta)
                for i = 1:numHeaders
                    displayMeta(end+1) = struct('header', csvHeaders{i}, 'unit', '-', ...
                        'format', '%.6f', 'scale', 1.0, 'order', i); %#ok<AGROW>
                end
            else
                orders = [displayMeta.order];
                if (length(unique(orders)) == length(orders)) && ...
                        (min(orders) == 1) && (max(orders) == length(orders))
                    [~, sortIdx] = sort([displayMeta.order]);
                    displayMeta = displayMeta(sortIdx);
                else
                    for i = 1:length(displayMeta)
                        displayMeta(i).order = i;
                    end
                end

                existingHeaders = {displayMeta.header};
                missingHeaders = setdiff(csvHeaders, existingHeaders, 'stable');
                for i = 1:length(missingHeaders)
                    displayMeta(end+1) = struct('header', missingHeaders{i}, 'unit', '-', ...
                        'format', '%.6f', 'scale', 1.0, 'order', length(displayMeta) + i); %#ok<AGROW>
                end
            end

            for i = 1:length(displayMeta)
                if isMock, displayMeta(i).scale = 1.0; end
                colName = displayMeta(i).header;
                if displayMeta(i).scale ~= 1.0
                    dataTbl.(colName) = dataTbl.(colName) * displayMeta(i).scale;
                end
            end

            modelState = struct();
            modelState.rawData = dataTbl;
            modelState.mappedCols = mappedCols;
            modelState.displayMeta = displayMeta;
            modelState.selectedRow = 1;
            modelState.isMockData = isMock;
            if ~isMock
                obj.validateRequiredColumnData(modelState.rawData, modelState.mappedCols);
            end
        end

        function dataTbl = markInvalidGpsAsNaN(~, dataTbl, mappedCols)
            try
                if isfield(mappedCols, 'Lat') && isfield(mappedCols, 'Lon')
                    if isempty(mappedCols.Lat) || isempty(mappedCols.Lon), return; end
                    lats = dataTbl.(mappedCols.Lat);
                    lons = dataTbl.(mappedCols.Lon);
                    invalid = ((lats == 0) & (lons == 0)) | ~isfinite(lats) | ~isfinite(lons);
                    if any(invalid)
                        lats(invalid) = NaN;
                        lons(invalid) = NaN;
                        dataTbl.(mappedCols.Lat) = lats;
                        dataTbl.(mappedCols.Lon) = lons;
                    end
                end
            catch
            end
        end

        function modelState = generateMockFlightData(obj, fIdx, bounds)
            latRange = bounds.maxLat - bounds.minLat;
            lonRange = bounds.maxLon - bounds.minLon;
            if latRange <= 0, latRange = 0.1; end
            if lonRange <= 0, lonRange = 0.1; end

            minLat = bounds.minLat;
            maxLat = bounds.maxLat;
            minLon = bounds.minLon;
            maxLon = bounds.maxLon;

            currLat = minLat + latRange / 2 + (fIdx * 0.02);
            currLon = minLon + lonRange / 2 - (fIdx * 0.02);
            currAlt = 5000 + (fIdx * 500);
            currHdg = (rand() * 360) - 180;
            currRoll = 0;
            currPitch = 5;
            speed = min(latRange, lonRange) * 0.005;

            N = flightdash.util.AppConstants.MOCK_STEP_COUNT;
            time_s = zeros(N, 1);
            lat_deg = zeros(N, 1);
            lon_deg = zeros(N, 1);
            alt_ft = zeros(N, 1);
            hdg_deg = zeros(N, 1);
            roll_deg = zeros(N, 1);
            pitch_deg = zeros(N, 1);

            for i = 1:N
                time_s(i) = i-1;
                lat_deg(i) = currLat;
                lon_deg(i) = currLon;
                alt_ft(i) = currAlt;
                hdg_deg(i) = currHdg;
                roll_deg(i) = currRoll;
                pitch_deg(i) = currPitch;

                if i > 50 && i < 100
                    currRoll = min(currRoll + 2, 45);
                    currHdg = currHdg + currRoll * 0.1;
                elseif i >= 100 && i < 130
                    currRoll = currRoll * 0.9;
                elseif i > 150
                    currRoll = max(currRoll - 2, -45);
                    currHdg = currHdg + currRoll * 0.1;
                else
                    currRoll = currRoll * 0.9;
                end

                if currHdg > 180, currHdg = currHdg - 360; end
                if currHdg <= -180, currHdg = currHdg + 360; end

                if i < 80
                    currPitch = 5;
                    currAlt = currAlt + 20;
                elseif i > 120
                    currPitch = -3;
                    currAlt = currAlt - 15;
                else
                    currPitch = 0;
                end

                currPitch = currPitch + (rand() - 0.5) * 1;
                currRoll = currRoll + (rand() - 0.5) * 2;

                if currPitch > 180, currPitch = currPitch - 360; end
                if currPitch <= -180, currPitch = currPitch + 360; end
                if currRoll > 180, currRoll = currRoll - 360; end
                if currRoll <= -180, currRoll = currRoll + 360; end

                mathAngle = (90 - currHdg) * pi / 180;
                currLon = currLon + cos(mathAngle) * speed;
                currLat = currLat + sin(mathAngle) * speed;

                if currLat > maxLat
                    currLat = maxLat - (currLat - maxLat);
                    currHdg = -currHdg;
                elseif currLat < minLat
                    currLat = minLat + (minLat - currLat);
                    currHdg = -currHdg;
                end
                if currLon > maxLon
                    currLon = maxLon - (currLon - maxLon);
                    currHdg = 180 - currHdg;
                elseif currLon < minLon
                    currLon = minLon + (minLon - currLon);
                    currHdg = 180 - currHdg;
                end

                if currHdg > 180, currHdg = currHdg - 360; end
                if currHdg <= -180, currHdg = currHdg + 360; end
            end

            optFileName = sprintf('option%d.dat', fIdx);
            baseKeys = flightdash.util.AppConstants.REQ_KEYS;
            varNames = baseKeys;
            if isfile(optFileName)
                lines = readlines(optFileName, 'EmptyLineRule', 'skip');
                section = 0;
                for idxLine = 1:length(lines)
                    lineStr = strtrim(lines(idxLine));
                    if startsWith(lineStr, '#'), section = section + 1; continue; end
                    if section == 1
                        parts = split(lineStr, ':');
                        if length(parts) >= 2
                            k = char(strtrim(parts(1)));
                            v = char(strtrim(parts(2)));
                            matchIdx = find(strcmp(baseKeys, k));
                            if ~isempty(matchIdx), varNames{matchIdx} = v; end
                        end
                    end
                end
            end

            mockTbl = table(time_s, roll_deg, pitch_deg, hdg_deg, alt_ft, lat_deg, lon_deg, ...
                'VariableNames', varNames);
            modelState = obj.applyOptionFile(fIdx, mockTbl, true);
        end

        function [bounds, altBounds] = calculateBounds(~, rawData, mappedCols, coastlineData, fixedAreaBounds, currentBounds, currentAltBounds)
            if nargin < 6 || isempty(currentBounds)
                currentBounds = struct('minLat', 0, 'maxLat', 0, 'minLon', 0, 'maxLon', 0, 'isValid', false);
            end
            if nargin < 7 || isempty(currentAltBounds)
                currentAltBounds = struct('minAlt', 0, 'maxAlt', 0);
            end

            bounds = currentBounds;
            altBounds = currentAltBounds;
            minLat = 90; maxLat = -90; minLon = 180; maxLon = -180;
            minAlt = 99999; maxAlt = -99999; hasData = false; hasFlightGeo = false;

            if ~isempty(coastlineData)
                minLat = min(minLat, min(coastlineData(:,1))); maxLat = max(maxLat, max(coastlineData(:,1)));
                minLon = min(minLon, min(coastlineData(:,2))); maxLon = max(maxLon, max(coastlineData(:,2)));
                hasData = true;
            end

            if ~isempty(rawData) && height(rawData) > 0 && isstruct(mappedCols) && ...
                    isfield(mappedCols, 'Lat') && isfield(mappedCols, 'Lon') && isfield(mappedCols, 'Alt') && ...
                    ismember(mappedCols.Lat, rawData.Properties.VariableNames) && ...
                    ismember(mappedCols.Lon, rawData.Properties.VariableNames) && ...
                    ismember(mappedCols.Alt, rawData.Properties.VariableNames)
                lats = rawData.(mappedCols.Lat);
                lons = rawData.(mappedCols.Lon);
                alts = rawData.(mappedCols.Alt);

                validGeo = isfinite(lats) & isfinite(lons);
                if any(validGeo)
                    minLat = min(lats(validGeo));
                    maxLat = max(lats(validGeo));
                    minLon = min(lons(validGeo));
                    maxLon = max(lons(validGeo));
                    hasFlightGeo = true;
                end
                validAlt = isfinite(alts);
                if any(validAlt)
                    minAlt = min(minAlt, min(alts(validAlt)));
                    maxAlt = max(maxAlt, max(alts(validAlt)));
                end
                hasData = true;
            end

            if ~isempty(fixedAreaBounds)
                bounds.minLat = fixedAreaBounds.minLat;
                bounds.maxLat = fixedAreaBounds.maxLat;
                bounds.minLon = fixedAreaBounds.minLon;
                bounds.maxLon = fixedAreaBounds.maxLon;
                bounds.isValid = true;
            elseif hasFlightGeo
                latPad = max((maxLat - minLat) * 0.05, 0.01);
                lonPad = max((maxLon - minLon) * 0.05, 0.01);
                bounds.minLat = minLat - latPad; bounds.maxLat = maxLat + latPad;
                bounds.minLon = minLon - lonPad; bounds.maxLon = maxLon + lonPad;
                bounds.isValid = true;
            elseif hasData && isfinite(minLat) && isfinite(maxLat) && isfinite(minLon) && isfinite(maxLon) && ...
                    minLat <= maxLat && minLon <= maxLon
                latPad = max((maxLat - minLat) * 0.05, 0.01);
                lonPad = max((maxLon - minLon) * 0.05, 0.01);
                bounds.minLat = minLat - latPad; bounds.maxLat = maxLat + latPad;
                bounds.minLon = minLon - lonPad; bounds.maxLon = maxLon + lonPad;
                bounds.isValid = true;
            end

            if hasData && isfinite(minAlt) && isfinite(maxAlt)
                altPad = max((maxAlt - minAlt) * 0.1, 100);
                altBounds.minAlt = minAlt - altPad;
                altBounds.maxAlt = maxAlt + altPad;
            end
        end
    end

    methods (Access = private)
        function validateRequiredColumns(~, dataTbl, mappedCols, fIdx)
            reqKeys = flightdash.util.AppConstants.REQ_KEYS;
            vars = dataTbl.Properties.VariableNames;
            missing = {};
            for i = 1:numel(reqKeys)
                keyName = reqKeys{i};
                if ~isfield(mappedCols, keyName) || isempty(mappedCols.(keyName)) || ...
                        ~ismember(mappedCols.(keyName), vars)
                    missing{end+1} = keyName; %#ok<AGROW>
                end
            end
            if ~isempty(missing)
                error('flightdash:DataMapping:MissingRequiredColumn', ...
                    'Required flight-data columns were not mapped: %s. Check option%d.dat or file headers.', ...
                    strjoin(missing, ', '), fIdx);
            end
        end

        function validateRequiredColumnData(~, dataTbl, mappedCols)
            timeVals = dataTbl.(mappedCols.Time);
            if ~isnumeric(timeVals) || numel(timeVals) < 2 || any(~isfinite(timeVals)) || ...
                    any(diff(timeVals) <= 0)
                error('flightdash:DataMapping:InvalidTimeColumn', ...
                    'Mapped Time column must be numeric, finite, and strictly increasing.');
            end

            latVals = dataTbl.(mappedCols.Lat);
            lonVals = dataTbl.(mappedCols.Lon);
            finiteLat = latVals(isfinite(latVals));
            finiteLon = lonVals(isfinite(lonVals));
            if ~isnumeric(latVals) || ~isnumeric(lonVals) || isempty(finiteLat) || isempty(finiteLon) || ...
                    any(finiteLat < -90 | finiteLat > 90) || any(finiteLon < -180 | finiteLon > 180)
                error('flightdash:DataMapping:InvalidGeoColumns', ...
                    'Mapped Lat/Lon columns must be numeric and within latitude/longitude bounds.');
            end
        end

        function colName = inferRequiredColumn(obj, reqKey, csvHeaders)
            colName = '';
            candidates = obj.requiredColumnCandidates(reqKey);
            if isempty(candidates), return; end
            normalizedHeaders = cell(size(csvHeaders));
            for hIdx = 1:numel(csvHeaders)
                normalizedHeaders{hIdx} = obj.normalizeHeaderName(csvHeaders{hIdx});
            end
            for cIdx = 1:numel(candidates)
                normalizedCandidate = obj.normalizeHeaderName(candidates{cIdx});
                matchIdx = find(strcmp(normalizedHeaders, normalizedCandidate), 1, 'first');
                if ~isempty(matchIdx)
                    colName = csvHeaders{matchIdx};
                    return;
                end
            end
        end

        function candidates = requiredColumnCandidates(~, reqKey)
            switch char(reqKey)
                case 'Time'
                    candidates = {'time_s', 'time', 'times', 'timestamp', 'elapsed_time', 'elapsedtime', 'seconds', 'sec', 't'};
                case 'Roll'
                    candidates = {'Roll', 'roll_deg', 'rolldeg', 'phi'};
                case 'Pitch'
                    candidates = {'Pitch', 'pitch_deg', 'pitchdeg', 'theta'};
                case 'Heading'
                    candidates = {'Heading', 'heading_deg', 'headingdeg', 'Yaw', 'yaw_deg', 'yawdeg', 'CourseAngle', 'course_angle', 'course', 'track', 'psi'};
                case 'Alt'
                    candidates = {'Altitude', 'altitude_m', 'altitude_ft', 'alt', 'PressAltitude', 'press_altitude', 'baro_altitude', 'height'};
                case 'Lat'
                    candidates = {'Latitude', 'latitude_deg', 'lat_deg', 'lat', 'gps_lat', 'gpslatitude'};
                case 'Lon'
                    candidates = {'Longitude', 'longitude_deg', 'lon_deg', 'lon', 'lng', 'long', 'gps_lon', 'gpslongitude'};
                otherwise
                    candidates = {};
            end
        end

        function normalized = normalizeHeaderName(~, value)
            normalized = lower(regexprep(char(value), '[^A-Za-z0-9]', ''));
        end
    end
end
