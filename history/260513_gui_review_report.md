# 260513_gui(1).log 검토 보고서

> 구성 방식: `260513_gui(1).log`의 원문 문장을 최대한 그대로 유지하고, 각 문장 또는 의미 단위 바로 아래에 **검토 결과 / 답변**을 추가했습니다.

---

## 1. Flight 1 데이터 로딩 / option1.dat 매핑

**원문**  
Flight 1버튼 누르고 csv 파일 선택해서 비행데이터 로딩하면, 시간이 지난후에 다음 메시지가 error dlg에 뜸.

**검토 결과 / 답변**  
이 현상은 Flight 1 버튼 자체의 단순 클릭 오류라기보다, CSV 파일을 읽은 뒤 필수 비행데이터 컬럼을 `option1.dat` 또는 파일 header와 매칭하는 단계에서 실패한 것으로 판단됩니다. 즉, GUI 이벤트는 시작되었지만 데이터 매핑 검증 단계에서 중단된 상태입니다.

**원문**  
Error : Required flight-data columns were not mapped : Roll, Pitch, Check option1.dat or file headers.

**검토 결과 / 답변**  
`Roll`, `Pitch`가 필수 컬럼으로 요구되지만 현재 CSV header 또는 `option1.dat` 설정에서 해당 항목을 찾지 못하고 있습니다. 해결 방향은 다음과 같습니다.

```text
1. 실제 운용 option1.dat 파일 포맷 분석
2. 테스트용 option1.dat와 실제 option1.dat 포맷 차이 비교
3. CSV header normalize 기능 추가
   - 대소문자 무시
   - 공백 제거
   - 괄호/단위 제거
   - 특수문자 제거
4. Roll/Pitch/Heading/Altitude/Lat/Lon/Time alias table 추가
5. 필수 컬럼 누락 시 error dialog 대신 mapping 확인 dialog 표시
```

예시 alias table은 다음과 같습니다.

```matlab
aliases.Roll    = {'Roll','roll','ROLL','Roll(deg)','roll_deg','Phi','phi'};
aliases.Pitch   = {'Pitch','pitch','PITCH','Pitch(deg)','pitch_deg','Theta','theta'};
aliases.Heading = {'Heading','heading','Yaw','yaw','Psi','psi','Azimuth'};
```

**원문**  
-> 기존 option1.dat 파일을 업로드해서 다시 분석 필요

**검토 결과 / 답변**  
동의합니다. 실제 사용하는 `option1.dat`를 기준으로 parser와 mapping logic을 재검토해야 합니다. 테스트용 설정 파일만 기준으로 구현하면 실제 비행데이터 로딩 시 같은 오류가 반복될 가능성이 높습니다.

**원문**  
-> 테스트용 데이타용 option1.dat와 포멧 다름. 

**검토 결과 / 답변**  
이 경우 `option1.dat` parser는 단일 포맷만 가정하면 안 됩니다. 최소한 다음 둘 중 하나가 필요합니다.

```text
A. version-aware parser
   - 구버전 / 테스트용 / 실제 운용 포맷을 구분해서 해석

B. flexible parser
   - line pattern, delimiter, key-value 형식을 유연하게 인식
```

---

## 2. 최초 실행 / Project Explorer 표시

**원문**  
1. 최초 실행 : 

**검토 결과 / 답변**  
이 항목은 `FlightReviewStudio` 최초 실행 시 기본 workspace와 dock layout이 사용자가 기대하는 Studio 형태로 열리는지에 대한 문제입니다.

**원문**  
Project explore가 안뜸. "Welcome" 탭만 뜸. Phase를 모두 진행안해서 인지?

**검토 결과 / 답변**  
Phase 구현이 일부 미완성이라기보다는, 초기 GUI mode 또는 dock visibility 기본값 문제일 가능성이 있습니다. OriginPro 스타일 Studio를 목표로 한다면 최초 실행 시 Project Explorer는 기본 표시되는 것이 적절합니다.

권장 초기 상태는 다음과 같습니다.

```text
FlightReviewStudio 최초 실행:
- Left Dock: Project Explorer 표시
- Center Workspace: Welcome tab 표시
- Right Dock: Object Manager / Inspector는 표시 또는 접힘
- Status Bar: 현재 project/session 상태 표시
```

확인할 항목은 다음입니다.

