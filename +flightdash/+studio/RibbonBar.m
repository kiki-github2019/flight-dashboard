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
            obj.Container = uipanel(parent, ...
                'BorderType', 'none', ...
                'BackgroundColor', [0.94 0.94 0.94]);
            obj.OuterGrid = uigridlayout(obj.Container, [2 1]);
            obj.OuterGrid.RowHeight     = {26, '1x'};
            obj.OuterGrid.ColumnWidth   = {'1x'};
            obj.OuterGrid.RowSpacing    = 0;
            obj.OuterGrid.Padding       = [0 0 0 0];
            obj.OuterGrid.BackgroundColor = [0.94 0.94 0.94];

            obj.buildQuickAccess();
            obj.TabGroup = uitabgroup(obj.OuterGrid);
            obj.TabGroup.Layout.Row = 2;
            obj.TabGroup.Layout.Column = 1;
        end

        function addTab(obj, tab)
            obj.Tabs{end+1} = tab;
            try, tab.build(obj.TabGroup, obj.adapter()); catch, end
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
            obj.QuickAccessPanel = uipanel(obj.OuterGrid, ...
                'BorderType', 'none', ...
                'BackgroundColor', [0.92 0.92 0.92]);
            obj.QuickAccessPanel.Layout.Row = 1;
            obj.QuickAccessPanel.Layout.Column = 1;

            g = uigridlayout(obj.QuickAccessPanel, [1 5]);
            g.RowHeight     = {'1x'};
            g.ColumnWidth   = {'1x', 140, 80, 30, 30};
            g.ColumnSpacing = 4;
            g.Padding       = [6 2 6 2];
            g.BackgroundColor = [0.92 0.92 0.92];

            obj.QuickAccess.Title = uilabel(g, ...
                'Text', sprintf('Project: %s', char(obj.App.ProjectName)), ...
                'FontWeight', 'bold');
            obj.QuickAccess.ModeDropdown = uidropdown(g, ...
                'Items', {'Classic','Studio','Review','Analysis','Plot','Report','Compact','DockedFigure'}, ...
                'Value', 'Studio', ...
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
        end

        function showSettingsMenu(obj, src)
            obj.showMenuAt(src, ...
                {{'Auto Update Mode',  'Pref:AutoUpdate'}, ...
                 {'Toolbar Customize', 'Pref:ToolbarCustomize'}, ...
                 {'Shortcut Settings', 'Pref:Shortcuts'}, ...
                 {'Project Properties','Project:Properties'}, ...
                 {'Edit Project Details', 'Project:EditDetails'}, ...
                 {'Cleanup Project Cache','Project:CleanupCache'}, ...
                 {'Repair Missing Files', 'Project:RepairLinks'}});
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
