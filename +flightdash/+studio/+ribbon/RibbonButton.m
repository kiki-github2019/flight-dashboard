classdef RibbonButton < handle
    %RIBBONBUTTON  Icon+label ribbon button with optional dropdown chevron.
    %
    %   Configuration object. build(parent, adapter) materializes the
    %   actual uibutton(s) into the given parent grid cell. A button
    %   with HasDropdown=true renders as two adjacent buttons: a wide
    %   main button + a narrow ▼ chevron, sharing the icon background
    %   color so they read as a unit.
    %
    %   Click routing: main button calls adapter.dispatchCommand(cmdId).
    %   Chevron click invokes the DropdownItems list (cmdId pairs) via
    %   a uicontextmenu attached to the chevron.

    properties (Access = public)
        Label             char    = ''
        CmdId             char    = ''
        Tooltip           char    = ''
        HasDropdown       logical = false
        DropdownItems     cell    = {}   % {{label, cmdId}, ...}
        IconSize          double  = 24
        Enabled           logical = true
        DropdownEnabled
    end

    properties (Access = public, Transient)
        MainHandle             % uibutton
        ChevronHandle          % uibutton (only when HasDropdown)
        ContextMenu            % uicontextmenu (only when HasDropdown)
        AdapterRef             % flightdash.runtime.DashboardAppAdapter
    end

    methods
        function obj = RibbonButton(label, cmdId, varargin)
            obj.Label = char(label);
            obj.CmdId = char(cmdId);
            p = inputParser;
            p.addParameter('Tooltip', '', @(x) ischar(x) || isstring(x));
            p.addParameter('HasDropdown', false, @(x) islogical(x) || isnumeric(x));
            p.addParameter('DropdownItems', {}, @iscell);
            p.addParameter('IconSize', 24, @isnumeric);
            p.parse(varargin{:});
            obj.Tooltip       = char(p.Results.Tooltip);
            obj.HasDropdown   = logical(p.Results.HasDropdown);
            obj.DropdownItems = p.Results.DropdownItems;
            obj.IconSize      = double(p.Results.IconSize);
            obj.DropdownEnabled = containers.Map('KeyType', 'char', 'ValueType', 'logical');
        end

        function build(obj, parent, adapter)
            obj.AdapterRef = adapter;
            if obj.HasDropdown
                obj.buildSplit(parent);
            else
                obj.buildSingle(parent);
            end
        end

        function setEnabled(obj, tf)
            obj.Enabled = logical(tf);
            try
                theme = obj.currentTheme();
                if ~isempty(obj.MainHandle) && isvalid(obj.MainHandle)
                    obj.MainHandle.Enable = ternaryEnable(tf);
                    obj.MainHandle.Tooltip = obj.tooltipForState(tf);
                    flightdash.ui.StudioTheme.styleButton(obj.MainHandle, theme, 'secondary');
                end
                if ~isempty(obj.ChevronHandle) && isvalid(obj.ChevronHandle)
                    obj.ChevronHandle.Enable = ternaryEnable(tf);
                    obj.ChevronHandle.Tooltip = obj.tooltipForChevron(tf);
                    flightdash.ui.StudioTheme.styleButton(obj.ChevronHandle, theme, 'ghost');
                end
            catch
            end
        end

        function setDropdownEnabledByCmd(obj, cmdId, tf)
            try
                obj.ensureDropdownEnabledMap();
                obj.DropdownEnabled(char(cmdId)) = logical(tf);
            catch
            end
        end

        function delete(obj)
            try, if ~isempty(obj.MainHandle) && isvalid(obj.MainHandle), delete(obj.MainHandle); end, catch, end
            try, if ~isempty(obj.ChevronHandle) && isvalid(obj.ChevronHandle), delete(obj.ChevronHandle); end, catch, end
            try, if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu), delete(obj.ContextMenu); end, catch, end
        end
    end

    methods (Access = private)
        function buildSingle(obj, parent)
            iconRgb = obj.iconFor(obj.CmdId);
            theme = obj.currentTheme();
            btn = uibutton(parent, 'push', ...
                'Text', obj.Label, ...
                'Icon', iconRgb, ...
                'IconAlignment', 'top', ...
                'WordWrap', 'on', ...
                'Tooltip', obj.Tooltip, ...
                'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) obj.onMainClick());
            obj.MainHandle = btn;
            flightdash.ui.StudioTheme.styleButton(btn, theme, 'secondary');
        end

        function buildSplit(obj, parent)
            % Place main button + chevron in a 2-column sub-grid so they
            % visually merge inside one cell of the parent group grid.
            holder = uigridlayout(parent, [1 2]);
            holder.ColumnWidth   = {'1x', 14};
            holder.ColumnSpacing = 0;
            holder.RowSpacing    = 0;
            holder.Padding       = [0 0 0 0];

            iconRgb = obj.iconFor(obj.CmdId);
            theme = obj.currentTheme();
            obj.MainHandle = uibutton(holder, 'push', ...
                'Text', obj.Label, ...
                'Icon', iconRgb, ...
                'IconAlignment', 'top', ...
                'WordWrap', 'on', ...
                'Tooltip', obj.Tooltip, ...
                'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) obj.onMainClick());
            obj.ChevronHandle = uibutton(holder, 'push', ...
                'Text', char(9660), ...   % ▼
                'FontSize', 8, ...
                'Tooltip', sprintf('%s — more options', obj.Label), ...
                'ButtonPushedFcn', @(~,~) obj.onChevronClick());
            flightdash.ui.StudioTheme.styleButton(obj.MainHandle, theme, 'secondary');
            flightdash.ui.StudioTheme.styleButton(obj.ChevronHandle, theme, 'ghost');
        end

        function theme = currentTheme(obj)
            theme = flightdash.ui.StudioTheme.light();
            try
                if ~isempty(obj.AdapterRef) && isobject(obj.AdapterRef) && ...
                        isprop(obj.AdapterRef, 'App') && isprop(obj.AdapterRef.App, 'CurrentThemeStruct')
                    theme = obj.AdapterRef.App.CurrentThemeStruct;
                elseif isstruct(obj.AdapterRef) && isfield(obj.AdapterRef, 'App') && ...
                        isprop(obj.AdapterRef.App, 'CurrentThemeStruct')
                    theme = obj.AdapterRef.App.CurrentThemeStruct;
                end
            catch
            end
            if ~isstruct(theme) || ~isfield(theme, 'ButtonBg')
                theme = flightdash.ui.StudioTheme.light();
            end
        end

        function rgb = iconFor(obj, cmdId)
            try
                rgb = flightdash.ui.RibbonIconFactory.forCommand(cmdId, ...
                    'Size', obj.IconSize);
            catch
                rgb = uint8(zeros(obj.IconSize, obj.IconSize, 3) + 200);
            end
        end

        function onMainClick(obj)
            try
                if ~flightdash.studio.ribbon.RibbonButton.adapterUsable(obj.AdapterRef)
                    return;
                end
                obj.AdapterRef.dispatchCommand(obj.CmdId, 'Ribbon');
            catch ME
                try, obj.AdapterRef.logCaught(ME, 'Ribbon:click'); catch, end
            end
        end

        function onChevronClick(obj)
            try
                if isempty(obj.DropdownItems), return; end
                if isempty(obj.ChevronHandle) || ~isvalid(obj.ChevronHandle), return; end
                fig = ancestor(obj.ChevronHandle, 'figure');
                if isempty(fig) || ~isvalid(fig), return; end
                obj.rebuildContextMenu(fig);
                if isempty(obj.ContextMenu) || ~isvalid(obj.ContextMenu), return; end
                % Position the menu at the chevron's bottom-left in pixels.
                pos = getpixelposition(obj.ChevronHandle, true);
                obj.ContextMenu.Position = [pos(1), pos(2)];
                obj.ContextMenu.Visible = 'on';
            catch ME
                try, obj.AdapterRef.logCaught(ME, 'Ribbon:chevron'); catch, end
            end
        end

        function rebuildContextMenu(obj, fig)
            try, if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu), delete(obj.ContextMenu); end, catch, end
            obj.ContextMenu = uicontextmenu(fig);
            for k = 1:numel(obj.DropdownItems)
                item = obj.DropdownItems{k};
                if ~iscell(item) || numel(item) < 2, continue; end
                lbl = char(item{1}); cid = char(item{2});
                m = uimenu(obj.ContextMenu, 'Text', lbl, ...
                    'MenuSelectedFcn', @(~,~) obj.dispatchDropdown(cid));
                try, m.Enable = ternaryEnable(obj.dropdownItemEnabled(cid)); catch, end
            end
        end

        function dispatchDropdown(obj, cmdId)
            try
                if ~obj.dropdownItemEnabled(cmdId)
                    return;
                end
                if flightdash.studio.ribbon.RibbonButton.adapterUsable(obj.AdapterRef)
                    obj.AdapterRef.dispatchCommand(char(cmdId), 'Ribbon:Dropdown');
                end
            catch ME
                try, obj.AdapterRef.logCaught(ME, 'Ribbon:dropdownClick'); catch, end
            end
        end

        function tf = dropdownItemEnabled(obj, cmdId)
            tf = true;
            try
                obj.ensureDropdownEnabledMap();
                key = char(cmdId);
                if obj.DropdownEnabled.isKey(key)
                    tf = logical(obj.DropdownEnabled(key));
                end
            catch
                tf = true;
            end
        end

        function ensureDropdownEnabledMap(obj)
            if isempty(obj.DropdownEnabled) || ~isa(obj.DropdownEnabled, 'containers.Map')
                obj.DropdownEnabled = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            end
        end

        function tip = tooltipForState(obj, tf)
            tip = obj.Tooltip;
            if ~tf
                tip = obj.appendUnavailableTip(tip);
            end
        end

        function tip = tooltipForChevron(obj, tf)
            tip = sprintf('%s - more options', obj.Label);
            if ~tf
                tip = obj.appendUnavailableTip(tip);
            end
        end

        function tip = appendUnavailableTip(~, tip)
            if isempty(tip)
                tip = 'Unavailable until a review session is open.';
            else
                tip = sprintf('%s\nUnavailable until a review session is open.', tip);
            end
        end
    end

    methods (Static, Access = public)
        function tf = adapterUsable(ad)
            % Adapter may be either a flightdash.runtime.DashboardAppAdapter
            % handle OR a struct shim returned by RibbonBar.studioShim when
            % no dashboard is active. isvalid() throws/returns false for a
            % struct, so the previous `~isvalid(ad)` guard silently no-op'd
            % every ribbon click in the Welcome / standalone state. This
            % helper accepts both shapes.
            tf = false;
            if isempty(ad), return; end
            if isstruct(ad)
                tf = isfield(ad, 'dispatchCommand') && ...
                     isa(ad.dispatchCommand, 'function_handle');
                return;
            end
            try
                tf = isa(ad, 'handle') && isvalid(ad);
            catch
                tf = false;
            end
        end
    end
end

function s = ternaryEnable(tf)
    if tf, s = 'on'; else, s = 'off'; end
end