```text
1. ProjectExplorerPanel 객체가 생성되는지
2. LeftDock column width가 0으로 시작하지 않는지
3. Compact mode가 기본값으로 적용되어 Project Explorer를 숨기는지
4. Window > Show Project Explorer 메뉴 상태와 실제 표시 상태가 동기화되는지
```

---

## 3. AVI 파일 로딩 후 동기 전 동작

**원문**  
avi 파일을 열고나서

**검토 결과 / 답변**  
AVI 파일 로드 직후에는 video metadata, FPS, duration, total frame count가 정확히 읽히고 GUI에 표시되어야 합니다. 이 시점에는 아직 비행데이터와 video frame 간 동기 관계가 없으므로, 비행데이터 marker가 video frame을 움직이지 않는 것은 정상일 수 있습니다.

**원문**  
비행데이터의 항목이나 고도정보의 별표마크를 마우스로 드래그해도 비디오 플레이어의 화면이 변하지 않음.

**검토 결과 / 답변**  
동기화 전이라면 정상 동작입니다. 데이터 time/index와 video frame 사이의 변환식이 아직 설정되지 않았기 때문입니다.

**원문**  
-> 정상

**검토 결과 / 답변**  
동의합니다. 다만 사용자가 혼동하지 않도록 GUI에 다음과 같은 상태 표시가 있으면 좋습니다.

```text
Video/Data sync is not configured.
Drag marker updates data view only.
```

---

## 4. 비디오 슬라이더 실시간 업데이트

**원문**  
비디오 플레이어 슬라이드 바 드래그시 화면이 정지되었다가, 드래그가 멈추면 화면이 변경됨

**검토 결과 / 답변**  
현재 slider drag 중에는 frame preview가 실행되지 않고, mouse release 후 `ValueChangedFcn`에서만 최종 frame을 표시하는 구조일 가능성이 큽니다. 사용성 관점에서는 드래그 중에도 영상 frame이 일정 주기로 갱신되어야 합니다.

**원문**  
-> 실시간 업데이트 필요

**검토 결과 / 답변**  
반영 권장합니다. 구현 방향은 다음과 같습니다.

```text
드래그 중:
- uislider.ValueChangingFcn 사용
- 10~20 FPS 정도로 throttle 적용
- video frame preview만 수행
- 무거운 plot redraw, ROI recalc, sync quality 계산은 생략

드래그 종료:
- ValueChangedFcn에서 최종 frame 확정
- marker, plot, status bar, synced data index 전체 동기화
```

예시 구조:

```matlab
slider.ValueChangingFcn = @(src, evt) app.onVideoSliderChanging(fIdx, evt.Value);
slider.ValueChangedFcn  = @(src, evt) app.onVideoSliderChanged(fIdx, src.Value);
```

---

## 5. 비디오/비행데이터 동기 이후 동작

**원문**  
비디오와 비행데이터 동기시킨 이후에,,

**검토 결과 / 답변**  
동기화 이후에는 flight data time/index와 video frame 사이의 관계가 설정됩니다. 이 단계부터는 marker drag와 video frame 이동이 상호 연동되어야 합니다.

**원문**  
비행데이터의 항목이나 고도정보의 별표마크를 마우스로 드래그하면 비디오 플레이어 화면이 같이 변홤

**검토 결과 / 답변**  
정상 동작입니다. 이 기능은 유지해야 합니다. 다만 drag 중 frame update가 너무 무거우면 throttle을 적용해야 합니다.

**원문**  
-> ok

**검토 결과 / 답변**  
동의합니다. 동기 이후 marker drag → video frame update 동작은 핵심 기능입니다.

**원문**  
비디오 플레이어 슬라이드 바 드래그시 화면이 정지되었다가, 드래그가 멈추면 화면이 변경됨

**검토 결과 / 답변**  
동기화 후에도 동일 문제가 반복되므로 slider preview path 자체가 부족한 것으로 판단됩니다.

**원문**  
-> 실시간 업데이트 필요

**검토 결과 / 답변**  
동기화 후 video slider drag 중에는 다음 항목도 같이 갱신되어야 합니다.

```text
- video frame preview
- synced flight data index
- data plot marker 위치
- 현재값 label
```

단, 모든 plot을 매번 redraw하면 느려질 수 있으므로 preview 단계와 final commit 단계를 분리해야 합니다.

