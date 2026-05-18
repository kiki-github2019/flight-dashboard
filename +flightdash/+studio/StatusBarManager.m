classdef StatusBarManager < handle
    % flightdash.studio.StatusBarManager
    % Bottom status bar — OriginPro-style real-time summary.
    %
    % Phase 1: structure with placeholder values. Phase 6 wires real
    % project/session/sync/decode-queue data via EventBus listeners.
    %
    % Cells (left to right):
    %   project | session | channel | time | frame | video sync |
    %   flight sync | auto update | ROI summary | decode queue | errors

    properties (Access = public)
        App
        RootGrid
        ProjectLabel        % uilabel
        SessionLabel        % uilabel
        ChannelLabel        % uilabel
        TimeLabel           % uilabel
        FrameLabel          % uilabel
        VideoSyncLabel      % uilabel
        FlightSyncLabel     % uilabel
        AutoUpdateLabel     % uilabel
        RoiSummaryLabel     % uilabel
        DecodeQueueLabel    % uilabel
        ErrorCountLabel     % uilabel
        MessageLabel        % uilabel
    end

    methods
        function obj = StatusBarManager(app, parentPanel)
            obj.App = app;
            obj.build(parentPanel);
        end

        function delete(~)
        end

        function setMessage(obj, text)
            try
                if ~isempty(obj.MessageLabel) && isvalid(obj.MessageLabel)
                    obj.MessageLabel.Text = char(text);
                end
            catch
            end
        end

        function setActiveSession(obj, sessionId)
            try
                if ~isempty(obj.SessionLabel) && isvalid(obj.SessionLabel)
                    obj.SessionLabel.Text = sprintf('Session: %s', sessionId);
                end
            catch
            end
        end

        function setProjectName(obj, name)
            try
                if ~isempty(obj.ProjectLabel) && isvalid(obj.ProjectLabel)
                    obj.ProjectLabel.Text = sprintf('Project: %s', name);
                end
            catch
            end
        end

        function applyTheme(obj, tokens)
            if nargin < 2 || ~isstruct(tokens)
                tokens = flightdash.ui.StudioTheme.light();
            end
            try
                if ~isempty(obj.RootGrid) && isvalid(obj.RootGrid)
                    obj.RootGrid.BackgroundColor = tokens.HeaderBg;
                end
                labels = {obj.ProjectLabel, obj.SessionLabel, obj.ChannelLabel, ...
                    obj.TimeLabel, obj.FrameLabel, obj.VideoSyncLabel, obj.FlightSyncLabel, ...
                    obj.AutoUpdateLabel, obj.MessageLabel, obj.DecodeQueueLabel, obj.ErrorCountLabel};
                for k = 1:numel(labels)
                    h = labels{k};
                    if ~isempty(h) && isvalid(h)
                        h.FontColor = tokens.TextSecondary;
                    end
                end
                if ~isempty(obj.MessageLabel) && isvalid(obj.MessageLabel)
                    obj.MessageLabel.FontColor = tokens.TextPrimary;
                end
            catch
            end
        end
    end

    methods (Access = private)
        function build(obj, parentPanel)
            UIScale = flightdash.util.UIScale;

            grid = uigridlayout(parentPanel, [1 12], ...
                'RowHeight', {'1x'}, ...
                'ColumnSpacing', 6, 'Padding', [8 2 8 2], ...
                'BackgroundColor', [0.92 0.92 0.94]);
            obj.RootGrid = grid;
            grid.ColumnWidth = { ...
                UIScale.px(160), ...   % project
                UIScale.px(130), ...   % session
                UIScale.px(82), ...    % channel
                UIScale.px(108), ...   % time
                UIScale.px(96), ...    % frame
                UIScale.px(92), ...    % video sync
                UIScale.px(92), ...    % flight sync
                UIScale.px(76), ...    % auto update
                '1x', ...              % ROI summary / message (stretches)
                UIScale.px(104), ...   % decode queue
                UIScale.px(60),  ...   % errors
                UIScale.px(0)};        % spare

            obj.ProjectLabel     = obj.makeLabel(grid, sprintf('Project: %s', obj.App.ProjectName));
            obj.SessionLabel     = obj.makeLabel(grid, 'Session: standalone');
            obj.ChannelLabel     = obj.makeLabel(grid, 'Ch: -');
            obj.TimeLabel        = obj.makeLabel(grid, 'Time: -');
            obj.FrameLabel       = obj.makeLabel(grid, 'Frame: -');
            obj.VideoSyncLabel   = obj.makeLabel(grid, 'VidSync: -');
            obj.FlightSyncLabel  = obj.makeLabel(grid, 'FltSync: -');
            obj.AutoUpdateLabel  = obj.makeLabel(grid, 'AU: Manual');
            obj.MessageLabel     = obj.makeLabel(grid, 'Ready');
            obj.DecodeQueueLabel = obj.makeLabel(grid, 'Decode: idle');
            obj.ErrorCountLabel  = obj.makeLabel(grid, 'Err: 0');
            uilabel(grid, 'Text', '');  % spare

            % ROI summary label is the message slot in Phase 1; Phase 6
            % adds a separate slot if range stats need permanent display.
            obj.RoiSummaryLabel = obj.MessageLabel;
        end

        function lbl = makeLabel(~, parent, text)
            lbl = uilabel(parent, ...
                'Text', text, ...
                'FontSize', 10, ...
                'FontColor', [0.2 0.2 0.2]);
        end
    end
end
