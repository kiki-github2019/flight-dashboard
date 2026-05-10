플롯(Plot) 및 탭(Tab) 관리 로직의 독립 (PlotController / PlotView)
현재 메인 파일에서 가장 많은 라인을 차지하고 복잡도를 높이는 주범은 다중 플롯 탭을 생성하고 제어하는 로직입니다.

문제점: addPlotTab, plotSelectedVariable, updatePlotTimeLines, applyPlotAxisSettings 등 플롯의 생성, 스케일 조정, 범례(Legend) 적용, 라벨링을 메인 클래스가 직접 제어하고 있습니다.

개선안:

+view/PlotPanel.m은 현재 빈 껍데기(Shell)만 만들고 있습니다. 플롯을 그리고(plot, xline), 축을 설정하는 물리적인 시각화 코드는 모두 PlotPanel.m 내부로 이동해야 합니다.

메인 클래스는 "시간이 변경되었음" 또는 "새로운 변수가 선택되었음"을 EventBus로 브로드캐스팅만 하고, PlotController가 이를 수신하여 PlotPanel을 업데이트하도록 책임을 완전히 분리해야 합니다.


ep 1: PlotController.m 신설 (이벤트 및 로직 제어)
현재 PlaybackController에 섞여 있거나 메인 앱에 하드코딩된 플롯 관련 콜백들을 전담할 PlotController를 만듭니다. 이 컨트롤러는 EventBus의 이벤트를 수신하여 데이터(Model)를 가져오고 뷰(View)에 그리기 명령을 내립니다.  

+flightdash/+controller/PlotController.m 파일을 새로 생성하고 아래 코드를 작성합니다.

Matlab
classdef PlotController < handle
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = PlotController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            % 기존 PlaybackController에서 플롯 관련 이벤트 구독을 이쪽으로 이동
            obj.Listeners{end+1} = EB('PlotSelected', @(~,d) obj.onPlotSelected(d));
            obj.Listeners{end+1} = EB('PlotTabAddRequested', @(~,d) obj.onAddTab(d));
            obj.Listeners{end+1} = EB('PlotTabClearRequested', @(~,d) obj.onClearTab(d));
            obj.Listeners{end+1} = EB('PlotAxisChanged', @(~,d) obj.onPlotAxisChanged(d));
            % ... (기타 Plot 관련 이벤트들)
        end
        
        % [리팩토링 핵심] 기존 앱의 plotSelectedVariable 역할을 컨트롤러가 통제
        function onPlotSelected(obj, d)
            fIdx = d.ChannelIdx;
            model = obj.App.Models(fIdx);
            selRow = model.selectedRow;
            if isempty(selRow) || selRow < 1, return; end
            
            % 1. Model에서 메타데이터 및 실제 시계열 데이터 추출
            meta = model.displayMeta(selRow);
            yCol = meta.header;
            timeCol = model.mappedCols.Time;
            tData = model.rawData.(timeCol);
            yData = model.rawData.(yCol);
            currTime = tData(model.currentIndex);
            currY = yData(model.currentIndex);
            
            % 2. View에 그리기 명령 전달 (핸들 및 속성 조작은 View 내부에서 처리)
            obj.App.PlotView(fIdx).addPlotToCurrentTab(tData, yData, currTime, currY, meta);
            
            % 3. 기타 부수 효과 처리 (Plot Manager 테이블 갱신 등)
            obj.App.PlotView(fIdx).refreshPlotManager();
        end
        
        function onAddTab(obj, d)
            obj.App.PlotView(d.ChannelIdx).addNewTab();
        end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
        end
    end
end
Step 2: PlotView.m 클래스화 (상태 은닉 및 렌더링 전담)
현재 app.UI(fIdx) 구조체 안에 난잡하게 저장되어 있는 plotAxes, timeLines, plotData 등의 셀 배열들을 캡슐화합니다. (기존 PlotPanel.m을 확장하거나 새로운 PlotView 클래스를 만듭니다.)

+flightdash/+view/PlotView.m (또는 기존 PlotPanel 확장)

Matlab
classdef PlotView < handle
    % 앱 메인에 있던 그래픽 핸들 상태를 이 클래스 내부로 숨깁니다.
    properties (Access = private)
        TabGroup
        PlotTabs      = []
        PlotLayouts   = {}
        PlotAxes      = cell(1, 10)
        TimeLines     = cell(1, 10)
        TimeMarkers   = cell(1, 10)
        ValueLabels   = cell(1, 10)
        FIdx
    end
    
    methods
        function obj = PlotView(fIdx, tabGroupHandle)
            obj.FIdx = fIdx;
            obj.TabGroup = tabGroupHandle;
        end
        
        % 메인 앱의 plotSelectedVariable 내 '물리적인 UI 렌더링' 부분 이관
        function addPlotToCurrentTab(obj, tData, yData, currTime, currY, meta)
            currTab = obj.TabGroup.SelectedTab;
            tabIdx = find(obj.PlotTabs == currTab, 1);
            targetLayout = obj.PlotLayouts{tabIdx};
            
            % Panel 및 Axes 생성
            p = uipanel(targetLayout, 'BorderType', 'line', 'BackgroundColor', 'w');
            axGrid = uigridlayout(p, 'ColumnWidth', {'1x'}, 'RowHeight', {'1x'});
            ax = uiaxes(axGrid);
            
            % 실제 플로팅
            mainLine = plot(ax, tData, yData, 'LineWidth', 1.5, 'Color', [0.15 0.38 0.82]);
            title(ax, meta.header, 'Interpreter', 'none', 'FontWeight', 'bold');
            
            % 타임라인 및 마커 생성
            hold(ax, 'on');
            tl = xline(ax, currTime, 'r', 'LineWidth', 3.0, 'Alpha', 0.5);
            mk = plot(ax, currTime, currY, 'p', 'MarkerSize', 14);
            valLbl = text(ax, currTime, currY, num2str(currY));
            
            % 객체 내부에 핸들 보관 (App은 더 이상 이 핸들을 알 필요가 없음)
            obj.PlotAxes{tabIdx}{end+1} = ax;
            obj.TimeLines{tabIdx}{end+1} = tl;
            obj.TimeMarkers{tabIdx}{end+1} = mk;
            obj.ValueLabels{tabIdx}{end+1} = valLbl;
        end
        
        % 메인 앱의 updatePlotTimeLines 역할을 View가 스스로 수행
        function updateTimeIndicators(obj, currIdx, currTime, yDataArr)
            currTab = obj.TabGroup.SelectedTab;
            tabIdx = find(obj.PlotTabs == currTab, 1);
            if isempty(tabIdx), return; end
            
            tls = obj.TimeLines{tabIdx};
            mks = obj.TimeMarkers{tabIdx};
            
            for i = 1:length(tls)
                if isvalid(tls{i}), set(tls{i}, 'Value', currTime); end
                if isvalid(mks{i})
                    yData = yDataArr{i}; % Controller에서 넘어오거나 Model 참조
                    set(mks{i}, 'XData', currTime, 'YData', yData(currIdx));
                end
            end
        end
    end