---

## 6. 해안선 정보 입력 / 지도 범위

**원문**  
해안선 정보 입력 파일 선택

**검토 결과 / 답변**  
해안선 파일 로드 후에는 coast data의 lon/lat bounds, flight data bounds, fixed area bounds를 분리해서 관리해야 합니다.

**원문**  
Y축 : lat

**검토 결과 / 답변**  
정상입니다. 위도는 Y축으로 표시하는 것이 맞습니다.

**원문**  
X축 : lon

**검토 결과 / 답변**  
정상입니다. 경도는 X축으로 표시하는 것이 맞습니다.

**원문**  
X축 , Y축 최대범위를 무시하고 일부분만 표시됨. 

**검토 결과 / 답변**  
수정이 필요합니다. 가능 원인은 다음과 같습니다.

```text
1. option_flight_area.dat 또는 FixedAreaBounds가 강제로 적용됨
2. xlim/ylim 설정 후 axis auto가 다시 적용됨
3. coastline bounds가 아니라 flight bounds만 사용됨
4. NaN 또는 0 좌표 제거 과정에서 범위가 축소됨
5. axis equal 또는 aspect ratio 적용 순서 문제
```

**원문**  
-> 수정필요

**검토 결과 / 답변**  
수정 방향은 다음과 같습니다.

```text
1. Coastline bounds, Flight bounds, FixedArea bounds를 별도 계산
2. 해안선만 로드한 경우 기본은 coastline 전체 범위 표시
3. 비행데이터도 있으면 union bounds 옵션 제공
4. FixedAreaBounds 적용 시 GUI에 Fixed Area mode 표시
5. xlim/ylim 설정을 마지막 단계에서 확정
```

---

## 7. Standalone FlightDataDashboard와 Studio embedded Dashboard 불일치

**원문**  
FligthDashBoard.m을 단독 실행하면 화면이 전혀 다르게 나옴. Flight 1 버튼 눌러서 csv 파일을 선택해도 처리를 안함. 

**검토 결과 / 답변**  
중요한 구조적 문제입니다. 단독 실행과 Studio embedded 실행이 서로 다른 UI/초기화 경로를 타고 있을 가능성이 큽니다. standalone도 embedded와 동일한 controller/view/model 초기화를 거쳐야 합니다.

**원문**  
FlightReviewStudio.m에서 session을 추가하면 나오는 FlightDashBoard와 완전히 다름. 

**검토 결과 / 답변**  
목표 구조에서는 standalone과 embedded가 동일한 Dashboard class를 사용해야 합니다. 차이는 다음 정도로 제한되어야 합니다.

```text
Standalone:
- 자체 uifigure 생성
- RootContainer = UIFigure
- CloseRequestFcn / SizeChangedFcn 직접 소유

Embedded:
- Studio tab/panel에 렌더링
- RootContainer = parentContainer
- MouseRouter / shared services / UndoService는 Studio에서 주입
```

**원문**  
FligthDashBoard.m은 단독 실행할 수도 있고, FlightReviewStudio.m을 실행했을때 탭의 GUI로 사용할수 있는 방식으로 코드 수정가능한지?

**검토 결과 / 답변**  
가능합니다. 핵심은 `createLayout()`이 `UIFigure`가 아니라 `RootContainer` 기준으로 UI를 생성하도록 통합하는 것입니다.

권장 구조:

```matlab
function app = FlightDataDashboard(parentContainer, sessionId)
    if nargin >= 1 && ~isempty(parentContainer)
        app.IsEmbedded = true;
        app.RootContainer = parentContainer;
        app.UIFigure = ancestor(parentContainer, 'figure');
    else
        app.IsEmbedded = false;
        app.UIFigure = uifigure(...);
        app.RootContainer = app.UIFigure;
    end

    app.createModels();
    app.createControllers();
    app.createLayout(app.RootContainer);
end
```

---

## 8. 화면 확대 시 버튼 / editbox 크기 문제

**원문**  
화면을 확대화면 "Import CFG" ,"Rst","Sync Time" 버튼의 가로길이가 늘어남. 

**검토 결과 / 답변**  
`uigridlayout.ColumnWidth`에서 버튼 column이 `'1x'` 또는 비율형으로 설정된 것으로 보입니다. 버튼은 고정 폭이어야 하고, 남는 공간만 spacer가 가져가야 합니다.

