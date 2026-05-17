classdef CommandRouter < handle
    % flightdash.studio.CommandRouter
    % Central routing for Studio toolbar/menu commands.

    properties (Access = public)
        App
    end

    methods
        function obj = CommandRouter(app)
            obj.App = app;
        end

        function delete(~)
        end

        function dispatch(obj, cmdId, source)
            if nargin < 3 || isempty(source)
                source = 'Command';
            end
            cmdId = char(cmdId);
            source = char(source);

            try
                scope = obj.commandScope(cmdId);
                switch scope
                    case 'global'
                        obj.dispatchGlobal(cmdId, source);
                    case 'session'
                        obj.dispatchSession(cmdId, source);
                    otherwise
                        obj.noop(source, cmdId);
                end
            catch ME
                obj.reportException(source, cmdId, ME);
            end
        end

        function scope = commandScope(~, cmdId)
            cmdId = char(cmdId);

            globalCommands = { ...
                'Toolbar:New', 'Toolbar:Open', 'Toolbar:Save', 'Toolbar:AddSession', ...
                'Toolbar:ToggleExplorer', 'Edit:Undo', 'Edit:Redo', ...
                'File:NewProject', 'File:OpenProject', 'File:SaveProject', ...
                'File:SaveProjectAs', 'File:PackProject', 'File:Exit', ...
                'Project:AddSession', 'Project:Find', 'Project:Properties', ...
                'Project:CleanupCache', ...
                'Window:TileH', 'Window:TileV', 'Window:Cascade', ...
                'Window:CloseActive', 'Window:CloseAll', 'Window:ShowExplorer', ...
                'Window:ShowObjectMgr', 'Window:ShowLogs', ...
                'Toolbar:ToggleRightDock', 'Window:ToggleRightDock', ...
                'Project:EditDetails', ...
                'Pref:Mode:Classic', 'Pref:Mode:Studio', ...
                'Pref:Mode:Review', 'Pref:Mode:Analysis', 'Pref:Mode:Plot', ...
                'Pref:Mode:Report', 'Pref:Mode:Compact', 'Pref:Mode:DockedFigure', ...
                'Pref:Theme:Toggle', 'Pref:AutoUpdate', ...
                'Pref:ToolbarCustomize', 'Pref:Shortcuts', ...
                'Pref:Experimental:SharedDecode', ...
                'Help:Shortcuts', 'Help:Samples', 'Help:ErrorLog', 'Help:About', ...
                'Help:QuickStart', 'Help:Troubleshooting', 'Help:License', ...
                'Help:SupportBundle', 'Project:HealthCheck', 'Project:RepairLinks'};

            if any(strcmp(cmdId, globalCommands))
                scope = 'global';
                return;
            end

            sessionPrefixes = { ...
                'Toolbar:Load', 'Toolbar:Sync', 'Toolbar:Play', 'Toolbar:Stop', ...
                'Toolbar:Prev', 'Toolbar:Next', 'Toolbar:ROI', 'Toolbar:Marker', ...
                'Toolbar:Analyze', 'Toolbar:Recalc', ...
                'Analysis:SyncCheck', 'Analysis:SyncQuality', ...
                'Project:DuplicateSession', 'Project:RenameSession', 'Project:DeleteSession', ...
                'File:ImportSession', 'File:ExportSession', ...
                'Edit:', ...
                'Data:', 'Video:', 'Sync:', 'Review:', 'Analysis:', 'Plot:'};

            scope = 'noop';
            for k = 1:numel(sessionPrefixes)
                if startsWith(cmdId, sessionPrefixes{k})
                    scope = 'session';
                    return;
                end
            end
        end

        function tf = isGlobalCommand(obj, cmdId)
            tf = strcmp(obj.commandScope(cmdId), 'global');
        end

        function tf = isSessionCommand(obj, cmdId)
            tf = strcmp(obj.commandScope(cmdId), 'session');
        end

        function [dashboard, sessionId] = activeDashboard(obj)
            dashboard = [];
            sessionId = '';
            try
                if isempty(obj.App) || ~isvalid(obj.App), return; end
                if ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace)
                    raw = obj.App.Workspace.activeSessionId();
                    if ~isempty(raw) && ~strcmp(char(raw), 'standalone')
                        sessionId = char(raw);
                    end
                end
                if isempty(sessionId), return; end
                if ismethod(obj.App, 'getActiveDashboard')
                    dashboard = obj.App.getActiveDashboard();
                end
            catch
                dashboard = [];
                sessionId = '';
            end
        end
    end

    methods (Static, Access = public)
        function ids = knownCommands()
            % Returns the consolidated list of command IDs the router
            % has an explicit case for. Used by the ribbon mapping test
            % so a regression that adds a button without wiring its
            % handler fails fast.
            ids = { ...
                ... % Global scope (dispatchGlobal switch)
                'File:NewProject','File:OpenProject','File:SaveProject', ...
                'File:SaveProjectAs','File:PackProject','File:Exit', ...
                'Edit:Undo','Edit:Redo', ...
                'Window:CloseActive','Window:CloseAll', ...
                'Window:ShowObjectMgr','Window:ShowLogs', ...
                'Pref:Mode:Classic','Pref:Mode:Studio','Pref:Mode:Review', ...
                'Pref:Mode:Analysis','Pref:Mode:Plot','Pref:Mode:Report', ...
                'Pref:Mode:Compact','Pref:Mode:DockedFigure', ...
                'Pref:Theme:Toggle','Pref:AutoUpdate', ...
                'Pref:ToolbarCustomize','Pref:Shortcuts', ...
                'Pref:Experimental:SharedDecode', ...
                'Help:About','Help:License','Help:QuickStart', ...
                'Help:Troubleshooting','Help:SupportBundle','Help:ErrorLog', ...
                'Help:Shortcuts','Help:Samples', ...
                'Project:HealthCheck','Project:RepairLinks','Project:EditDetails', ...
                'Toolbar:ToggleExplorer','Toolbar:ToggleRightDock','Window:ToggleRightDock', ...
                'Project:AddSession','Project:Properties','Project:CleanupCache', ...
                'Window:TileH','Window:TileV','Window:Cascade', ...
                ... % Session scope (dispatchSession switch)
                'Project:DuplicateSession','Project:RenameSession','Project:DeleteSession', ...
                'Toolbar:LoadData','Data:LoadFlight1','Data:LoadFlight2', ...
                'Data:ImportWizard','Data:LoadCoast', ...
                'Data:Validate','Data:EstimateFps','Data:Summary', ...
                'Toolbar:LoadVideo','Video:LoadVideo1','Video:LoadVideo2', ...
                'Video:Clear','Video:Snapshot','Video:DecodeSettings','Video:Metadata', ...
                'Toolbar:Sync','Sync:Flight','Sync:VideoData', ...
                'Sync:ResetVideo','Sync:OffsetEditor','Sync:QualityCheck', ...
                'Toolbar:SyncTime', ...
                'Toolbar:Play','Toolbar:Stop','Toolbar:Prev','Toolbar:Next', ...
                'Toolbar:ROI','Review:AddRoi','Toolbar:Marker','Review:AddEvent', ...
                'Review:Compare','Review:ExportTable','Review:Report', ...
                'Toolbar:Analyze','Analysis:RoiStats', ...
                'Analysis:SyncCheck','Analysis:SyncQuality', ...
                'Analysis:EventDetect','Analysis:Filter','Analysis:Smooth', ...
                'Analysis:FFT','Analysis:Compare', ...
                'Toolbar:Recalc','Analysis:Recalculate', ...
                'Plot:AddSelected','Plot:NewGraph','Plot:NewComparison', ...
                'Plot:Details','Plot:Axis','Plot:LinkAxes','Plot:Export','Plot:Copy', ...
                'Plot:ObjectManager', ...
                'Studio:OpenSampleProject'};
        end
    end

    methods (Access = private)
        function dispatchGlobal(obj, cmdId, source)
            app = obj.App;
            switch cmdId
                case {'Toolbar:New', 'File:NewProject'}
                    app.newProject();
                case {'Toolbar:Open', 'File:OpenProject'}
                    app.openProject();
                case {'Toolbar:Save', 'File:SaveProject'}
                    app.saveProject();
                case 'File:SaveProjectAs'
                    app.saveProjectAs();
                case 'File:PackProject'
                    obj.packProject(app);
                case {'Toolbar:AddSession', 'Project:AddSession'}
                    app.addSession();
                case 'Edit:Undo'
                    obj.dispatchUndo();
                case 'Edit:Redo'
                    obj.dispatchRedo();
                case 'Window:CloseActive'
                    if ~isempty(app.Workspace) && isvalid(app.Workspace)
                        app.Workspace.closeActiveTab();
                        obj.setStatus('Closed active tab');
                    end
                case 'Window:CloseAll'
                    if ~isempty(app.Workspace) && isvalid(app.Workspace)
                        app.Workspace.closeAllTabs();
                        obj.setStatus('Closed all session tabs');
                    end
                case {'Toolbar:ToggleExplorer', 'Window:ShowExplorer'}
                    % P0-2: prefer app-level width-reclaim toggle; fall
                    % back to legacy visibility-only flip if absent.
                    if ismethod(app, 'toggleExplorer')
                        app.toggleExplorer();
                        obj.setStatus(sprintf('Project Explorer: %s', ...
                            obj.collapsedToOnOff(app.IsExplorerCollapsed)));
                    else
                        obj.togglePanelVisible(app.ProjectExplorer, 'Project Explorer');
                    end
                case {'Toolbar:ToggleRightDock', 'Window:ToggleRightDock'}
                    if ismethod(app, 'toggleRightDock')
                        app.toggleRightDock();
                        obj.setStatus(sprintf('Tools & Inspector: %s', ...
                            obj.collapsedToOnOff(app.IsRightDockCollapsed)));
                    else
                        obj.togglePanelVisible(app.RightDock, 'Tools & Inspector');
                    end
                case 'Window:ShowObjectMgr'
                    obj.showRightDockTab('ObjectManagerTab', 'Object Manager');
                case 'Window:ShowLogs'
                    obj.showRightDockTab('LogsTab', 'Logs');
                case 'Pref:Mode:Review'
                    app.applyGuiMode('Review');
                case 'Pref:Mode:Classic'
                    app.applyGuiMode('Classic');
                case 'Pref:Mode:Studio'
                    app.applyGuiMode('Studio');
                case 'Pref:Mode:Analysis'
                    app.applyGuiMode('Analysis');
                case 'Pref:Mode:Plot'
                    app.applyGuiMode('Plot');
                case 'Pref:Mode:Report'
                    app.applyGuiMode('Report');
                case 'Pref:Mode:Compact'
                    app.applyGuiMode('Compact');
                case 'Pref:Mode:DockedFigure'
                    app.applyGuiMode('DockedFigure');
                case 'Pref:Theme:Toggle'
                    if ismethod(app, 'toggleTheme')
                        app.toggleTheme();
                    end
                case 'Help:About'
                    flightdash.ui.AboutDialog.show(app);
                case 'Help:License'
                    flightdash.ui.LicenseDialog.show(app);
                case 'Help:QuickStart'
                    obj.openHelpDoc('QuickStart.md');
                case 'Help:Troubleshooting'
                    obj.openHelpDoc('Troubleshooting.md');
                case 'Help:SupportBundle'
                    obj.exportSupportBundle(app);
                case 'Help:ErrorLog'
                    obj.openErrorLog(app);
                case 'Help:Shortcuts'
                    obj.openHelpDoc('Shortcuts.md');
                case 'Help:Samples'
                    obj.openHelpDoc('LearningSamples.md');
                case 'Pref:AutoUpdate'
                    obj.setStatus('Auto Update Mode — preferences dialog pending.');
                case 'Pref:ToolbarCustomize'
                    obj.setStatus('Toolbar Customize — ribbon is fixed in this build.');
                case 'Pref:Shortcuts'
                    obj.openHelpDoc('Shortcuts.md');
                case 'Pref:Experimental:SharedDecode'
                    obj.toggleSharedDecode();
                case 'Project:HealthCheck'
                    obj.runProjectHealthCheck(app);
                case 'Project:RepairLinks'
                    flightdash.ui.MissingFileRepairDialog.show(app);
                case 'Project:EditDetails'
                    if ismethod(app, 'openProjectFileEditor')
                        app.openProjectFileEditor();
                    else
                        obj.setStatus('Project File Editor not available.');
                    end
                case 'File:Exit'
                    delete(app);
                otherwise
                    obj.noop(source, cmdId);
            end
        end

        function dispatchSession(obj, cmdId, source)
            % P0-1: define `app` so the openAnalysisDialog cases below
            % (Toolbar:Analyze, Analysis:RoiStats, Analysis:SyncCheck,
            % Analysis:SyncQuality) resolve at runtime. dispatchGlobal
            % already does the same.
            app = obj.App;
            [dashboard, sessionId] = obj.activeDashboard();
            if isempty(sessionId) || isempty(dashboard) || ~isvalid(dashboard)
                obj.setStatus('No active session - open or add a session first');
                return;
            end

            switch cmdId
                case 'Project:DuplicateSession'
                    obj.App.duplicateSession(sessionId);
                case 'Project:RenameSession'
                    obj.promptAndRename(sessionId);
                case 'Project:DeleteSession'
                    obj.confirmAndDelete(sessionId);
                case {'Toolbar:LoadData', 'Data:LoadFlight1'}
                    dashboard.handleFlightFile(1);
                case 'Data:ImportWizard'
                    wiz = flightdash.ui.ImportFlightDataWizard(app);
                    wiz.show();
                case 'Data:LoadFlight2'
                    dashboard.handleFlightFile(2);
                case 'Data:LoadCoast'
                    dashboard.handleCoastFile();
                case {'Toolbar:LoadVideo', 'Video:LoadVideo1'}
                    dashboard.loadAviFile(1);
                case 'Video:LoadVideo2'
                    dashboard.loadAviFile(2);
                case {'Toolbar:Sync', 'Sync:Flight'}
                    dashboard.toggleSync();
                case {'Toolbar:Play'}
                    dashboard.startFlightPlayback(1);
                case {'Toolbar:Stop'}
                    dashboard.stopFlightPlayback(1);
                case {'Toolbar:Prev'}
                    obj.publishDashboardEvent('NavActionRequested', 1, 'prev', sessionId);
                case {'Toolbar:Next'}
                    obj.publishDashboardEvent('NavActionRequested', 1, 'next', sessionId);
                case {'Toolbar:ROI', 'Review:AddRoi'}
                    obj.publishDashboardEvent('RoiAddRequested', 1, [], sessionId);
                case {'Toolbar:Analyze', 'Analysis:RoiStats'}
                    obj.publishDashboardEvent('AnalysisComputeRequested', 1, [], sessionId);
                    obj.openAnalysisDialog(app, 'flightdash.analysis.RoiStatisticsDialog', sessionId, 1);
                case {'Analysis:SyncCheck', 'Analysis:SyncQuality'}
                    obj.openAnalysisDialog(app, 'flightdash.analysis.SyncQualityDialog', sessionId, 1);
                case 'Edit:Undo'
                    if ismethod(dashboard, 'undo')
                        dashboard.undo();
                        obj.setStatus(sprintf('Undo: %s', sessionId));
                    end
                case 'Edit:Redo'
                    if ismethod(dashboard, 'redo')
                        dashboard.redo();
                        obj.setStatus(sprintf('Redo: %s', sessionId));
                    end
                case 'Plot:AddSelected'
                    obj.publishDashboardEvent('PlotSelected', 1, [], sessionId);
                case 'Plot:NewGraph'
                    obj.publishDashboardEvent('PlotTabAddRequested', 1, [], sessionId);
                case 'Plot:ObjectManager'
                    obj.showRightDockTab('ObjectManagerTab', 'Object Manager');
                case 'Plot:Details'
                    obj.publishDashboardEvent('PlotDetailsToggled', 1, [], sessionId);
                case 'Plot:NewComparison'
                    obj.publishDashboardEvent('PlotTabAddRequested', 1, [], sessionId);
                case 'Plot:Axis'
                    obj.publishDashboardEvent('PlotDetailsToggled', 1, [], sessionId);
                case 'Plot:LinkAxes'
                    if ismethod(dashboard, 'toggleLinkAxes')
                        dashboard.toggleLinkAxes();
                    else
                        obj.setStatus('Link Axes — not implemented yet.');
                    end
                case 'Plot:Export'
                    obj.setStatus('Plot:Export — handler pending.');
                case 'Plot:Copy'
                    if ismethod(dashboard, 'copyActivePlot')
                        dashboard.copyActivePlot();
                    else
                        obj.setStatus('Plot:Copy — copy active figure not implemented yet.');
                    end
                case 'Video:Clear'
                    if ismethod(dashboard, 'clearVideo')
                        dashboard.clearVideo(1);
                        try, dashboard.clearVideo(2); catch, end
                        obj.setStatus('Video cleared.');
                    else
                        obj.setStatus('Video:Clear — handler pending.');
                    end
                case 'Video:Snapshot'
                    if ismethod(dashboard, 'snapshotCurrentFrame')
                        dashboard.snapshotCurrentFrame(1);
                    else
                        obj.setStatus('Video:Snapshot — handler pending.');
                    end
                case 'Video:DecodeSettings'
                    obj.setStatus('Video:DecodeSettings — dialog pending.');
                case 'Video:Metadata'
                    obj.setStatus('Video:Metadata — read-only viewer pending.');
                case 'Data:Validate'
                    if ismethod(dashboard, 'validateLoadedData')
                        dashboard.validateLoadedData();
                    else
                        obj.setStatus('Data:Validate — validator pending.');
                    end
                case 'Data:EstimateFps'
                    obj.setStatus('Data:EstimateFps — estimator pending.');
                case 'Data:Summary'
                    obj.setStatus('Data:Summary — summary dialog pending.');
                case 'Sync:VideoData'
                    obj.publishDashboardEvent('VideoSyncRequested', 1, [], sessionId);
                case 'Sync:ResetVideo'
                    obj.setStatus('Sync:ResetVideo — reset action pending.');
                case 'Sync:OffsetEditor'
                    obj.setStatus('Sync:OffsetEditor — editor dialog pending.');
                case 'Sync:QualityCheck'
                    obj.openAnalysisDialog(app, 'flightdash.analysis.SyncQualityDialog', sessionId, 1);
                case {'Toolbar:Marker', 'Review:AddEvent'}
                    obj.publishDashboardEvent('RoiAddRequested', 1, [], sessionId);
                case {'Toolbar:Recalc', 'Analysis:Recalculate'}
                    obj.publishDashboardEvent('AnalysisComputeRequested', 1, [], sessionId);
                case 'Analysis:EventDetect'
                    obj.setStatus('Analysis:EventDetect — detector pending.');
                case 'Analysis:Filter'
                    obj.setStatus('Analysis:Filter — filter dialog pending.');
                case 'Analysis:Smooth'
                    obj.setStatus('Analysis:Smooth — smoothing dialog pending.');
                case 'Analysis:FFT'
                    obj.setStatus('Analysis:FFT — FFT viewer pending.');
                case 'Analysis:Compare'
                    obj.setStatus('Analysis:Compare — comparison dialog pending.');
                case 'Review:Compare'
                    obj.setStatus('Review:Compare — comparison view pending.');
                case 'Review:ExportTable'
                    obj.setStatus('Review:ExportTable — exporter pending.');
                case 'Review:Report'
                    obj.setStatus('Review:Report — report generator pending.');
                case 'Studio:OpenSampleProject'
                    if ismethod(app, 'openSampleProject')
                        app.openSampleProject();
                    else
                        obj.setStatus('Sample project entry not registered.');
                    end
                case 'Toolbar:SyncTime'
                    obj.publishDashboardEvent('VideoSyncRequested', 1, [], sessionId);
                otherwise
                    obj.noop(source, cmdId, sessionId);
            end
        end

        function publishDashboardEvent(~, eventName, channelIdx, payload, sessionId)
            data = flightdash.util.AppEventData(channelIdx, payload, sessionId);
            flightdash.util.EventBus.publish(eventName, data);
        end

        function dispatchUndo(obj)
            svc = obj.activeUndoService();
            if isempty(svc) || ~isvalid(svc)
                obj.setStatus('No undo stack for active session');
                return;
            end
            if ~svc.canUndo()
                obj.setStatus('Nothing to undo');
                return;
            end
            svc.undo();
        end

        function dispatchRedo(obj)
            svc = obj.activeUndoService();
            if isempty(svc) || ~isvalid(svc)
                obj.setStatus('No redo stack for active session');
                return;
            end
            if ~svc.canRedo()
                obj.setStatus('Nothing to redo');
                return;
            end
            svc.redo();
        end

        function svc = activeUndoService(obj)
            svc = [];
            try
                dash = obj.App.getActiveDashboard();
                if ~isempty(dash) && isvalid(dash) && isprop(dash, 'UndoService')
                    svc = dash.UndoService;
                end
            catch
                svc = [];
            end
        end

        function promptAndRename(obj, sessionId)
            sess = obj.App.Project.findSession(sessionId);
            if isempty(sess), return; end
            answer = inputdlg({'New session name:'}, 'Rename Session', [1 50], {sess.DisplayName});
            if isempty(answer), return; end
            newName = strtrim(answer{1});
            if isempty(newName), return; end
            obj.App.renameSession(sessionId, newName);
        end

        function confirmAndDelete(obj, sessionId)
            sess = obj.App.Project.findSession(sessionId);
            if isempty(sess), return; end
            fig = obj.App.UIFigure;
            if ~isempty(fig) && isvalid(fig)
                sel = uiconfirm(fig, ...
                    sprintf('Delete session "%s"?', sess.DisplayName), ...
                    'Confirm Delete Session', ...
                    'Options', {'Delete', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(sel, 'Delete'), return; end
            end
            obj.App.removeSession(sessionId);
        end

        function s = collapsedToOnOff(~, isCollapsed)
            if isCollapsed, s = 'off'; else, s = 'on'; end
        end

        function packProject(obj, app)
            % Phase F entry point. Prompts the user for a destination
            % folder, runs ProjectPacker (which operates on a deep
            % copy — never mutates the live app.Project), and reports
            % warnings + the packed .frsproj path to the status bar.
            try
                if isempty(app) || ~isvalid(app) || isempty(app.Project)
                    obj.setStatus('Pack Project: no project loaded.');
                    return;
                end
                destFolder = uigetdir(pwd, 'Pack Project — choose destination folder');
                if isequal(destFolder, 0), return; end
                opts = struct('IncludeVideo', true, 'IncludeFlightData', true, ...
                    'IncludeOptionFiles', true, 'UseRelativePaths', true, ...
                    'Overwrite', false);
                result = flightdash.project.ProjectPacker.pack(app.Project, destFolder, opts);
                if result.OK
                    msg = sprintf('Packed: %s', result.PackedProjectPath);
                    if ~isempty(result.Warnings)
                        msg = sprintf('%s (%d warnings)', msg, numel(result.Warnings));
                    end
                    obj.setStatus(msg);
                    if ~isempty(result.Warnings) && ~isempty(app.UIFigure) ...
                            && isvalid(app.UIFigure)
                        uialert(app.UIFigure, strjoin(result.Warnings, newline), ...
                            'Pack Project — warnings', 'Icon', 'warning');
                    end
                else
                    obj.setStatus(['Pack Project failed: ' strjoin(result.Warnings, ' | ')]);
                end
            catch ME
                obj.reportException('Command', 'File:PackProject', ME);
            end
        end

        function runProjectHealthCheck(obj, app)
            try
                report = flightdash.project.ProjectHealthChecker.check(app.Project);
                summary = flightdash.project.ProjectHealthChecker.summarize(report);
                obj.setStatus(summary);
                if ~flightdash.project.ProjectHealthChecker.isHealthy(report)
                    flightdash.ui.MissingFileRepairDialog.show(app);
                end
            catch ME
                obj.reportException('Command', 'Project:HealthCheck', ME);
            end
        end

        function toggleSharedDecode(obj)
            % Review priority 5: surface the SharedDecodeService
            % prototype as an explicit opt-in. Toggles the per-active-
            % dashboard UseSharedDecodeService flag + reports the new
            % state. When no dashboard is active the toggle is a no-op
            % with a status message.
            try
                [dash, sessionId] = obj.activeDashboard();
                if isempty(dash) || ~isvalid(dash)
                    obj.setStatus(['Shared Decode toggle ignored — ' ...
                        'no active session.']);
                    return;
                end
                current = false;
                if isprop(dash, 'UseSharedDecodeService')
                    current = logical(dash.UseSharedDecodeService);
                end
                if ismethod(dash, 'setSharedDecodeEnabled')
                    dash.setSharedDecodeEnabled(~current);
                elseif isprop(dash, 'UseSharedDecodeService')
                    dash.UseSharedDecodeService = ~current;
                end
                if ~current
                    obj.setStatus(sprintf( ...
                        'Experimental Shared Decode enabled for %s (opt-in prototype).', ...
                        sessionId));
                else
                    obj.setStatus(sprintf( ...
                        'Experimental Shared Decode disabled for %s.', sessionId));
                end
            catch ME
                obj.reportException('Command', 'Pref:Experimental:SharedDecode', ME);
            end
        end

        function openErrorLog(obj, app) %#ok<INUSD>
            try
                if exist('flightdash.util.ErrorLog', 'class') == 8 ...
                        && ismethod('flightdash.util.ErrorLog', 'showRecent')
                    flightdash.util.ErrorLog.showRecent();
                    obj.setStatus('Showing recent error log entries.');
                else
                    obj.setStatus('Error log viewer not available.');
                end
            catch ME
                obj.reportException('Command', 'Help:ErrorLog', ME);
            end
        end

        function exportSupportBundle(obj, app)
            try
                zipPath = flightdash.util.SupportBundle.exportFor(app);
                if isempty(zipPath)
                    obj.setStatus('Support bundle export cancelled');
                else
                    obj.setStatus(sprintf('Support bundle: %s', zipPath));
                end
            catch ME
                obj.reportException('Command', 'Help:SupportBundle', ME);
            end
        end

        function openHelpDoc(obj, basename)
            % Phase B-2: open a Markdown doc from docs/user/. Falls
            % back to a status-bar message if the doc is missing —
            % never blocks the user. Uses `web` so MATLAB's built-in
            % browser handles the .md (renders as plain text).
            try
                here = fileparts(mfilename('fullpath'));
                root = fullfile(here, '..', '..', '..');
                docPath = fullfile(root, 'docs', 'user', char(basename));
                if isfile(docPath)
                    try, web(docPath, '-browser'); catch, web(docPath); end
                    obj.setStatus(sprintf('Help: opened %s', basename));
                else
                    obj.setStatus(sprintf('Help doc not found: %s', basename));
                end
            catch ME
                obj.reportException('Command', sprintf('Help:%s', basename), ME);
            end
        end

        function togglePanelVisible(obj, mgr, label)
            try
                if isempty(mgr) || ~isvalid(mgr) || ~isprop(mgr, 'Panel') || ~isgraphics(mgr.Panel)
                    obj.noop('Command', label);
                    return;
                end
                if strcmpi(char(mgr.Panel.Visible), 'on')
                    mgr.Panel.Visible = 'off';
                else
                    mgr.Panel.Visible = 'on';
                end
                obj.setStatus(sprintf('%s: %s', label, char(mgr.Panel.Visible)));
            catch ME
                obj.reportException('Command', label, ME);
            end
        end

        function openAnalysisDialog(obj, app, dialogClass, sessionId, channelIdx)
            % Phase 7 entry point: instantiate an AnalysisDialog subclass
            % for the active session, switch the right-dock to the
            % Analysis tab as a visual cue, and show the dialog.
            try
                if isempty(sessionId)
                    sessionId = char(app.ActiveSessionId);
                end
                if nargin < 5 || isempty(channelIdx), channelIdx = 1; end
                ctor = str2func(char(dialogClass));
                dlg = ctor(app, sessionId, channelIdx);
                obj.showRightDockTab('AnalysisTab', 'Analysis');
                dlg.show();
            catch ME
                obj.reportException('Command', 'openAnalysisDialog', ME);
            end
        end

        function showRightDockTab(obj, propName, label)
            try
                rd = obj.App.RightDock;
                if isempty(rd) || ~isvalid(rd) || isempty(rd.TabGroup) || ~isvalid(rd.TabGroup)
                    obj.noop('Command', label);
                    return;
                end
                if isprop(rd, propName) && ~isempty(rd.(propName)) && isvalid(rd.(propName))
                    rd.TabGroup.SelectedTab = rd.(propName);
                    obj.setStatus(sprintf('Showing %s', label));
                else
                    obj.noop('Command', label);
                end
            catch ME
                obj.reportException('Command', label, ME);
            end
        end

        function noop(obj, source, cmdId, sessionId)
            if nargin >= 4 && ~isempty(sessionId)
                obj.setStatus(sprintf('%s: %s no-op for %s', source, cmdId, sessionId));
            else
                obj.setStatus(sprintf('%s: %s no-op', source, cmdId));
            end
        end

        function reportException(obj, source, cmdId, ME)
            try, obj.App.logCaught(ME, ['CommandRouter:' char(cmdId)]); catch, end
            obj.setStatus(sprintf('%s %s failed: %s', source, char(cmdId), ME.message));
        end

        function setStatus(obj, msg)
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(obj.shorten(char(msg), 140));
                end
            catch
            end
        end

        function out = shorten(~, msg, maxLen)
            if nargin < 3, maxLen = 140; end
            msg = regexprep(char(msg), '\s+', ' ');
            if numel(msg) > maxLen
                out = [msg(1:maxLen-3) '...'];
            else
                out = msg;
            end
        end
    end
end
