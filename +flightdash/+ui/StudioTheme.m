classdef StudioTheme
    %STUDIOTHEME  Centralized color palette + theme apply helper.
    %
    %   Path 2 emulated MATLAB Desktop / OriginPro multi-pane look.
    %   GUI modernization review §15-18: now exposes Dark + Light
    %   palettes through static methods (avoids properties(Constant)
    %   struct-with-cells classdef edge cases) and an apply() helper
    %   that walks figure children to restyle non-data UI safely.
    %
    %   Usage:
    %       c = flightdash.ui.StudioTheme.colors();            % legacy alias for light()
    %       theme = flightdash.ui.StudioTheme.dark();
    %       flightdash.ui.StudioTheme.apply(app.UIFigure, theme);

    methods (Static)
        function c = colors()
            % Back-compat alias for callers that already use colors().
            c = flightdash.ui.StudioTheme.light();
        end

        function c = light()
            c.Name           = 'Light';
            c.AppBg          = [0.95 0.96 0.98];
            c.PanelBg        = [0.98 0.99 1.00];
            c.CardBg         = [1.00 1.00 1.00];
            c.InputBg        = [1.00 1.00 1.00];
            c.HeaderBg       = [0.93 0.94 0.96];
            c.RibbonBg       = [0.96 0.97 0.98];
            c.TabBg          = [0.90 0.91 0.93];
            c.TabActiveBg    = [1.00 1.00 1.00];
            c.TextPrimary    = [0.07 0.09 0.13];
            c.TextSecondary  = [0.25 0.29 0.35];
            c.TextMuted      = [0.45 0.49 0.56];
            c.TextDisabled   = [0.62 0.65 0.70];
            c.Border         = [0.72 0.75 0.80];
            c.BorderSoft     = [0.84 0.86 0.89];
            c.ButtonBg       = [0.98 0.99 1.00];
            c.ButtonText     = [0.08 0.10 0.14];
            c.ButtonBorder   = [0.68 0.71 0.76];
            c.ButtonDisabledBg   = [0.90 0.92 0.94];
            c.ButtonDisabledText = [0.55 0.58 0.63];
            c.Primary        = [0.12 0.37 0.85];
            c.PrimaryText    = [1.00 1.00 1.00];
            c.Accent         = [0.55 0.20 0.85];
            c.Success        = [0.00 0.55 0.40];
            c.Warning        = [0.85 0.48 0.08];
            c.Danger         = [0.75 0.12 0.12];
            c.AxesBg         = [1.00 1.00 1.00];
            c.AxesGrid       = [0.86 0.88 0.91];
            c.AxesText       = [0.10 0.12 0.16];
            c = flightdash.ui.StudioTheme.addLegacyAliases(c);
        end

        function c = dark()
            c.Name           = 'Dark';
            c.AppBg          = [0.06 0.07 0.09];
            c.PanelBg        = [0.08 0.09 0.11];
            c.CardBg         = [0.10 0.12 0.15];
            c.InputBg        = [0.07 0.08 0.10];
            c.HeaderBg       = [0.12 0.13 0.16];
            c.RibbonBg       = [0.11 0.12 0.15];
            c.TabBg          = [0.10 0.10 0.12];
            c.TabActiveBg    = [0.16 0.18 0.22];
            c.TextPrimary    = [0.94 0.95 0.97];
            c.TextSecondary  = [0.70 0.74 0.80];
            c.TextMuted      = [0.48 0.52 0.58];
            c.TextDisabled   = [0.36 0.38 0.42];
            c.Border         = [0.28 0.31 0.36];
            c.BorderSoft     = [0.20 0.22 0.26];
            c.ButtonBg       = [0.13 0.15 0.19];
            c.ButtonText     = [0.94 0.95 0.97];
            c.ButtonBorder   = [0.34 0.37 0.43];
            c.ButtonDisabledBg   = [0.12 0.13 0.15];
            c.ButtonDisabledText = [0.42 0.45 0.50];
            c.Primary        = [0.16 0.39 0.92];
            c.PrimaryText    = [1.00 1.00 1.00];
            c.Accent         = [0.60 0.22 0.92];
            c.Success        = [0.05 0.60 0.45];
            c.Warning        = [0.90 0.55 0.12];
            c.Danger         = [0.70 0.15 0.15];
            c.AxesBg         = [0.11 0.12 0.15];
            c.AxesGrid       = [0.22 0.24 0.28];
            c.AxesText       = [0.82 0.85 0.90];
            c = flightdash.ui.StudioTheme.addLegacyAliases(c);
        end

        function c = forName(themeName)
            if nargin < 1 || isempty(themeName)
                themeName = 'Light';
            end
            if strcmpi(char(themeName), 'dark')
                c = flightdash.ui.StudioTheme.dark();
            else
                c = flightdash.ui.StudioTheme.light();
            end
        end

        function apply(fig, theme)
            % Walk the figure's non-data chrome and apply theme colors.
            % Conservative: never touches existing Line/Patch/Image objects
            % so plot data and gauge needle colors stay as authored.
            if isempty(fig) || ~isvalid(fig), return; end
            if nargin < 2 || ~isstruct(theme)
                theme = flightdash.ui.StudioTheme.light();
            end
            try, fig.Color = theme.Background; catch, end

            try
                children = findall(fig);
            catch
                return;
            end
            for i = 1:numel(children)
                h = children(i);
                try
                    cls = class(h);
                    switch cls
                        case {'matlab.ui.container.Panel', ...
                              'matlab.ui.container.Tab', ...
                              'matlab.ui.container.TabGroup'}
                            if isprop(h, 'BackgroundColor'), h.BackgroundColor = theme.Panel; end
                            if isprop(h, 'ForegroundColor'), h.ForegroundColor = theme.Text;  end
                        case 'matlab.ui.container.GridLayout'
                            if isprop(h, 'BackgroundColor'), h.BackgroundColor = theme.Background; end
                        case {'matlab.ui.control.Label', ...
                              'matlab.ui.control.EditField', ...
                              'matlab.ui.control.NumericEditField', ...
                              'matlab.ui.control.DropDown', ...
                              'matlab.ui.control.CheckBox'}
                            if isprop(h, 'FontColor'), h.FontColor = theme.Text; end
                            if isprop(h, 'BackgroundColor') && ~strcmp(cls, 'matlab.ui.control.Label')
                                h.BackgroundColor = theme.InputBg;
                            end
                        case 'matlab.ui.control.Button'
                            role = flightdash.ui.StudioTheme.inferButtonRole(h);
                            flightdash.ui.StudioTheme.styleButton(h, theme, role);
                        case {'matlab.graphics.axis.Axes', 'matlab.ui.control.UIAxes'}
                            if isprop(h, 'Color'),          h.Color          = theme.AxesBg;    end
                            if isprop(h, 'XColor'),         h.XColor         = theme.AxesText; end
                            if isprop(h, 'YColor'),         h.YColor         = theme.AxesText; end
                            if isprop(h, 'GridColor'),      h.GridColor      = theme.AxesGrid; end
                            if isprop(h, 'MinorGridColor'), h.MinorGridColor = theme.AxesGrid; end
                            try, if isprop(h, 'GridAlpha'), h.GridAlpha = 0.28; end, catch, end
                            try, if isprop(h, 'MinorGridAlpha'), h.MinorGridAlpha = 0.18; end, catch, end
                    end
                catch
                end
            end
        end

        function styleButton(btn, tokens, role, state)
            if nargin < 3 || isempty(role), role = 'secondary'; end
            if nargin < 4 || isempty(state), state = ''; end
            try
                if isprop(btn, 'Enable') && strcmpi(char(btn.Enable), 'off')
                    role = 'disabled';
                elseif strcmpi(char(state), 'disabled')
                    role = 'disabled';
                end
                switch lower(char(role))
                    case 'primary'
                        bg = tokens.Primary; fg = tokens.PrimaryText;
                    case {'accent', 'flight2', 'sync'}
                        bg = tokens.Accent; fg = tokens.PrimaryText;
                    case {'success', 'coast', 'map'}
                        bg = tokens.Success; fg = tokens.PrimaryText;
                    case 'warning'
                        bg = tokens.Warning; fg = tokens.PrimaryText;
                    case {'danger', 'stop'}
                        bg = tokens.Danger; fg = tokens.PrimaryText;
                    case 'ghost'
                        bg = tokens.RibbonBg; fg = tokens.TextSecondary;
                    case 'disabled'
                        bg = tokens.ButtonDisabledBg; fg = tokens.ButtonDisabledText;
                    otherwise
                        bg = tokens.ButtonBg; fg = tokens.ButtonText;
                end
                if isprop(btn, 'BackgroundColor'), btn.BackgroundColor = bg; end
                if isprop(btn, 'FontColor'), btn.FontColor = fg; end
            catch
            end
        end

        function role = inferButtonRole(btn)
            role = 'secondary';
            try
                txt = lower(strtrim(char(btn.Text)));
                if any(strcmp(txt, {'flight 1', '비행 1'}))
                    role = 'primary';
                elseif any(strcmp(txt, {'flight 2', '비행 2'}))
                    role = 'accent';
                elseif contains(txt, 'coast') || contains(txt, '해안')
                    role = 'success';
                elseif contains(txt, 'sync') || contains(txt, '동기')
                    role = 'accent';
                elseif contains(txt, 'stop')
                    role = 'danger';
                elseif contains(txt, 'reset') || strcmp(txt, 'rst') || contains(txt, '초기화')
                    role = 'warning';
                end
            catch
                role = 'secondary';
            end
        end

        function c = addLegacyAliases(c)
            c.Background  = c.AppBg;
            c.Panel       = c.PanelBg;
            c.Header      = c.HeaderBg;
            c.Text        = c.TextPrimary;
            c.MutedText   = c.TextMuted;
            c.Active      = c.TabActiveBg;
            c.Error       = c.Danger;
            c.SplitBar    = c.Border;
            c.PlotBg      = c.AxesBg;
            c.GridColor   = c.AxesGrid;
            c.AxisColor   = c.AxesText;
            c.PanelTitle  = c.TextPrimary;
            c.GaugeFace   = c.CardBg;
            c.GaugeNeedle = c.Warning;
            c.GaugeScale  = c.TextSecondary;
        end
    end
end
