classdef MissingFileRepairDialog
    %MISSINGFILEREPAIRDIALOG  Phase D-3 Locate/Search/Skip workflow.
    %
    %   Modal-ish uifigure (uses figure focus, not real modality so
    %   the user can still see Project Explorer behind it). Mutates a
    %   LOCAL COPY of the project; the caller must commit by calling
    %   the returned applyFn or discard by closing the figure.
    %
    %   Operations exposed per missing file:
    %     - Locate File…    open uigetfile, replace path on accept
    %     - Search Folder…  uigetdir, search by basename, replace if hit
    %     - Skip            ignore this entry for this session
    %     - Remove Link     blank out the path in the model
    %
    %   No actual save is performed — the caller commits via
    %   app.Project = repairedCopy.

    methods (Static)
        function show(app)
            try
                if isempty(app) || ~isvalid(app) || isempty(app.Project)
                    return;
                end
                report = flightdash.project.ProjectHealthChecker.check(app.Project);
                missing = report.Items(~[report.Items.Exists]);
                if isempty(missing)
                    if ~isempty(app.StatusBar)
                        app.StatusBar.setMessage('Project Health: all files present');
                    end
                    return;
                end

                UIScale = flightdash.util.UIScale;
                fig = uifigure('Name', 'Missing External Files', ...
                    'Position', [220 220 UIScale.px(640) UIScale.px(360)], ...
                    'Resize', 'on');
                try
                    if isprop(app, 'CurrentThemeStruct') ...
                            && isstruct(app.CurrentThemeStruct) ...
                            && isfield(app.CurrentThemeStruct, 'Background')
                        fig.Color = app.CurrentThemeStruct.Background;
                    end
                catch
                end

                grid = uigridlayout(fig, [3 1], ...
                    'RowHeight', {UIScale.px(36), '1x', UIScale.px(40)}, ...
                    'RowSpacing', 6, 'Padding', [12 12 12 12]);

                uilabel(grid, 'Text', sprintf( ...
                    'The project references %d file(s) that were not found.', ...
                    numel(missing)), ...
                    'FontWeight', 'bold');

                tableData = cell(numel(missing), 3);
                for k = 1:numel(missing)
                    tableData{k, 1} = missing(k).Role;
                    tableData{k, 2} = missing(k).Path;
                    tableData{k, 3} = missing(k).Message;
                end
                t = uitable(grid, ...
                    'Data', tableData, ...
                    'ColumnName', {'Role', 'Path', 'Status'}, ...
                    'ColumnWidth', {120, 'auto', 140}, ...
                    'ColumnEditable', [false false false], ...
                    'RowName', []);
                t.Layout.Row = 2;

                btnRow = uigridlayout(grid, [1 5], ...
                    'ColumnWidth', {'1x', UIScale.px(110), UIScale.px(130), UIScale.px(110), UIScale.px(96)}, ...
                    'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
                btnRow.Layout.Row = 3;

                uilabel(btnRow, 'Text', '');
                uibutton(btnRow, 'Text', 'Locate…', ...
                    'ButtonPushedFcn', @(~,~) flightdash.ui.MissingFileRepairDialog.onLocate(app, t, missing));
                uibutton(btnRow, 'Text', 'Search folder…', ...
                    'ButtonPushedFcn', @(~,~) flightdash.ui.MissingFileRepairDialog.onSearchFolder(app, t, missing));
                uibutton(btnRow, 'Text', 'Remove link', ...
                    'ButtonPushedFcn', @(~,~) flightdash.ui.MissingFileRepairDialog.onRemoveLink(app, t, missing));
                uibutton(btnRow, 'Text', 'Close', ...
                    'ButtonPushedFcn', @(~,~) delete(fig));
            catch ME
                try, warning('MissingFileRepair:show', '%s', ME.message); catch, end
            end
        end

        function onLocate(app, table, missing)
            row = flightdash.ui.MissingFileRepairDialog.selectedRow(table);
            if row < 1, return; end
            entry = missing(row);
            [f, p] = uigetfile('*.*', sprintf('Locate %s', entry.Role));
            if isequal(f, 0), return; end
            newPath = fullfile(p, f);
            flightdash.ui.MissingFileRepairDialog.replacePath(app, entry, newPath);
            table.Data{row, 2} = newPath;
            table.Data{row, 3} = 'REPAIRED';
        end

        function onSearchFolder(app, table, missing)
            row = flightdash.ui.MissingFileRepairDialog.selectedRow(table);
            if row < 1, return; end
            entry = missing(row);
            folder = uigetdir(pwd, sprintf('Search folder for %s', entry.Role));
            if isequal(folder, 0), return; end
            [~, base, ext] = fileparts(entry.Path);
            target = fullfile(folder, [base ext]);
            if isfile(target)
                flightdash.ui.MissingFileRepairDialog.replacePath(app, entry, target);
                table.Data{row, 2} = target;
                table.Data{row, 3} = 'REPAIRED';
            else
                table.Data{row, 3} = 'NOT FOUND in folder';
            end
        end

        function onRemoveLink(app, table, missing)
            row = flightdash.ui.MissingFileRepairDialog.selectedRow(table);
            if row < 1, return; end
            entry = missing(row);
            flightdash.ui.MissingFileRepairDialog.replacePath(app, entry, '');
            table.Data{row, 2} = '';
            table.Data{row, 3} = 'LINK REMOVED';
        end
    end

    methods (Static, Access = private)
        function row = selectedRow(table)
            row = -1;
            try
                sel = table.Selection;
                if ~isempty(sel), row = sel(1, 1); end
            catch
            end
        end

        function replacePath(app, entry, newPath)
            % Map the entry.Role back to the right SessionModel field.
            % Format examples: flight_data_1, video_2, option1_dat.
            try
                role = char(entry.Role);
                oldPath = char(entry.Path);
                sessionIndex = flightdash.ui.MissingFileRepairDialog.entryNumber( ...
                    entry, 'SessionIndex', NaN);
                if startsWith(role, 'flight_data_')
                    ch = str2double(extractAfter(role, 'flight_data_'));
                    flightdash.ui.MissingFileRepairDialog.assignChannelPath( ...
                        app, 'FlightFilePath', ch, oldPath, newPath, sessionIndex);
                elseif startsWith(role, 'video_')
                    ch = str2double(extractAfter(role, 'video_'));
                    flightdash.ui.MissingFileRepairDialog.assignChannelPath( ...
                        app, 'VideoFilePath', ch, oldPath, newPath, sessionIndex);
                elseif startsWith(role, 'option')
                    ch = str2double(regexp(role, '\d+', 'match', 'once'));
                    flightdash.ui.MissingFileRepairDialog.assignChannelPath( ...
                        app, 'OptionFilePath', ch, oldPath, newPath, sessionIndex);
                elseif strcmp(role, 'project_json')
                    app.Project.ProjectFilePath = char(newPath);
                end
                try, app.Project.DirtyFlag = true; catch, end
            catch ME
                try, app.logCaught(ME, 'MissingFileRepair:assign'); catch, end
            end
        end

        function assignChannelPath(app, propName, ch, oldPath, newPath, sessionIndex)
            if ~isnumeric(ch) || ~isscalar(ch) || ~isfinite(ch) || ch ~= fix(ch)
                return;
            end
            ch = double(ch);
            targetIndex = flightdash.ui.MissingFileRepairDialog.resolveSessionIndex( ...
                app, propName, ch, oldPath, sessionIndex);
            if isempty(targetIndex)
                return;
            end
            for k = targetIndex(:)'
                sess = app.Project.Sessions(k);
                if ~isprop(sess, propName), continue; end
                paths = sess.(propName);
                if iscell(paths) && ch >= 1 && ch <= numel(paths)
                    paths{ch} = char(newPath);
                    sess.(propName) = paths;
                    try, sess = sess.touch(); catch, end
                    app.Project.Sessions(k) = sess;
                end
            end
        end

        function idx = resolveSessionIndex(app, propName, ch, oldPath, sessionIndex)
            idx = [];
            try
                nSessions = numel(app.Project.Sessions);
                if isnumeric(sessionIndex) && isscalar(sessionIndex) ...
                        && isfinite(sessionIndex) && sessionIndex >= 1 ...
                        && sessionIndex <= nSessions && sessionIndex == fix(sessionIndex)
                    idx = double(sessionIndex);
                    return;
                end
                for k = 1:nSessions
                    sess = app.Project.Sessions(k);
                    if ~isprop(sess, propName), continue; end
                    paths = sess.(propName);
                    if iscell(paths) && ch >= 1 && ch <= numel(paths) ...
                            && strcmp(char(paths{ch}), char(oldPath))
                        idx = k;
                        return;
                    end
                end
            catch
                idx = [];
            end
        end

        function value = entryNumber(entry, fieldName, defaultValue)
            value = defaultValue;
            try
                if isstruct(entry) && isfield(entry, fieldName)
                    value = double(entry.(fieldName));
                end
            catch
                value = defaultValue;
            end
        end
    end
end
