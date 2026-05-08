classdef FigureModel
    % flightdash.project.FigureModel
    % Persistent figure record (graph window, comparison plot, layout, etc).
    % Lives independently of running uifigure; rebuilt at load time.

    properties
        SchemaVersion       uint32   = uint32(1)

        FigureId            char     = ''
        SourceSessionId     char     = ''      % '' for cross-session figures
        FigureType          char     = 'Graph' % Dashboard|Graph|ComparisonGraph|ROIResult|VideoSnapshot|Layout|Report
        Title               char     = ''

        Layers              cell     = {}      % cell array of layer-spec structs
        Variables           cell     = {}      % variable names plotted
        AxisSettings        struct   = struct()
        StyleSettings       struct   = struct()
        ViewState           struct   = struct()
        ExportPath          char     = ''

        RecalculateMode     char     = 'Auto'  % Manual|Auto|Frozen
        DirtyFlag           logical  = false

        CreatedAt           char     = ''
        ModifiedAt          char     = ''
    end

    methods
        function obj = FigureModel(figureType, title, sourceSessionId)
            if nargin < 1 || isempty(figureType), figureType = 'Graph'; end
            if nargin < 2, title = ''; end
            if nargin < 3, sourceSessionId = ''; end

            obj.FigureType      = char(figureType);
            obj.Title           = char(title);
            obj.SourceSessionId = char(sourceSessionId);
            obj.FigureId        = flightdash.project.ProjectModel.newId('FIG');
            obj.CreatedAt       = flightdash.project.ProjectModel.nowIso();
            obj.ModifiedAt      = obj.CreatedAt;
        end

        function obj = setRecalculateMode(obj, mode)
            valid = {'Manual', 'Auto', 'Frozen'};
            mode = char(mode);
            if ~ismember(mode, valid)
                error('FigureModel:InvalidMode', ...
                    'RecalculateMode must be one of: %s', strjoin(valid, ', '));
            end
            obj.RecalculateMode = mode;
            obj = obj.touch();
        end

        function obj = touch(obj)
            obj.ModifiedAt = flightdash.project.ProjectModel.nowIso();
            obj.DirtyFlag  = true;
        end
    end
end
