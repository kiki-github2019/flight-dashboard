classdef ChannelLayout
    % flightdash.view.ChannelLayout
    % - 한 채널(fIdx)의 메인 패널 + 컨트롤 헤더 + 6컬럼 dataGrid 골격
    % - 6개 컬럼은 각 view 클래스로 위임
    
    methods (Static)
        function ui = build(bodyGrid, fIdx, titleStr, panelColor)
            % [REFACTOR] app 의존 완전 제거 - 모든 하위 view가 EventBus + AppConstants만 사용
            import flightdash.util.EventBus
            import flightdash.util.AppEventData
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
            glCtrl = uigridlayout(controlPanel, [1 8]);
            glCtrl.ColumnWidth = { ...
                UIScale.px(100), UIScale.px(150), UIScale.px(110), UIScale.px(120), ...
                '1x', UIScale.px(80), UIScale.px(85), UIScale.px(80)};
            glCtrl.RowHeight = {'1x'};
            glCtrl.Padding = [2 2 2 2];
            
            uilabel(glCtrl, 'Text', '입력 시간(s):', 'FontWeight', 'bold', 'FontSize', 12);
            ui.spinner = uispinner(glCtrl, 'Enable', 'off', 'FontSize', 13, ...
                'ValueDisplayFormat', '%.3f', ...
                'ValueChangedFcn', @(~, event) EventBus.publish('SpinnerChanged', AppEventData(fIdx, event.Value)));
            uilabel(glCtrl, 'Text', '실시간 현재값:', 'FontWeight', 'bold', 'FontSize', 12);
            ui.currentTimeLabel = uilabel(glCtrl, 'Text', '0.000 s', ...
                'FontWeight', 'bold', 'FontSize', 13, 'FontColor', [0.8 0.1 0.1]);
            ui.fileNameLabel = uilabel(glCtrl, 'Text', '파일 없음', ...
                'FontColor', [0.2 0.2 0.2], 'FontSize', 11, 'FontWeight', 'bold');
            
            ui.btnAtt = uibutton(glCtrl, 'Text', '자세 ▾', ...
                'ButtonPushedFcn', @(~,~) EventBus.publish('PanelToggled', AppEventData(fIdx, 'attitude')));
            ui.btnAtt.Layout.Column = 6;
            ui.btnMap = uibutton(glCtrl, 'Text', '지도/고도 ▾', ...
                'ButtonPushedFcn', @(~,~) EventBus.publish('PanelToggled', AppEventData(fIdx, 'map')));
            ui.btnMap.Layout.Column = 7;
            ui.btnVid = uibutton(glCtrl, 'Text', '비디오 ▾', ...
                'ButtonPushedFcn', @(~,~) EventBus.publish('PanelToggled', AppEventData(fIdx, 'video')));
            ui.btnVid.Layout.Column = 8;
            ui.PanelVisible = struct('attitude', true, 'map', true, 'video', true);
            
            % 6컬럼 dataGrid - DPI 스케일 반영 (96 DPI 기준 디자인 → 실효 픽셀)
            ui.dataGrid = uigridlayout(fGrid, [1 6]);
            ui.dataGrid.ColumnWidth = { ...
                UIScale.px(200), UIScale.px(500), UIScale.px(250), ...
                '1x', UIScale.px(8), UIScale.px(500)};
            ui.dataGrid.RowHeight = {'1x'};
            ui.dataGrid.Padding = [0 0 0 0];
            ui.dataGrid.ColumnSpacing = 3;
            
            % 6개 컬럼 위임
            attUi   = flightdash.view.AttitudePanel.build(ui.dataGrid);
            mapUi   = flightdash.view.MapAltPanel.build(ui.dataGrid, panelColor);
            infoUi  = flightdash.view.InfoPanel.build(ui.dataGrid, fIdx);
            plotUi  = flightdash.view.PlotPanel.build(ui.dataGrid, fIdx);
            splitUi = flightdash.view.HISplitter.build(ui.dataGrid, fIdx);
            videoUi = flightdash.view.VideoPanel.build(ui.dataGrid, fIdx);
            
            % 평면 alias (기존 app.UI(fIdx).xxx 100% 호환)
            ui = flightdash.view.ChannelLayout.mergeStructs(ui, attUi, mapUi, infoUi, plotUi, splitUi, videoUi);
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
    end
end