end
Step 3: 메인 파일(FlightDataDashboard.m) 다이어트 적용
이제 거대한 메인 파일에서 다음 작업들을 수행하여 코드를 대폭 줄입니다.

컨트롤러 등록: 생성자에 PlotController를 등록합니다.

Matlab
app.PlotCtrl = flightdash.controller.PlotController(app);
이벤트 리스너 삭제: PlaybackController에서 플롯 관련 EventBus.subscribe 라인들을 지웁니다.

거대 메서드 삭제 (완전 제거): FlightDataDashboard.m 안에 있는 다음 함수들을 과감히 삭제합니다.

plotSelectedVariable(app, fIdx) (약 80라인 이상)

addPlotTab(app, fIdx) (약 30라인)

updatePlotTimeLines(app, fIdx, currIdx, currTime) (약 50라인)

clearCurrentTab(app, fIdx), clearAllTabs(app, fIdx)

handlePlotXLimChange(app, fIdx, ax)

applyPlotAxisSettings, onPlotDetailChanged, onPlotAxisChanged 등

updateDashboard 메서드 수정: 시간 이동 시 호출되던 렌더링 로직을 다음과 같이 간소화합니다.

Matlab
   % 변경 전
   app.updatePlotTimeLines(fIdx, index, currTime);
   
   % 변경 후
   % 데이터를 묶어서 View 모듈에 업데이트만 지시
   app.PlotView(fIdx).updateTimeIndicators(index, currTime, app.UI(fIdx).plotData);

=============================================================================================================
chatGPT cowork
=============================================================================================================

검토 결과, 방향은 타당합니다. 특히 `PlaybackController`에 섞인 Plot/ROI/Tab 이벤트를 `PlotController`로 분리하고, `FlightDataDashboard.m`의 `plotSelectedVariable`, `updatePlotTimeLines`, `handlePlotXLimChange`, `applyPlotAxisSettings` 등을 밖으로 빼는 것은 우선순위가 높습니다.

단, 현재 파일 배치가 먼저 문제입니다. `D:\flightdashboard\5. 4th\root`에는 소스가 없고, 실제 소스는 `D:\flightdashboard\5. 4th\+flightdash\FlightDataDashboard.m`에 있습니다. 현재 파일 기준 라인 수는 5,719줄입니다. 작업 디렉토리를 `root`로 유지할지, 소스를 `root` 아래로 옮길지 먼저 정해야 합니다.

**검토 의견**
- `PlotController` 신설은 적절합니다. 현재 `PlaybackController.m`이 이미 `PlotSelected`, `PlotTabAddRequested`, `PlotAxisChanged`, ROI 이벤트까지 받아서 다시 App 메서드를 호출하고 있으므로, 이 부분을 `PlotController`로 떼는 것이 자연스럽습니다.
- `PlotView` 신설도 적절하지만, 제안처럼 App이 plot handle을 “전혀 모르게” 만드는 방식은 바로 적용하면 위험합니다. 현재 `ConfigManager`, `AuxWindowManager`, Details/ROI/Manager, 저장/복원 로직이 `app.UI(fIdx).plotAxes`, `plotData`, `plotMeta`, `roiRows` 등에 의존할 가능성이 큽니다.
- 따라서 1차 리팩토링은 “완전 은닉”보다 `PlotView`가 내부 상태를 관리하되, 기존 `app.UI(fIdx)` 필드는 호환 alias로 유지하는 방식이 안전합니다.
- `PlotPanel.m`은 빈 shell이 아닙니다. 현재 Manager, Details, ROI, Panner, TabGroup의 UI 골격을 상당히 만들고 있습니다. 그래서 `PlotPanel`은 “정적 UI 빌더”로 남기고, 새 `PlotView`는 런타임 plot 렌더링/핸들 관리 전담으로 분리하는 편이 좋습니다.
- 메인 파일의 플롯 메서드를 바로 삭제하는 것은 위험합니다. 먼저 wrapper로 남겨서 `app.PlotCtrl` 또는 `app.PlotView`에 위임하고, MATLAB Online 검증 후 삭제하는 strangler 방식이 맞습니다.

**권장 적용 순서**
1. `+flightdash/+controller/PlotController.m` 추가  
   `PlaybackController`에서 Plot/Tab/ROI/Manager/Details/Axis 이벤트 구독을 이동합니다.

2. `+flightdash/+view/PlotView.m` 추가  
   `plotSelectedVariable`, `updatePlotTimeLines`, `applyPlotAxisSettings`의 렌더링 부분부터 이동합니다.

3. `FlightDataDashboard.m`에는 wrapper만 남김  
   예: 기존 `plotSelectedVariable(app,fIdx)`는 삭제하지 말고 `app.PlotCtrl.plotSelected(fIdx)` 또는 `app.PlotView(fIdx)...`로 위임합니다.

4. 저장/복원, ROI, Details, AuxWindowManager 연동 확인  
   `plotData`, `plotMeta`, `roiRows`의 소유권을 갑자기 바꾸지 말고, 먼저 기존 구조와 동기화합니다.

5. 안정화 후 메인 메서드 제거  
   MATLAB Online에서 plot 추가, tab 추가/삭제, legend, ROI, config 복원이 정상일 때 메인 파일에서 실제 삭제합니다.

**추가 주의**
최근 MATLAB Online의 “입력 인수가 너무 많습니다” 오류는 리팩토링 중 함수/생성자 시그니처와 호출부가 어긋났을 때 흔히 발생합니다. PlotController/PlotView를 넣을 때도 생성자 인자 수와 `AppEventData` 인자 수를 반드시 현재 코드 기준으로 맞춰야 합니다. 현재 `AppEventData`는 기본적으로 `ChannelIdx, Payload` 구조입니다.

=============================================================================================================
Gemini
=============================================================================================================

부가 기능 컴포넌트(ROI, Panner, Flight Modes)의 모듈화
문제점: drawRoiBands, computeRoiAnalysis, updatePannerViewport, computeFlightModeBands 등 특정 기능에 국한된 도메인 로직이 메인 파일에 혼재되어 있습니다.

개선안:

ROI 모듈: +controller/RoiController.m을 신설하여 ROI 선택, 삭제, 통계 분석(computeRoiAnalysis) 로직을 위임합니다.

