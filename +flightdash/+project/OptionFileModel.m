classdef OptionFileModel < handle
    %OPTIONFILEMODEL  Editable in-memory representation of an option*.dat.
    %
    %   Pre-PFE-1 foundation class. No GUI dependency. Used by the
    %   Project File Editor (Sections 3 / 4) to back the two editable
    %   regions of option1.dat / option2.dat:
    %
    %     Section 1 — Key Mapping  (Time / Roll / Pitch / Heading /
    %                               Alt / Lat / Lon → CSV column)
    %     Section 2 — Display Metadata (FieldName / Unit / Format /
    %                                   Order / ScaleFactor / Visible)
    %
    %   Section 2 supports add / remove / rename / order normalization.
    %
    %   The class is a `handle` so the editor's debounce timer can
    %   mutate a shared instance across sub-tab builders.

    properties (Access = public)
        FilePath         char     = ''
        FlightIndex      double   = 1
        Mapping          table
        Display          table
        HeaderComments   cell     = {}
        SectionComments  cell     = {}
        Dirty            logical  = false
        LastValidation   struct   = struct('OK', true, 'Errors', {{}}, 'Warnings', {{}})
    end

    properties (Constant, Access = public)
        CriticalKeys = {'Time', 'Lat', 'Lon', 'Alt'}
        OptionalKeys = {'Roll', 'Pitch', 'Heading'}
        DefaultUnit   = '-'
        DefaultFormat = '%.6f'
        DefaultScale  = 1
    end

    methods
        function obj = OptionFileModel(flightIndex)
            if nargin >= 1 && ~isempty(flightIndex)
                obj.FlightIndex = double(flightIndex);
            end
            obj.Mapping = obj.emptyMappingTable();
            obj.Display = obj.emptyDisplayTable();
        end

        function markDirty(obj)
            obj.Dirty = true;
        end

        function report = validate(obj, availableFields)
            % availableFields: cellstr of CSV header names; pass {} when
            % no flight data is loaded — availability is then 'unknown'.
            if nargin < 2, availableFields = {}; end
            report = struct('OK', true, 'Errors', {{}}, 'Warnings', {{}});
            hasFields = ~isempty(availableFields);

            % --- Mapping validation ---
            for k = 1:height(obj.Mapping)
                key = char(obj.Mapping.Key(k));
                mapped = char(obj.Mapping.MappedField(k));
                isCrit = ismember(key, obj.CriticalKeys);
                avail = false; msg = '';
                if isempty(mapped)
                    if isCrit
                        report.Errors{end+1} = sprintf('Critical key "%s" not mapped', key);
                        msg = 'CRITICAL MISSING';
                    else
                        report.Warnings{end+1} = sprintf('Optional key "%s" not mapped', key);
                        msg = 'optional missing';
                    end
                else
                    if hasFields
                        avail = any(strcmp(availableFields, mapped));
                        if ~avail
                            if isCrit
                                report.Errors{end+1} = sprintf( ...
                                    'Critical key "%s" maps to missing column "%s"', key, mapped);
                                msg = 'CRITICAL MISSING IN CSV';
                            else
                                report.Warnings{end+1} = sprintf( ...
                                    'Optional key "%s" maps to missing column "%s"', key, mapped);
                                msg = 'optional missing in CSV';
                            end
                        else
                            msg = 'OK';
                        end
                    else
                        msg = 'unknown (no CSV loaded)';
                    end
                end
                obj.Mapping.Available(k) = avail;
                obj.Mapping.Message(k) = string(msg);
            end

            % --- Display validation ---
            seen = strings(0, 1);
            for k = 1:height(obj.Display)
                fn = char(obj.Display.FieldName(k));
                avail = false; msg = '';
                if isempty(fn)
                    report.Errors{end+1} = sprintf('Display row %d has empty FieldName', k);
                    msg = 'EMPTY FIELD';
                elseif any(seen == string(fn))
                    report.Errors{end+1} = sprintf('Duplicate display FieldName "%s"', fn);
                    msg = 'DUPLICATE';
                else
                    seen(end+1, 1) = string(fn); %#ok<AGROW>
                    if hasFields
                        avail = any(strcmp(availableFields, fn));
                        if avail, msg = 'OK';
                        else,     msg = 'not in CSV'; end
                    else
                        msg = 'unknown (no CSV loaded)';
                    end
                end
                % Format sprintf test.
                fmt = char(obj.Display.Format(k));
                if ~isempty(fmt)
                    try
                        s = sprintf(fmt, 1.23); %#ok<NASGU>
                    catch
                        report.Errors{end+1} = sprintf( ...
                            'Display row %d ("%s") has invalid format "%s"', k, fn, fmt);
                        msg = 'INVALID FORMAT';
                    end
                end
                % Order / scale sanity.
                ordVal = obj.Display.Order(k);
                if ~(isnumeric(ordVal) && isfinite(ordVal) && ordVal == round(ordVal) && ordVal >= 1)
                    report.Errors{end+1} = sprintf( ...
                        'Display row %d ("%s") has invalid Order %g', k, fn, ordVal);
                end
                scl = obj.Display.ScaleFactor(k);
                if ~(isnumeric(scl) && isfinite(scl))
                    report.Errors{end+1} = sprintf( ...
                        'Display row %d ("%s") has invalid ScaleFactor', k, fn);
                end
                obj.Display.Available(k) = avail;
                obj.Display.Message(k) = string(msg);
            end

            % Critical-mapped fields should have a Display row.
            critMapped = strings(0, 1);
            for k = 1:height(obj.Mapping)
                if ismember(char(obj.Mapping.Key(k)), obj.CriticalKeys) ...
                        && ~isempty(char(obj.Mapping.MappedField(k)))
                    critMapped(end+1, 1) = string(char(obj.Mapping.MappedField(k))); %#ok<AGROW>
                end
            end
            for k = 1:numel(critMapped)
                if ~any(string(obj.Display.FieldName) == critMapped(k))
                    report.Warnings{end+1} = sprintf( ...
                        'Critical mapped field "%s" has no display row', char(critMapped(k)));
                end
            end

            report.OK = isempty(report.Errors);
            obj.LastValidation = report;
        end

        function mappedCols = toMappedCols(obj)
            % Returns a struct keyed by required-key with the mapped CSV
            % column name, matching the FlightDataLoader.applyOptionFile
            % output shape so app.Models(fIdx).mappedCols can be swapped.
            mappedCols = struct();
            keys = [obj.CriticalKeys, obj.OptionalKeys];
            for k = 1:numel(keys)
                idx = find(string(obj.Mapping.Key) == string(keys{k}), 1);
                if ~isempty(idx)
                    mappedCols.(keys{k}) = char(obj.Mapping.MappedField(idx));
                else
                    mappedCols.(keys{k}) = '';
                end
            end
        end

        function meta = toDisplayMeta(obj)
            % Returns struct array matching FlightDataLoader displayMeta.
            n = height(obj.Display);
            meta = repmat(struct('header', '', 'unit', '', 'format', '', ...
                'scale', 1, 'order', 1), 1, n);
            for k = 1:n
                meta(k).header = char(obj.Display.FieldName(k));
                meta(k).unit   = char(obj.Display.Unit(k));
                meta(k).format = char(obj.Display.Format(k));
                meta(k).scale  = double(obj.Display.ScaleFactor(k));
                meta(k).order  = double(obj.Display.Order(k));
            end
        end

        function addDisplayRow(obj, fieldName, unit, format, order, scaleFactor, visible)
            % Reject empty FieldName + duplicates.
            fieldName = char(fieldName);
            if isempty(strtrim(fieldName))
                error('OptionFileModel:EmptyFieldName', ...
                    'FieldName must be non-empty.');
            end
            if obj.hasDisplayField(fieldName)
                error('OptionFileModel:DuplicateFieldName', ...
                    'Display row "%s" already exists. Update instead.', fieldName);
            end
            if nargin < 3 || isempty(unit),         unit = obj.DefaultUnit;   end
            if nargin < 4 || isempty(format),       format = obj.DefaultFormat; end
            if nargin < 5 || isempty(order),        order = height(obj.Display) + 1; end
            if nargin < 6 || isempty(scaleFactor),  scaleFactor = obj.DefaultScale; end
            if nargin < 7 || isempty(visible),      visible = true; end
            newRow = table(string(fieldName), string(unit), string(format), ...
                double(order), double(scaleFactor), logical(visible), false, "", ...
                'VariableNames', {'FieldName', 'Unit', 'Format', ...
                    'Order', 'ScaleFactor', 'Visible', 'Available', 'Message'});
            obj.Display = [obj.Display; newRow];
            obj.markDirty();
        end

        function removeDisplayRow(obj, rowIndex)
            n = height(obj.Display);
            if rowIndex < 1 || rowIndex > n
                error('OptionFileModel:InvalidRowIndex', ...
                    'rowIndex %d outside [1,%d].', rowIndex, n);
            end
            fn = char(obj.Display.FieldName(rowIndex));
            % If the row is referenced by a critical mapping, refuse.
            for k = 1:height(obj.Mapping)
                if ismember(char(obj.Mapping.Key(k)), obj.CriticalKeys) ...
                        && strcmp(char(obj.Mapping.MappedField(k)), fn)
                    error('OptionFileModel:CriticalReference', ...
                        ['Cannot remove "%s" — it is referenced by ' ...
                         'critical mapping key "%s".'], fn, char(obj.Mapping.Key(k)));
                end
            end
            obj.Display(rowIndex, :) = [];
            obj.markDirty();
        end

        function normalizeDisplayOrder(obj)
            n = height(obj.Display);
            if n == 0, return; end
            [~, sortIdx] = sort(obj.Display.Order);
            obj.Display = obj.Display(sortIdx, :);
            obj.Display.Order = (1:n)';
            obj.markDirty();
        end

        function tf = hasDisplayField(obj, fieldName)
            tf = false;
            try
                tf = any(string(obj.Display.FieldName) == string(char(fieldName)));
            catch
            end
        end

        function setMapping(obj, key, mappedField)
            % Update or insert a mapping row.
            key = char(key);
            mappedField = char(mappedField);
            idx = find(string(obj.Mapping.Key) == string(key), 1);
            if isempty(idx)
                isCrit = ismember(key, obj.CriticalKeys);
                reqType = "optional"; if isCrit, reqType = "critical"; end
                newRow = table(string(key), string(mappedField), reqType, ...
                    false, "", 'VariableNames', ...
                    {'Key', 'MappedField', 'RequiredType', 'Available', 'Message'});
                obj.Mapping = [obj.Mapping; newRow];
            else
                obj.Mapping.MappedField(idx) = string(mappedField);
                obj.Mapping.Message(idx) = "";
            end
            obj.markDirty();
        end
    end

    methods (Static, Access = public)
        function t = emptyMappingTable()
            t = table('Size', [0 5], ...
                'VariableTypes', {'string', 'string', 'string', 'logical', 'string'}, ...
                'VariableNames', {'Key', 'MappedField', 'RequiredType', 'Available', 'Message'});
        end

        function t = emptyDisplayTable()
            t = table('Size', [0 8], ...
                'VariableTypes', {'string', 'string', 'string', 'double', 'double', 'logical', 'logical', 'string'}, ...
                'VariableNames', {'FieldName', 'Unit', 'Format', 'Order', 'ScaleFactor', 'Visible', 'Available', 'Message'});
        end
    end
end
