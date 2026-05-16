classdef OptionFileParser
    %OPTIONFILEPARSER  Disk I/O for option*.dat files (Pre-PFE-1).
    %
    %   Pure static API. Reads and writes the two-section option file
    %   format used by FlightDataDashboard / FlightDataLoader:
    %
    %     Section 1 — Key Mapping     "Key : MappedField"
    %     Section 2 — Display Metadata "FieldName,Unit,Format,Order,ScaleFactor"
    %
    %   Sections are separated by `#` comment lines. The writer
    %   re-emits the structured model — display rows may be added or
    %   removed via OptionFileModel.add/removeDisplayRow before write.
    %
    %   write() always creates a timestamped backup and rotates so at
    %   most MaxBackups copies survive.

    properties (Constant, Access = public)
        DisplayMetadataHeader = ...
            ['# Flight data field name, unit, format, ' ...
             'order, scale factor (written by FlightReviewStudio)']
        KeyMappingHeader = '# Key mapping: required-key : CSV-column'
        MaxBackups = 5
    end

    methods (Static)
        function model = read(filePath)
            model = flightdash.project.OptionFileModel();
            model.FilePath = char(filePath);
            if ~isfile(model.FilePath)
                return;
            end
            try
                lines = readlines(model.FilePath, 'EmptyLineRule', 'skip');
            catch ME
                error('OptionFileParser:ReadFailed', ...
                    'Failed to read %s: %s', model.FilePath, ME.message);
            end
            section = 0;
            % Pre-fill mapping rows with the canonical key order so the
            % Section-1 grid in the editor always has the same 7 rows.
            keys = [model.CriticalKeys, model.OptionalKeys];
            for k = 1:numel(keys)
                model.setMapping(keys{k}, '');
            end
            model.Dirty = false;

            for i = 1:numel(lines)
                lineStr = strtrim(lines(i));
                if isempty(lineStr), continue; end
                if startsWith(lineStr, '#')
                    if section == 0
                        model.HeaderComments{end+1} = char(lineStr); %#ok<AGROW>
                    else
                        model.SectionComments{end+1} = char(lineStr); %#ok<AGROW>
                    end
                    section = section + 1;
                    continue;
                end
                if section <= 1
                    % Mapping line.
                    parts = split(lineStr, ':');
                    if length(parts) >= 2
                        key = char(strtrim(parts(1)));
                        val = char(strtrim(parts(2)));
                        if ~isempty(key)
                            model.setMapping(key, val);
                        end
                    end
                else
                    % Display metadata line.
                    parts = split(lineStr, ',');
                    if length(parts) < 4, continue; end
                    fn = char(strtrim(parts(1)));
                    if isempty(fn), continue; end
                    unit = char(strtrim(parts(2)));
                    fmt  = char(strtrim(parts(3)));
                    ord  = str2double(strtrim(parts(4)));
                    scl  = 1;
                    if length(parts) >= 5
                        scl = str2double(strtrim(parts(5)));
                    end
                    if isnan(ord), ord = height(model.Display) + 1; end
                    if isnan(scl), scl = 1; end
                    try
                        model.addDisplayRow(fn, unit, fmt, ord, scl, true);
                    catch
                        % Duplicate / invalid; skip silently — validate()
                        % surfaces a structured report later.
                    end
                end
            end
            model.Dirty = false;
        end

        function write(model, filePath)
            if nargin < 2 || isempty(filePath), filePath = model.FilePath; end
            if isempty(filePath)
                error('OptionFileParser:NoPath', 'Destination file path missing.');
            end
            % Backup + rotate first.
            try
                if isfile(filePath)
                    flightdash.project.OptionFileParser.backup(filePath);
                    flightdash.project.OptionFileParser.rotateBackups(filePath, ...
                        flightdash.project.OptionFileParser.MaxBackups);
                end
            catch
            end

            fid = fopen(filePath, 'w', 'n', 'UTF-8');
            if fid == -1
                error('OptionFileParser:OpenFailed', ...
                    'Failed to open %s for writing.', filePath);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

            % Header / Section 1.
            fprintf(fid, '%s\n', flightdash.project.OptionFileParser.KeyMappingHeader);
            keys = [model.CriticalKeys, model.OptionalKeys];
            for k = 1:numel(keys)
                idx = find(string(model.Mapping.Key) == string(keys{k}), 1);
                if isempty(idx)
                    val = '';
                else
                    val = char(model.Mapping.MappedField(idx));
                end
                fprintf(fid, '%s : %s\n', keys{k}, val);
            end
            fprintf(fid, '\n');

            % Section 2 — display metadata.
            fprintf(fid, '%s\n', flightdash.project.OptionFileParser.DisplayMetadataHeader);
            for k = 1:height(model.Display)
                fn  = char(model.Display.FieldName(k));
                if isempty(fn), continue; end
                unit = char(model.Display.Unit(k));
                fmt  = char(model.Display.Format(k));
                ord  = double(model.Display.Order(k));
                scl  = double(model.Display.ScaleFactor(k));
                fprintf(fid, '%s,%s,%s,%g,%g\n', fn, unit, fmt, ord, scl);
            end

            model.FilePath = char(filePath);
            model.Dirty = false;
        end

        function report = validate(model, availableFields)
            if nargin < 2, availableFields = {}; end
            report = model.validate(availableFields);
        end

        function backupPath = backup(filePath)
            backupPath = '';
            try
                if ~isfile(filePath), return; end
                stamp = datestr(now, 'yyyymmdd_HHMMSS');
                backupPath = sprintf('%s.bak_%s', filePath, stamp);
                copyfile(filePath, backupPath);
            catch ME
                try, flightdash.util.ErrorLog.log(ME, 'OptionFileParser:backup'); catch, end
            end
        end

        function rotateBackups(filePath, maxCount)
            if nargin < 2 || isempty(maxCount)
                maxCount = flightdash.project.OptionFileParser.MaxBackups;
            end
            try
                [folder, name, ext] = fileparts(filePath);
                if isempty(folder), folder = pwd; end
                pattern = [name ext '.bak_*'];
                listing = dir(fullfile(folder, pattern));
                if numel(listing) <= maxCount, return; end
                [~, order] = sort([listing.datenum], 'descend');
                listing = listing(order);
                for k = (maxCount + 1):numel(listing)
                    try
                        delete(fullfile(listing(k).folder, listing(k).name));
                    catch
                    end
                end
            catch
            end
        end
    end
end
