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
                'Pref:Mode:Classic', 'Pref:Mode:Studio', ...
                'Pref:Mode:Review', 'Pref:Mode:Analysis', 'Pref:Mode:Plot', ...
                'Pref:Mode:Report', 'Pref:Mode:Compact', 'Pref:Mode:DockedFigure', ...
                'Pref:AutoUpdate', ...
                'Pref:ToolbarCustomize', 'Pref:Shortcuts', ...
                'Help:Shortcuts', 'Help:Samples', 'Help:ErrorLog', 'Help:About'};

            if any(strcmp(cmdId, globalCommands))
                scope = 'global';
                return;
            end

            sessionPrefixes = { ...
                'Toolbar:Load', 'Toolbar:Sync', 'Toolbar:Play', 'Toolbar:Stop', ...
                'Toolbar:Prev', 'Toolbar:Next', 'Toolbar:ROI', 'Toolbar:Marker', ...
                'Toolbar:Analyze', 'Toolbar:Recalc', ...
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
                    obj.togglePanelVisible(app.ProjectExplorer, 'Project Explorer');
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
                case 'File:Exit'
                    delete(app);
                otherwise
                    obj.noop(source, cmdId);
            end
        end

        function dispatchSession(obj, cmdId, source)
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
