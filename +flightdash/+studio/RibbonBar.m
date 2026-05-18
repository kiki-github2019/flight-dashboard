classdef RibbonBar < handle
    %RIBBONBAR  Top-level ribbon: tab strip + active-tab content area.
    %
    %   Composed of:
    %     - Top row : Quick Access strip (project title, mode dropdown, help)
    %     - Tab row : uitabgroup with one RibbonTab per category
    %
    %   Phase 1 ships the shell + tab plumbing. Subsequent ribbon
    %   phases populate the tabs with concrete RibbonGroup+RibbonButton
    %   trees and migrate functionality off MenuManager + ToolbarManager.

    properties (Access = public)
        App                    % flightdash.studio.FlightReviewStudioApp
        Tabs       cell = {}   % cell of RibbonTab handles
        QuickAccess struct = struct()
    end

    properties (Access = public, Transient)
        Container              % uipanel
        OuterGrid              % uigridlayout
        QuickAccessPanel       % uipanel
        TabGroup               % uitabgroup
    end

    methods
        function obj = RibbonBar(app)
            obj.App = app;
        end

        function build(obj, parent)
            theme = obj.theme();
            obj.Container = uipanel(parent, ...
                'BorderType', 'none', ...
                'BackgroundColor', theme.RibbonBg);
            obj.OuterGrid = uigridlayout(obj.Container, [2 1]);
            obj.OuterGrid.RowHeight     = {26, '1x'};
            obj.OuterGrid.ColumnWidth   = {'1x'};
            obj.OuterGrid.RowSpacing    = 0;
            obj.OuterGrid.Padding       = [0 0 0 0];
            obj.OuterGrid.BackgroundColor = theme.RibbonBg;

            obj.buildQuickAccess();
            obj.TabGroup = uitabgroup(obj.OuterGrid);
            obj.TabGroup.Layout.Row = 2;
            obj.TabGroup.Layout.Column = 1;
        end

        function addTab(obj, tab)
            % P2-fix: build-before-register so a tab whose build throws
            % is NOT silently counted in obj.Tabs. Errors are surfaced
            % through app.logCaught (when available) so the
            % buildShell-level catch can see and report them.
            if isempty(tab) || ~isvalid(tab), return; end
            try
                tab.build(obj.TabGroup, obj.adapter());
            catch ME
                try, obj.App.logCaught(ME, 'Ribbon:tabBuild'); catch, end
                try, delete(tab); catch, end
                rethrow(ME);
            end
            obj.Tabs{end+1} = tab;
        end

        function syncMode(obj, modeName)
            % Called from FlightReviewStudioApp.syncGuiModeMenuState
            % so the Mode dropdown stays in step with menu/project
            % state. Tolerates partial construction.
            try
                if isempty(obj.QuickAccess) || ~isfield(obj.QuickAccess, 'ModeDropdown')
                    return;
                end
                dd = obj.QuickAccess.ModeDropdown;
                if isempty(dd) || ~isvalid(dd), return; end
                mode = char(modeName);
                if any(strcmp(dd.Items, mode))
                    dd.Value = mode;
                end
            catch
            end
        end

        function syncProjectName(obj, name)
            % Keep the editable project field in step with external
            % renames (e.g. Open Project flow).
            try
                if isempty(obj.QuickAccess) || ~isfield(obj.QuickAccess, 'Title')
                    return;
                end
                ed = obj.QuickAccess.Title;
                if isempty(ed) || ~isvalid(ed), return; end
                ed.Value = char(name);
            catch
            end
        end

        function ad = adapter(obj)
            ad = [];
            try
                dash = obj.activeDashboard();
                if ~isempty(dash) && ismethod(dash, 'getAdapter')
                    ad = dash.getAdapter();
                end
            catch
            end
            % Fallback: a thin adapter shim that dispatches via the
            % Studio app's CommandRouter when no embedded dashboard is
            % active. This keeps ribbon clicks responsive in the
            % Welcome / standalone state.
            if isempty(ad)
                ad = flightdash.studio.RibbonBar.studioShim(obj.App);
            end
        end

        function setEnabledByCmd(obj, cmdId, tf)
            % Enable/disable any ribbon button whose CmdId matches.
            for ti = 1:numel(obj.Tabs)
                t = obj.Tabs{ti};
                if isempty(t), continue; end
                for gi = 1:numel(t.Groups)
                    g = t.Groups{gi};
                    if isempty(g), continue; end
                    for bi = 1:numel(g.Buttons)
                        b = g.Buttons{bi};
                        if isempty(b), continue; end
                        if strcmp(b.CmdId, cmdId)
                            try, b.setEnabled(tf); catch, end
                        end
                        try, b.setDropdownEnabledByCmd(cmdId, tf); catch, end
                    end
                end
            end
        end

        function setUndoState(obj, canUndo, canRedo)
            obj.setEnabledByCmd('Edit:Undo', canUndo);
            obj.setEnabledByCmd('Edit:Redo', canRedo);
        end

        function ids = allCommandIds(obj)
            % Walks every tab > group > button (incl. dropdown items)
            % and returns a unique cellstr of command IDs the ribbon
            % can dispatch. Used by the mapping test that asserts each
            % id is recognised by CommandRouter.
            seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            for ti = 1:numel(obj.Tabs)
                t = obj.Tabs{ti};
                if isempty(t), continue; end
                for gi = 1:numel(t.Groups)
                    g = t.Groups{gi};
                    if isempty(g), continue; end
                    for bi = 1:numel(g.Buttons)
                        b = g.Buttons{bi};
                        if isempty(b), continue; end
                        if ~isempty(b.CmdId), seen(b.CmdId) = true; end
                        for di = 1:numel(b.DropdownItems)
                            it = b.DropdownItems{di};
                            if iscell(it) && numel(it) >= 2 && ~isempty(it{2})
                                seen(char(it{2})) = true;
                            end
                        end
                    end
                end
            end
            ids = keys(seen);
        end

        function delete(obj)
            for k = 1:numel(obj.Tabs)
                try
                    t = obj.Tabs{k};
                    if ~isempty(t) && isvalid(t), delete(t); end
                catch
                end
            end
            obj.Tabs = {};
            try, if ~isempty(obj.Container) && isvalid(obj.Container), delete(obj.Container); end, catch, end
        end
    end

    methods (Access = private)
        function buildQuickAccess(obj)
            theme = obj.theme();
            obj.QuickAccessPanel = uipanel(obj.OuterGrid, ...
                'BorderType', 'none', ...
                'BackgroundColor', theme.HeaderBg);
            obj.QuickAccessPanel.Layout.Row = 1;
            obj.QuickAccessPanel.Layout.Column = 1;

            g = uigridlayout(obj.QuickAccessPanel, [1 5]);
            g.RowHeight     = {'1x'};
            g.ColumnWidth   = {'1x', 140, 80, 30, 30};
            g.ColumnSpacing = 4;
            g.Padding       = [6 2 6 2];
            g.BackgroundColor = theme.HeaderBg;

            obj.QuickAccess.Title = uieditfield(g, 'text', ...
                'Value', char(obj.App.ProjectName), ...
                'FontWeight', 'bold', ...
                'Tooltip', 'Rename the active project', ...
                'ValueChangedFcn', @(src,~) obj.onProjectRename(src.Value));
            modeItems = {'Classic','Studio','Review','Analysis','Plot', ...
                         'Report','Compact','DockedFigure'};
            initialMode = obj.resolveInitialMode(modeItems);
            obj.QuickAccess.ModeDropdown = uidropdown(g, ...
                'Items', modeItems, ...
                'Value', initialMode, ...
                'ValueChangedFcn', @(src,~) obj.onModeChange(src.Value));
            obj.QuickAccess.ThemeBtn = uibutton(g, 'push', 'Text', 'Theme', ...
                'ButtonPushedFcn', @(~,~) obj.dispatch('Pref:Theme:Toggle'));
            % Preferences gear with submenu (Phase 6).
            obj.QuickAccess.SettingsBtn = uibutton(g, 'push', ...
                'Text', char(9881), ...        % ⚙
                'FontWeight', 'bold', ...
                'Tooltip', 'Preferences', ...
                'ButtonPushedFcn', @(src,~) obj.showSettingsMenu(src));
            % Help button with submenu (Phase 6).
            obj.QuickAccess.HelpBtn = uibutton(g, 'push', 'Text', '?', ...
                'FontWeight', 'bold', ...
                'Tooltip', 'Help & support', ...
                'ButtonPushedFcn', @(src,~) obj.showHelpMenu(src));
            flightdash.ui.StudioTheme.styleButton(obj.QuickAccess.ThemeBtn, theme, 'secondary');
            flightdash.ui.StudioTheme.styleButton(obj.QuickAccess.SettingsBtn, theme, 'ghost');
            flightdash.ui.StudioTheme.styleButton(obj.QuickAccess.HelpBtn, theme, 'ghost');
        end

        function theme = theme(obj)
            try
                theme = obj.App.CurrentThemeStruct;
            catch
                theme = flightdash.ui.StudioTheme.light();
            end
            if ~isstruct(theme) || ~isfield(theme, 'RibbonBg')
                theme = flightdash.ui.StudioTheme.light();
            end
        end

        function showSettingsMenu(obj, src)
            % Experimental opt-in row reports its current state so the
            % user can see whether the shared decode prototype is
            % active. Label includes the "Experimental" tag so it is
            % never mistaken for a stable feature.
            sharedOn = obj.isSharedDecodeOn();
            if sharedOn, mark = 'ON'; else, mark = 'OFF'; end
            sharedLabel = sprintf('Experimental: Shared Decode (opt-in) — %s', mark);
            obj.showMenuAt(src, ...
                {{'Auto Update Mode',  'Pref:AutoUpdate'}, ...
                 {'Toolbar Customize', 'Pref:ToolbarCustomize'}, ...
                 {'Shortcut Settings', 'Pref:Shortcuts'}, ...
                 {sharedLabel,         'Pref:Experimental:SharedDecode'}, ...
                 {'Project Properties','Project:Properties'}, ...
                 {'Edit Project Details', 'Project:EditDetails'}, ...
                 {'Cleanup Project Cache','Project:CleanupCache'}, ...
                 {'Repair Missing Files', 'Project:RepairLinks'}});
        end

        function tf = isSharedDecodeOn(obj)
            tf = false;
            try
                dash = obj.activeDashboard();
                if ~isempty(dash) && isvalid(dash) && isprop(dash, 'UseSharedDecodeService')
                    tf = logical(dash.UseSharedDecodeService);
                end
            catch
            end
        end

        function showHelpMenu(obj, src)
            obj.showMenuAt(src, ...
                {{'Quick Start',         'Help:QuickStart'}, ...
                 {'Shortcut Guide',      'Help:Shortcuts'}, ...
                 {'Learning Samples',    'Help:Samples'}, ...
                 {'Troubleshooting',     'Help:Troubleshooting'}, ...
                 {'Error Log',           'Help:ErrorLog'}, ...
                 {'Export Support Bundle', 'Help:SupportBundle'}, ...
                 {'About Flight Review Studio', 'Help:About'}});
        end

        function showMenuAt(obj, src, items)
            try
                fig = ancestor(src, 'figure');
                if isempty(fig) || ~isvalid(fig), return; end
                cm = uicontextmenu(fig);
                for k = 1:numel(items)
                    item = items{k};
                    if ~iscell(item) || numel(item) < 2, continue; end
                    uimenu(cm, 'Text', char(item{1}), ...
                        'MenuSelectedFcn', @(~,~) obj.dispatch(char(item{2})));
                end
                pos = getpixelposition(src, true);
                cm.Position = [pos(1), pos(2)];
                cm.Visible = 'on';
            catch
            end
        end

        function dispatch(obj, cmdId)
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ismethod(obj.App, 'dispatchCommand')
                    obj.App.dispatchCommand(cmdId, 'Ribbon:QuickAccess');
                end
            catch
            end
        end

        function onModeChange(obj, value)
            obj.dispatch(['Pref:Mode:' char(value)]);
        end

        function onProjectRename(obj, newName)
            % P2-fix: editable Quick Access project name. Forwards to
            % the app's rename hook; falls back to a direct value-class
            % reassign so the rename works even before a dedicated
            % rename verb is wired.
            try
                newName = char(newName);
                if isempty(strtrim(newName)), newName = 'Untitled'; end
                if ~isempty(obj.App) && isvalid(obj.App)
                    if ismethod(obj.App, 'renameProject')
                        obj.App.renameProject(newName);
                    elseif isprop(obj.App, 'Project') && ~isempty(obj.App.Project)
                        tmp = obj.App.Project;
                        tmp.ProjectName = newName;
                        obj.App.Project = tmp;
                        if ismethod(obj.App, 'refreshTitle'), obj.App.refreshTitle(); end
                    end
                end
            catch ME
                try, obj.App.logCaught(ME, 'Ribbon:projectRename'); catch, end
            end
        end

        function mode = resolveInitialMode(obj, fallbackItems)
            mode = fallbackItems{2}; % 'Studio'
            try
                if ~isempty(obj.App) && isvalid(obj.App)
                    if ismethod(obj.App, 'currentGuiMode')
                        v = char(obj.App.currentGuiMode());
                    elseif isprop(obj.App, 'Project') && ~isempty(obj.App.Project) ...
                            && isprop(obj.App.Project, 'GuiMode')
                        v = char(obj.App.Project.GuiMode);
                    else
                        v = '';
                    end
                    if ~isempty(v) && any(strcmpi(fallbackItems, v))
                        idx = find(strcmpi(fallbackItems, v), 1);
                        mode = fallbackItems{idx};
                    end
                end
            catch
            end
        end

        function dash = activeDashboard(obj)
            dash = [];
            try
                if ~isempty(obj.App) && isvalid(obj.App) && ismethod(obj.App, 'getActiveDashboard')
                    dash = obj.App.getActiveDashboard();
                end
            catch
            end
        end
    end

    methods (Static, Access = private)
        function shim = studioShim(app)
            % Returns an object that exposes dispatchCommand / logCaught
            % matching the DashboardAppAdapter surface so RibbonButton
            % can call it without branching on adapter availability.
            shim = struct( ...
                'dispatchCommand', @(cmdId, src) localDispatch(app, cmdId, src), ...
                'logCaught',       @(ME, tag)  localLog(app, ME, tag), ...
                'isValidApp',      @() ~isempty(app) && isvalid(app));
        end
    end
end

function localDispatch(app, cmdId, src)
    try
        if ~isempty(app) && isvalid(app) && ismethod(app, 'dispatchCommand')
            app.dispatchCommand(char(cmdId), char(src));
        end
    catch
    end
end

function localLog(app, ME, tag)
    try
        if ~isempty(app) && isvalid(app) && ismethod(app, 'logCaught')
            app.logCaught(ME, char(tag));
        end
    catch
    end
end
