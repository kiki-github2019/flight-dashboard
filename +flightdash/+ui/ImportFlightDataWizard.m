classdef ImportFlightDataWizard < handle
    %IMPORTFLIGHTDATAWIZARD  Phase E-2 multi-step CSV + option mapping.
    %
    %   Single uifigure with one body grid that the next-step methods
    %   repopulate. Steps:
    %     1. Pick channel (1 or 2) + CSV path.
    %     2. Pick option*.dat (auto-detect sample_data + same-folder).
    %     3. Show mapping table (Required / Mapped / Status) +
    %        20-row head preview.
    %     4. Confirm -> stamp Session.FlightFilePath / OptionFilePath
    %        and call the existing FileController loader to commit.

    properties (Access = public)
        App
        UIFigure
        BodyGrid
        StatusLabel
        ChannelField
        CsvPathField
        OptionPathField
        MappingTable
        HeadTable
        CsvPath  char = ''
        OptionPath char = ''
        ChannelIdx double = 1
        Preview = struct()
    end

    methods
        function obj = ImportFlightDataWizard(app)
            obj.App = app;
        end

        function show(obj)
            try
                obj.build();
                obj.renderStep1();
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                    obj.UIFigure.Visible = 'on';
                    figure(obj.UIFigure);
                end
            catch ME
                try, warning('ImportFlightDataWizard:show', '%s', ME.message); catch, end
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                    delete(obj.UIFigure);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function build(obj)
            UIScale = flightdash.util.UIScale;
            obj.UIFigure = uifigure('Name', 'Import Flight Data Wizard', ...
                'Position', [200 200 UIScale.px(720) UIScale.px(520)], ...
                'Visible', 'off');
            try
                if isprop(obj.App, 'CurrentThemeStruct') ...
                        && isstruct(obj.App.CurrentThemeStruct) ...
                        && isfield(obj.App.CurrentThemeStruct, 'Background')
                    obj.UIFigure.Color = obj.App.CurrentThemeStruct.Background;
                end
            catch
            end
            root = uigridlayout(obj.UIFigure, [2 1], ...
                'RowHeight', {'1x', UIScale.px(28)}, ...
                'RowSpacing', 6, 'Padding', [12 12 12 12]);
            obj.BodyGrid = uigridlayout(root, [1 1], 'Padding', [0 0 0 0]);
            obj.StatusLabel = uilabel(root, 'Text', '', 'FontColor', [0.35 0.35 0.35]);
        end

        function clearBody(obj)
            try
                kids = obj.BodyGrid.Children;
                for i = numel(kids):-1:1
                    try, delete(kids(i)); catch, end
                end
            catch
            end
        end

        function renderStep1(obj)
            UIScale = flightdash.util.UIScale;
            obj.clearBody();
            g = uigridlayout(obj.BodyGrid, [5 2], ...
                'ColumnWidth', {UIScale.px(140), '1x'}, ...
                'RowHeight', {UIScale.px(28), UIScale.px(28), UIScale.px(28), '1x', UIScale.px(36)}, ...
                'RowSpacing', 6, 'Padding', [4 4 4 4]);
            uilabel(g, 'Text', 'Step 1 — CSV file', 'FontWeight', 'bold');
            uilabel(g, 'Text', 'Pick the flight data CSV and channel to import into.', ...
                'FontColor', [0.4 0.4 0.4]);

            uilabel(g, 'Text', 'Channel (Flight #)');
            obj.ChannelField = uispinner(g, 'Limits', [1 2], 'Step', 1, ...
                'Value', obj.ChannelIdx);

            uilabel(g, 'Text', 'CSV path');
            csvRow = uigridlayout(g, [1 2], ...
                'ColumnWidth', {'1x', UIScale.px(96)}, ...
                'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
            obj.CsvPathField = uieditfield(csvRow, 'text', 'Value', obj.CsvPath);
            uibutton(csvRow, 'Text', 'Browse…', ...
                'ButtonPushedFcn', @(~,~) obj.onPickCsv());

            % Spacer.
            uilabel(g, 'Text', '');
            uilabel(g, 'Text', '');

            % Nav buttons.
            btnRow = uigridlayout(g, [1 3], ...
                'ColumnWidth', {'1x', UIScale.px(96), UIScale.px(96)}, ...
                'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
            btnRow.Layout.Column = [1 2];
            uilabel(btnRow, 'Text', '');
            uibutton(btnRow, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) delete(obj));
            uibutton(btnRow, 'Text', 'Next →', ...
                'ButtonPushedFcn', @(~,~) obj.advanceToStep2());
        end

        function onPickCsv(obj)
            [f, p] = uigetfile({'*.csv;*.txt', 'Flight data files (*.csv, *.txt)'}, ...
                'Pick flight data CSV');
            if isequal(f, 0), return; end
            obj.CsvPath = fullfile(p, f);
            obj.CsvPathField.Value = obj.CsvPath;
        end

        function advanceToStep2(obj)
            obj.CsvPath = char(obj.CsvPathField.Value);
            obj.ChannelIdx = double(obj.ChannelField.Value);
            if isempty(obj.CsvPath) || ~isfile(obj.CsvPath)
                obj.setStatus('Pick a valid CSV path first.');
                return;
            end
            obj.renderStep2();
        end

        function renderStep2(obj)
            UIScale = flightdash.util.UIScale;
            obj.clearBody();
            % Auto-detect option file: same folder as CSV, then sample_data.
            if isempty(obj.OptionPath)
                obj.OptionPath = obj.autoDetectOptionPath();
            end
            g = uigridlayout(obj.BodyGrid, [4 2], ...
                'ColumnWidth', {UIScale.px(140), '1x'}, ...
                'RowHeight', {UIScale.px(28), UIScale.px(28), '1x', UIScale.px(36)}, ...
                'RowSpacing', 6, 'Padding', [4 4 4 4]);
            uilabel(g, 'Text', 'Step 2 — Option file', 'FontWeight', 'bold');
            uilabel(g, 'Text', sprintf('Channel %d — pick the option%d.dat mapping (optional).', ...
                obj.ChannelIdx, obj.ChannelIdx), 'FontColor', [0.4 0.4 0.4]);

            uilabel(g, 'Text', 'Option file');
            row = uigridlayout(g, [1 2], ...
                'ColumnWidth', {'1x', UIScale.px(96)}, ...
                'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
            obj.OptionPathField = uieditfield(row, 'text', 'Value', obj.OptionPath);
            uibutton(row, 'Text', 'Browse…', ...
                'ButtonPushedFcn', @(~,~) obj.onPickOption());

            uilabel(g, 'Text', '');
            uilabel(g, 'Text', '');

            btnRow = uigridlayout(g, [1 4], ...
                'ColumnWidth', {'1x', UIScale.px(96), UIScale.px(96), UIScale.px(96)}, ...
                'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
            btnRow.Layout.Column = [1 2];
            uilabel(btnRow, 'Text', '');
            uibutton(btnRow, 'Text', '← Back', ...
                'ButtonPushedFcn', @(~,~) obj.renderStep1());
            uibutton(btnRow, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) delete(obj));
            uibutton(btnRow, 'Text', 'Preview →', ...
                'ButtonPushedFcn', @(~,~) obj.advanceToStep3());
        end

        function onPickOption(obj)
            [f, p] = uigetfile({'*.dat', 'Option mapping (*.dat)'}, 'Pick option file');
            if isequal(f, 0), return; end
            obj.OptionPath = fullfile(p, f);
            obj.OptionPathField.Value = obj.OptionPath;
        end

        function path = autoDetectOptionPath(obj)
            path = '';
            try
                csvFolder = fileparts(obj.CsvPath);
                candidate = fullfile(csvFolder, sprintf('option%d.dat', obj.ChannelIdx));
                if isfile(candidate), path = candidate; return; end
                here = fileparts(mfilename('fullpath'));
                root = fullfile(here, '..', '..');
                candidate = fullfile(root, 'sample_data', sprintf('option%d.dat', obj.ChannelIdx));
                if isfile(candidate), path = candidate; return; end
            catch
            end
        end

        function advanceToStep3(obj)
            obj.OptionPath = char(obj.OptionPathField.Value);
            try
                loader = flightdash.model.FlightDataLoader();
                obj.Preview = loader.previewMapping(obj.CsvPath, obj.OptionPath);
            catch ME
                obj.setStatus(sprintf('Preview failed: %s', ME.message));
                return;
            end
            obj.renderStep3();
        end

        function renderStep3(obj)
            UIScale = flightdash.util.UIScale;
            obj.clearBody();
            g = uigridlayout(obj.BodyGrid, [4 1], ...
                'RowHeight', {UIScale.px(28), UIScale.px(180), '1x', UIScale.px(36)}, ...
                'RowSpacing', 6, 'Padding', [4 4 4 4]);
            verdict = 'Mapping preview — OK';
            if obj.Preview.HasCriticalMissing
                verdict = 'Mapping preview — CRITICAL columns missing';
            elseif obj.Preview.HasOptionalMissing
                verdict = 'Mapping preview — optional columns missing (will warn)';
            end
            uilabel(g, 'Text', verdict, 'FontWeight', 'bold');

            obj.MappingTable = uitable(g, ...
                'Data', obj.Preview.Rows, ...
                'ColumnName', {'Required key', 'Mapped column', 'Status'}, ...
                'ColumnWidth', {130, 'auto', 200}, ...
                'RowName', []);

            % Head preview (first 20 rows).
            try
                obj.HeadTable = uitable(g, ...
                    'Data', obj.Preview.HeadPreview, ...
                    'RowName', []);
            catch
                obj.HeadTable = uilabel(g, 'Text', '(no CSV preview)', ...
                    'FontColor', [0.5 0.5 0.5]);
            end

            btnRow = uigridlayout(g, [1 4], ...
                'ColumnWidth', {'1x', UIScale.px(96), UIScale.px(96), UIScale.px(120)}, ...
                'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
            uilabel(btnRow, 'Text', '');
            uibutton(btnRow, 'Text', '← Back', ...
                'ButtonPushedFcn', @(~,~) obj.renderStep2());
            uibutton(btnRow, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) delete(obj));
            cancelOnCrit = obj.Preview.HasCriticalMissing;
            confirmBtn = uibutton(btnRow, 'Text', 'Confirm & Load', ...
                'ButtonPushedFcn', @(~,~) obj.commit());
            if cancelOnCrit
                confirmBtn.Enable = 'off';
                obj.setStatus('Cannot load: critical columns missing. Pick a different CSV or option file.');
            end
        end

        function commit(obj)
            % Apply the mapping into the active session's model AND
            % invoke the existing dashboard load path so the user sees
            % their data in the plots/markers immediately.
            try
                dash = obj.activeDashboard();
                if isempty(dash) || ~isvalid(dash)
                    obj.setStatus('No active dashboard — Confirm aborted.');
                    return;
                end
                fIdx = max(1, min(2, obj.ChannelIdx));
                if ismethod(dash, 'loadFlightFromPath')
                    dash.loadFlightFromPath(fIdx, obj.CsvPath);
                else
                    % Fallback: have the dashboard's FileController open the
                    % path via its public API.
                    try
                        if isprop(dash, 'FileCtrl') && ~isempty(dash.FileCtrl) ...
                                && ismethod(dash.FileCtrl, 'loadFlightFromPath')
                            dash.FileCtrl.loadFlightFromPath(fIdx, obj.CsvPath);
                        else
                            obj.setStatus('Loader path not exposed; copy CSV manually.');
                            return;
                        end
                    catch
                        obj.setStatus('Loader path not exposed; copy CSV manually.');
                        return;
                    end
                end
                % Stamp paths into the active session model for Pack /
                % Health Check.
                obj.stampSessionPaths();
                obj.setStatus('Imported. Closing wizard.');
                delete(obj);
            catch ME
                obj.setStatus(sprintf('Commit failed: %s', ME.message));
            end
        end

        function stampSessionPaths(obj)
            try
                if isempty(obj.App) || ~isvalid(obj.App) || isempty(obj.App.Project)
                    return;
                end
                activeId = char(obj.App.ActiveSessionId);
                for k = 1:numel(obj.App.Project.Sessions)
                    sess = obj.App.Project.Sessions(k);
                    if strcmp(char(sess.SessionId), activeId)
                        ff = sess.FlightFilePath;
                        of = sess.OptionFilePath;
                        if ~iscell(ff), ff = {'',''}; end
                        if ~iscell(of), of = {'',''}; end
                        if numel(ff) < 2, ff{2} = ''; end
                        if numel(of) < 2, of{2} = ''; end
                        ch = max(1, min(2, obj.ChannelIdx));
                        ff{ch} = obj.CsvPath;
                        if isfile(obj.OptionPath), of{ch} = obj.OptionPath; end
                        sess.FlightFilePath = ff;
                        sess.OptionFilePath = of;
                        obj.App.Project.Sessions(k) = sess;
                        obj.App.Project.DirtyFlag = true;
                        break;
                    end
                end
            catch
            end
        end

        function dash = activeDashboard(obj)
            dash = [];
            try
                if ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace) ...
                        && ismethod(obj.App.Workspace, 'activeDashboard')
                    dash = obj.App.Workspace.activeDashboard();
                end
            catch
            end
        end

        function setStatus(obj, txt)
            try
                if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                    obj.StatusLabel.Text = char(txt);
                end
            catch
            end
        end
    end
end