Panner 모듈: 줌/팬 미니맵 역할을 하는 Panner 관련 렌더링 로직(drawPannerModeBands, pannerHandleDragMotion)을 독립된 뷰 컴포넌트로 분리합니다.

부가 기능(ROI, Panner, Flight Modes)의 모듈화는 메인 앱(FlightDataDashboard.m)에서 무려 800라인 이상의 도메인 로직과 UI 제어 코드를 덜어낼 수 있는 매우 효과적인 작업입니다.  

이 세 가지 기능은 각각 독립적인 라이프사이클을 가지고 있으므로, 각각의 컨트롤러와 서비스 모델로 분리하는 것이 이상적입니다. 다음과 같이 3개의 독립된 모듈로 분할하는 방안과 예시 코드를 제안합니다.

1. ROI 관리 모듈 (RoiController.m)
ROI(Region of Interest)는 특정 시간 구간의 데이터를 분석(RMSE, Std, Mean)하고 화면에 노란색 밴드로 표시하는 기능입니다. 이 로직을 전담할 컨트롤러를 생성합니다.  

+flightdash/+controller/RoiController.m

Matlab
classdef RoiController < handle
    properties (Access = private)
        App
        Listeners cell = {}
    end
    
    methods
        function obj = RoiController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('RoiAddRequested', @(~,d) obj.addCurrentRoi(d.ChannelIdx));
            obj.Listeners{end+1} = EB('RoiSelectionChanged', @(~,d) obj.onSelectionChanged(d));
            obj.Listeners{end+1} = EB('RoiDeleteSelectedRequested', @(~,d) obj.deleteSelectedRoi(d.ChannelIdx));
            obj.Listeners{end+1} = EB('RoiClearRequested', @(~,d) obj.clearRois(d.ChannelIdx));
            obj.Listeners{end+1} = EB('AnalysisComputeRequested', @(~,d) obj.computeRoiAnalysis(d.ChannelIdx));
        end
        
        % 메인 파일의 computeRoiAnalysis 로직 이관
        function computeRoiAnalysis(obj, fIdx)
            if ~isfield(obj.App.UI(fIdx), 'roiRows') || isempty(obj.App.UI(fIdx).roiRows)
                obj.App.openStatsFigure(fIdx);
                return;
            end
            
            % Model에서 데이터 가져오기
            timeCol = obj.App.Models(fIdx).mappedCols.Time;
            times = obj.App.Models(fIdx).rawData.(timeCol);
            rows = obj.App.UI(fIdx).roiRows;
            
            % 분석 로직 수행 (Mean, RMSE, STD 계산 등)
            for r = 1:size(rows, 1)
                signalName = rows{r, 3};
                % ... (기존 메인 파일의 computeRoiAnalysis 내부 계산 로직 그대로 복사) ...
            end
            
            % 결과 업데이트
            obj.App.UI(fIdx).roiRows = rows;
            
            % View 업데이트 지시 (View 클래스가 있다면 View의 메서드 호출)
            if isprop(obj.App, 'PlotView')
                obj.App.PlotView(fIdx).refreshRoiTable(rows);
                obj.App.PlotView(fIdx).drawRoiBands(rows);
            end
            obj.App.openStatsFigure(fIdx);
        end
        
        % 기타 addCurrentRoi, deleteSelectedRoi 등의 로직도 동일하게 이관
        % ...
        
        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try, if isvalid(obj.Listeners{k}), delete(obj.Listeners{k}); end, catch, end
            end
        end
    end
end
2. Panner(미니맵/네비게이터) 모듈 (PannerController.m)
Panner는 전체 데이터 축을 보여주고, 사용자가 핸들을 드래그하여 X축(XLim)을 제어하는 핵심 UI입니다. 드래그 모션 제어 로직이 메인 파일에 있으면 마우스 이벤트 관리(WindowButtonMotionFcn 등)가 꼬일 위험이 큽니다.  

+flightdash/+controller/PannerController.m

Matlab
classdef PannerController < handle
    properties (Access = private)
        App
        Listeners cell = {}
        IsDragging = false
        DragFIdx = 0
        DragSide = ''
    end
    
    methods
        function obj = PannerController(app)
            obj.App = app;
            obj.subscribeEvents();
        end
        
        function subscribeEvents(obj)
            EB = @flightdash.util.EventBus.subscribe;
            obj.Listeners{end+1} = EB('PannerToggled', @(~,d) obj.togglePanner(d.ChannelIdx));
            obj.Listeners{end+1} = EB('PannerClicked', @(~,d) obj.onPannerClicked(d.ChannelIdx));
            obj.Listeners{end+1} = EB('PannerRangeChanged', @(~,d) obj.onPannerRangeChanged(d));
            obj.Listeners{end+1} = EB('PannerResetRequested', @(~,d) obj.resetPannerRange(d.ChannelIdx));
        end

        % Panner 토글 제어
        function togglePanner(obj, fIdx)
            ui = obj.App.UI(fIdx);
            nextState = ~ui.PannerVisible;
            ui.PannerVisible = nextState;
            ui.pannerPanel.Visible = flightdash.util.AppConstants.visibleState(nextState);
            
            rh = ui.plotShellGrid.RowHeight;
            if nextState
                rh{3} = flightdash.util.UIScale.px(58);
                obj.refreshPanner(fIdx); % Panner 렌더링 호출
            else
                rh{3} = 0;
            end
            ui.plotShellGrid.RowHeight = rh;
        end
        
        % 핸들 드래그 이벤트 (startPannerHandleDrag, pannerHandleDragMotion, stopPannerHandleDrag)
        % 기존 메인 파일에 있던 마우스 이벤트 캡처 로직을 이 컨트롤러로 옮깁니다.
        % ...
    end
end
3. Flight Mode 분석 서비스 (FlightModeAnalyzer.m)
비행 모드(Cruise, Turn, Loiter, Climb 등)를 분석하고 색상 밴드를 추출하는 로직은 UI 제어나 이벤트 응답이라기보다 순수한 데이터 분석(Domain Logic)에 가깝습니다. 따라서 Controller가 아닌 Model(또는 Utility/Service)로 분리하는 것이 맞습니다.  

+flightdash/+model/FlightModeAnalyzer.m