**원문**  
->수정필요

**검토 결과 / 답변**  
수정 예시는 다음과 같습니다.

```matlab
grid.ColumnWidth = {80, 60, 90, 80, '1x'};
```

버튼 column은 px 고정, 마지막 빈 column만 `'1x'`로 설정합니다.

**원문**  
화면을 확대화면 "Sync Time" 버튼의 왼쪽에 있는 editbox도 길이가 늘어남

**검토 결과 / 답변**  
EditBox도 최대 폭 제한 또는 고정 폭이 필요합니다. 시간 입력 필드라면 지나치게 길어질 이유가 없습니다.

**원문**  
->수정필요

**검토 결과 / 답변**  
권장 폭은 80~120 px 정도입니다.

```matlab
grid.ColumnWidth = {..., 100, 80, '1x'};
```

---

## 9. Session 초기 표시 화면

**원문**  
Session1 추가하면 처음 표시되는 화면은 "현재비행정보", "H: Data View Panel" 2개만 보이고 나머지는 버튼을 눌러야 보이게 수정

**검토 결과 / 답변**  
좋은 방향입니다. 현재 GUI가 처음부터 너무 많은 패널을 보여주면 15인치 노트북 또는 MATLAB Online에서 화면이 복잡해집니다.

권장 기본 layout:

```text
Session 최초 생성:
- 현재비행정보 표시
- H: Data View Panel 표시
- Video panel 접힘
- Map/Manager/Detail/Analyzer 접힘
- ROI/Analyzer는 필요 시 버튼으로 표시
```

비디오 파일이 로드되면 Video panel을 자동으로 펼치는 방식도 좋습니다.

---

## 10. Manager / Detail / +ROI / Analyzer 보조 Figure

**원문**  
"Manager","Detail",'+ROI","Analyzer" 버튼을 눌렀을때 나오는 Figure들에 대한 동작 개선 필요함. 

**검토 결과 / 답변**  
현재 이 기능들은 동작 정의와 context 표시가 부족한 상태로 보입니다. 장기적으로는 독립 figure보다 Studio의 RightDock tab 또는 Workspace tab으로 통합하는 것이 더 안정적입니다.

**원문**  
다음의 의견을 검토해서 개선방안 검토바람.

**검토 결과 / 답변**  
아래 항목별로 개선 방향을 제시합니다.

**원문**  
-> Flight 1, Flight 2 어느 것에 해당되는지 식별되어야 함.

**검토 결과 / 답변**  
반드시 필요합니다. 모든 Manager/Detail/ROI/Analyzer UI에는 active session과 channel context를 표시해야 합니다.

예:

```text
ROI Manager - Session 1 / Flight 1
Plot Detail - Session 2 / Flight 2 / Altitude
Analyzer - Session 1 / Flight 1 / H Panel
```

**원문**  
-> Tab1, Tab2, Tab3 등이 구별되어야 함.

**검토 결과 / 답변**  
각 보조 UI는 어떤 workspace tab, plot tab, data panel에 연결되어 있는지 명확히 표시해야 합니다. 내부적으로는 context object를 두는 것이 좋습니다.

```text
SessionId
ChannelIdx
PanelId
TabId
ObjectId
```

**원문**  
    각 figure도 tab이 생겨서 "H: Data View Panel" 탭과 동기되어야 함.

**검토 결과 / 답변**  
동의합니다. 가능하면 독립 figure 대신 RightDock 또는 Workspace 내부 tab으로 전환하는 것이 좋습니다. 독립 figure를 유지한다면 active tab 변경 시 자동 refresh되어야 합니다.

**원문**  
-> ROI 버튼 누르면 plot 전체가 오렌지 색 배경이 된 이후에 무슨 동작을 하는지 알 수가 없음.

**검토 결과 / 답변**  
ROI mode 진입 안내가 부족합니다. plot 전체 배경색 변경보다 상태 표시와 안내 메시지가 필요합니다.

권장 UX:

```text
StatusBar: ROI mode - drag over Data View Panel to select range. Esc to cancel.
Cursor: crosshair
Plot overlay: 반투명 selection guide
Toolbar ROI button: active 상태 표시
```

**원문**  
    -> 이상태 이후에 "H: Data View Panel" 의 별표 표식을 마우스 드래그 하면 움직임이 자연스럽지 않음.

