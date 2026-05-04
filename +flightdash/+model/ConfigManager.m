classdef ConfigManager < handle
    % flightdash.model.ConfigManager
    % Session config import/export facade. The app still owns live state;
    % this class owns file dialogs, markdown/json IO, and config orchestration.

    methods
        function exportConfigInteractive(obj, app)
            filePath = obj.saveSessionConfig(app, 'manual', true);
            if ~isempty(filePath)
                app.notifyUser('Config Export', sprintf('Session config saved:\n%s', filePath), false);
            end
        end

        function importConfigInteractive(obj, app)
            configDir = app.sessionConfigFolder();
            [fname, pname] = uigetfile({'config_*.md;*.md', 'Markdown config (*.md)'}, ...
                'Import session config', configDir);
            if isequal(fname, 0), return; end
            configPath = fullfile(pname, fname);
            try
                obj.importSessionConfig(app, configPath);
                app.notifyUser('Config Import', sprintf('Session config imported:\n%s', configPath), false);
            catch ME
                app.logCaught(ME, 'Config:importInteractive');
                app.notifyUser('Config Import Failed', ME.message, true);
            end
        end

        function autoSaveConfigOnClose(obj, app)
            obj.saveSessionConfig(app, 'autosave', false);
        end

        function filePath = saveSessionConfig(obj, app, saveMode, showErrors)
            if nargin < 3 || isempty(saveMode), saveMode = 'manual'; end
            if nargin < 4, showErrors = false; end
            filePath = '';
            try
                configDir = app.sessionConfigFolder();
                if ~isfolder(configDir), mkdir(configDir); end
                filePath = fullfile(configDir, ['config_' datestr(now, 'yyyymmdd_HHMMSS') '.md']);
                cfg = obj.collectSessionConfig(app, saveMode, filePath);
                obj.writeSessionConfigMarkdown(cfg, filePath);
            catch ME
                filePath = '';
                app.logCaught(ME, ['Config:save:' char(saveMode)]);
                if showErrors
                    app.notifyUser('Config Save Failed', ME.message, true);
                end
            end
        end

        function importSessionConfig(obj, app, configPath)
            cfg = obj.readSessionConfigMarkdown(configPath);
            if ~isfield(cfg, 'Channels'), return; end
            viewMode = app.currentChannelViewMode();
            if isfield(cfg, 'ChannelViewMode')
                viewMode = app.structChar(cfg, 'ChannelViewMode', 'both');
            end

            channels = cfg.Channels;
            for fIdx = 1:min(2, numel(channels))
                ch = channels(fIdx);
                flightPath = app.structChar(ch, 'FlightDataPath', '');
                if ~isempty(flightPath) && isfile(flightPath)
                    app.loadFlightDataFromPath(fIdx, flightPath, true);
                    app.applyStoredMappingIfCompatible(fIdx, ch);
                end
            end

            for fIdx = 1:min(2, numel(channels))
                ch = channels(fIdx);
                videoPath = app.structChar(ch, 'VideoPath', '');
                if ~isempty(videoPath) && isfile(videoPath)
                    app.loadAviFromPathForConfig(fIdx, videoPath);
                    app.restoreVideoSyncStateFromConfig(fIdx, ch);
                end
            end

            for fIdx = 1:min(2, numel(channels))
                ch = channels(fIdx);
                if ~isempty(app.Models(fIdx).rawData)
                    app.restorePlotsFromConfig(fIdx, ch);
                    app.restoreRoisFromConfig(fIdx, ch);
                    app.restoreCurrentIndexFromConfig(fIdx, ch);
                end
            end
            app.setChannelViewMode(viewMode);
        end

        function cfg = collectSessionConfig(~, app, saveMode, filePath)
            if nargin < 3 || isempty(saveMode), saveMode = 'manual'; end
            if nargin < 4, filePath = ''; end
            cfg = struct();
            cfg.SchemaVersion = 1;
            cfg.App = 'FlightDataDashboard';
            cfg.SaveMode = char(saveMode);
            cfg.CreatedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            cfg.ConfigPath = filePath;
            cfg.RootFolder = app.sessionConfigFolder();
            cfg.LayoutProfile = app.currentLayoutProfile();
            cfg.ChannelViewMode = app.currentChannelViewMode();
            cfg.FigurePosition = app.finiteVectorOrEmpty(app.currentFigurePosition());
            cfg.SyncState = app.SyncState;
            channels = repmat(app.emptyChannelConfig(), 1, 2);
            for cfgIdx = 1:2
                channels(cfgIdx) = app.collectChannelConfig(cfgIdx);
            end
            cfg.Channels = channels;
        end

        function writeSessionConfigMarkdown(~, cfg, filePath)
            try
                jsonText = jsonencode(cfg, 'PrettyPrint', true);
            catch
                jsonText = jsonencode(cfg);
            end

            fid = fopen(filePath, 'w');
            if fid < 0
                error('flightdash:Config:OpenFailed', 'Cannot write config file: %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid));
            fprintf(fid, '# FlightDataDashboard Session Config\n\n');
            fprintf(fid, '- Created: %s\n', cfg.CreatedAt);
            fprintf(fid, '- Save mode: %s\n', cfg.SaveMode);
            fprintf(fid, '- Schema version: %d\n', cfg.SchemaVersion);
            fprintf(fid, '- Root folder: `%s`\n\n', cfg.RootFolder);
            fprintf(fid, '## Files\n\n');
            fprintf(fid, '| Flight | Data file | Video file |\n');
            fprintf(fid, '|---:|---|---|\n');
            for cfgIdx = 1:numel(cfg.Channels)
                fprintf(fid, '| %d | `%s` | `%s` |\n', cfgIdx, ...
                    cfg.Channels(cfgIdx).FlightDataPath, cfg.Channels(cfgIdx).VideoPath);
            end
            fprintf(fid, '\n## Option Mapping Snapshots\n\n');
            for cfgIdx = 1:numel(cfg.Channels)
                fprintf(fid, '### Flight %d - %s\n\n', cfgIdx, cfg.Channels(cfgIdx).OptionFile);
                fprintf(fid, '```text\n%s\n```\n\n', cfg.Channels(cfgIdx).OptionText);
            end
            fprintf(fid, '## Machine-Readable Config\n\n');
            fprintf(fid, '```json\n%s\n```\n', jsonText);
            clear cleaner;
        end

        function cfg = readSessionConfigMarkdown(~, filePath)
            txt = fileread(filePath);
            token = regexp(txt, '```json\s*(.*?)\s*```', 'tokens', 'once');
            if isempty(token)
                error('flightdash:Config:JsonMissing', 'No JSON config block found: %s', filePath);
            end
            cfg = jsondecode(token{1});
        end
    end
end