Matlab
classdef FlightModeAnalyzer
    % 비행 데이터를 기반으로 비행 모드 구간(Bands)을 분석하는 서비스
    
    methods (Static)
        function bands = computeBands(mappedCols, rawData)
            bands = struct('Start', {}, 'End', {}, 'Mode', {}, 'Color', {});
            if isempty(rawData), return; end
            
            timeCol = mappedCols.Time;
            times = rawData.(timeCol);
            if numel(times) < 2, return; end
            
            % 메인 앱에 있던 computeFlightModeBands와 flightModeLabelsFromData 로직 이동
            labels = flightdash.model.FlightModeAnalyzer.extractLabels(rawData);
            
            % 휴리스틱 분석 로직 (Roll, Speed, Alt 기반)
            if isempty(labels)
                % ... (고도/속도/기울기 기반 Cruise, Turn, Climb 추정 로직)
            end
            
            % 구간 묶기 로직
            startIdx = 1;
            for k = 2:numel(labels)
                if ~strcmp(labels{k}, labels{startIdx})
                    bands(end+1) = flightdash.model.FlightModeAnalyzer.modeBand(times(startIdx), times(k-1), labels{startIdx}); 
                    startIdx = k;
                end
            end
            bands(end+1) = flightdash.model.FlightModeAnalyzer.modeBand(times(startIdx), times(end), labels{startIdx});
        end
        
        function label = extractLabels(rawData)
            % 컬럼 이름에서 FlightMode를 찾는 로직
            % ...
        end
        
        function band = modeBand(t0, t1, modeName)
            % 모드별 색상 매핑 로직
            % ...
        end
    end
end
🚀 메인 파일(FlightDataDashboard.m)에서 삭제될 목록
위 3가지 모듈을 생성하고 컨트롤러들을 FlightDataDashboard의 생성자에서 등록(app.RoiCtrl = flightdash.controller.RoiController(app); 등)해 주면, 메인 파일에서 다음 메서드들을 완전히 삭제(Delete)할 수 있습니다.

ROI 로직 (삭제 대상):
addCurrentRoi, onRoiSelectionChanged, deleteSelectedRoi, clearRois, refreshRoiTable, computeRoiAnalysis, matchTargetColumn, drawRoiBands, deleteRoiGraphics

Panner 로직 (삭제 대상):
togglePanner, refreshPanner, drawPannerModeBands, pannerSignalData, updatePannerViewport, onPannerClicked, startPannerHandleDrag, pannerHandleDragMotion, stopPannerHandleDrag, onPannerRangeChanged, resetPannerRange, setCurrentTabXLim, resetProgrammaticXLim

Flight Mode 로직 (삭제 대상):
updateFlightModeBands, computeFlightModeBands, flightModeLabelsFromData, flightModeCodeLabel, modeBand, drawModeAxes

기대 효과: 이렇게 3가지 부가 기능을 들어내는 것만으로도 메인 코드가 대폭 줄어들어, 향후 UI/UX 수정이나 버그 픽스 시 스크롤을 헤매는 일이 획기적으로 줄어들게 됩니다.


=============================================================================================================
chatGPT cowork
=============================================================================================================
특히 현재 FlightDataDashboard.m에 ROI/Panner/Flight Mode 관련 메서드가 4013~4755 라인대에 집중되어 있고, 방금 만든 PlotView.m도 아직 drawRoiBands, updateFlightModeBands, updatePannerViewport, refreshPanner를 App에 의존하고 있어 다음 분리 대상으로 적절합니다.

다만 입력하신 예시 구조는 그대로 적용하기보다 조금 조정하는 편이 안전합니다.

권장 방향


RoiController는 신설하는 것이 맞습니다.

현재 PlotController.m가 ROI 이벤트까지 구독하고 있으므로, RoiAddRequested, RoiSelectionChanged, RoiDeleteSelectedRequested, RoiClearRequested, AnalysisComputeRequested는 RoiController로 이동하는 것이 좋습니다. 단, 통계 계산은 RoiController 안에 모두 넣기보다 장기적으로 +model/RoiAnalyzer.m 또는 +analysis/RoiStatisticsAnalyzer.m로 빼는 편이 더 깨끗합니다.



PannerController도 신설 가치가 큽니다.

togglePanner, onPannerClicked, startPannerHandleDrag, pannerHandleDragMotion, stopPannerHandleDrag, resetPannerRange는 독립 라이프사이클이 분명합니다. 다만 예시 코드처럼 ui = obj.App.UI(fIdx); ui.PannerVisible = ... 방식은 MATLAB struct copy 문제로 실제 app.UI(fIdx)가 갱신되지 않을 수 있습니다. 반드시 obj.App.UI(fIdx).PannerVisible = ...처럼 원본에 직접 쓰거나, 수정 후 obj.App.UI(fIdx) = ui로 되돌려야 합니다.



Flight Mode는 Controller보다 Model/Service가 맞습니다.

computeFlightModeBands, flightModeLabelsFromData, flightModeCodeLabel, modeBand는 순수 데이터 분석 성격이므로 +flightdash/+model/FlightModeAnalyzer.m로 분리하는 방향이 좋습니다. 반면 drawModeAxes, drawPannerModeBands는 View 렌더링이므로 Panner/Plot View 쪽에 두는 것이 자연스럽습니다.



주의할 점


Panner 드래그는 WindowButtonMotionFcn/WindowButtonUpFcn을 사용하므로 Plot marker drag, splitter drag와 충돌할 수 있습니다. 분리 시 “누가 현재 드래그를 소유하는지”를 명확히 해야 합니다.

ROI band는 PlotView, Panner, Stats/AuxWindow와 모두 연결됩니다. 한 번에 완전 삭제하지 말고, 먼저 App wrapper를 남겨둔 strangler 방식이 안전합니다.

PlotController가 현재 Plot+ROI+Panner+Analysis 이벤트를 모두 갖고 있으므로, 다음 단계에서는 “이벤트 구독 이동”부터 하는 것이 저위험입니다.


추천 적용 순서

RoiController 생성 후 ROI/Analysis 이벤트만 PlotController에서 이동.
FlightModeAnalyzer 생성 후 계산 로직만 먼저 이동. 렌더링은 유지.
PannerController 생성 후 Panner 이벤트와 드래그 상태만 이동.
PannerView 또는 PlotView 확장으로 refreshPanner, drawPannerModeBands, updatePannerViewport 렌더링 이동.
마지막에 FlightDataDashboard.m의 ROI/Panner/FlightMode 메서드를 wrapper로 줄이고, MATLAB Online에서 드래그/줌/ROI/분석 동작을 검증.

결론적으로, 개선안은 맞습니다. 다만 ROI, Panner, FlightMode를 모두 컨트롤러로만 나누기보다는 Controller + View + Analyzer로 역할을 더 선명하게 나누는 것이 유지보수성이 더 좋습니다.

RoiController, PannerController, FlightModeAnalyzer를 추가하는 수준이 아니라 역할을 이렇게 나누는 전제입니다.