**검토 결과 / 답변**  
ROI selection mode와 marker drag mode가 충돌하는 것으로 보입니다. interaction state machine을 분리해야 합니다.

```text
InteractionMode:
- normal
- markerDrag
- roiSelect
- pan
- splitterDrag
```

ROI mode에서는 marker drag를 비활성화하거나, marker hover 시 marker drag가 우선권을 갖도록 명확히 정해야 합니다.

**원문**  
-> 버튼을 누르고 session GUI에 마우스 클릭하면 figure가 사라지는데, 다시 Manager","Detail",'+ROI","Analyzer"의 버튼을 누르면 해당 figure가 session gui앞으로 활성화 되어야 함.

**검토 결과 / 답변**  
맞습니다. 보조 figure는 새로 계속 생성하지 말고, 이미 존재하면 bring-to-front 해야 합니다.

```matlab
if isempty(fig) || ~isvalid(fig)
    fig = uifigure(...);
else
    figure(fig);
end
```

`uifigure`에서는 focus/visibility 제어가 제한될 수 있으므로 `Visible`, `WindowState`, `drawnow`를 함께 사용해야 할 수 있습니다.

**원문**  
-> "Manager","Detail",'+ROI","Analyzer" 세부 버튼을 눌러도 동작안하는 기능이 많음. 구체화 및 구현방안 필요함.

**검토 결과 / 답변**  
미구현 버튼은 숨기거나 disabled 상태로 두는 것이 좋습니다. 버튼이 동작하지 않으면 사용자는 오류로 인식합니다.

정책:

```text
구현 완료: enabled
구현 예정: disabled + tooltip
삭제 예정: UI에서 제거
```

**원문**  
    예를 들면 "Detail" 버튼을 누르면 어떤 tab에 있는 그래프인지 구분이 안됨, Show 항목의 체크 박스를 체크해도 변화가 없음. '

**검토 결과 / 답변**  
Detail panel은 selected graphics object 또는 active plot tab과 반드시 연결되어야 합니다. Show checkbox는 해당 object의 `Visible` 속성과 직접 연결되어야 합니다.

예:

```matlab
target.Visible = matlab.lang.OnOffSwitchState(showCheckBox.Value);
```

또는:

```matlab
target.Visible = onOff(showCheckBox.Value);
```

**원문**  
    매트랩 app designer로 코딩시 ui 버튼의 속성뷰어 GUI등을 참고해서 보완 바람.

**검토 결과 / 답변**  
좋은 참고 방향입니다. MATLAB App Designer의 Component Browser처럼 object tree와 property inspector를 나누는 구조가 적절합니다.

권장 구조:

```text
Object Manager:
- Session
- Flight 1 / Flight 2
- Data panels
- Plot lines
- ROI objects
- Markers

Property Inspector:
- Selected object name
- Visible
- Color
- LineWidth
- Marker
- Axis binding
```

**원문**  
    https://kr.mathworks.com/help/matlab/creating_guis/app-designer-code-generation.html 의 컴포넌트 브라우져

**검토 결과 / 답변**  
Component Browser 개념을 참고해 현재 Studio의 Project Explorer와 Object Manager를 구분하는 것이 좋습니다.

```text
Project Explorer:
- project/session/result 중심

Object Manager:
- 현재 session 내부 graphics/UI object 중심
```

---

## 11. 비행데이터 plot slider 추가

**원문**  
비행데이터 탭의 plot에 대한 슬라이드바를 비디오 플레이어와 동일한 형식으로 추가바람. 위치는 "실시간 현재값:"이 표시되는 영역의 빈공간으로 해주기 바람. 

**검토 결과 / 답변**  
반영 권장합니다. 데이터 plot slider는 현재 data index/time을 직접 조절하는 주요 UX가 될 수 있습니다.

권장 동작:

```text
DataSlider.ValueChangingFcn:
- marker preview 이동
- 현재값 label 업데이트
- synced video frame preview 요청

DataSlider.ValueChangedFcn:
- 최종 data index 확정
- plot x-window follow
- video frame sync
- status bar update
```

위치는 요청대로 “실시간 현재값:” 옆 빈 공간이 적절합니다.

---

## 12. 로드된 파일명 표시

