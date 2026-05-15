classdef VideoPanel
    % flightdash.view.VideoPanel
    % - Col 9: I:AVI Video Player (5행 레이아웃)
    %   Row 1: AVI 파일 열기 + 동기 상태 라벨
    %   Row 2: Frame No / Time(s) + 동기 버튼
    %   Row 3: 영상 표시 영역
    %   Row 4: ▶ Frame Navigator (라벨 + 슬라이더 + 4 네비 버튼)
    %   Row 5: Video FPS / Data Hz / Cache 드롭다운
    
    methods (Static)
        function ui = build(dataGrid, fIdx)
            % [REFACTOR] app 의존 제거 - 모든 콜백 EventBus.publish
            ui = struct();
            ui.panelVideo = uipanel(dataGrid, 'Title', 'I: AVI Video Player', ...
                'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', 'w');
            ui.panelVideo.Layout.Column = 9;
            
            UIScale = flightdash.util.UIScale;   % High-DPI 행 높이 보정
            rootGrid = uigridlayout(ui.panelVideo, [1 1]);
            rootGrid.Padding = [0 0 0 0];
            rootGrid.RowSpacing = 0;
            rootGrid.ColumnSpacing = 0;

            ui.videoContent = uipanel(rootGrid, 'BorderType', 'none', 'BackgroundColor', 'w');
            ui.videoContent.Layout.Row = 1;
            ui.videoContent.Layout.Column = 1;

            iGrid2 = uigridlayout(ui.videoContent, [5 1]);
            iGrid2.RowHeight = {UIScale.px(32), UIScale.px(32), '1x', UIScale.px(140), UIScale.px(35)};
            iGrid2.Padding = [2 2 2 2];
            iGrid2.RowSpacing = 5;
            
            % Row 1
            vBtnPnl = uipanel(iGrid2, 'BorderType', 'none', 'BackgroundColor', 'w');
            vBtnPnl.Layout.Row = 1;
            glVB = uigridlayout(vBtnPnl, [1 2], 'ColumnWidth', {110, '1x'}, 'Padding', [3 3 3 3]);
            uibutton(glVB, 'Text', 'AVI 파일 열기', 'FontSize', 11, ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('AviFileRequested', flightdash.util.AppEventData(fIdx)));
            ui.vidSyncStatus = uilabel(glVB, 'Text', '동기 미설정', 'FontSize', 11, ...
                'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'right');
            
            % Row 2
            syncPnl = uipanel(iGrid2, 'BorderType', 'none', 'BackgroundColor', 'w');
            syncPnl.Layout.Row = 2;
            glSync = uigridlayout(syncPnl, [1 6], ...
                'ColumnWidth', {55, 75, 55, 90, '1x', 75}, ...
                'Padding', [3 3 3 3], 'ColumnSpacing', 3);
            uilabel(glSync, 'Text', 'Frame:', 'FontSize', 11, 'FontWeight', 'bold');
            ui.vidSyncFrameInput = uispinner(glSync, 'Value', 1, 'Step', 1, ...
                'Limits', [1 1e9], 'ValueDisplayFormat', '%d', 'FontSize', 11);
            uilabel(glSync, 'Text', 'Time(s):', 'FontSize', 11, 'FontWeight', 'bold');
            ui.vidSyncTimeInput = uispinner(glSync, 'Value', 0, 'Step', 0.1, ...
                'ValueDisplayFormat', '%.3f', 'FontSize', 11);
            uilabel(glSync, 'Text', '');
            ui.vidSyncBtn = uibutton(glSync, 'Text', '동기', ...
                'BackgroundColor', [0.58 0.0 0.83], 'FontColor', 'w', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('VideoSyncRequested', flightdash.util.AppEventData(fIdx)));
            
            % Row 3: 영상 표시
            vidContainer = uipanel(iGrid2, 'BorderType', 'none', 'BackgroundColor', [0.94 0.94 0.94]);
            vidContainer.Layout.Row = 3;
            vGrid = uigridlayout(vidContainer, [1 1], 'Padding', [0 0 0 0]);
            ui.vidAxes = uiaxes(vGrid);
            axis(ui.vidAxes, 'image');
            axis(ui.vidAxes, 'off');
            disableDefaultInteractivity(ui.vidAxes);
            ui.vidAxes.Toolbar.Visible = 'off';
            ui.vidImageHandle = image(ui.vidAxes, zeros(100,100,3,'uint8'));
            
            % Row 4: Frame Navigator
            vdubGroupPnl = uipanel(iGrid2, 'Title', '▶ Frame Navigator', ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.97 0.97 0.99], ...
                'BorderType', 'line', 'ForegroundColor', [0.1 0.2 0.5]);
            vdubGroupPnl.Layout.Row = 4;
            
            vdubGrid = uigridlayout(vdubGroupPnl, [3 1]);
            vdubGrid.RowHeight = {UIScale.px(20), UIScale.px(45), UIScale.px(30)};
            vdubGrid.Padding = [5 2 5 2];
            vdubGrid.RowSpacing = 2;
            
            ui.vidVdubLabel = uilabel(vdubGrid, ...
                'Text', 'Frame 1 / 1  (00:00:00.000)', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontName', 'Consolas', 'FontColor', [0.1 0.2 0.5], ...
                'HorizontalAlignment', 'center');
            
            % [PERF] Throttle 선체크 - 어차피 버려질 드래그 이벤트는 publish 자체를 생략
            %        (AppEventData 생성/EventBus notify 오버헤드 제거)
            ui.vidVdubSlider = uislider(vdubGrid, ...
                'Limits', [1 100], 'Value', 1, ...
                'MajorTicks', [1 25 50 75 100], ...
                'MajorTickLabels', {'1', '25', '50', '75', '100'}, ...
                'MinorTicks', [], ...
                'ValueChangingFcn', @(~,evt) flightdash.view.VideoPanel.publishSliderChanging(fIdx, evt.Value), ...
                'ValueChangedFcn',  @(src,~) flightdash.util.EventBus.publish('SliderChanged', flightdash.util.AppEventData(fIdx, src)));
            
            navPnl = uipanel(vdubGrid, 'BorderType', 'none', 'BackgroundColor', [0.97 0.97 0.99]);
            glNav = uigridlayout(navPnl, [1 4], ...
                'ColumnWidth', {'1x', '1x', '1x', '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 10);
            uibutton(glNav, 'Text', '◄◄', 'FontSize', 11, 'FontWeight', 'bold', ...
                'Tooltip', '10 프레임 뒤로 (-10)', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('NavActionRequested', flightdash.util.AppEventData(fIdx, 'jumpBack')));
            uibutton(glNav, 'Text', '◄', 'FontSize', 11, 'FontWeight', 'bold', ...
                'Tooltip', '이전 frame (-1)', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('NavActionRequested', flightdash.util.AppEventData(fIdx, 'prev')));
            uibutton(glNav, 'Text', '►', 'FontSize', 11, 'FontWeight', 'bold', ...
                'Tooltip', '다음 frame (+1)', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('NavActionRequested', flightdash.util.AppEventData(fIdx, 'next')));
            uibutton(glNav, 'Text', '►►', 'FontSize', 11, 'FontWeight', 'bold', ...
                'Tooltip', '10 프레임 앞으로 (+10)', ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('NavActionRequested', flightdash.util.AppEventData(fIdx, 'jumpForward')));
            
            ui.vidFrameAxes   = gobjects(0);
            ui.vidFrameXLine  = gobjects(0);
            ui.vidFrameMarker = gobjects(0);
            
            % Row 5: Hz + Cache
            hzPnl = uipanel(iGrid2, 'BorderType', 'none', 'BackgroundColor', 'w');
            hzPnl.Layout.Row = 5;
            glHz = uigridlayout(hzPnl, [1 12], ...
                'ColumnWidth', {65, 22, 45, 22, 8, 55, 22, 45, 22, 12, 50, 75}, ...
                'Padding', [2 2 2 2], 'ColumnSpacing', 2);
            
            uilabel(glHz, 'Text', 'Video FPS:', 'FontSize', 10, 'FontWeight', 'bold');
            uibutton(glHz, 'Text', '◄', 'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('HzAdjustRequested', flightdash.util.AppEventData(fIdx, struct('target','video','delta',-1))));
            ui.vidVideoFpsInput = uispinner(glHz, 'Value', 15, 'Step', 1, ...
                'Limits', [1 1000], 'ValueDisplayFormat', '%d', 'FontSize', 10, ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('HzInputChanged', flightdash.util.AppEventData(fIdx, struct('target','video','value',src.Value))));
            uibutton(glHz, 'Text', '►', 'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('HzAdjustRequested', flightdash.util.AppEventData(fIdx, struct('target','video','delta',1))));
            uilabel(glHz, 'Text', '');
            
            uilabel(glHz, 'Text', 'Data Hz:', 'FontSize', 10, 'FontWeight', 'bold');
            uibutton(glHz, 'Text', '◄', 'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('HzAdjustRequested', flightdash.util.AppEventData(fIdx, struct('target','data','delta',-1))));
            ui.vidDataFpsInput = uispinner(glHz, 'Value', 50, 'Step', 1, ...
                'Limits', [1 1000], 'ValueDisplayFormat', '%d', 'FontSize', 10, ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('HzInputChanged', flightdash.util.AppEventData(fIdx, struct('target','data','value',src.Value))));
            uibutton(glHz, 'Text', '►', 'FontSize', 10, ...
                'ButtonPushedFcn', @(~,~) flightdash.util.EventBus.publish('HzAdjustRequested', flightdash.util.AppEventData(fIdx, struct('target','data','delta',1))));
            uilabel(glHz, 'Text', '');
            
            uilabel(glHz, 'Text', 'Cache:', 'FontSize', 10, 'FontWeight', 'bold');
            ui.vidCacheBudget = uidropdown(glHz, ...
                'Items', {'30 MB', '50 MB', '100 MB'}, ...
                'ItemsData', [30, 50, 100], ...
                'Value', 30, 'FontSize', 10, ...
                'ValueChangedFcn', @(src,~) flightdash.util.EventBus.publish('CacheBudgetChanged', flightdash.util.AppEventData(0, src.Value)));

            ui.videoRail = uibutton(rootGrid, ...
                'Text', sprintf('VID\nNo AVI'), ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.97 1.00], ...
                'FontColor', [0.20 0.12 0.35], ...
                'Tooltip', 'Video frame summary', ...
                'Visible', 'off');
            ui.videoRail.Layout.Row = 1;
            ui.videoRail.Layout.Column = 1;
        end

        function publishSliderChanging(fIdx, val, sessionId)
            % [PERF] Throttle pre-check helper - only publish if it passes.
            % Commit 5: when sessionId is not threaded in, read the active
            % session from SessionScope. This fixes multi-session throttle
            % collisions where every dashboard shared the 'standalone' slot.
            % Also stamps the published AppEventData so per-session
            % controllers can gate on it (matches Phase 4 contract).
            if nargin < 3 || isempty(sessionId)
                try
                    sessionId = char(flightdash.util.SessionScope.getActive());
                catch
                    sessionId = '';
                end
                if isempty(sessionId), sessionId = 'standalone'; end
            end
            scopedSlot = [sessionId ':LastSliderPublish'];
            if flightdash.util.Throttle.instance().hit(scopedSlot, fIdx, flightdash.util.AppConstants.SLIDER_THROTTLE_S)
                return;
            end
            flightdash.util.EventBus.publish('SliderChanging', ...
                flightdash.util.AppEventData(fIdx, val, sessionId));
        end
    end
end
