classdef AnalysisDialog < handle
    %ANALYSISDIALOG  Base class for Studio analysis dialogs (Phase 7).
    %
    %   Subclasses (e.g. RoiStatisticsAnalyzer, SyncQualityAnalyzer)
    %   provide:
    %     - AnalysisType (char)  — matches AnalysisThemeModel.AnalysisType
    %     - DialogTitle  (char)
    %     - buildBody(parentGrid) — populates the body region with inputs
    %     - readInputs()          — returns a settings struct
    %     - compute(settings)     — returns a ComputedValues struct
    %
    %   Lifecycle:
    %       d = SubAnalyzer(app, sessionId, channelIdx);
    %       d.show();    % builds + displays the modal-style uifigure
    %       d.applyTheme(themeStruct); % optional pre-fill from saved theme
    %
    %   On OK / Apply the dialog:
    %     1. Reads inputs.
    %     2. Calls subclass compute().
    %     3. Builds a ReviewResultModel populated with ComputedValues.
    %     4. Calls app.Project = app.Project.addResult(result).
    %     5. Refreshes the Project Explorer Results node.
    %     6. Publishes 'AnalysisResultCreated' on the EventBus.
    %
    %   Apply keeps the dialog open; OK closes it; Cancel discards.

    properties (Access = public)
        App
        SessionId    char = ''
        ChannelIdx   double = 1
        AnalysisType char = ''
        DialogTitle  char = 'Analysis'
        UIFigure
        BodyGrid     % subclass populates this
        ContextLabel
        StatusLabel
    end

    properties (Access = protected)
        OkBtn
        ApplyBtn
        CancelBtn
        SaveThemeBtn
        LastSettings struct = struct()
    end

    methods
        function obj = AnalysisDialog(app, sessionId, channelIdx)
            obj.App        = app;
            obj.SessionId  = char(sessionId);
            if nargin >= 3 && ~isempty(channelIdx)
                obj.ChannelIdx = double(channelIdx);
            end
        end

        function show(obj)
            try
                obj.build();
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                    obj.UIFigure.Visible = 'on';
                    figure(obj.UIFigure);
                end
            catch ME
                obj.failGracefully(ME);
            end
        end

        function applyTheme(obj, themeStruct)
            % Default = no-op; subclasses may override to populate widgets.
            if nargin < 2 || ~isstruct(themeStruct), return; end
            obj.LastSettings = themeStruct;
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

    methods (Access = protected)
        function build(obj)
            UIScale = flightdash.util.UIScale;
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                figure(obj.UIFigure);
                return;
            end

            titleText = sprintf('%s — Session %s / Flight %d', ...
                obj.DialogTitle, obj.shortSessionId(), obj.ChannelIdx);

            obj.UIFigure = uifigure('Name', titleText, ...
                'Position', [200 200 UIScale.px(520) UIScale.px(440)], ...
                'Visible', 'off', ...
                'Resize', 'on', ...
                'CloseRequestFcn', @(~,~) obj.onCancel());

            try
                if ~isempty(obj.App) && isvalid(obj.App) ...
                        && isprop(obj.App, 'CurrentThemeStruct') ...
                        && isstruct(obj.App.CurrentThemeStruct) ...
                        && isfield(obj.App.CurrentThemeStruct, 'Background')
                    obj.UIFigure.Color = obj.App.CurrentThemeStruct.Background;
                end
            catch
            end

            root = uigridlayout(obj.UIFigure, [3 1], ...
                'RowHeight', {UIScale.px(28), '1x', UIScale.px(40)}, ...
                'RowSpacing', 4, 'Padding', [8 8 8 8]);

            obj.ContextLabel = uilabel(root, ...
                'Text', titleText, ...
                'FontSize', 11, 'FontWeight', 'bold');

            obj.BodyGrid = uigridlayout(root, [1 1], 'Padding', [0 0 0 0]);
            obj.buildBody(obj.BodyGrid);

            buttonRow = uigridlayout(root, [1 5], ...
                'ColumnWidth', {'1x', UIScale.px(90), UIScale.px(72), UIScale.px(72), UIScale.px(72)}, ...
                'ColumnSpacing', 6, 'Padding', [0 0 0 0]);
            obj.StatusLabel = uilabel(buttonRow, 'Text', '', ...
                'FontColor', [0.35 0.35 0.35]);
            obj.SaveThemeBtn = uibutton(buttonRow, 'Text', 'Save Theme', ...
                'ButtonPushedFcn', @(~,~) obj.onSaveTheme());
            obj.OkBtn = uibutton(buttonRow, 'Text', 'OK', ...
                'ButtonPushedFcn', @(~,~) obj.onOk());
            obj.ApplyBtn = uibutton(buttonRow, 'Text', 'Apply', ...
                'ButtonPushedFcn', @(~,~) obj.onApply());
            obj.CancelBtn = uibutton(buttonRow, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) obj.onCancel());
        end

        function buildBody(~, ~)
            % Subclasses override. Default body is a single info label.
            % (Intentionally a no-op here.)
        end

        function s = readInputs(obj)
            s = obj.LastSettings;
        end

        function out = compute(~, ~)
            % Subclasses override. Returns a struct that will be stored
            % into ReviewResultModel.ComputedValues.
            out = struct('Status', 'unimplemented');
        end

        function onApply(obj)
            try
                obj.setStatus('Running analysis…');
                drawnow limitrate;
                settings = obj.readInputs();
                obj.LastSettings = settings;
                values = obj.compute(settings);
                if ~isstruct(values), values = struct('Value', values); end
                obj.persistResult(settings, values);
                obj.setStatus('Result saved.');
            catch ME
                obj.failGracefully(ME);
            end
        end

        function onOk(obj)
            obj.onApply();
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                delete(obj.UIFigure);
            end
            delete(obj);
        end

        function onCancel(obj)
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                delete(obj.UIFigure);
            end
            delete(obj);
        end

        function onSaveTheme(obj)
            try
                settings = obj.readInputs();
                theme = flightdash.project.AnalysisThemeModel( ...
                    sprintf('%s @ %s', obj.DialogTitle, datestr(now,'HHMMSS')), ...
                    obj.AnalysisType);
                theme = theme.setSettings(settings);
                if ~isempty(obj.App) && isvalid(obj.App) ...
                        && isprop(obj.App, 'Project') && ~isempty(obj.App.Project)
                    obj.App.Project = obj.App.Project.addAnalysisTheme(theme);
                    if ismethod(obj.App, 'refreshExplorer')
                        obj.App.refreshExplorer();
                    end
                end
                obj.setStatus(sprintf('Theme "%s" saved.', theme.ThemeName));
            catch ME
                obj.failGracefully(ME);
            end
        end

        function persistResult(obj, settings, values)
            if isempty(obj.App) || ~isvalid(obj.App) ...
                    || ~isprop(obj.App, 'Project') || isempty(obj.App.Project)
                return;
            end
            result = flightdash.project.ReviewResultModel( ...
                obj.SessionId, obj.AnalysisType, obj.ChannelIdx);
            result = result.setComputedValues(values);
            result.UserComment = obj.summaryLine(values);
            result.ComputeFnSpec = struct( ...
                'analyzer',      class(obj), ...
                'method',        'compute', ...
                'inputSnapshot', settings);
            obj.App.Project = obj.App.Project.addResult(result);
            try
                if ismethod(obj.App, 'refreshExplorer')
                    obj.App.refreshExplorer();
                end
            catch
            end
            try
                flightdash.util.EventBus.publish('AnalysisResultCreated', ...
                    flightdash.util.AppEventData(obj.ChannelIdx, ...
                        struct('ResultId', result.ResultId, ...
                               'AnalysisType', obj.AnalysisType), ...
                        obj.SessionId));
            catch
            end
        end

        function setStatus(obj, msg)
            try
                if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                    obj.StatusLabel.Text = char(msg);
                end
            catch
            end
        end

        function s = summaryLine(~, values)
            try
                names = fieldnames(values);
                parts = cell(1, min(3, numel(names)));
                for k = 1:numel(parts)
                    v = values.(names{k});
                    if isnumeric(v) && isscalar(v)
                        parts{k} = sprintf('%s=%.4g', names{k}, v);
                    else
                        parts{k} = names{k};
                    end
                end
                s = strjoin(parts, ', ');
            catch
                s = '';
            end
        end

        function sid = shortSessionId(obj)
            sid = char(obj.SessionId);
            if numel(sid) > 12
                sid = sid(end-11:end);
            end
        end

        function failGracefully(obj, ME)
            try
                obj.setStatus(sprintf('Error: %s', ME.message));
            catch
            end
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ismethod(obj.App, 'logCaught')
                    obj.App.logCaught(ME, ['AnalysisDialog:' class(obj)]);
                end
            catch
            end
        end
    end
end