**원문**  
fligh 1, fligh 2 로드된 비행데이타 파일명을 GUI 적당한 위치에 표시해주기 ㅂ라마. 

**검토 결과 / 답변**  
반드시 반영하는 것이 좋습니다. 현재 여러 flight/session/video를 다루는 구조에서는 파일명을 표시하지 않으면 사용자가 쉽게 혼동합니다.

권장 표시:

```text
Flight 1 Data: xxx.csv
Flight 1 Video: xxx.avi
Flight 2 Data: yyy.csv
Flight 2 Video: yyy.avi
```

긴 경로는 basename만 표시하고 전체 path는 tooltip으로 제공하는 것이 좋습니다.

```matlab
[~, name, ext] = fileparts(filePath);
label.Text = [name ext];
label.Tooltip = filePath;
```

---

## 13. 패널 제목 / 프레임 숫자 시인성

**원문**  
패널 제목, 비디오 플레이어 슬라이드바 위에 프레임 숫자등이 배경과 폰트 색이 조화가 안맞아서 새시인성이 깨짐. 전부 조사해서 시인성 개선 필요함. 

**검토 결과 / 답변**  
전체 UI theme 정리가 필요합니다. 개별 컴포넌트마다 임의 RGB를 쓰면 화면 크기나 배경에 따라 시인성이 깨집니다.

권장 theme:

```text
Panel header:
- Background: #F3F4F6
- Text: #111827
- FontWeight: bold

Readout label:
- Background: white 또는 transparent
- Text: #1F2937

Active/warning mode:
- Background: #FEF3C7
- Text: #92400E

Video frame label:
- Background: #111827
- Text: #F9FAFB
```

`flightdash.ui.Theme` 또는 `flightdash.util.UIColors` 같은 중앙화 helper를 두는 것이 좋습니다.

---

## 14. AVI FPS 표시 문제

**원문**  
flight 1에 avi 파일을 열면 FPS는 무조건 230이고 flight 2에 avi 파일을 열면 FPS는 무조건 830임. 확인 필요함.

**검토 결과 / 답변**  
매우 의심스러운 현상입니다. 실제 FPS가 아니라 frame count, duration, anchor frame, 또는 잘못된 channel-specific 값이 FPS field에 표시되는 것일 가능성이 있습니다.

정상 계산은 다음이어야 합니다.

```matlab
vr = VideoReader(filePath);
fps = vr.FrameRate;
duration = vr.Duration;
totalFrames = floor(duration * fps);
```

확인할 항목:

```text
1. VideoReader.FrameRate 값을 그대로 읽는지
2. VideoSyncState(fIdx).VideoFps에 잘못된 값이 들어가는지
3. Flight 1/2별 default FPS가 하드코딩되어 있는지
4. TotalFrames 또는 AnchorFrame이 FPS label에 표시되는지
5. metadata 읽기 실패 시 fallback 값이 잘못 적용되는지
```

---

## 15. Range 버튼

**원문**  
"Range"버튼을 누르면 아무것도 안나옴. 

**검토 결과 / 답변**  
아무 동작도 하지 않는 버튼은 UX 품질을 크게 떨어뜨립니다.

**원문**  
->기능구현계획없으면 삭제 요망

**검토 결과 / 답변**  
동의합니다. 선택지는 둘입니다.

```text
A. 기능 구현
- 현재 plot x-range 입력 dialog
- ROI range로 zoom
- full range reset

B. 미구현 유지
- 버튼 disabled
- Tooltip: Range tool is planned
```

현재 단계에서는 disabled + tooltip이 가장 안전합니다.

---

## 16. 마우스 십자 커서 고착 / 동작 멈춤

**원문**  
fligh1, fligh2 데이터를 로딩하고 패널 간격을 조정하고 비행데이터 표시 별표표식을 좌우로 드래그하면서 마우스 왼쪽 버튼 클릭을 push, release를 반복했는데

**검토 결과 / 답변**  
패널 splitter drag와 marker drag가 반복되면서 interaction state가 꼬인 것으로 보입니다. 특히 mouse down/up 이벤트 중 예외가 발생하면 `WindowButtonUpFcn` 또는 drag lock release가 누락될 수 있습니다.

**원문**  
십자 마우스 모양이 어느순간 안사라지고 동작이 멈춤