Controller: EventBus 구독, 사용자 입력, 버튼/드래그/선택 이벤트 처리
View: axes, ROI band, panner handle, mode band 같은 그래픽 객체 생성/갱신
Analyzer: ROI 통계, Flight Mode 추정처럼 UI와 무관한 순수 계산
그래서 순서를 일부러 이렇게 잡았습니다.

RoiController
ROI 이벤트 소유권부터 PlotController에서 분리

FlightModeAnalyzer
비행 모드 “계산”만 먼저 model/service로 분리

PannerController
Panner 토글/클릭/드래그 이벤트 소유권 분리

PannerView 또는 PlotView 확장
Panner/Mode band의 실제 렌더링 분리

FlightDataDashboard.m wrapper 축소
마지막에 메인 파일에서 남은 로직 제거

즉, 검토결과의 “Controller + View + Analyzer로 역할을 선명하게 나누자”는 방향을 반영한 적용 순서입니다. 다만 ROI 쪽도 더 엄밀하게 가면 RoiController + RoiView + RoiStatisticsAnalyzer까지 나누는 것이 최종 형태로 가장 좋습니다.

=============================================================================================================
Gemini
=============================================================================================================
3. 반응형 레이아웃(Responsive Layout) 위임의 완결
문제점: +view/ResponsiveLayoutManager.m를 생성하셨지만, 여전히 메인 파일 안에 applyResponsiveShellLayout, applyResponsiveHeaderLayout, applyResponsiveBodyLayout, isSplitterRestricted 등 수백 라인의 화면 크기 계산 코드가 남아있습니다.

개선안: 메인 앱의 SizeChangedFcn 콜백에서는 LayoutMgr.applyLayout(app.UIFigure) 단 한 줄만 호출하고, 창 크기 계산 및 프로필(Wide, Compact 등)에 따른 컬럼 폭 조절 로직은 100% ResponsiveLayoutManager 내부로 은닉해야 합니다.

메인 파일(FlightDataDashboard.m)에서 창 크기 조절 시마다 호출되는 반응형 레이아웃(Responsive Layout) 계산 로직은 UI 코드 중에서도 가장 복잡하고 라인 수를 많이 차지하는 영역입니다.

이미 ResponsiveLayoutManager를 생성해 두셨으나, 메인 파일이 여전히 컬럼 폭, 스플리터 상태, 프로필(Wide/Compact 등)에 따른 분기 처리를 직접 하고 있습니다. 이를 완전한 위임(Full Delegation) 형태로 리팩토링하는 3단계 방안을 제안합니다.

Step 1: ResponsiveLayoutManager.m의 통제권 강화
메인 앱이 하던 크기 측정, 프로필 판별, 헤더/바디 레이아웃 갱신 로직을 모두 Manager가 흡수하도록 합니다. 이 클래스는 app 인스턴스(또는 app.UI, app.LayoutHandles 등 필요한 뷰 객체)를 전달받아 화면을 재구성합니다.

+flightdash/+view/ResponsiveLayoutManager.m (확장 및 덮어쓰기)

Matlab
classdef ResponsiveLayoutManager < handle
    % 화면 크기 변경 시 전체 레이아웃 배분을 책임지는 매니저 클래스
    
    methods
        % 1. 단일 진입점: 메인 파일에서 이 함수만 호출합니다.
        function applyLayout(obj, app)
            if app.InResponsiveLayout, return; end
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
            
            app.InResponsiveLayout = true;
            cleanup_ = onCleanup(@() obj.finishResponsiveLayout(app)); 
            
            try
                % 창 크기 및 프로필(Wide/Compact 등) 판별
                [figW, figH] = obj.currentFigureSizePx(app);
                profile = flightdash.util.UIScale.profileForSize(figW, figH);
                app.LayoutProfile = profile;
                app.LastLayoutSize = [figW, figH];
                
                % 쉘(헤더/바디) 레이아웃 적용
                obj.applyResponsiveShellLayout(app, profile, figH);
                
                % 채널별 내부 레이아웃 적용
                if isempty(app.UI), return; end
                nChannels = min(2, numel(app.UI));
                for fIdx = 1:nChannels
                    obj.applyResponsiveChannelLayout(app, fIdx, profile);
                    try, app.updatePlotRowHeights(fIdx); catch, end
                end
            catch ME
                % ErrorLog 유틸리티로 전달
                flightdash.util.ErrorLog.log(ME, 'Layout:responsive');
            end
        end
        
        function finishResponsiveLayout(~, app)
            app.InResponsiveLayout = false;
        end
        
        % 2. 메인 파일에서 뜯어온 세부 레이아웃 로직들
        function applyResponsiveShellLayout(obj, app, profile, figH)
            obj.applyResponsiveHeaderLayout(app, profile);
            obj.applyResponsiveBodyLayout(app, profile, figH);
        end
        
        function applyResponsiveHeaderLayout(obj, app, profile)
            % 기존 메인 파일의 applyResponsiveHeaderLayout 내용 복사
            % 예: h = app.LayoutHandles.header; ...
            % ...
        end
        
        function applyResponsiveBodyLayout(obj, app, profile, figH)
            % 기존 메인 파일의 applyResponsiveBodyLayout 내용 복사 (flight1/flight2 모드 분기 등)
            % ...
        end
        
        function applyResponsiveChannelLayout(obj, app, fIdx, profile)
            % 기존 메인 파일의 applyResponsiveChannelLayout 내용 복사
            % ...
            % 패널 요약 텍스트 갱신 호출 (데이터 결합 영역)
            obj.updatePanelRailSummaries(app, fIdx);
        end

        % 레일(접힌 상태) 요약 정보 텍스트 갱신도 레이아웃 매니저 또는 뷰로 이동
        function updatePanelRailSummaries(obj, app, fIdx)
            % 기존 메인 파일의 updatePanelRailSummaries 내용 복사
            % (모델에서 값을 읽어와 Rail 텍스트를 채우는 로직)
        end
        
        % ... (기타 isSplitterRestricted, setHandleVisible 등의 헬퍼 함수들 모두 이동)
    end
end
Step 2: FlightDataDashboard.m 레이아웃 진입점 간소화
메인 파일의 창 크기 조절 이벤트나 레이아웃 갱신 요구가 발생했을 때, 이제 복잡한 판단 없이 LayoutMgr에 통째로 위임합니다.

+flightdash/FlightDataDashboard.m (수정)

