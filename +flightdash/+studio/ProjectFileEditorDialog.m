classdef ProjectFileEditorDialog < handle
    %PROJECTFILEEDITORDIALOG  Modeless editor for option*.dat files (PFE-1 shell).
    %
    %   Owns its own uifigure separate from the Studio window. Single
    %   instance per Studio app — enforced by FlightReviewStudioApp
    %   storing the handle in app.ProjectEditor and reusing/focusing on
    %   the second openProjectFileEditor() call.
    %
    %   This phase ships the dialog shell + the Display Metadata
    %   add / delete / move / normalize / validate / save workflow.
    %   Heavy dashboard apply remains a non-goal (see prompt §9).

    properties (Access = public)
        App                          % flightdash.studio.FlightReviewStudioApp (back-ref)
        Figure          matlab.ui.Figure
        TabGroup        matlab.ui.container.TabGroup
        StatusLabel     matlab.ui.control.Label

        Option1Model    % flightdash.project.OptionFileModel
        Option2Model    % flightdash.project.OptionFileModel

        Option1Tab      struct = struct()
        Option2Tab      struct = struct()
        FilesTab        struct = struct()
        ApplyTab        struct = struct()
        HealthTab       struct = struct()

        AvailableFields cell    = {}
        FlightIndex     double  = 1

        % Dirty bookkeeping — PFE-1 surfaces these via the close prompt.
        ProjectDirty    logical = false
        Option1Dirty    logical = false
        Option2Dirty    logical = false
        DashboardDirty  logical = false

        IsDeleting      logical = false
    end

    properties (Constant, Access = private)
        DefaultUnit   = '-'
        DefaultFormat = '%.6f'
    end

    methods
        function obj = ProjectFileEditorDialog(app)
            obj.App = app;
            obj.Option1Model = flightdash.project.OptionFileModel(1);
            obj.Option2Model = flightdash.project.OptionFileModel(2);
            obj.buildUI();
            obj.loadFromAppContext();
        end

        function delete(obj)
            if obj.IsDeleting, return; end
            obj.IsDeleting = true;
            try
                if ~isempty(obj.App) && isa(obj.App, 'handle') && isvalid(obj.App)
                    if isprop(obj.App, 'ProjectEditor') && isequal(obj.App.ProjectEditor, obj)
                        obj.App.ProjectEditor = [];
                    end
                end
            catch
            end
            try
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    delete(obj.Figure);
                end
            catch
            end
        end

        function focus(obj)
            try
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    figure(obj.Figure);
                end
            catch
            end
        end

        function tf = isDirty(obj)
            tf = obj.ProjectDirty || obj.Option1Dirty || obj.Option2Dirty || obj.DashboardDirty;
        end

        function tf = confirmClose(obj)
            % Pre-PFE-5 contract: return true to allow Studio close,
            % false to abort. Save All / Discard / Cancel only when dirty.
            tf = true;
            try
                if ~obj.isDirty()
                    obj.cleanup();
                    return;
                end
                choice = obj.askDirtyChoice();
                switch lower(choice)
                    case 'save all'
                        ok = obj.saveAll();
                        if ~ok, tf = false; return; end
                        obj.cleanup();
                    case 'discard'
                        obj.clearDirty();
                        obj.cleanup();
                    otherwise
                        tf = false;
                end
            catch ME
                try, obj.logCaught(ME, 'PFE:confirmClose'); catch, end
                tf = true;
                obj.cleanup();
            end
        end

        function setAvailableFields(obj, fields, flightIndex)
            if nargin >= 2 && iscell(fields), obj.AvailableFields = fields; end
            if nargin >= 3 && ~isempty(flightIndex), obj.FlightIndex = double(flightIndex); end
            obj.runValidation(1);
            obj.runValidation(2);
        end
    end

    % ---------- Public-but-internal add/delete API (used by tests) ----------
    methods (Access = public)
        function addDisplayRow(obj, optIdx)
            model = obj.modelFor(optIdx);
            base = 'NewField';
            name = base;
            suffix = 2;
            while model.hasDisplayField(name)
                name = sprintf('%s_%d', base, suffix);
                suffix = suffix + 1;
            end
            order = height(model.Display) + 1;
            model.addDisplayRow(name, obj.DefaultUnit, obj.DefaultFormat, order, 1, true);
            obj.markOptionDirty(optIdx);
            obj.refreshDisplayTable(optIdx);
            obj.runValidation(optIdx);
        end

        function tf = deleteDisplayRow(obj, optIdx, rowIndex, force)
            tf = false;
            if nargin < 4, force = false; end
            model = obj.modelFor(optIdx);
            if rowIndex < 1 || rowIndex > height(model.Display), return; end
            fn = char(model.Display.FieldName(rowIndex));

            critRef = obj.findMappingReference(model, fn, model.CriticalKeys);
            if ~isempty(critRef)
                obj.alert(sprintf( ...
                    ['Cannot delete display row "%s" — it is referenced ' ...
                     'by critical mapping key "%s".'], fn, critRef), ...
                    'Deletion blocked', 'error');
                return;
            end
            optRef = obj.findMappingReference(model, fn, model.OptionalKeys);
            if ~isempty(optRef) && ~force
                if ~obj.confirm(sprintf( ...
                        ['Display row "%s" is referenced by optional ' ...
                         'mapping key "%s". Delete anyway?'], fn, optRef), ...
                        'Confirm deletion')
                    return;
                end
            elseif ~force
                if ~obj.confirm(sprintf('Delete display row "%s"?', fn), ...
                        'Confirm deletion')
                    return;
                end
            end
            try
                model.removeDisplayRow(rowIndex);
            catch ME
                obj.alert(ME.message, 'Deletion failed', 'error');
                return;
            end
            obj.markOptionDirty(optIdx);
            obj.refreshDisplayTable(optIdx);
            obj.runValidation(optIdx);
            tf = true;
        end

        function moveDisplayRow(obj, optIdx, rowIndex, direction)
            model = obj.modelFor(optIdx);
            n = height(model.Display);
            if rowIndex < 1 || rowIndex > n, return; end
            newIdx = rowIndex + sign(direction);
            if newIdx < 1 || newIdx > n, return; end
            model.Display([rowIndex newIdx], :) = model.Display([newIdx rowIndex], :);
            model.markDirty();
            obj.markOptionDirty(optIdx);
            obj.refreshDisplayTable(optIdx);
        end

        function normalizeOrder(obj, optIdx)
            model = obj.modelFor(optIdx);
            model.normalizeDisplayOrder();
            obj.markOptionDirty(optIdx);
            obj.refreshDisplayTable(optIdx);
        end

        function ok = saveOption(obj, optIdx)
            ok = false;
            model = obj.modelFor(optIdx);
            if isempty(model.FilePath)
                obj.alert('No option file path set; nothing to save.', ...
                    'Save failed', 'warning');
                return;
            end
            report = model.validate(obj.AvailableFields);
            if ~report.OK
                obj.alert(sprintf( ...
                    'Validation failed (%d error(s)). Fix before saving.', ...
                    numel(report.Errors)), 'Save blocked', 'error');
                return;
            end
            try
                flightdash.project.OptionFileParser.write(model, model.FilePath);
            catch ME
                obj.alert(sprintf('Write failed: %s', ME.message), ...
                    'Save failed', 'error');
                return;
            end
            obj.clearOptionDirty(optIdx);
            obj.setStatus(sprintf('Saved option%d.dat (%s).', optIdx, ...
                datestr(now, 'HH:MM:SS')));
            ok = true;
        end

        function ok = saveAll(obj)
            % PFE-2: Save All applies pending dashboard changes first
            % (when DashboardDirty) so the saved file and the live
            % dashboard agree, then persists option*.dat. Apply failures
            % do not block save — option-file persistence is the more
            % durable change.
            ok = true;
            if obj.DashboardDirty
                try
                    if obj.Option1Dirty, obj.applyToDashboard(1); end
                    if obj.Option2Dirty, obj.applyToDashboard(2); end
                catch ME
                    try, obj.logCaught(ME, 'PFE:saveAll:apply'); catch, end
                end
            end
            if obj.Option1Dirty
                ok = obj.saveOption(1) && ok;
            end
            if obj.Option2Dirty
                ok = obj.saveOption(2) && ok;
            end
            if ok
                obj.setStatus(sprintf('Save All complete (%s).', ...
                    datestr(now, 'HH:MM:SS')));
            else
                obj.setStatus('Save All completed with errors.');
            end
        end

        function ok = applyToDashboard(obj, optIdx)
            % PFE-2: push the edited OptionFileModel into the live
            % FlightDataDashboard via its public applyOptionFileModel
            % wrapper. Validation gates the apply: critical errors block,
            % optional-only warnings prompt the user (headless path
            % auto-allows). rawData is preserved; only mappedCols +
            % displayMeta change.
            ok = false;
            try
                model = obj.modelFor(optIdx);
                report = model.validate(obj.AvailableFields);
                if ~isempty(report.Errors)
                    obj.alert(sprintf( ...
                        ['Cannot apply: %d critical error(s). Fix the ' ...
                         'mapping / display rows first.'], ...
                        numel(report.Errors)), 'Apply blocked', 'error');
                    return;
                end
                if ~isempty(report.Warnings)
                    if ~isempty(obj.Figure) && isvalid(obj.Figure)
                        proceed = obj.confirm(sprintf( ...
                            'Apply with %d warning(s)?', numel(report.Warnings)), ...
                            'Apply with warnings');
                        if ~proceed, return; end
                    end
                end
                if isempty(obj.App) || ~isvalid(obj.App)
                    obj.alert('Studio app unavailable; cannot apply.', ...
                        'Apply blocked', 'error');
                    return;
                end
                dash = obj.App.getActiveDashboard();
                if isempty(dash) || ~isvalid(dash)
                    obj.alert('No active dashboard; cannot apply.', ...
                        'Apply blocked', 'warning');
                    return;
                end
                if ~ismethod(dash, 'applyOptionFileModel')
                    obj.alert('Dashboard apply wrapper unavailable.', ...
                        'Apply blocked', 'error');
                    return;
                end
                applied = dash.applyOptionFileModel(obj.FlightIndex, model);
                if ~applied
                    obj.alert('Dashboard refused the model.', ...
                        'Apply failed', 'error');
                    return;
                end
                try, dash.refreshFlightDataTable(obj.FlightIndex); catch, end
                try, dash.refreshPlotFieldChoices(obj.FlightIndex); catch, end
                try, dash.refreshDashboardLightweight('PFE apply'); catch, end
                obj.DashboardDirty = false;
                obj.refreshDirtyDots();
                obj.setStatus(sprintf('Applied option%d.dat to dashboard (%s).', ...
                    optIdx, datestr(now, 'HH:MM:SS')));
                ok = true;
            catch ME
                try, obj.logCaught(ME, 'PFE:applyToDashboard'); catch, end
                obj.alert(sprintf('Apply failed: %s', ME.message), ...
                    'Apply failed', 'error');
            end
        end
    end

    % ---------- UI build ----------
    methods (Access = private)
        function buildUI(obj)
            obj.Figure = uifigure( ...
                'Name', 'Project File Editor', ...
                'Position', [120 120 1080 720], ...
                'AutoResizeChildren', 'off', ...
                'CloseRequestFcn', @(~,~) obj.onCloseRequest());
            try, obj.Figure.WindowStyle = 'normal'; catch, end

            root = uigridlayout(obj.Figure, [2 1]);
            root.RowHeight   = {'1x', 26};
            root.ColumnWidth = {'1x'};
            root.Padding     = [6 6 6 6];
            root.RowSpacing  = 4;

            obj.TabGroup = uitabgroup(root);
            obj.TabGroup.Layout.Row = 1;
            obj.TabGroup.Layout.Column = 1;

            obj.buildFilesTab();
            obj.Option1Tab = obj.buildOptionTab(1, 'option1.dat');
            obj.Option2Tab = obj.buildOptionTab(2, 'option2.dat');
            obj.buildApplyTab();
            obj.buildHealthTab();

            obj.StatusLabel = uilabel(root, ...
                'Text', 'Ready.', 'FontColor', [0.25 0.25 0.25]);
            obj.StatusLabel.Layout.Row = 2;
            obj.StatusLabel.Layout.Column = 1;
        end

        function buildFilesTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'Files & Sync Preview');
            g = uigridlayout(tab, [3 1]);
            g.RowHeight = {26, 26, '1x'};
            g.ColumnWidth = {'1x'};
            obj.FilesTab.OptionPath1Label = uilabel(g, ...
                'Text', 'option1.dat: (not set)');
            obj.FilesTab.OptionPath2Label = uilabel(g, ...
                'Text', 'option2.dat: (not set)');
            obj.FilesTab.PreviewLabel = uilabel(g, ...
                'Text', 'Sync preview lands in PFE-2+.', ...
                'FontColor', [0.4 0.4 0.4]);
        end

        function tab = buildOptionTab(obj, optIdx, titleText)
            tab = struct();
            tabObj = uitab(obj.TabGroup, 'Title', titleText);
            outer = uigridlayout(tabObj, [4 1]);
            outer.RowHeight   = {26, '0.4x', 30, '1x'};
            outer.ColumnWidth = {'1x'};
            outer.Padding     = [4 4 4 4];
            outer.RowSpacing  = 4;

            % Row 1 — toolbar (path, Reset/Validate/Apply/Save + dirty dot).
            tb = uigridlayout(outer, [1 7]);
            tb.RowHeight   = {26};
            tb.ColumnWidth = {'1x', 110, 90, 130, 90, 90, 26};
            tb.Padding     = [0 0 0 0];
            tab.PathLabel    = uilabel(tb, 'Text', sprintf('%s: (not set)', titleText));
            tab.LoadBtn      = uibutton(tb, 'Text', 'Reset from file', ...
                'ButtonPushedFcn', @(~,~) obj.onReload(optIdx));
            tab.ValidateBtn  = uibutton(tb, 'Text', 'Validate', ...
                'ButtonPushedFcn', @(~,~) obj.runValidation(optIdx));
            tab.ApplyBtn     = uibutton(tb, 'Text', 'Apply to Dashboard', ...
                'ButtonPushedFcn', @(~,~) obj.applyToDashboard(optIdx));
            tab.SaveBtn      = uibutton(tb, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~,~) obj.saveOption(optIdx));
            tab.SaveAllBtn   = uibutton(tb, 'Text', 'Save All', ...
                'ButtonPushedFcn', @(~,~) obj.saveAll());
            tab.DirtyDot     = uilabel(tb, 'Text', '', ...
                'FontColor', [0.85 0.4 0.1], 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');

            % Row 2 — mapping table.
            mapPanel = uipanel(outer, 'Title', 'Key Mapping (Section 1)');
            mapGrid  = uigridlayout(mapPanel, [1 1]);
            mapGrid.Padding = [4 4 4 4];
            tab.MappingTable = uitable(mapGrid, ...
                'ColumnName',  {'Key', 'MappedField', 'RequiredType', 'Available', 'Message'}, ...
                'ColumnEditable', [false true false false false], ...
                'ColumnWidth', {80, 220, 100, 80, 'auto'}, ...
                'CellEditCallback', @(src, evt) obj.onMappingEdit(optIdx, evt));

            % Row 3 — display toolbar.
            dtb = uigridlayout(outer, [1 7]);
            dtb.RowHeight   = {26};
            dtb.ColumnWidth = {110, 130, 90, 90, 110, 130, '1x'};
            dtb.Padding     = [0 0 0 0];
            tab.AddBtn        = uibutton(dtb, 'Text', 'Add Row', ...
                'ButtonPushedFcn', @(~,~) obj.addDisplayRow(optIdx));
            tab.DeleteBtn     = uibutton(dtb, 'Text', 'Delete Selected', ...
                'ButtonPushedFcn', @(~,~) obj.onDeleteSelected(optIdx));
            tab.UpBtn         = uibutton(dtb, 'Text', 'Move Up', ...
                'ButtonPushedFcn', @(~,~) obj.onMoveSelected(optIdx, -1));
            tab.DownBtn       = uibutton(dtb, 'Text', 'Move Down', ...
                'ButtonPushedFcn', @(~,~) obj.onMoveSelected(optIdx, +1));
            tab.NormalizeBtn  = uibutton(dtb, 'Text', 'Normalize Order', ...
                'ButtonPushedFcn', @(~,~) obj.normalizeOrder(optIdx));
            tab.RevalidateBtn = uibutton(dtb, 'Text', 'Validate Display', ...
                'ButtonPushedFcn', @(~,~) obj.runValidation(optIdx));
            tab.ValidationLabel = uilabel(dtb, 'Text', '', ...
                'FontColor', [0.4 0.4 0.4]);

            % Row 4 — display table.
            dispPanel = uipanel(outer, 'Title', 'Display Metadata (Section 2)');
            dispGrid  = uigridlayout(dispPanel, [1 1]);
            dispGrid.Padding = [4 4 4 4];
            tab.DisplayTable = uitable(dispGrid, ...
                'ColumnName',  {'FieldName', 'Unit', 'Format', 'Order', ...
                                'ScaleFactor', 'Visible', 'Available', 'Message'}, ...
                'ColumnEditable', [true true true true true true false false], ...
                'ColumnWidth', {180, 70, 90, 60, 90, 70, 80, 'auto'}, ...
                'CellEditCallback', @(src, evt) obj.onDisplayEdit(optIdx, evt), ...
                'CellSelectionCallback', @(src, evt) obj.onDisplaySelect(optIdx, evt));

            tab.SelectedRow = 0;

            if optIdx == 1
                obj.Option1Tab = tab;
            else
                obj.Option2Tab = tab;
            end
        end

        function buildApplyTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'Apply / Save Queue');
            g = uigridlayout(tab, [2 1]);
            g.RowHeight = {26, '1x'};
            obj.ApplyTab.Header = uilabel(g, 'Text', 'Pending changes:');
            obj.ApplyTab.QueueLabel = uilabel(g, ...
                'Text', 'Apply queue lands in PFE-2+. PFE-1 saves directly via the Save buttons.', ...
                'WordWrap', 'on');
        end

        function buildHealthTab(obj)
            tab = uitab(obj.TabGroup, 'Title', 'Project Health Preview');
            g = uigridlayout(tab, [1 1]);
            obj.HealthTab.Label = uilabel(g, ...
                'Text', 'Project health preview lands in PFE-2+.', ...
                'FontColor', [0.4 0.4 0.4]);
        end
    end

    % ---------- App context ----------
    methods (Access = private)
        function loadFromAppContext(obj)
            try
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                dash = obj.App.getActiveDashboard();
                if isempty(dash), return; end
                ctx = dash.getOptionEditorContext(obj.FlightIndex);
                obj.AvailableFields = ctx.AvailableFields;
                if ~isempty(ctx.OptionFilePath) && isfile(ctx.OptionFilePath)
                    obj.Option1Model = flightdash.project.OptionFileParser.read(ctx.OptionFilePath);
                end
                % Best-effort: option2 sits beside option1.
                try
                    op2 = obj.guessSecondOptionPath(ctx.OptionFilePath);
                    if ~isempty(op2) && isfile(op2)
                        obj.Option2Model = flightdash.project.OptionFileParser.read(op2);
                    end
                catch
                end
                obj.refreshAllTables();
            catch ME
                try, obj.logCaught(ME, 'PFE:loadFromAppContext'); catch, end
            end
        end

        function p2 = guessSecondOptionPath(~, op1)
            p2 = '';
            try
                if isempty(op1), return; end
                [folder, name, ext] = fileparts(op1);
                if contains(name, '1')
                    p2 = fullfile(folder, [strrep(name, '1', '2') ext]);
                end
            catch
            end
        end
    end

    % ---------- Refresh / validation ----------
    methods (Access = private)
        function refreshAllTables(obj)
            obj.refreshMappingTable(1);
            obj.refreshDisplayTable(1);
            obj.refreshMappingTable(2);
            obj.refreshDisplayTable(2);
            obj.refreshPathLabels();
            obj.runValidation(1);
            obj.runValidation(2);
        end

        function refreshPathLabels(obj)
            try
                p1 = obj.Option1Model.FilePath;
                p2 = obj.Option2Model.FilePath;
                if isempty(p1), p1 = '(not set)'; end
                if isempty(p2), p2 = '(not set)'; end
                if isfield(obj.Option1Tab, 'PathLabel') && isvalid(obj.Option1Tab.PathLabel)
                    obj.Option1Tab.PathLabel.Text = sprintf('option1.dat: %s', p1);
                end
                if isfield(obj.Option2Tab, 'PathLabel') && isvalid(obj.Option2Tab.PathLabel)
                    obj.Option2Tab.PathLabel.Text = sprintf('option2.dat: %s', p2);
                end
                if isfield(obj.FilesTab, 'OptionPath1Label')
                    obj.FilesTab.OptionPath1Label.Text = sprintf('option1.dat: %s', p1);
                    obj.FilesTab.OptionPath2Label.Text = sprintf('option2.dat: %s', p2);
                end
            catch
            end
        end

        function refreshMappingTable(obj, optIdx)
            try
                tab = obj.tabFor(optIdx);
                model = obj.modelFor(optIdx);
                if ~isfield(tab, 'MappingTable') || ~isvalid(tab.MappingTable), return; end
                tab.MappingTable.Data = model.Mapping;
            catch
            end
        end

        function refreshDisplayTable(obj, optIdx)
            try
                tab = obj.tabFor(optIdx);
                model = obj.modelFor(optIdx);
                if ~isfield(tab, 'DisplayTable') || ~isvalid(tab.DisplayTable), return; end
                tab.DisplayTable.Data = model.Display;
            catch
            end
        end

        function runValidation(obj, optIdx)
            try
                model = obj.modelFor(optIdx);
                report = model.validate(obj.AvailableFields);
                obj.refreshMappingTable(optIdx);
                obj.refreshDisplayTable(optIdx);
                tab = obj.tabFor(optIdx);
                if isfield(tab, 'ValidationLabel') && isvalid(tab.ValidationLabel)
                    if report.OK
                        tab.ValidationLabel.Text = sprintf('OK (%d warning(s)).', ...
                            numel(report.Warnings));
                        tab.ValidationLabel.FontColor = [0 0.5 0];
                    else
                        tab.ValidationLabel.Text = sprintf('%d error(s), %d warning(s).', ...
                            numel(report.Errors), numel(report.Warnings));
                        tab.ValidationLabel.FontColor = [0.7 0 0];
                    end
                end
            catch
            end
        end
    end

    % ---------- Callbacks ----------
    methods (Access = private)
        function onCloseRequest(obj)
            try
                if obj.confirmClose()
                    delete(obj);
                end
            catch
                delete(obj);
            end
        end

        function onMappingEdit(obj, optIdx, evt)
            try
                row = evt.Indices(1);
                col = evt.Indices(2);
                if col ~= 2, return; end  % only MappedField editable
                model = obj.modelFor(optIdx);
                key = char(model.Mapping.Key(row));
                model.setMapping(key, char(evt.NewData));
                obj.markOptionDirty(optIdx);
                obj.runValidation(optIdx);
            catch ME
                try, obj.logCaught(ME, 'PFE:onMappingEdit'); catch, end
            end
        end

        function onDisplayEdit(obj, optIdx, evt)
            try
                row = evt.Indices(1);
                col = evt.Indices(2);
                model = obj.modelFor(optIdx);
                colName = char(model.Display.Properties.VariableNames{col});
                switch colName
                    case 'FieldName'
                        newName = char(evt.NewData);
                        if isempty(strtrim(newName))
                            obj.alert('FieldName cannot be empty.', 'Edit blocked', 'error');
                            obj.refreshDisplayTable(optIdx); return;
                        end
                        if obj.duplicatesElsewhere(model, newName, row)
                            obj.alert(sprintf('FieldName "%s" already exists.', newName), ...
                                'Edit blocked', 'error');
                            obj.refreshDisplayTable(optIdx); return;
                        end
                        model.Display.FieldName(row) = string(newName);
                    case 'Unit'
                        model.Display.Unit(row) = string(char(evt.NewData));
                    case 'Format'
                        model.Display.Format(row) = string(char(evt.NewData));
                    case 'Order'
                        model.Display.Order(row) = double(evt.NewData);
                    case 'ScaleFactor'
                        model.Display.ScaleFactor(row) = double(evt.NewData);
                    case 'Visible'
                        model.Display.Visible(row) = logical(evt.NewData);
                end
                model.markDirty();
                obj.markOptionDirty(optIdx);
                obj.runValidation(optIdx);
            catch ME
                try, obj.logCaught(ME, 'PFE:onDisplayEdit'); catch, end
                obj.refreshDisplayTable(optIdx);
            end
        end

        function onDisplaySelect(obj, optIdx, evt)
            try
                if ~isempty(evt.Indices)
                    tab = obj.tabFor(optIdx);
                    tab.SelectedRow = evt.Indices(1);
                    if optIdx == 1, obj.Option1Tab = tab; else, obj.Option2Tab = tab; end
                end
            catch
            end
        end

        function onDeleteSelected(obj, optIdx)
            tab = obj.tabFor(optIdx);
            row = 0;
            if isfield(tab, 'SelectedRow'), row = tab.SelectedRow; end
            if row < 1
                obj.alert('Select a row first.', 'Delete', 'info');
                return;
            end
            obj.deleteDisplayRow(optIdx, row, false);
        end

        function onMoveSelected(obj, optIdx, direction)
            tab = obj.tabFor(optIdx);
            row = 0;
            if isfield(tab, 'SelectedRow'), row = tab.SelectedRow; end
            if row < 1
                obj.alert('Select a row first.', 'Move', 'info'); return;
            end
            obj.moveDisplayRow(optIdx, row, direction);
        end

        function onReload(obj, optIdx)
            model = obj.modelFor(optIdx);
            if isempty(model.FilePath)
                obj.alert('No path set.', 'Reload', 'info'); return;
            end
            if obj.optionDirty(optIdx)
                if ~obj.confirm('Discard unsaved changes and reload?', 'Reload')
                    return;
                end
            end
            try
                newModel = flightdash.project.OptionFileParser.read(model.FilePath);
                obj.setModel(optIdx, newModel);
                obj.clearOptionDirty(optIdx);
                obj.refreshMappingTable(optIdx);
                obj.refreshDisplayTable(optIdx);
                obj.runValidation(optIdx);
                obj.setStatus(sprintf('Reloaded option%d.dat.', optIdx));
            catch ME
                obj.alert(sprintf('Reload failed: %s', ME.message), ...
                    'Reload failed', 'error');
            end
        end
    end

    % ---------- Helpers ----------
    methods (Access = private)
        function model = modelFor(obj, optIdx)
            if optIdx == 1, model = obj.Option1Model; else, model = obj.Option2Model; end
        end

        function setModel(obj, optIdx, model)
            if optIdx == 1, obj.Option1Model = model; else, obj.Option2Model = model; end
        end

        function tab = tabFor(obj, optIdx)
            if optIdx == 1, tab = obj.Option1Tab; else, tab = obj.Option2Tab; end
        end

        function tf = optionDirty(obj, optIdx)
            if optIdx == 1, tf = obj.Option1Dirty; else, tf = obj.Option2Dirty; end
        end

        function markOptionDirty(obj, optIdx)
            if optIdx == 1, obj.Option1Dirty = true; else, obj.Option2Dirty = true; end
            obj.DashboardDirty = true;
            obj.refreshDirtyDots();
        end

        function clearOptionDirty(obj, optIdx)
            if optIdx == 1, obj.Option1Dirty = false; else, obj.Option2Dirty = false; end
            if ~obj.Option1Dirty && ~obj.Option2Dirty
                obj.DashboardDirty = false;
            end
            obj.refreshDirtyDots();
        end

        function clearDirty(obj)
            obj.Option1Dirty = false; obj.Option2Dirty = false;
            obj.ProjectDirty = false; obj.DashboardDirty = false;
            obj.refreshDirtyDots();
        end

        function refreshDirtyDots(obj)
            try
                if isfield(obj.Option1Tab, 'DirtyDot') && isvalid(obj.Option1Tab.DirtyDot)
                    if obj.Option1Dirty, obj.Option1Tab.DirtyDot.Text = '*';
                    else, obj.Option1Tab.DirtyDot.Text = ''; end
                end
                if isfield(obj.Option2Tab, 'DirtyDot') && isvalid(obj.Option2Tab.DirtyDot)
                    if obj.Option2Dirty, obj.Option2Tab.DirtyDot.Text = '*';
                    else, obj.Option2Tab.DirtyDot.Text = ''; end
                end
            catch
            end
        end

        function tf = duplicatesElsewhere(~, model, name, ignoreRow)
            tf = false;
            for k = 1:height(model.Display)
                if k == ignoreRow, continue; end
                if strcmp(char(model.Display.FieldName(k)), name)
                    tf = true; return;
                end
            end
        end

        function refKey = findMappingReference(~, model, fieldName, keyList)
            refKey = '';
            for k = 1:height(model.Mapping)
                if ismember(char(model.Mapping.Key(k)), keyList) && ...
                        strcmp(char(model.Mapping.MappedField(k)), fieldName)
                    refKey = char(model.Mapping.Key(k)); return;
                end
            end
        end

        function choice = askDirtyChoice(obj)
            choice = 'cancel';
            try
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    sel = uiconfirm(obj.Figure, ...
                        'Project File Editor has unsaved changes.', ...
                        'Unsaved changes', ...
                        'Options',     {'Save All', 'Discard', 'Cancel'}, ...
                        'DefaultOption', 1, ...
                        'CancelOption',  3, ...
                        'Icon', 'warning');
                    choice = char(sel);
                end
            catch
                choice = 'cancel';
            end
        end

        function alert(obj, message, title, icon)
            try
                if nargin < 4, icon = 'info'; end
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    uialert(obj.Figure, message, title, 'Icon', icon);
                end
            catch
            end
        end

        function tf = confirm(obj, message, title)
            tf = false;
            try
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    sel = uiconfirm(obj.Figure, message, title, ...
                        'Options', {'OK', 'Cancel'}, ...
                        'DefaultOption', 1, 'CancelOption', 2);
                    tf = strcmpi(char(sel), 'OK');
                end
            catch
                tf = false;
            end
        end

        function setStatus(obj, msg)
            try
                if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                    obj.StatusLabel.Text = msg;
                end
            catch
            end
        end

        function cleanup(obj)
            % Tear down editor-owned timers etc. PFE-1 has no timers yet
            % but the hook is in place for PFE-2 AutoApplyTimer.
            try
                if ~isempty(obj.App) && isa(obj.App, 'handle') && isvalid(obj.App)
                    if isprop(obj.App, 'ProjectEditor') && isequal(obj.App.ProjectEditor, obj)
                        obj.App.ProjectEditor = [];
                    end
                end
            catch
            end
        end

        function logCaught(obj, ME, tag)
            try
                if ~isempty(obj.App) && isa(obj.App, 'handle') && isvalid(obj.App) ...
                        && ismethod(obj.App, 'logCaught')
                    obj.App.logCaught(ME, tag);
                else
                    fprintf('[%s] %s\n', tag, ME.message);
                end
            catch
            end
        end
    end
end
