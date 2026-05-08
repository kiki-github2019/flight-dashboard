classdef AnalysisThemeModel
    % flightdash.project.AnalysisThemeModel
    % Reusable analysis dialog preset (OriginPro Dialog Theme analogue).
    % Lets users save common ROI/sync/FFT/etc. dialog settings and re-apply
    % them with one click in Phase 7.

    properties
        SchemaVersion       uint32   = uint32(1)

        ThemeId             char     = ''
        ThemeName           char     = ''
        AnalysisType        char     = ''   % matches dialog id, e.g. 'RoiStats'
        InputDefaults       struct   = struct()
        Settings            struct   = struct()
        OutputOptions       struct   = struct()
        IsDefault           logical  = false

        CreatedAt           char     = ''
        ModifiedAt          char     = ''
    end

    methods
        function obj = AnalysisThemeModel(themeName, analysisType)
            if nargin < 1, themeName = 'New Theme'; end
            if nargin < 2, analysisType = ''; end
            obj.ThemeName    = char(themeName);
            obj.AnalysisType = char(analysisType);
            obj.ThemeId      = flightdash.project.ProjectModel.newId('THM');
            obj.CreatedAt    = flightdash.project.ProjectModel.nowIso();
            obj.ModifiedAt   = obj.CreatedAt;
        end

        function obj = setInputDefaults(obj, s)
            mustBeA(s, 'struct');
            obj.InputDefaults = s;
            obj = obj.touch();
        end

        function obj = setSettings(obj, s)
            mustBeA(s, 'struct');
            obj.Settings = s;
            obj = obj.touch();
        end

        function obj = setOutputOptions(obj, s)
            mustBeA(s, 'struct');
            obj.OutputOptions = s;
            obj = obj.touch();
        end

        function obj = setAsDefault(obj, isDefault)
            obj.IsDefault = logical(isDefault);
            obj = obj.touch();
        end

        function obj = touch(obj)
            obj.ModifiedAt = flightdash.project.ProjectModel.nowIso();
        end
    end
end