**검토 결과 / 답변**  
중요한 안정성 이슈입니다. 모든 drag 종료 경로에서 cursor와 상태를 강제로 복구하는 fail-safe가 필요합니다.

권장 helper:

```matlab
function forceEndAllDrag(app, reason)
    try, app.State = 'IDLE'; catch, end
    try, app.IsDraggingSplitter = false; catch, end
    try, app.IsDraggingPanelSplitter = false; catch, end
    try, app.IsDraggingPanner = false; catch, end

    try
        if ~isempty(app.MouseRouter) && isvalid(app.MouseRouter)
            app.MouseRouter.releaseDragLock();
        end
    catch
    end

    try
        if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
            app.UIFigure.Pointer = 'arrow';
        end
    catch
    end
end
```

이 helper는 다음 위치에서 호출해야 합니다.

```text
- WindowButtonUpFcn
- WindowKeyPressFcn에서 Esc 입력
- tab switch
- tab close
- figure close
- drag motion callback catch 블록
```

**원문**  
별도 에러 메시지 참조

**검토 결과 / 답변**  
해당 에러 메시지가 있으면 추가 분석이 필요합니다. 특히 callback stack trace가 있으면 어떤 drag controller에서 release가 누락되는지 확인할 수 있습니다.

---

## 17. Pitch / Roll / Heading 원형 게이지

**원문**  
Pitch, Roll, Heading 표시 원 게이지 원 라인을 따라서 표시되는 삼각형 지시자 크기가 작아서 움직임잘 인식되지 않음. 삼각형지시자의 크기와 색을 선명하게 변경필요

**검토 결과 / 답변**  
반영 권장합니다. 삼각형 indicator는 gauge radius 기준으로 동적 크기를 계산해야 합니다.

권장 계산:

```matlab
needleSize = max(8, round(radius * 0.08));
```

색상은 배경 대비가 큰 색상을 사용해야 합니다.

```text
Roll: orange/red
Pitch: blue
Heading: green
```

**원문**  
단, GUI 전체 사이즈 변경시 동기되서 변경되어야 

**검토 결과 / 답변**  
맞습니다. gauge indicator는 고정 pixel 크기만 쓰면 안 되고, panel resize 시 반지름에 맞춰 재계산되어야 합니다.

권장 구조:

```text
onPanelResize 또는 refreshLayout:
- gauge radius 재계산
- triangle size 재계산
- indicator 위치 재계산
- redraw
```

---

## 종합 우선순위

### P0: 즉시 수정 권장

```text
1. 실제 option1.dat / CSV header mapping 호환
2. standalone FlightDataDashboard와 Studio embedded Dashboard UI 통합
3. cleanupHandleProperty 문법 및 handle array cleanup 안정화
4. mouse drag/cursor 고착 방지 forceEndAllDrag 추가
```

### P1: UX 핵심 개선

```text
5. video slider ValueChangingFcn 기반 실시간 preview
6. data plot slider 추가
7. synced data/video frame conversion 정리
8. FPS metadata 계산/표시 오류 확인
```

### P2: 화면 구성 / 시인성

```text
9. 버튼/editbox fixed width 적용
10. Session 초기 표시 panel 단순화
11. 로드된 파일명 표시
12. panel title/frame label 색상 theme 정리
13. gauge indicator 크기/색 개선
```

### P3: 도구창 / 분석 기능 구체화

```text
14. Manager/Detail/ROI/Analyzer를 RightDock tab 중심으로 정리
15. 보조 figure bring-to-front 정책 구현
16. ROI mode 안내/상태 머신 충돌 방지
17. Range 버튼 구현 또는 disabled 처리
```

---

## 최종 결론

자동 테스트가 모두 통과했다면 구조적 안정성은 상당히 개선된 상태입니다. 그러나 `260513_gui(1).log`의 내용은 실제 사용 시 드러나는 UX와 데이터 호환성 문제를 보여줍니다.

가장 먼저 해결해야 할 항목은 다음 4개입니다.

```text
1. 실제 option1.dat와 CSV header mapping 문제
2. standalone Dashboard와 Studio embedded Dashboard의 UI 불일치
3. video slider drag 중 실시간 frame preview 부재
4. mouse drag/cursor 고착 문제
```

이 네 가지를 먼저 안정화한 뒤, Manager/Detail/ROI/Analyzer 정리와 시인성 개선을 진행하는 것이 가장 안전합니다.