Matlab
        % 창 크기 조절 이벤트 콜백
        function onUIFigureResized(app)
            if app.IsDeleting, return; end
            app.applyResponsiveLayout('resize');
        end

        % 레이아웃 갱신 단일 진입점 (기존의 수백 줄을 1줄로 단축)
        function applyResponsiveLayout(app, reason)
            if nargin < 2, reason = ''; end
            if isempty(app.LayoutMgr) || ~isvalid(app.LayoutMgr), return; end
            
            % 모든 레이아웃 판단과 실행을 매니저에게 100% 위임
            app.LayoutMgr.applyLayout(app);
        end
🚀 Step 3: 메인 파일에서 대거 삭제(Delete) 될 메서드 목록
LayoutMgr가 책임을 넘겨받았으므로, FlightDataDashboard.m 안에 있는 아래의 함수들은 통째로 삭제해야 합니다. (약 400~500 라인이 즉시 줄어듭니다.)

상위 레이아웃 제어 로직:

finishResponsiveLayout

applyResponsiveShellLayout

applyResponsiveHeaderLayout

applyResponsiveBodyLayout

setChannelRootVisible, channelMinHeightForProfile, placeGridItem

채널 내부 레이아웃 및 컬럼 제어 로직:

applyResponsiveChannelLayout

resolvePreferredVideoWidth

isSplitterRestricted, isSplitterRestrictedForProfile

isPanelVisibleForLayout

shrinkWidth, setHandleVisible

접이식 패널(Rail) 상태 및 데이터 연동 로직:

applyResponsiveRailStates

isRailColumn

setContentRailMode

updatePanelRailSummaries (레이아웃이 접힐 때 요약 데이터 보여주는 로직)

modelValueAt, formatRailNumber (Rail 요약을 위한 헬퍼 함수들)

💡 리팩토링 포인트:
이전에는 메인 파일이 "데이터 모델도 알고", "창 크기도 계산하고", "UI 패널도 껐다 켰다 하는" 만능 객체(God Object)였습니다.
이번 위임을 통해 메인 파일은 오직 app.LayoutMgr.applyLayout(app)만 호출하고, LayoutMgr가 내부적으로 화면 크기에 따라 Grid Column 너비를 맞추고 불필요한 패널을 숨기는 일을 전담하게 됩니다. UI가 깨지거나 창 크기 반응형 버그가 생기면 오직 ResponsiveLayoutManager.m 파일만 열어보면 됩니다!

=============================================================================================================
chatGPT cowork
=============================================================================================================
현재 ResponsiveLayoutManager.m는 이름과 달리 아직 “전체 레이아웃 매니저”가 아니라 currentFigureSizePx, computeResponsiveColumnWidths, layoutDesignWidths 정도의 계산 helper 역할만 합니다. 실제 responsive layout의 핵심 제어는 여전히 FlightDataDashboard.m에 남아 있습니다.

다만 제안 중 LayoutMgr.applyLayout(app.UIFigure) 한 줄만 호출하는 방식은 현재 구조에서는 부족합니다. LayoutManager가 다음 상태를 알아야 하기 때문입니다.


app.UI

app.LayoutHandles

app.Models

app.ChannelViewMode

app.ManualPanelWidths

app.ManualVideoWidth

app.PreferredVideoWidth

app.LayoutProfile

app.InResponsiveLayout

app.updatePlotRowHeights

rail summary용 현재 데이터 값


따라서 현실적인 1차 목표는 app.LayoutMgr.applyLayout(app, reason)가 맞습니다. UIFigure만 넘기는 완전 분리는 나중에 LayoutContext 구조체를 만든 뒤 가능합니다.

현재 코드 반영 상태


ResponsiveLayoutManager 존재: 있음

메인에서 LayoutMgr 생성: 있음

메인에서 일부 helper 위임: 있음

전체 responsive layout 위임: 미완

메인에 남은 주요 레이아웃 메서드: 많음


현재 메인에 남은 대표 메서드는 다음입니다.


applyResponsiveLayout

finishResponsiveLayout

applyResponsiveShellLayout

applyResponsiveHeaderLayout

applyResponsiveBodyLayout

applyResponsiveChannelLayout

setChannelRootVisible

placeGridItem

isSplitterRestricted

isSplitterRestrictedForProfile

applyResponsiveRailStates

setContentRailMode

updatePanelRailSummaries

modelValueAt

formatRailNumber


권장 수정 방식


ResponsiveLayoutManager.applyLayout(app, reason)를 단일 진입점으로 만든다.

FlightDataDashboard.applyResponsiveLayout은 이 메서드를 호출하는 wrapper만 남깁니다.



먼저 “순수 레이아웃”만 이동한다.

applyResponsiveShellLayout, applyResponsiveHeaderLayout, applyResponsiveBodyLayout, applyResponsiveChannelLayout, placeGridItem, setHandleVisible부터 이동하는 것이 안전합니다.



두 번째로 splitter 제한/폭 계산을 이동한다.

isSplitterRestricted, isSplitterRestrictedForProfile, resolvePreferredVideoWidth, isPanelVisibleForLayout, shrinkWidth를 옮깁니다. 단, 현재 DragController와도 연결되어 있어 wrapper는 당분간 남겨야 합니다.



마지막으로 rail summary를 이동한다.

updatePanelRailSummaries, modelValueAt, formatRailNumber는 데이터 모델을 읽기 때문에 레이아웃과 데이터 표시가 섞여 있습니다. 이 부분은 ResponsiveLayoutManager 안에 넣어도 되지만, 더 엄밀하게는 RailSummaryView로 분리하는 편이 좋습니다.



주의점


이 작업은 ROI/Panner보다 위험도가 높습니다. 창 크기, 스플리터, 패널 토글, 1채널/2채널 모드, MATLAB Online compact 화면이 모두 영향을 받습니다.

한 번에 삭제하지 말고, 기존 App 메서드는 wrapper로 남기는 strangler 방식이 안전합니다.

DragController가 app.isSplitterRestricted, app.applyResponsiveChannelLayout 같은 메서드를 호출하고 있으므로, 이 이름들은 당분간 유지해야 합니다.


결론적으로, 제안은 맞습니다. 다만 최종 형태는 LayoutMgr.applyLayout(app.UIFigure)보다는 먼저 LayoutMgr.applyLayout(app, reason)가 현실적이고 안전합니다. 이후 안정화되면 app 전체 대신 LayoutContext만 넘기는 구조로 더 줄이면 됩니다.
=============================================================================================================
Gemini
=============================================================================================================

4. 상태(State) 플래그의 파편화 해소
문제점: app.IsUpdating, app.InGoToFrame, app.IsDecoding, app.PendingFrame, app.IsDraggingMarker 등 수많은 불리언(Boolean) 상태 플래그들이 메인 클래스 프로퍼티로 파편화되어 있어 상태 추적이 어렵습니다.

개선안:

