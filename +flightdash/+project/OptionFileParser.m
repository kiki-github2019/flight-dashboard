classdef OptionFileParser
    %OPTIONFILEPARSER Disk I/O for option*.dat files.
    %
    %   Lines beginning with # are comments. A comment can also declare
    %   the section when it includes [mapping] or [display]. Older
    %   descriptive section comments are still recognized by keyword.

    properties (Constant, Access = public)
        DisplayMetadataHeader = ...
            '# [display] field name, unit, numeric format, display order, scale factor'
        KeyMappingHeader = '# [mapping] required key : CSV column'
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

            keys = [model.CriticalKeys, model.OptionalKeys];
            for k = 1:numel(keys)
                model.setMapping(keys{k}, '');
            end
            model.Dirty = false;

            section = '';
            for i = 1:numel(lines)
                lineStr = strtrim(lines(i));
                if isempty(lineStr), continue; end

                if startsWith(lineStr, '#')
                    comment = char(strtrim(extractAfter(lineStr, 1)));
                    nextSection = flightdash.project.OptionFileParser.sectionFromComment(comment);
                    if ~isempty(nextSection)
                        section = nextSection;
                    end
                    if strcmp(section, 'mapping') || isempty(section)
                        model.HeaderComments{end+1} = char(lineStr); %#ok<AGROW>
                    else
                        model.SectionComments{end+1} = char(lineStr); %#ok<AGROW>
                    end
                    continue;
                end

                if isempty(section)
                    section = flightdash.project.OptionFileParser.sectionFromData(lineStr);
                end

                if strcmp(section, 'mapping')
                    parsed = flightdash.project.OptionFileParser.parseMappingLine(model, lineStr);
                    if ~parsed && contains(lineStr, ',')
                        flightdash.project.OptionFileParser.parseDisplayLine(model, lineStr);
                    end
                elseif strcmp(section, 'display')
                    parsed = flightdash.project.OptionFileParser.parseDisplayLine(model, lineStr);
                    if ~parsed && contains(lineStr, ':')
                        flightdash.project.OptionFileParser.parseMappingLine(model, lineStr);
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
            filePath = char(filePath);
            [folder, ~, ~] = fileparts(filePath);
            if isempty(folder), folder = pwd; end
            if ~isfolder(folder), mkdir(folder); end

            tmpPath = [tempname(folder) '.tmp'];
            tmpCleanup = onCleanup(@() flightdash.project.OptionFileParser.deleteIfExists(tmpPath)); %#ok<NASGU>
            fid = fopen(tmpPath, 'w', 'n', 'UTF-8');
            if fid == -1
                error('OptionFileParser:OpenFailed', ...
                    'Failed to open %s for writing.', tmpPath);
            end
            closeCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

            try
                flightdash.project.OptionFileParser.writeModel(fid, model);
                clear closeCleanup;
            catch ME
                clear closeCleanup;
                rethrow(ME);
            end

            if isfile(filePath)
                flightdash.project.OptionFileParser.backup(filePath);
                flightdash.project.OptionFileParser.rotateBackups(filePath, ...
                    flightdash.project.OptionFileParser.MaxBackups);
            end
            [ok, msg] = movefile(tmpPath, filePath, 'f');
            if ~ok
                error('OptionFileParser:MoveFailed', ...
                    'Failed to replace %s: %s', filePath, msg);
            end
            clear tmpCleanup;

            model.FilePath = filePath;
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
                listing = dir(fullfile(folder, [name ext '.bak_*']));
                if numel(listing) <= maxCount, return; end
                [~, order] = sort([listing.datenum], 'descend');
                listing = listing(order);
                for k = (maxCount + 1):numel(listing)
                    try, delete(fullfile(listing(k).folder, listing(k).name)); catch, end
                end
            catch
            end
        end

        function section = sectionFromComment(comment)
            section = '';
            text = lower(char(comment));
            if contains(text, '[mapping]') || contains(text, 'key mapping') || ...
                    (contains(text, 'mapping') && contains(text, 'key')) || ...
                    (contains(text, 'mapping') && contains(text, 'variable'))
                section = 'mapping';
            elseif contains(text, '[display]') || contains(text, 'display') || ...
                    contains(text, 'field name') || ...
                    (contains(text, 'format') && contains(text, 'order')) || ...
                    contains(text, 'scale factor')
                section = 'display';
            end
        end

        function section = sectionFromData(lineStr)
            if contains(lineStr, ':')
                section = 'mapping';
            elseif contains(lineStr, ',')
                section = 'display';
            else
                section = '';
            end
        end

        function tf = parseMappingLine(model, lineStr)
            tf = false;
            parts = split(lineStr, ':');
            if length(parts) < 2, return; end
            key = char(strtrim(parts(1)));
            if isempty(key) || ~ismember(key, [model.CriticalKeys, model.OptionalKeys])
                return;
            end
            val = char(strtrim(strjoin(parts(2:end), ':')));
            model.setMapping(key, val);
            tf = true;
        end

        function tf = parseDisplayLine(model, lineStr)
            tf = false;
            parts = split(lineStr, ',');
            if length(parts) < 4, return; end
            fn = char(strtrim(parts(1)));
            if isempty(fn), return; end
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
                tf = true;
            catch
            end
        end

        function writeModel(fid, model)
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
        end

        function deleteIfExists(filePath)
            try
                if isfile(filePath), delete(filePath); end
            catch
            end
        end
    end
end
