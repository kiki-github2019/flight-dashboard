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
            c.Background     = [0.94 0.94 0.96];
            c.Panel          = [1.00 1.00 1.00];
            c.Header         = [0.90 0.91 0.93];
            c.Border         = [0.70 0.72 0.76];
            c.Text           = [0.10 0.10 0.10];
            c.MutedText      = [0.35 0.35 0.35];
            c.Active         = [0.80 0.88 1.00];
            c.Warning        = [1.00 0.94 0.75];
            c.Error          = [1.00 0.85 0.85];
            c.SplitBar       = [0.78 0.78 0.82];
            % Plot / axes (used only by apply(); plot data colors are NOT styled).
            c.PlotBg         = [0.99 0.99 0.99];
            c.GridColor      = [0.75 0.75 0.78];
            c.AxisColor      = [0.20 0.20 0.22];
            % Optional accents (referenced by future gauge theming).
            c.PanelTitle     = [0.10 0.10 0.10];
            c.Accent         = [0.00 0.45 0.85];
            c.GaugeFace      = [0.97 0.97 0.98];
            c.GaugeNeedle    = [0.95 0.45 0.00];
            c.GaugeScale     = [0.30 0.30 0.35];
            c.Success        = [0.10 0.70 0.10];
        end

        function c = dark()
            c.Name           = 'Dark';
            c.Background     = [0.0588 0.0588 0.0706];
            c.Panel          = [0.1020 0.1020 0.1255];
            c.Header         = [0.1490 0.1490 0.1843];
            c.Border         = [0.30 0.30 0.34];
            c.Text           = [0.9412 0.9412 0.9412];
            c.MutedText      = [0.6275 0.6275 0.6471];
            c.Active         = [0.10 0.32 0.55];
            c.Warning        = [0.45 0.35 0.10];
            c.Error          = [0.55 0.20 0.20];
            c.SplitBar       = [0.30 0.30 0.34];
            c.PlotBg         = [0.12 0.12 0.15];
            c.GridColor      = [0.35 0.35 0.38];
            c.AxisColor      = [0.78 0.78 0.82];
            c.PanelTitle     = [0.00 0.83 1.00];
            c.Accent         = [0.00 0.75 1.00];
            c.GaugeFace      = [0.15 0.15 0.18];
            c.GaugeNeedle    = [1.00 0.58 0.00];
            c.GaugeScale     = [0.85 0.85 0.88];
            c.Success        = [0.20 0.85 0.20];
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
                        case 'matlab.ui.control.Button'
                            % Leave per-button BackgroundColor alone (callers
                            % paint domain colors like Flight 1 blue); only
                            % nudge FontColor when it would be unreadable.
                            if isprop(h, 'FontColor') && isequal(h.FontColor, [0 0 0]) ...
                                    && mean(theme.Background) < 0.5
                                h.FontColor = theme.Text;
                            end
                        case {'matlab.graphics.axis.Axes', 'matlab.ui.control.UIAxes'}
                            if isprop(h, 'Color'),          h.Color          = theme.PlotBg;    end
                            if isprop(h, 'XColor'),         h.XColor         = theme.AxisColor; end
                            if isprop(h, 'YColor'),         h.YColor         = theme.AxisColor; end
                            if isprop(h, 'GridColor'),      h.GridColor      = theme.GridColor; end
                            if isprop(h, 'MinorGridColor'), h.MinorGridColor = theme.GridColor; end
                    end
                catch
                end
            end
        end
    end
end