이러한 상태들은 Redux 패턴의 Store처럼 +model/AppStateModel.m (또는 PlaybackState)로 묶어 관리하는 것이 좋습니다.

마우스 드래그 상태와 관련된 플래그들(IsDraggingMarker, DraggedFIdx)은 이미 존재하는 DragController의 내부 상태로 옮겨 메인 앱의 의존성을 줄일 수 있습니다.

현재 메인 파일(FlightDataDashboard.m)의 properties (Access = private) 블록을 보면 IsUpdating, InGoToFrame, IsDraggingMarker, PendingFrame, IsDecoding, InCascade 등 수십 개의 상태(State) 플래그들이 흩어져 있습니다.  

이러한 '상태 파편화(Spaghetti State)'는 버그 추적을 어렵게 만들고, 특정 콜백이 실행될 때 앱이 어떤 상태인지 예측하기 힘들게 합니다. 이를 해결하기 위해 상태 변수들을 성격에 맞게 1) 전용 상태 모델(State Model)로 분리하고, 2) 관련 컨트롤러의 내부 상태로 은닉하는 방안을 제안합니다.

Step 1: 재생 및 동기화 상태 모델 (PlaybackStateModel.m) 신설
루프 방지용 가드(Guard) 플래그나 프레임 지연(Pending)과 관련된 상태들은 하나의 객체로 묶어 관리해야 합니다. Redux의 Store처럼 상태를 읽고 쓰는 전용 모델을 만듭니다.

+flightdash/+model/PlaybackStateModel.m

Matlab
classdef PlaybackStateModel < handle
    % 비행 데이터 재생, 프레임 이동, 재귀 호출 방지(Guard) 상태를 관리하는 모델
    % 채널별(fIdx)로 인스턴스를 생성하여 사용합니다.

    properties (SetAccess = private)
        IsUpdating   logical = false   % updateDashboard 재귀 방지
        InGoToFrame  logical = false   % goToFrame 재진입 방지
        IsDecoding   logical = false   % 비디오 디코딩 진행 중 여부
        InCascade    logical = false   % 마커 드래그 시 연쇄 업데이트 방지
        PendingFrame double  = NaN     % 처리 중 들어온 최신 프레임 예약
        PendingMode  char    = ''      % 예약된 프레임의 모드 ('drag', 'final' 등)
    end
    
    methods
        % --- 상태 변경 메서드 (Setters) ---
        function setUpdating(obj, state)
            obj.IsUpdating = logical(state);
        end
        
        function setGoToFrame(obj, state)
            obj.InGoToFrame = logical(state);
        end
        
        function setDecoding(obj, state)
            obj.IsDecoding = logical(state);
        end
        
        function setCascade(obj, state)
            obj.InCascade = logical(state);
        end
        
        % --- Pending 처리 로직 캡슐화 ---
        function setPendingRequest(obj, frameNo, mode)
            obj.PendingFrame = frameNo;
            obj.PendingMode = mode;
        end
        
        function [hasPending, frameNo, mode] = consumePendingRequest(obj)
            hasPending = ~isnan(obj.PendingFrame);
            frameNo = obj.PendingFrame;
            mode = obj.PendingMode;
            
            % 소비 후 초기화
            obj.PendingFrame = NaN;
            obj.PendingMode = '';
        end
    end
end
Step 2: 드래그 상태를 DragController 내부로 은닉
IsDraggingMarker, DraggedMarker, DraggedFIdx, DraggedFromVideo 등은 오직 마우스 드래그 동작 중에만 유효한 상태입니다. 이 변수들을 메인 앱에 두지 말고, 이미 존재하는 DragController의 내부(private) 프로퍼티로 완전히 옮깁니다.

+flightdash/+controller/DragController.m (확장)

Matlab
classdef DragController < handle
    % 드래그 이벤트를 전담하며, 드래그 진행 상태를 내부적으로 캡슐화합니다.
    
    properties (Access = private)
        App
        Listeners cell = {}
        
        % 메인 앱에서 이관된 드래그 상태 변수들
        IsDraggingMarker logical = false
        DraggedMarker            = []
        DraggedFIdx      double  = 0
        DraggedFromVideo logical = false
        VideoThrottleDyn double  = 0.05
    end
    
    methods
        function obj = DragController(app)
            obj.App = app;
            % 이벤트 구독 (EventBus 사용)
            % ...
        end
        
        % 기존 메인 앱의 startPlotMarkerDrag 로직을 이관
        function startMarkerDrag(obj, fIdx, src, event, isFromVideo)
            if event.Button ~= 1, return; end
            
            % 상태 설정 (메인 앱 대신 컨트롤러 내부에 저장)
            obj.IsDraggingMarker = true;
            obj.DraggedMarker = src;
            obj.DraggedFIdx = fIdx;
            obj.DraggedFromVideo = isFromVideo;
            obj.VideoThrottleDyn = 0.05;
            
            % 글로벌 상태 업데이트
            % EventBus를 통해 'StateChanged' 브로드캐스트 ('IDLE' -> 'DRAGGING')
            flightdash.util.EventBus.publish('AppStatusChanged', 'DRAGGING');
            
            src.HitTest = 'off';
            % 마우스 모션 콜백 등록 등...
        end
        
        function stopDrag(obj)
            obj.IsDraggingMarker = false;
            obj.DraggedMarker = [];
            obj.DraggedFIdx = 0;
            
            flightdash.util.EventBus.publish('AppStatusChanged', 'IDLE');
            % ...
        end
    end
end
Step 3: 메인 파일(FlightDataDashboard.m) 다이어트 적용
이제 메인 파일에서 지저분한 상태 변수들을 지우고, 객체 지향적으로 접근합니다.

1. 프로퍼티 블록 대폭 삭제
메인 파일의 properties (Access = private)에서 다음 변수들을 전부 삭제합니다.

Matlab
% [삭제 대상]
% IsUpdating, IsDraggingMarker, DraggedMarker, IsProgrammaticXLim, 
% IsDraggingPanner, PannerDragFIdx, PannerDragSide, IsDraggingInfoRow, 
% InfoDragFIdx, InfoDragSourceRow, DraggedFIdx, DraggedFromVideo, 
% VideoThrottleDyn, LastDragTime, InGoToFrame, PendingFrame, PendingMode, 
% InCascade, IsDecoding, State
2. 상태 객체 생성
삭제한 변수들 대신, 새로 만든 PlaybackStateModel 배열 하나만 선언합니다.

Matlab
properties (Access = private)
    PlaybackState = [] % [1x2] 배열로 초기화됨
end

