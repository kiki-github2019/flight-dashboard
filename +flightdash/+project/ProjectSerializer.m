classdef ProjectSerializer
    %PROJECTSERIALIZER  Phase 9 v1 — save/load .frsproj projects.
    %
    %   Container layout (per docs/design-serialization.md):
    %       <project>.frsproj  (zip)
    %         manifest.json        — magic, schema, sessions[], counts
    %         project.json         — ProjectModel metadata
    %         sessions/SXXX/session.json   — one per session
    %         themes/<id>.json     — one per analysis theme
    %         external_links.json  — linked-mode external assets (v1: paths only)
    %
    %   v1 scope: metadata + session paths + theme presets. Raw flight
    %   table / video bytes are NOT copied (linked mode). Future v2 can
    %   add MAT v7.3 raw data inside sessions/SXXX/data/ and the
    %   "copied" / "packed" packageMode states.
    %
    %   The class is stateless: every entry point is a static method.
    %   handle classes (managers, controllers) are deliberately NOT
    %   serialized — load() reconstructs ProjectModel only; the Studio
    %   shell rebuilds the live UI around it.

    properties (Constant)
        MagicTag      = 'FRSPROJ'
        SchemaVersion = uint32(1)
        FileExt       = '.frsproj'
    end

    methods (Static)

        function save(project, filePath)
            %SAVE  Write a ProjectModel to a .frsproj zip file.
            mustBeA(project, 'flightdash.project.ProjectModel');
            filePath = char(filePath);
            if isempty(filePath)
                error('ProjectSerializer:EmptyPath', 'filePath is empty.');
            end

            tmpDir = tempname();
            mkdir(tmpDir);
            cleaner = onCleanup(@() flightdash.project.ProjectSerializer.tryRmdir(tmpDir));

            try
                % --- project.json ---
                pStruct = flightdash.project.ProjectSerializer.projectToStruct(project);
                flightdash.project.ProjectSerializer.writeJson(fullfile(tmpDir, 'project.json'), pStruct);

                % --- sessions/<SessionId>/session.json ---
                if ~isempty(project.Sessions)
                    sessionsRoot = fullfile(tmpDir, 'sessions');
                    mkdir(sessionsRoot);
                    for k = 1:numel(project.Sessions)
                        sess = project.Sessions(k);
                        sDir = fullfile(sessionsRoot, char(sess.SessionId));
                        mkdir(sDir);
                        sStruct = flightdash.project.ProjectSerializer.sessionToStruct(sess);
                        flightdash.project.ProjectSerializer.writeJson(fullfile(sDir, 'session.json'), sStruct);
                    end
                end

                % --- themes/<id>.json ---
                if ~isempty(project.AnalysisThemes)
                    themesRoot = fullfile(tmpDir, 'themes');
                    mkdir(themesRoot);
                    for k = 1:numel(project.AnalysisThemes)
                        th = project.AnalysisThemes(k);
                        tStruct = flightdash.project.ProjectSerializer.themeToStruct(th);
                        flightdash.project.ProjectSerializer.writeJson( ...
                            fullfile(themesRoot, [char(th.ThemeId) '.json']), tStruct);
                    end
                end

                % --- external_links.json (linked mode v1: enumerate session asset paths) ---
                links = flightdash.project.ProjectSerializer.collectExternalLinks(project);
                flightdash.project.ProjectSerializer.writeJson( ...
                    fullfile(tmpDir, 'external_links.json'), struct('links', {links}));

                % --- manifest.json (LAST) ---
                manifest = flightdash.project.ProjectSerializer.buildManifest(project);
                flightdash.project.ProjectSerializer.writeJson(fullfile(tmpDir, 'manifest.json'), manifest);

                entries = flightdash.project.ProjectSerializer.listEntries(tmpDir);
                flightdash.project.ProjectSerializer.writeZipToTarget(filePath, entries, tmpDir);
            catch ME
                clear cleaner;
                rethrow(ME);
            end
            clear cleaner;
        end


        function project = load(filePath)
            %LOAD  Restore a ProjectModel from a .frsproj zip file.
            filePath = char(filePath);
            if ~isfile(filePath)
                error('ProjectSerializer:FileNotFound', 'File not found: %s', filePath);
            end

            tmpDir = tempname();
            mkdir(tmpDir);
            cleaner = onCleanup(@() flightdash.project.ProjectSerializer.tryRmdir(tmpDir));

            unzip(filePath, tmpDir);

            % --- manifest.json ---
            manifestPath = fullfile(tmpDir, 'manifest.json');
            if ~isfile(manifestPath)
                error('ProjectSerializer:Corrupt', '%s missing manifest.json', filePath);
            end
            manifest = flightdash.project.ProjectSerializer.readJson(manifestPath);
            if ~isfield(manifest, 'magic') || ~strcmp(manifest.magic, flightdash.project.ProjectSerializer.MagicTag)
                error('ProjectSerializer:NotFrsproj', 'Bad magic tag — not a .frsproj file.');
            end
            if ~isfield(manifest, 'schemaVersion') || double(manifest.schemaVersion) > double(flightdash.project.ProjectSerializer.SchemaVersion)
                error('ProjectSerializer:SchemaTooNew', ...
                    'Project schemaVersion %d > supported %d. Upgrade the Studio.', ...
                    double(manifest.schemaVersion), double(flightdash.project.ProjectSerializer.SchemaVersion));
            end

            % --- project.json ---
            pStruct = flightdash.project.ProjectSerializer.readJson(fullfile(tmpDir, 'project.json'));
            project = flightdash.project.ProjectSerializer.structToProject(pStruct);

            % --- sessions/* ---
            sessionsRoot = fullfile(tmpDir, 'sessions');
            sessions = flightdash.project.SessionModel.empty;
            if isfolder(sessionsRoot)
                entries = dir(sessionsRoot);
                for k = 1:numel(entries)
                    if ~entries(k).isdir, continue; end
                    if any(strcmp(entries(k).name, {'.', '..'})), continue; end
                    sj = fullfile(sessionsRoot, entries(k).name, 'session.json');
                    if isfile(sj)
                        s = flightdash.project.ProjectSerializer.readJson(sj);
                        sessions(end+1) = flightdash.project.ProjectSerializer.structToSession(s); %#ok<AGROW>
                    end
                end
            end
            project.Sessions = sessions;

            % --- themes/* ---
            themesRoot = fullfile(tmpDir, 'themes');
            themes = flightdash.project.AnalysisThemeModel.empty;
            if isfolder(themesRoot)
                files = dir(fullfile(themesRoot, '*.json'));
                for k = 1:numel(files)
                    t = flightdash.project.ProjectSerializer.readJson(fullfile(themesRoot, files(k).name));
                    themes(end+1) = flightdash.project.ProjectSerializer.structToTheme(t); %#ok<AGROW>
                end
            end
            project.AnalysisThemes = themes;

            project.DirtyFlag = false;
            clear cleaner;
        end

    end

    methods (Static, Access = private)

        % ===== Project ↔ struct =====
        function s = projectToStruct(p)
            s = struct( ...
                'SchemaVersion',     double(p.SchemaVersion), ...
                'ProjectId',         char(p.ProjectId), ...
                'ProjectName',       char(p.ProjectName), ...
                'ProjectFilePath',   char(p.ProjectFilePath), ...
                'ProjectFolderPath', char(p.ProjectFolderPath), ...
                'CreatedAt',         char(p.CreatedAt), ...
                'ModifiedAt',        char(p.ModifiedAt), ...
                'GuiMode',           char(p.GuiMode), ...
                'AutoUpdateMode',    char(p.AutoUpdateMode));
        end

        function p = structToProject(s)
            p = flightdash.project.ProjectModel(flightdash.project.ProjectSerializer.fieldChar(s, 'ProjectName', 'Untitled'));
            p.SchemaVersion     = uint32(flightdash.project.ProjectSerializer.fieldNum(s,  'SchemaVersion', 1));
            p.ProjectId         = flightdash.project.ProjectSerializer.fieldChar(s, 'ProjectId',         p.ProjectId);
            p.ProjectFilePath   = flightdash.project.ProjectSerializer.fieldChar(s, 'ProjectFilePath',   '');
            p.ProjectFolderPath = flightdash.project.ProjectSerializer.fieldChar(s, 'ProjectFolderPath', '');
            p.CreatedAt         = flightdash.project.ProjectSerializer.fieldChar(s, 'CreatedAt',         p.CreatedAt);
            p.ModifiedAt        = flightdash.project.ProjectSerializer.fieldChar(s, 'ModifiedAt',        p.ModifiedAt);
            p.GuiMode           = flightdash.project.ProjectSerializer.fieldChar(s, 'GuiMode',           'Review');
            p.AutoUpdateMode    = flightdash.project.ProjectSerializer.fieldChar(s, 'AutoUpdateMode',    'Manual');
        end

        % ===== Session ↔ struct =====
        function s = sessionToStruct(sess)
            s = struct( ...
                'SchemaVersion',  double(sess.SchemaVersion), ...
                'SessionId',      char(sess.SessionId), ...
                'DisplayName',    char(sess.DisplayName), ...
                'FolderPath',     char(sess.FolderPath), ...
                'FlightFilePath', {sess.FlightFilePath}, ...
                'VideoFilePath',  {sess.VideoFilePath}, ...
                'AutoUpdateMode', char(sess.AutoUpdateMode), ...
                'CurrentIndex',   sess.CurrentIndex, ...
                'CurrentFrame',   sess.CurrentFrame, ...
                'CreatedAt',      char(sess.CreatedAt), ...
                'ModifiedAt',     char(sess.ModifiedAt));
        end

        function sess = structToSession(s)
            sess = flightdash.project.SessionModel(flightdash.project.ProjectSerializer.fieldChar(s, 'DisplayName', 'Session'));
            sess.SchemaVersion  = uint32(flightdash.project.ProjectSerializer.fieldNum(s, 'SchemaVersion', 1));
            sess.SessionId      = flightdash.project.ProjectSerializer.fieldChar(s, 'SessionId',  sess.SessionId);
            sess.FolderPath     = flightdash.project.ProjectSerializer.fieldChar(s, 'FolderPath', '');
            sess.FlightFilePath = flightdash.project.ProjectSerializer.fieldCellPair(s, 'FlightFilePath');
            sess.VideoFilePath  = flightdash.project.ProjectSerializer.fieldCellPair(s, 'VideoFilePath');
            sess.AutoUpdateMode = flightdash.project.ProjectSerializer.fieldChar(s, 'AutoUpdateMode', 'Inherit');
            sess.CurrentIndex   = flightdash.project.ProjectSerializer.fieldNumPair(s, 'CurrentIndex', [1 1]);
            sess.CurrentFrame   = flightdash.project.ProjectSerializer.fieldNumPair(s, 'CurrentFrame', [1 1]);
            sess.CreatedAt      = flightdash.project.ProjectSerializer.fieldChar(s, 'CreatedAt',  sess.CreatedAt);
            sess.ModifiedAt     = flightdash.project.ProjectSerializer.fieldChar(s, 'ModifiedAt', sess.ModifiedAt);
            sess.DirtyFlag      = false;
        end

        % ===== Theme ↔ struct =====
        function s = themeToStruct(th)
            s = struct( ...
                'SchemaVersion', double(th.SchemaVersion), ...
                'ThemeId',       char(th.ThemeId), ...
                'ThemeName',     char(th.ThemeName), ...
                'AnalysisType',  char(th.AnalysisType), ...
                'InputDefaults', th.InputDefaults, ...
                'Settings',      th.Settings, ...
                'OutputOptions', th.OutputOptions, ...
                'IsDefault',     logical(th.IsDefault), ...
                'CreatedAt',     char(th.CreatedAt), ...
                'ModifiedAt',    char(th.ModifiedAt));
        end

        function th = structToTheme(s)
            th = flightdash.project.AnalysisThemeModel( ...
                flightdash.project.ProjectSerializer.fieldChar(s, 'ThemeName', 'Theme'), ...
                flightdash.project.ProjectSerializer.fieldChar(s, 'AnalysisType', ''));
            th.SchemaVersion = uint32(flightdash.project.ProjectSerializer.fieldNum(s, 'SchemaVersion', 1));
            th.ThemeId       = flightdash.project.ProjectSerializer.fieldChar(s, 'ThemeId', th.ThemeId);
            if isfield(s, 'InputDefaults') && isstruct(s.InputDefaults), th.InputDefaults = s.InputDefaults; end
            if isfield(s, 'Settings')      && isstruct(s.Settings),      th.Settings      = s.Settings;      end
            if isfield(s, 'OutputOptions') && isstruct(s.OutputOptions), th.OutputOptions = s.OutputOptions; end
            th.IsDefault   = logical(flightdash.project.ProjectSerializer.fieldNum(s, 'IsDefault', 0));
            th.CreatedAt   = flightdash.project.ProjectSerializer.fieldChar(s, 'CreatedAt',  th.CreatedAt);
            th.ModifiedAt  = flightdash.project.ProjectSerializer.fieldChar(s, 'ModifiedAt', th.ModifiedAt);
        end

        % ===== Manifest =====
        function manifest = buildManifest(project)
            sessionIds = cell(1, numel(project.Sessions));
            for k = 1:numel(project.Sessions)
                sessionIds{k} = char(project.Sessions(k).SessionId);
            end
            manifest = struct( ...
                'format',        'FlightReviewStudio Project', ...
                'magic',         flightdash.project.ProjectSerializer.MagicTag, ...
                'schemaVersion', double(flightdash.project.ProjectSerializer.SchemaVersion), ...
                'createdAt',     char(project.CreatedAt), ...
                'modifiedAt',    char(project.ModifiedAt), ...
                'createdBy',     struct( ...
                    'studioVersion', '1.0.0', ...
                    'matlabVersion', version('-release'), ...
                    'host',          flightdash.project.ProjectSerializer.safeHost()), ...
                'packageMode',   'linked', ...
                'sessions',      {sessionIds}, ...
                'figureCount',   numel(project.Figures), ...
                'resultCount',   numel(project.Results), ...
                'themeCount',    numel(project.AnalysisThemes));
        end

        function links = collectExternalLinks(project)
            links = {};
            for k = 1:numel(project.Sessions)
                s = project.Sessions(k);
                for ch = 1:numel(s.FlightFilePath)
                    p = s.FlightFilePath{ch};
                    if ~isempty(p)
                        links{end+1} = struct( ...
                            'sessionId', char(s.SessionId), ...
                            'channelIdx', ch, ...
                            'kind', 'flight_data', ...
                            'absolutePath', char(p)); %#ok<AGROW>
                    end
                end
                for ch = 1:numel(s.VideoFilePath)
                    p = s.VideoFilePath{ch};
                    if ~isempty(p)
                        links{end+1} = struct( ...
                            'sessionId', char(s.SessionId), ...
                            'channelIdx', ch, ...
                            'kind', 'video', ...
                            'absolutePath', char(p)); %#ok<AGROW>
                    end
                end
            end
        end

        % ===== JSON helpers =====
        function writeJson(filePath, data)
            try
                txt = jsonencode(data, 'PrettyPrint', true);
            catch
                txt = jsonencode(data);
            end
            fid = fopen(filePath, 'w');
            if fid < 0
                error('ProjectSerializer:WriteFailed', 'Cannot write %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, txt, 'char');
            clear cleaner;
        end

        function data = readJson(filePath)
            txt = fileread(filePath);
            data = jsondecode(txt);
        end

        % ===== Field coercion helpers (jsondecode tolerance) =====
        function v = fieldChar(s, name, dflt)
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                v = char(s.(name));
            else
                v = dflt;
            end
        end

        function v = fieldNum(s, name, dflt)
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                v = double(s.(name));
            else
                v = dflt;
            end
        end

        function v = fieldCellPair(s, name)
            v = {'', ''};
            if ~isstruct(s) || ~isfield(s, name), return; end
            raw = s.(name);
            if iscell(raw)
                for k = 1:min(2, numel(raw))
                    if ischar(raw{k}) || isstring(raw{k})
                        v{k} = char(raw{k});
                    end
                end
            end
        end

        function v = fieldNumPair(s, name, dflt)
            v = dflt;
            if isstruct(s) && isfield(s, name) && isnumeric(s.(name)) && numel(s.(name)) >= 2
                v = double(reshape(s.(name)(1:2), 1, 2));
            end
        end

        % ===== Filesystem helpers =====
        function names = listEntries(root)
            d = dir(root);
            names = {};
            for k = 1:numel(d)
                if any(strcmp(d(k).name, {'.', '..'})), continue; end
                names{end+1} = fullfile(root, d(k).name); %#ok<AGROW>
            end
        end

        function writeZipToTarget(filePath, entries, rootDir)
            [targetDir, ~, ~] = fileparts(filePath);
            if isempty(targetDir)
                targetDir = pwd;
            elseif ~isfolder(targetDir)
                error('ProjectSerializer:WriteFailed', 'Target folder not found: %s', targetDir);
            end

            tempBase = tempname(targetDir);
            tempZip = [tempBase '.zip'];
            backupPath = [tempBase '.bak'];
            candidates = {tempZip, [tempZip '.zip'], [filePath '.zip']};
            existedBefore = cellfun(@(p) exist(p, 'file') == 2, candidates);
            tempCreated = '';
            backupMade = false;

            cleanup = onCleanup(@() flightdash.project.ProjectSerializer.cleanupZipWrite( ...
                candidates, existedBefore, tempCreated));

            zip(tempZip, entries, rootDir);
            tempCreated = flightdash.project.ProjectSerializer.firstCreatedFile(candidates, existedBefore);
            if isempty(tempCreated)
                error('ProjectSerializer:WriteFailed', 'zip() did not create a project archive.');
            end

            try
                if exist(filePath, 'file') == 2
                    [ok, msg] = movefile(filePath, backupPath, 'f');
                    if ~ok
                        error('ProjectSerializer:WriteFailed', ...
                            'Cannot replace existing project file: %s', msg);
                    end
                    backupMade = true;
                end

                [ok, msg] = movefile(tempCreated, filePath, 'f');
                if ~ok
                    if backupMade && exist(backupPath, 'file') == 2 && exist(filePath, 'file') ~= 2
                        movefile(backupPath, filePath, 'f');
                        backupMade = false;
                    end
                    error('ProjectSerializer:WriteFailed', ...
                        'Cannot move project archive into place: %s', msg);
                end
                tempCreated = '';

                if ~isfile(filePath)
                    if backupMade && exist(backupPath, 'file') == 2 && exist(filePath, 'file') ~= 2
                        movefile(backupPath, filePath, 'f');
                        backupMade = false;
                    end
                    error('ProjectSerializer:WriteFailed', ...
                        'save() completed but did not create %s', filePath);
                end

                if backupMade && exist(backupPath, 'file') == 2
                    delete(backupPath);
                    backupMade = false;
                end
            catch ME
                if backupMade && exist(backupPath, 'file') == 2
                    try
                        if exist(filePath, 'file') == 2
                            delete(filePath);
                        end
                        movefile(backupPath, filePath, 'f');
                        backupMade = false;
                    catch
                    end
                end
                rethrow(ME);
            end

            clear cleanup;
        end

        function p = firstCreatedFile(candidates, existedBefore)
            p = '';
            for k = 1:numel(candidates)
                if ~existedBefore(k) && exist(candidates{k}, 'file') == 2
                    p = candidates{k};
                    return;
                end
            end
        end

        function cleanupZipWrite(candidates, existedBefore, tempCreated)
            for k = 1:numel(candidates)
                try
                    if ~existedBefore(k) && ~isempty(candidates{k}) && exist(candidates{k}, 'file') == 2
                        delete(candidates{k});
                    end
                catch
                end
            end
            try
                if ~isempty(tempCreated) && exist(tempCreated, 'file') == 2
                    delete(tempCreated);
                end
            catch
            end
        end

        function tryRmdir(p)
            try
                if isfolder(p), rmdir(p, 's'); end
            catch
            end
        end
    end

    methods (Static)
        function delIfExists(p)
            % Public so verifyPhase4 (or other tooling) can clean up
            % temp .frsproj files written during round-trip tests.
            try
                if exist(p, 'file') == 2, delete(p); end
            catch
            end
        end

        function h = safeHost()
            h = '';
            try
                h = char(getenv('COMPUTERNAME'));
                if isempty(h), h = char(getenv('HOSTNAME')); end
            catch
            end
        end
    end
end
