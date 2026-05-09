classdef MenuManager < handle
    % flightdash.studio.MenuManager
    % Builds the top menu bar (File / Project / Data / Video / Sync / Review /
    % Analysis / Plot / Window / Preferences / Help) on the Studio uifigure.
    %
    % Phase 1: structure only. Most actions are placeholders that publish
    % EventBus events for Phase 6+ wiring; for now they show 'not implemented'.

    properties (Access = public)
        App
        Roots struct = struct()    % Map of menu name -> root uimenu
        ModeMenus struct = struct()
    end

    methods
        function obj = MenuManager(app)
            obj.App = app;
            obj.build();
        end

        function delete(obj)
            % Menus auto-delete when uifigure is deleted.
            obj.Roots = struct();
            obj.ModeMenus = struct();
        end

        function syncGuiMode(obj, modeName)
            try
                mode = char(modeName);
                names = fieldnames(obj.ModeMenus);
                for k = 1:numel(names)
                    item = obj.ModeMenus.(names{k});
                    if isempty(item) || ~isvalid(item), continue; end
                    if strcmpi(names{k}, mode)
                        item.Checked = 'on';
                    else
                        item.Checked = 'off';
                    end
                end
            catch
            end
        end
    end

    methods (Access = private)
        function build(obj)
            fig = obj.App.UIFigure;

            obj.Roots.File = obj.makeRoot(fig, 'File');
            obj.addLeaf(obj.Roots.File, 'New Project',           'File:NewProject');
            obj.addLeaf(obj.Roots.File, 'Open Project...',       'File:OpenProject');
            obj.addLeaf(obj.Roots.File, 'Save Project',          'File:SaveProject');
            obj.addLeaf(obj.Roots.File, 'Save Project As...',    'File:SaveProjectAs');
            obj.addSeparator(obj.Roots.File, 'Pack Project...',  'File:PackProject');
            obj.addLeaf(obj.Roots.File, 'Import Session Config', 'File:ImportSession');
            obj.addLeaf(obj.Roots.File, 'Export Session Config', 'File:ExportSession');
            obj.addSeparator(obj.Roots.File, 'Exit', 'File:Exit');

            obj.Roots.Project = obj.makeRoot(fig, 'Project');
            obj.addLeaf(obj.Roots.Project, 'Add Review Session', 'Project:AddSession');
            obj.addLeaf(obj.Roots.Project, 'Duplicate Session',  'Project:DuplicateSession');
            obj.addLeaf(obj.Roots.Project, 'Rename Session',     'Project:RenameSession');
            obj.addLeaf(obj.Roots.Project, 'Delete Session',     'Project:DeleteSession');
            obj.addSeparator(obj.Roots.Project, 'Find in Project', 'Project:Find');
            obj.addLeaf(obj.Roots.Project, 'Project Properties', 'Project:Properties');
            obj.addLeaf(obj.Roots.Project, 'Cleanup Project Cache', 'Project:CleanupCache');

            obj.Roots.Data = obj.makeRoot(fig, 'Data');
            obj.addLeaf(obj.Roots.Data, 'Load Flight 1 Data', 'Data:LoadFlight1');
            obj.addLeaf(obj.Roots.Data, 'Load Flight 2 Data', 'Data:LoadFlight2');
            obj.addLeaf(obj.Roots.Data, 'Load Coastline...',  'Data:LoadCoast');
            obj.addSeparator(obj.Roots.Data, 'Column Mapping', 'Data:ColumnMapping');
            obj.addLeaf(obj.Roots.Data, 'Validate Data',      'Data:Validate');
            obj.addLeaf(obj.Roots.Data, 'Estimate Data FPS',  'Data:EstimateFps');
            obj.addLeaf(obj.Roots.Data, 'Show Data Summary',  'Data:Summary');

            obj.Roots.Video = obj.makeRoot(fig, 'Video');
            obj.addLeaf(obj.Roots.Video, 'Load Video 1', 'Video:LoadVideo1');
            obj.addLeaf(obj.Roots.Video, 'Load Video 2', 'Video:LoadVideo2');
            obj.addLeaf(obj.Roots.Video, 'Clear Video',  'Video:Clear');
            obj.addSeparator(obj.Roots.Video, 'Clear Video Cache', 'Video:ClearCache');
            obj.addLeaf(obj.Roots.Video, 'Snapshot Current Frame', 'Video:Snapshot');
            obj.addLeaf(obj.Roots.Video, 'Decode Settings',  'Video:DecodeSettings');
            obj.addLeaf(obj.Roots.Video, 'Video Metadata',   'Video:Metadata');

            obj.Roots.Sync = obj.makeRoot(fig, 'Sync');
            obj.addLeaf(obj.Roots.Sync, 'Flight Time Sync',  'Sync:Flight');
            obj.addLeaf(obj.Roots.Sync, 'Video Data Sync',   'Sync:VideoData');
            obj.addSeparator(obj.Roots.Sync, 'Reset Flight Sync', 'Sync:ResetFlight');
            obj.addLeaf(obj.Roots.Sync, 'Reset Video Sync',  'Sync:ResetVideo');
            obj.addLeaf(obj.Roots.Sync, 'Sync Offset Editor', 'Sync:OffsetEditor');
            obj.addLeaf(obj.Roots.Sync, 'Sync Quality Check', 'Sync:QualityCheck');

            obj.Roots.Review = obj.makeRoot(fig, 'Review');
            obj.addLeaf(obj.Roots.Review, 'Add ROI',                'Review:AddRoi');
            obj.addLeaf(obj.Roots.Review, 'Add Event Marker',       'Review:AddEvent');
            obj.addSeparator(obj.Roots.Review, 'Save Review Result', 'Review:SaveResult');
            obj.addLeaf(obj.Roots.Review, 'Compare Sessions',       'Review:Compare');
            obj.addLeaf(obj.Roots.Review, 'Export Review Table',    'Review:ExportTable');
            obj.addLeaf(obj.Roots.Review, 'Generate Review Report', 'Review:Report');

            obj.Roots.Analysis = obj.makeRoot(fig, 'Analysis');
            obj.addLeaf(obj.Roots.Analysis, 'ROI Statistics',     'Analysis:RoiStats');
            obj.addLeaf(obj.Roots.Analysis, 'Event Detection',    'Analysis:EventDetect');
            obj.addLeaf(obj.Roots.Analysis, 'Sync Quality Analysis', 'Analysis:SyncQuality');
            obj.addLeaf(obj.Roots.Analysis, 'Signal Filtering',   'Analysis:Filter');
            obj.addLeaf(obj.Roots.Analysis, 'Smoothing',          'Analysis:Smooth');
            obj.addLeaf(obj.Roots.Analysis, 'FFT',                'Analysis:FFT');
            obj.addLeaf(obj.Roots.Analysis, 'Compare Sessions',   'Analysis:Compare');
            obj.addSeparator(obj.Roots.Analysis, 'Analysis Themes', 'Analysis:Themes');
            obj.addLeaf(obj.Roots.Analysis, 'Recalculate',        'Analysis:Recalculate');

            obj.Roots.Plot = obj.makeRoot(fig, 'Plot');
            obj.addLeaf(obj.Roots.Plot, 'New Graph',              'Plot:NewGraph');
            obj.addLeaf(obj.Roots.Plot, 'New Comparison Graph',   'Plot:NewComparison');
            obj.addLeaf(obj.Roots.Plot, 'Add Selected Variable',  'Plot:AddSelected');
            obj.addSeparator(obj.Roots.Plot, 'Object Manager',    'Plot:ObjectManager');
            obj.addLeaf(obj.Roots.Plot, 'Plot Details',           'Plot:Details');
            obj.addLeaf(obj.Roots.Plot, 'Axis Settings',          'Plot:Axis');
            obj.addLeaf(obj.Roots.Plot, 'Link Axes',              'Plot:LinkAxes');
            obj.addLeaf(obj.Roots.Plot, 'Export Figure',          'Plot:Export');
            obj.addLeaf(obj.Roots.Plot, 'Copy Figure',            'Plot:Copy');

            obj.Roots.Window = obj.makeRoot(fig, 'Window');
            obj.addLeaf(obj.Roots.Window, 'Tile Horizontally',    'Window:TileH');
            obj.addLeaf(obj.Roots.Window, 'Tile Vertically',      'Window:TileV');
            obj.addLeaf(obj.Roots.Window, 'Cascade',              'Window:Cascade');
            obj.addSeparator(obj.Roots.Window, 'Close Active Tab', 'Window:CloseActive');
            obj.addLeaf(obj.Roots.Window, 'Close All Tabs',       'Window:CloseAll');
            obj.addSeparator(obj.Roots.Window, 'Show Project Explorer', 'Window:ShowExplorer');
            obj.addLeaf(obj.Roots.Window, 'Show Object Manager',  'Window:ShowObjectMgr');
            obj.addLeaf(obj.Roots.Window, 'Show Logs',            'Window:ShowLogs');

            obj.Roots.Preferences = obj.makeRoot(fig, 'Preferences');
            modeRoot = obj.addSubmenu(obj.Roots.Preferences, 'GUI Mode');
            obj.ModeMenus.Classic  = obj.addLeaf(modeRoot, 'Classic Mode',    'Pref:Mode:Classic');
            obj.ModeMenus.Studio   = obj.addLeaf(modeRoot, 'Studio Mode',     'Pref:Mode:Studio');
            obj.ModeMenus.Review   = obj.addLeaf(modeRoot, 'Review Mode',     'Pref:Mode:Review');
            obj.ModeMenus.Analysis = obj.addLeaf(modeRoot, 'Analysis Mode',   'Pref:Mode:Analysis');
            obj.ModeMenus.Plot     = obj.addLeaf(modeRoot, 'Plot Mode',       'Pref:Mode:Plot');
            obj.ModeMenus.Report   = obj.addLeaf(modeRoot, 'Report Mode',     'Pref:Mode:Report');
            obj.ModeMenus.Compact  = obj.addLeaf(modeRoot, 'Compact Mode',    'Pref:Mode:Compact');
            obj.addLeaf(obj.Roots.Preferences, 'Auto Update Mode',     'Pref:AutoUpdate');
            obj.addLeaf(obj.Roots.Preferences, 'Toolbar Customize',    'Pref:ToolbarCustomize');
            obj.addLeaf(obj.Roots.Preferences, 'Shortcut Settings',    'Pref:Shortcuts');

            obj.Roots.Help = obj.makeRoot(fig, 'Help');
            obj.addLeaf(obj.Roots.Help, 'Shortcut Guide',  'Help:Shortcuts');
            obj.addLeaf(obj.Roots.Help, 'Learning Samples', 'Help:Samples');
            obj.addLeaf(obj.Roots.Help, 'Error Log',       'Help:ErrorLog');
            obj.addSeparator(obj.Roots.Help, 'About', 'Help:About');
        end

        function m = makeRoot(~, fig, label)
            m = uimenu(fig, 'Text', label);
        end

        function m = addLeaf(obj, parent, label, cmdId)
            m = uimenu(parent, 'Text', label, ...
                'MenuSelectedFcn', @(~,~) obj.dispatch(cmdId));
        end

        function m = addSeparator(obj, parent, label, cmdId)
            m = uimenu(parent, 'Text', label, 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.dispatch(cmdId));
        end

        function sub = addSubmenu(~, parent, label)
            sub = uimenu(parent, 'Text', label);
        end

        function dispatch(obj, cmdId)
            % Delegate to the shared command router so menu and toolbar
            % commands use the same active-session target.
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ismethod(obj.App, 'dispatchCommand')
                    obj.App.dispatchCommand(cmdId, 'Menu');
                end
            catch ME
                if ~isempty(obj.App) && isvalid(obj.App) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Menu %s failed: %s', cmdId, ME.message));
                end
            end
        end

        function id = activeSessionIdOrWarn(obj)
            % [PHASE 5] Look up the workspace's active tab session id.
            % Returns '' if the user is on the Welcome tab so callers can
            % surface a friendly status bar message.
            id = '';
            try
                if ~isempty(obj.App.Workspace) && isvalid(obj.App.Workspace)
                    raw = obj.App.Workspace.activeSessionId();
                    if ~isempty(raw) && ~strcmp(raw, 'standalone')
                        id = char(raw);
                    end
                end
                if isempty(id) && ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage('No active session — open or add a session first');
                end
            catch
            end
        end

        function promptAndRename(obj, sessionId)
            try
                sess = obj.App.Project.findSession(sessionId);
                if isempty(sess), return; end
                answer = inputdlg({'New session name:'}, 'Rename Session', ...
                    [1 50], {sess.DisplayName});
                if isempty(answer), return; end
                newName = strtrim(answer{1});
                if isempty(newName), return; end
                obj.App.renameSession(sessionId, newName);
            catch ME
                if ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Rename failed: %s', ME.message));
                end
            end
        end

        function confirmAndDelete(obj, sessionId)
            try
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
            catch ME
                if ~isempty(obj.App.StatusBar)
                    obj.App.StatusBar.setMessage(sprintf('Delete failed: %s', ME.message));
                end
            end
        end
    end
end
