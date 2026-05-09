classdef ProjectModel
    % flightdash.project.ProjectModel
    % Top-level project container. Value class — all mutations return a
    % new instance (see docs/design-serialization.md §3.1).
    %
    % Hierarchy:
    %   ProjectModel
    %     +- Sessions       (SessionModel array)
    %     +- Figures        (FigureModel array, session-independent figs)
    %     +- Results        (ReviewResultModel array)
    %     +- AnalysisThemes (AnalysisThemeModel array)
    %
    % Phase 2: in-memory only. Phase 9 adds persistence (.frsproj zip).

    properties
        SchemaVersion       uint32   = uint32(1)

        ProjectId           char     = ''
        ProjectName         char     = 'Untitled'
        ProjectFilePath     char     = ''
        ProjectFolderPath   char     = ''
        CreatedAt           char     = ''
        ModifiedAt          char     = ''

        Sessions       % flightdash.project.SessionModel array
        Figures        % flightdash.project.FigureModel array
        Results        % flightdash.project.ReviewResultModel array
        AnalysisThemes % flightdash.project.AnalysisThemeModel array

        % Global preferences (Phase 6 wiring)
        GuiMode             char     = 'Review'      % Review|Analysis|Plot|Report|Compact
        AutoUpdateMode      char     = 'Manual'      % Manual|Auto|Frozen

        DirtyFlag           logical  = false
    end

    methods
        function obj = ProjectModel(name)
            % Default ctor creates a blank Untitled project.
            if nargin >= 1 && ~isempty(name)
                obj.ProjectName = char(name);
            end
            obj.ProjectId   = flightdash.project.ProjectModel.newId('PROJ');
            obj.CreatedAt   = flightdash.project.ProjectModel.nowIso();
            obj.ModifiedAt  = obj.CreatedAt;
            obj.Sessions       = flightdash.project.SessionModel.empty;
            obj.Figures        = flightdash.project.FigureModel.empty;
            obj.Results        = flightdash.project.ReviewResultModel.empty;
            obj.AnalysisThemes = flightdash.project.AnalysisThemeModel.empty;
        end

        % --- Session management (value semantics) ---
        function obj = addSession(obj, session)
            mustBeA(session, 'flightdash.project.SessionModel');
            if obj.hasSession(session.SessionId)
                error('ProjectModel:DuplicateSession', ...
                    'Session id "%s" already exists.', session.SessionId);
            end
            obj.Sessions = [obj.Sessions, session];
            obj = obj.touch();
        end

        function obj = removeSession(obj, sessionId)
            sessionId = char(sessionId);
            mask = arrayfun(@(s) strcmp(s.SessionId, sessionId), obj.Sessions);
            if ~any(mask), return; end
            obj.Sessions(mask) = [];
            % Cascade: drop results whose session no longer exists
            if ~isempty(obj.Results)
                rmask = arrayfun(@(r) strcmp(r.SessionId, sessionId), obj.Results);
                obj.Results(rmask) = [];
            end
            obj = obj.touch();
        end

        function tf = hasSession(obj, sessionId)
            tf = false;
            if isempty(obj.Sessions), return; end
            tf = any(arrayfun(@(s) strcmp(s.SessionId, char(sessionId)), obj.Sessions));
        end

        function s = findSession(obj, sessionId)
            s = flightdash.project.SessionModel.empty;
            if isempty(obj.Sessions), return; end
            mask = arrayfun(@(x) strcmp(x.SessionId, char(sessionId)), obj.Sessions);
            if any(mask)
                s = obj.Sessions(find(mask, 1));
            end
        end

        function s = getSession(obj, sessionId)
            s = obj.findSession(sessionId);
        end

        function obj = updateSession(obj, sessionId, updatedSession)
            mustBeA(updatedSession, 'flightdash.project.SessionModel');
            mask = arrayfun(@(x) strcmp(x.SessionId, char(sessionId)), obj.Sessions);
            if ~any(mask)
                error('ProjectModel:UnknownSession', ...
                    'Session id "%s" not found.', sessionId);
            end
            obj.Sessions(find(mask, 1)) = updatedSession;
            obj = obj.touch();
        end

        function n = sessionCount(obj)
            n = numel(obj.Sessions);
        end

        % --- Figures / Results / Themes (analogous CRUD) ---
        function obj = addFigure(obj, fig)
            mustBeA(fig, 'flightdash.project.FigureModel');
            obj.Figures = [obj.Figures, fig];
            obj = obj.touch();
        end

        function obj = addResult(obj, result)
            mustBeA(result, 'flightdash.project.ReviewResultModel');
            obj.Results = [obj.Results, result];
            obj = obj.touch();
        end

        function obj = addTheme(obj, theme)
            mustBeA(theme, 'flightdash.project.AnalysisThemeModel');
            obj.AnalysisThemes = [obj.AnalysisThemes, theme];
            obj = obj.touch();
        end

        function obj = addAnalysisTheme(obj, theme)
            obj = obj.addTheme(theme);
        end

        function obj = addAnalysisThemeModel(obj, theme)
            obj = obj.addTheme(theme);
        end

        % --- Internal ---
        function obj = touch(obj)
            obj.ModifiedAt = flightdash.project.ProjectModel.nowIso();
            obj.DirtyFlag  = true;
        end
    end

    methods (Static)
        function id = newId(prefix)
            % [PHASE 4 review] Persistent monotonic counter combined
            % with a millisecond timestamp guarantees uniqueness within
            % a MATLAB session and makes test runs reproducible. The
            % previous randi(9999) approach risked rare collisions when
            % many sessions/results were created back-to-back.
            persistent counter
            if isempty(counter), counter = uint64(0); end
            counter = counter + 1;
            if nargin < 1, prefix = 'OBJ'; end
            id = sprintf('%s_%s_%06d', prefix, ...
                datestr(now, 'yyyymmddHHMMSSFFF'), ...
                counter);
        end

        function s = nowIso()
            s = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
        end
    end
end
