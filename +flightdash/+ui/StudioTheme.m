classdef StudioTheme
    %STUDIOTHEME  Centralized color palette for Studio chrome panels.
    %
    %   Path 2 emulated MATLAB Desktop / OriginPro multi-pane look.
    %   Apply only to non-data UI (panel BG, header BG, status BG,
    %   muted text). Do NOT use for plot lines / data series colors —
    %   those have their own theme path.
    %
    %   Usage:
    %       c = flightdash.ui.StudioTheme.colors();
    %       panel.BackgroundColor = c.Panel;

    methods (Static)
        function c = colors()
            c.Background = [0.94 0.94 0.96];
            c.Panel      = [1.00 1.00 1.00];
            c.Header     = [0.90 0.91 0.93];
            c.Border     = [0.70 0.72 0.76];
            c.Text       = [0.10 0.10 0.10];
            c.MutedText  = [0.35 0.35 0.35];
            c.Active     = [0.80 0.88 1.00];
            c.Warning    = [1.00 0.94 0.75];
            c.Error      = [1.00 0.85 0.85];
            c.SplitBar   = [0.78 0.78 0.82];
        end
    end
end