% 생성자(Constructor) 내부
app.PlaybackState = [flightdash.model.PlaybackStateModel(), flightdash.model.PlaybackStateModel()];
3. 가드(Guard) 로직 수정
상태 체크가 필요한 함수(applyTimeChange, goToFrame 등)의 시작 부분을 다음과 같이 수정합니다.

기존 코드 (파편화된 변수 사용):

Matlab
function applyTimeChange(app, fIdx, index)
    if app.IsUpdating(fIdx), return; end
    app.IsUpdating(fIdx) = true;
    cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx));
    % ...
end
수정된 코드 (객체 상태 사용):

Matlab
function applyTimeChange(app, fIdx, index)
    if app.PlaybackState(fIdx).IsUpdating, return; end
    
    app.PlaybackState(fIdx).setUpdating(true);
    cleanup_ = onCleanup(@() app.PlaybackState(fIdx).setUpdating(false));
    
    % ... 메인 로직 ...
end
💡 요약:
플래그 변수들을 PlaybackStateModel과 DragController 안으로 밀어 넣으면 메인 클래스의 '전역 변수' 오염이 사라집니다. 특히 PendingFrame이나 IsUpdating 같은 변수는 멀티 채널(Flight 1, Flight 2) 간 간섭 버그를 유발하기 쉬운데, 채널별로 인스턴스화된 PlaybackStateModel 객체를 사용하면 동시성 제어가 훨씬 안전하고 명확해집니다.
=============================================================================================================
chatGPT cowork
=============================================================================================================
검토 결과, 방향은 **맞습니다.** 현재 [FlightDataDashboard.m](</D:/flightdashboard/5. 4th/+flightdash/FlightDataDashboard.m>)에는 실제로 상태 플래그가 꽤 많이 남아 있고, 이 플래그들이 비디오 디코딩, plot marker drag, panner, info row drag, XLim listener guard, goToFrame coalescing을 동시에 다루고 있어 추적 난도가 높습니다.

다만 제안처럼 모든 플래그를 한 번에 `PlaybackStateModel`로 넣는 것은 조금 위험합니다. 상태의 성격이 다릅니다.

**분류가 필요함**
- `PlaybackStateModel` 대상  
  `IsUpdating`, `InGoToFrame`, `PendingFrame`, `PendingMode`, `IsDecoding`  
  프레임 이동, 업데이트 재진입, 디코딩 pending과 직접 관련됩니다.

- `InteractionState` 또는 Controller 내부 대상  
  `IsDraggingMarker`, `DraggedMarker`, `DraggedFIdx`, `DraggedFromVideo`, `LastDragTime`, `VideoThrottleDyn`  
  실제로는 marker drag 세션 상태입니다. `DragController` 또는 별도 `MarkerDragController`가 더 적합합니다.

- `PannerController` 대상  
  `IsDraggingPanner`, `PannerDragFIdx`, `PannerDragSide`  
  이미 `PannerController` 내부 상태로 이동한 구조이므로, 메인에 남은 기존 속성은 사용 여부 확인 후 제거 후보입니다.

- `InfoPanel`/`InfoController` 대상  
  `IsDraggingInfoRow`, `InfoDragFIdx`, `InfoDragSourceRow`  
  현재 비행정보 row reorder 전용 상태라 `PlaybackStateModel`에는 넣지 않는 편이 맞습니다.

- `PlotView` 또는 Plot interaction state 대상  
  `IsProgrammaticXLim`  
  이것은 playback이 아니라 plot XLim listener guard입니다. `PlotView`나 `PlotStateModel` 쪽이 자연스럽습니다.

- 전역 상태 후보  
  `InCascade`, `State`  
  `InCascade`는 채널별이라기보다 cascade 전체 재진입 방지라 per-channel `PlaybackStateModel`에 넣으면 의미가 흐려질 수 있습니다. `State = 'IDLE'|'DRAGGING'...`는 실제 제어보다 디버그/상태 표시 성격이 강하므로, 장기적으로는 파생 상태로 만드는 편이 좋습니다.

**권장 적용 방식**
1. `PlaybackStateModel`을 먼저 추가하되, 기존 속성은 즉시 삭제하지 않습니다.  
   처음에는 `app.PlaybackState(fIdx).IsUpdating` 같은 새 상태와 기존 `app.IsUpdating(fIdx)`를 wrapper로 연결하는 방식이 안전합니다.

2. `IsUpdating`, `InGoToFrame`, `PendingFrame`, `PendingMode`, `IsDecoding`만 1차 이전합니다.  
   이 다섯 개는 `goToFrame`, `requestFrame`, `clearDecodingFlag`, `queuePendingFrame`, `processPendingDecodeRequest`에 집중되어 있어 효과가 크고 범위도 비교적 명확합니다.

3. Marker drag 상태는 `DragController`로 바로 넣기보다 별도 `MarkerDragController` 또는 `DragController` 확장으로 단계적으로 이전합니다.  
   현재 `DragController`는 splitter 이벤트만 다루므로, marker drag까지 한 번에 넣으면 클래스 책임이 갑자기 커집니다. 그래도 이름상 드래그 컨트롤러로 모을 수는 있습니다.

4. `IsProgrammaticXLim`은 `PlotView` 쪽으로 분리하는 것이 맞습니다.  
   `PannerController`도 현재 이 값을 쓰고 있으므로, `PlotView.setProgrammaticXLimGuard(fIdx,true/false)` 같은 경유 API가 필요합니다.

5. `Info row drag`는 나중에 `InfoController` 또는 `InfoPanel` 책임으로 분리합니다.  
   이건 playback/state 안정화와 직접 관련이 적어 후순위가 좋습니다.

**주의점**
- `PendingFrame/PendingMode`는 최근에 “디코딩 중 최신 요청을 버리지 않기” 위해 중요한 보강이 들어간 영역입니다. 이 부분을 모델화할 때 consume 순서가 조금만 바뀌어도 빠른 slider drag 후 최종 프레임 불일치가 재발할 수 있습니다.
- `InCascade`는 dual flight sync와 연결되어 있어 per-channel로 단순 분리하면 오히려 재귀 방지가 약해질 수 있습니다.
- `DragController` 내부로 marker state를 옮길 때, 기존 `stopPlotMarkerDrag`가 XLim listener 복원, alpha 복원, sync/preload까지 같이 하므로 단순 상태 이동보다 메서드 단위 이관이 필요합니다.

결론적으로, 제안은 타당하지만 `PlaybackStateModel` 하나로 모든 상태를 넣기보다는 `PlaybackStateModel + MarkerDragController/DragController + Plot interaction state + Info state`로 나누는 것이 더 안전합니다. 1차 적용 우선순위는 `IsUpdating/InGoToFrame/PendingFrame/PendingMode/IsDecoding`입니다.