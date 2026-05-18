classdef ChannelLayout
    % flightdash.view.ChannelLayout
    % - 한 채널(fIdx)의 메인 패널 + 컨트롤 헤더 + 9컬럼 dataGrid 골격
    % - 5개 콘텐츠 컬럼과 4개 splitter 컬럼은 각 view 클래스로 위임
    
    methods (Static)
        function ui = build(bodyGrid, fIdx, titleStr, panelColor)
            % [REFACTOR] app 의존 완전 제거 - 모든 하위 view가 EventBus + AppConstants만 사용
            ui = struct();
            
            % 메인 패널 + control header
            ui.panel = uipanel(bodyGrid, 'Title', titleStr, ...
                'FontWeight', 'bold', 'FontSize', 14, 'BackgroundColor', panelColor);
            UIScale = flightdash.util.UIScale;   % High-DPI 행 높이 보정
            fGrid = uigridlayout(ui.panel, [2 1]);
            fGrid.ColumnWidth = {'1x'};
            fGrid.RowHeight = {UIScale.px(45), '1x'};
            fGrid.Padding = [2 2 2 2];
            fGrid.RowSpacing = 2;
            
            controlPanel = uipanel(fGrid, 'BackgroundColor', 'w', 'BorderType', 'line');
            glCtrl = uigridlayout(controlPanel, [1 12]);
            glCtrl.ColumnWidth = { ...
                UIScale.px(100), UIScale.px(150), UIScale.px(110), UIScale.px(120), ...
                '1x', UIScale.px(42), UIScale.px(58), UIScale.px(58), UIScale.px(58), ...
                UIScale.px(80), UIScale.px(85), UIScale.px(80)};
            glCtrl.RowHeight = {'1x'};
            glCtrl.Padding = [2 2 2 2];
            
            uilabel(glCtrl, 'Text', '입력 시간(s):', 'FontWeight', 'bold', 'FontSize', 12);
            ui.spinner = uispinner(glCtrl, 'Enable', 'off', 'FontSize', 13, ...
                'ValueDisplayFormat', '%.3f', ...
                'ValueChangedFcn', @(~, event) flightdash.util.EventBus.publish('SpinnerChanged', flightdash.util.AppEventData(fIdx, event.Value)));
            uilabel(glCtrl, 'Text', '실시간 현재값:', 'FontWeight', 'bold', 'FontSize', 12);
            ui.currentTimeLabel = uilabel(glCtrl, 'Text', '0.000 s', ...
                'FontWeight', 'bold', 'FontSize', 13, 'FontColor', [0.8 0.1 0.1]);
            ui.fileNameLabel = uilabel(glCtrl, 'Text', '파일 없음', ...
                'FontColor', [0.2 0.2 0.2], 'FontSize', 11, 'FontWeight', 'bold');

            uilabel(glCtrl, 'Text', 'Step', 'HorizontalAlignment', 'right', ...
                'Tooltip', 'Flight-data playback interval in seconds');
            ui.flightPlayInterval = uieditfield(glCtrl, 'numeric', ...
                'Limits', [0 Inf], 'Value', 1, 'ValueDisplayFormat', '%.3g', ...
                'Tooltip', 'Playback interval in seconds. Values below the data period are clamped.', ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('FlightPlayIntervalChanged', ...
                    flightdash.util.AppEventData(fIdx, src.Value)));
            ui.flightPlayButton = uibutton(glCtrl, 'Text', 'Play', ...
                'Tooltip', 'Play flight data from current marker', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('FlightPlayRequested', flightdash.util.AppEventData(fIdx)));
            ui.flightStopButton = uibutton(glCtrl, 'Text', 'Stop', ...
                'Tooltip', 'Stop flight-data playback', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('FlightStopRequested', flightdash.util.AppEventData(fIdx)));
            
            ui.btnAtt = uibutton(glCtrl, 'Text', '자세 ▾', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PanelToggled', flightdash.util.AppEventData(fIdx, 'attitude')));
            ui.btnAtt.Layout.Column = 10;
            ui.btnMap = uibutton(glCtrl, 'Text', '지도/고도 ▾', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PanelToggled', flightdash.util.AppEventData(fIdx, 'map')));
            ui.btnMap.Layout.Column = 11;
            ui.btnVid = uibutton(glCtrl, 'Text', '비디오 ▾', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('PanelToggled', flightdash.util.AppEventData(fIdx, 'video')));
            ui.btnVid.Layout.Column = 12;
            % Per UX spec: initial review session opens with ONLY the
            % "Current Flight Data" (info) panel + plot-add column
            % active. Attitude / Map-Altitude / Video are hidden until
            % the user explicitly toggles them on. The toggle buttons
            % retain their default Korean labels until first click,
            % after which togglePanel() switches to the English ON/OFF
            % form (matches existing convention).
            ui.PanelVisible = struct('attitude', false, 'map', false, 'video', false);
            
            % 9컬럼 dataGrid - DPI 스케일 반영 (96 DPI 기준 디자인 → 실효 픽셀)
            ui.dataGrid = uigridlayout(fGrid, [1 9]);
            ui.dataGrid.ColumnWidth = flightdash.view.ChannelLayout.defaultDataGridColumnWidth();
            ui.dataGrid.RowHeight = {'1x'};
            ui.dataGrid.Padding = [0 0 0 0];
            ui.dataGrid.ColumnSpacing = 3;
            
            % 콘텐츠 및 splitter 컬럼 위임
            ui.attMapSplitter = flightdash.view.ChannelLayout.createPanelSplitter(ui.dataGrid, fIdx, 'att-map', 2, 'Attitude / Map');
            ui.mapInfoSplitter = flightdash.view.ChannelLayout.createPanelSplitter(ui.dataGrid, fIdx, 'map-info', 4, 'Map / Info');
            ui.infoPlotSplitter = flightdash.view.ChannelLayout.createPanelSplitter(ui.dataGrid, fIdx, 'info-plot', 6, 'Info / H plot');

            attUi   = flightdash.view.AttitudePanel.build(ui.dataGrid);
            mapUi   = flightdash.view.MapAltPanel.build(ui.dataGrid, panelColor);
            infoUi  = flightdash.view.InfoPanel.build(ui.dataGrid, fIdx);
            plotUi  = flightdash.view.PlotPanel.build(ui.dataGrid, fIdx);
            splitUi = flightdash.view.HISplitter.build(ui.dataGrid, fIdx);
            videoUi = flightdash.view.VideoPanel.build(ui.dataGrid, fIdx);
            
            % 평면 alias (기존 app.UI(fIdx).xxx 100% 호환)
            ui = flightdash.view.ChannelLayout.mergeStructs(ui, attUi, mapUi, infoUi, plotUi, splitUi, videoUi);

            % Apply the initial hidden state for attitude/map/video.
            try
                if isfield(ui, 'panelAttitude') && ~isempty(ui.panelAttitude) && isvalid(ui.panelAttitude)
                    ui.panelAttitude.Visible = 'off';
                end
            catch, end
            try
                if isfield(ui, 'panelMapAlt') && ~isempty(ui.panelMapAlt) && isvalid(ui.panelMapAlt)
                    ui.panelMapAlt.Visible = 'off';
                end
            catch, end
            try
                if isfield(ui, 'panelVideo') && ~isempty(ui.panelVideo) && isvalid(ui.panelVideo)
                    ui.panelVideo.Visible = 'off';
                end
            catch, end
        end
        
        function out = mergeStructs(varargin)
            out = struct();
            for k = 1:nargin
                s = varargin{k};
                f = fieldnames(s);
                for j = 1:numel(f)
                    out.(f{j}) = s.(f{j});
                end
            end
        end

        function h = createPanelSplitter(dataGrid, fIdx, kind, columnIdx, tooltipText)
            h = uipanel(dataGrid, ...
                'BackgroundColor', [0.78 0.78 0.82], ...
                'BorderType', 'line', 'BorderColor', [0.48 0.48 0.56], ...
                'Tooltip', ['Drag to resize ' tooltipText], ...
                'HitTest', 'on');
            h.Layout.Column = columnIdx;
            h.ButtonDownFcn = @(~,~) flightdash.util.EventBus.publish('PanelSplitterDragStarted', ...
                flightdash.util.AppEventData(fIdx, kind));
        end

        function widths = defaultDataGridColumnWidth(profile)
            if nargin < 1 || isempty(profile)
                profile = flightdash.util.AppConstants.LAYOUT_PROFILE_WIDE;
            end
            profile = flightdash.util.UIScale.normalizeProfile(profile);

            widths = { ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_ATT_WIDE, profile), ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_SPLITTER_W, profile), ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_MAP_WIDE, profile), ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_SPLITTER_W, profile), ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_INFO_WIDE, profile), ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_SPLITTER_W, profile), ...
                '1x', ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_SPLITTER_W, profile), ...
                flightdash.util.UIScale.pxForProfile(flightdash.util.AppConstants.LAYOUT_VIDEO_WIDE, profile)};
        end
    end
end
