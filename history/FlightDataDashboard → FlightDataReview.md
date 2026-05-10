아래는 업로드된 **OriginPro GUI 분석보고서**를 반영해 보완한 **최종 통합 계획서**입니다.
앞선 계획서의 “통합 Shell + Session Document + Shared Service” 구조를 유지하되, OriginPro의 핵심 GUI 설계 요소인 **Project Explorer, Object Manager, 상태 표시줄 통계, Analysis Dialog, Recalculate, Mini Toolbar, 역할 기반 GUI Mode, Command/Log/Result 시스템**을 FlightDataReviewStudio 설계에 추가했습니다. 업로드된 보고서는 OriginPro가 MDI 기반 프로젝트 구조, Project Explorer, Object Manager, 분석 대화상자, 자동 재계산, 로그 시스템, 역할 기반 GUI 모드 등을 통해 대규모 과학 데이터를 관리한다고 설명합니다. 

---

# FlightDataDashboard → FlightDataReviewStudio 전환 최종 보완 계획서

## 0. 최종 목표

현재 MATLAB `FlightDataDashboard`를 단일 대시보드 앱에서 **OriginPro식 프로젝트 기반 통합 GUI**로 전환한다.

최종 앱 이름은 다음으로 설정한다.

```text
FlightDataReviewStudio
```

최종 구조는 다음과 같다.

```text
FlightDataReviewStudio
 ├─ Project Explorer
 ├─ Object Manager
 ├─ Workspace Tab / MDI Area
 ├─ Property Inspector
 ├─ Analysis Dialog System
 ├─ Review Result Manager
 ├─ Command / Message / Result Log
 ├─ Status Bar with Live Summary
 ├─ Role-based GUI Mode
 ├─ Mini Toolbar
 ├─ SharedDecodeService
 ├─ SharedCacheService
 └─ Embedded FlightDataDashboard Document
```

핵심 전환 방향은 다음 한 문장으로 정리된다.

**FlightDataDashboard를 여러 개 독립 실행하는 것이 아니라, FlightDataReviewStudio라는 통합 프로젝트 Shell 안에서 각 FlightDataDashboard를 하나의 Review Session Document로 삽입·관리하고, 그래프·ROI·동기화·리뷰 결과·로그·분석 결과를 프로젝트 단위로 저장한다.**

---

# 1. OriginPro 분석보고서 반영 사항

업로드 보고서에서 FlightDataReviewStudio 설계에 반드시 반영해야 할 OriginPro GUI 핵심은 다음이다.

## 1.1 MDI 기반 프로젝트 구조

OriginPro는 `.OPJ` 또는 `.OPJU` 프로젝트 안에서 워크북, 그래프, 행렬, 이미지, 노트, 레이아웃 등 여러 하위 창을 관리하는 MDI 구조를 사용한다. 

FlightDataReviewStudio에서는 이를 다음처럼 치환한다.

| OriginPro        | FlightDataReviewStudio               |
| ---------------- | ------------------------------------ |
| Project          | Review Project                       |
| Workbook         | Flight Data Session                  |
| Graph Window     | Plot / Comparison Figure             |
| Image Window     | Video Snapshot / Video Review Window |
| Note Window      | Review Note / Analysis Report        |
| Layout Window    | Report Layout / Export Layout        |
| Project Explorer | FlightDataDashboard Explorer         |

## 1.2 Project Explorer

OriginPro의 Project Explorer는 폴더 트리와 선택 폴더의 하위 창 목록을 통해 대형 프로젝트를 관리한다. 창 이름 변경, 이동, 숨김/표시, 검색 기능을 제공한다. 

FlightDataReviewStudio에는 다음 기능을 넣는다.

```text
FlightDataDashboard Explorer
 ├─ Project
 ├─ Sessions
 ├─ Flight Data
 ├─ Videos
 ├─ Graphs
 ├─ ROI Results
 ├─ Sync Results
 ├─ Snapshots
 ├─ Reports
 ├─ Notes
 └─ Logs
```

필수 기능:

```text
- 세션 추가
- 세션 복제
- 세션 이름 변경
- 세션 삭제
- 세션 폴더 이동
- Graph/Result/Report 숨김 또는 표시
- 키워드 검색
- 최근 사용 세션 표시
- 연결된 데이터/비디오 파일 상태 표시
```

## 1.3 Object Manager

OriginPro의 Object Manager는 현재 활성 창 내부의 레이어, 플롯, 텍스트, 시트 등 미시적 객체를 트리로 표시하고, 체크박스로 표시/숨김 및 일괄 스타일 변경을 지원한다. 

FlightDataReviewStudio에는 Project Explorer와 별도로 **Object Manager**를 둔다.

예:

```text
Object Manager - Active Dashboard
 ├─ Flight 1
 │  ├─ Map
 │  ├─ Altitude Plot
 │  ├─ Video Panel
 │  ├─ Current Marker
 │  ├─ ROI Bands
 │  └─ Event Markers
 ├─ Flight 2
 │  ├─ Map
 │  ├─ Altitude Plot
 │  ├─ Video Panel
 │  ├─ Current Marker
 │  ├─ ROI Bands
 │  └─ Event Markers
 └─ Graph Layers
    ├─ Layer 1
    │  ├─ Altitude
    │  ├─ Roll
    │  └─ Pitch
    └─ Layer 2
       └─ Heading
```

필수 기능:

```text
- 객체 표시/숨김 체크박스
- ROI band 표시/숨김
- 특정 plot line 선택
- marker 선택
- layer 선택
- 복수 plot 일괄 스타일 변경
- 선택 객체를 Property Inspector에 전달
```

이 항목은 앞선 계획서에 부족했던 중요한 보완점이다.

## 1.4 상태 표시줄 + 실시간 요약 통계

OriginPro의 상태 표시줄은 현재 활성 창, 자동 업데이트 상태, 각도 단위, 메시지, 선택 데이터의 평균/합계/개수 등 요약 통계를 표시한다. 

FlightDataReviewStudio의 Status Bar는 단순 상태 문구가 아니라 **실시간 리뷰 요약 패널**이 되어야 한다.

표시 항목:

```text
Project: ReviewProject_001
Active Session: Session_003
Active Channel: Flight 1
Current Time: 123.450 s
Current Frame: 8642
Video Sync: ON / OFF
Flight Sync: ON / OFF
Auto Update: ON / OFF
Selected ROI: 12.5 s ~ 18.7 s
Selected Data Summary: mean, min, max, count
Decode Queue: idle / running / pending
Error Count: 0
```

데이터 테이블 또는 ROI 범위 선택 시:

```text
Mean
Min
Max
Std
Count
Duration
Frame Count
```

를 실시간 표시한다.

## 1.5 Analysis Dialog System

OriginPro의 분석 도구는 `Input Data`, `Settings`, `Output` 노드를 가진 일관된 분석 대화상자 구조를 사용하고, 설정값을 Dialog Theme로 저장해 반복 분석을 표준화한다. 

FlightDataReviewStudio도 단순 버튼 실행이 아니라 다음 구조의 분석 대화상자를 가져야 한다.

```text
Analysis Dialog
 ├─ Input
 │  ├─ Session
 │  ├─ Channel
 │  ├─ Time Range
 │  ├─ Frame Range
 │  └─ Variables
 ├─ Settings
 │  ├─ Filter
 │  ├─ Smoothing
 │  ├─ Threshold
 │  ├─ Sync Offset Option
 │  └─ Plot Option
 ├─ Output
 │  ├─ Result Table
 │  ├─ Graph
 │  ├─ ROI Result
 │  ├─ Report Note
 │  └─ Export File
 └─ Theme
    ├─ Save Theme
    ├─ Load Theme
    └─ Set Default
```

적용 대상:

```text
- ROI 통계 분석
- 비행 이벤트 검출
- Roll/Pitch/Yaw 변화율 분석
- Altitude 구간 분석
- 영상-데이터 동기 품질 분석
- 두 비행경로 비교
- 다중 세션 비교
- 필터링/평활화/FFT 등 신호 처리
```

## 1.6 자동 재계산 / Auto Update

OriginPro는 분석 결과와 원본 데이터를 동적으로 연결하고, 원본 데이터가 바뀌면 결과와 그래프를 자동 갱신하는 재계산 메커니즘을 제공한다. 

FlightDataReviewStudio도 다음 개념을 도입한다.

```text
Auto Update / Recalculate
 ├─ Manual
 ├─ Auto
 └─ Frozen
```

상태 의미:

```text
Manual:
    원본 데이터가 바뀌어도 사용자가 Recalculate를 눌러야 결과 갱신

Auto:
    데이터/동기/ROI/필터 설정 변경 시 결과 자동 갱신

Frozen:
    과거 리뷰 결과를 고정 보존
    원본 변경 시 stale warning만 표시
```

각 Result에는 다음 metadata를 저장한다.

```text
SourceSessionId
SourceDataHash
SourceVideoPath
SyncStateHash
AnalysisThemeId
CreatedAt
LastCalculatedAt
RecalculateMode
DirtyFlag
```

이 기능은 리뷰 결과의 신뢰성과 재현성을 위해 매우 중요하다.

## 1.7 Mini Toolbar

OriginPro는 축, 플롯, 텍스트 객체를 선택하면 커서 근처에 컨텍스트 기반 미니 도구 모음을 표시한다. 

MATLAB에서 완전 동일한 floating toolbar 구현은 부담이 크므로, 1차 구현은 다음과 같이 한다.

```text
Selection Mini Toolbar
 ├─ Plot 선택 시: show/hide, color, line width, export
 ├─ Axis 선택 시: xlim, ylim, auto scale, link axis
 ├─ ROI 선택 시: edit range, analyze, export, delete
 ├─ Marker 선택 시: jump, label, delete
 └─ Video 선택 시: snapshot, sync here, copy frame
```

구현 방식:

```text
초기 버전:
    오른쪽 Property Inspector 상단에 context quick action row 표시

후속 버전:
    선택 객체 위치 근처에 uipanel 형태의 floating mini toolbar 표시
```

## 1.8 역할 기반 GUI Mode

OriginPro 2025b의 Stats Mode처럼, 사용자 목적에 따라 메뉴와 toolbar를 단순화하는 구조를 도입한다. 

FlightDataReviewStudio GUI Mode:

```text
Review Mode
    비디오-데이터 동기, 재생, ROI, 이벤트 마커 중심

Analysis Mode
    통계, 필터링, FFT, 비교 분석, 결과 테이블 중심

Plot Mode
    그래프 생성, 축, 레이어, 스타일, export 중심

Report Mode
    노트, snapshot, 결과 요약, 보고서 생성 중심

Compact Mode
    노트북/작은 화면용 최소 UI
```

상단 메뉴:

```text
Preferences > GUI Mode
 ├─ Review Mode
 ├─ Analysis Mode
 ├─ Plot Mode
 ├─ Report Mode
 └─ Compact Mode
```

## 1.9 로그 시스템

OriginPro는 Message Log와 Result Log를 분리해 작업 이력, 오류, 분석 결과를 추적한다. 

FlightDataReviewStudio에는 다음 세 로그를 둔다.

```text
Message Log
    파일 로드, export, warning, UI operation

Error Log
    catch된 예외, stack, tag, session id

Result Log
    ROI 분석값, sync 품질, 이벤트 검출 결과, 통계 결과
```

Explorer에는 다음처럼 표시한다.

```text
Logs
 ├─ Message Log
 ├─ Error Log
 └─ Result Log
```

---

# 2. 최종 UI 구조

## 2.1 전체 레이아웃

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Title Bar: FlightDataReviewStudio - ProjectName - FolderPath               │
├────────────────────────────────────────────────────────────────────────────┤
│ Menu: File Project Data Video Sync Review Analysis Plot Window Help         │
├────────────────────────────────────────────────────────────────────────────┤
│ Toolbar: New Open Save | Load Sync Play ROI Analyze Graph Export Report     │
├──────────────────┬───────────────────────────────────────┬────────────────┤
│ Project Explorer │ Workspace Tabs                         │ Inspector      │
│                  │ Dashboard | Graph | Result | Report    │ Object Manager │
│                  │                                       │ Mini Toolbar   │
│                  │ Embedded FlightDataDashboard           │ Properties     │
│                  │ Graph Window                           │                │
│                  │ Result Table                           │                │
│                  │ Note / Report                          │                │
├──────────────────┴───────────────────────────────────────┴────────────────┤
│ Status Bar: active session | time | frame | ROI stats | AU | queue | errors │
└────────────────────────────────────────────────────────────────────────────┘
```

## 2.2 오른쪽 패널 구성

오른쪽 패널은 탭으로 구성한다.

```text
Right Dock Panel
 ├─ Inspector
 ├─ Object Manager
 ├─ Apps / Tools
 └─ Logs
```

이 구조가 좋은 이유:

```text
- Project Explorer는 프로젝트 전체를 관리
- Object Manager는 현재 활성 창 내부 객체를 관리
- Inspector는 선택 객체의 속성을 편집
- Logs는 분석/오류/작업 결과를 추적
```

---

# 3. 최종 아키텍처

## 3.1 신규 폴더 구조

```text
root/
├─ FlightReviewStudio.m
├─ FlightDataDashboard.m
├─ asyncDecodeFrame.m
├─ asyncDecodeFramePersistent.m
├─ cleanupAsyncDecodeCache.m
│
└─ +flightdash/
   ├─ FlightDataDashboard.m
   │
   ├─ +studio/
   │  ├─ FlightReviewStudioApp.m
   │  ├─ ProjectExplorerPanel.m
   │  ├─ WorkspaceManager.m
   │  ├─ ToolbarManager.m
   │  ├─ MenuManager.m
   │  ├─ StatusBarManager.m
   │  ├─ RightDockManager.m
   │  ├─ PropertyInspector.m
   │  ├─ ObjectManagerPanel.m
   │  ├─ MiniToolbarManager.m
   │  ├─ LogPanel.m
   │  └─ GuiModeManager.m
   │
   ├─ +project/
   │  ├─ ProjectModel.m
   │  ├─ SessionModel.m
   │  ├─ FigureModel.m
   │  ├─ ReviewResultModel.m
   │  ├─ AnalysisThemeModel.m
   │  ├─ ProjectSerializer.m
   │  ├─ ProjectPathResolver.m
   │  └─ ProjectDirtyTracker.m
   │
   ├─ +analysis/
   │  ├─ AnalysisDialog.m
   │  ├─ AnalysisRequest.m
   │  ├─ AnalysisResult.m
   │  ├─ RoiStatisticsAnalyzer.m
   │  ├─ SyncQualityAnalyzer.m
   │  ├─ EventDetector.m
   │  ├─ SignalProcessingAnalyzer.m
   │  └─ AnalysisThemeManager.m
   │
   ├─ +service/
   │  ├─ SharedDecodeService.m
   │  ├─ SharedCacheService.m
   │  ├─ SessionEventRouter.m
   │  ├─ ReviewResultService.m
   │  ├─ AutoUpdateService.m
   │  ├─ LogService.m
   │  └─ ProjectCommandService.m
   │
   ├─ +controller/
   ├─ +model/
   ├─ +view/
   └─ +util/
```

---

# 4. 핵심 모델 설계

## 4.1 ProjectModel

```text
ProjectModel
 ├─ ProjectId
 ├─ ProjectName
 ├─ ProjectFilePath
 ├─ ProjectFolderPath
 ├─ CreatedAt
 ├─ ModifiedAt
 ├─ Sessions[]
 ├─ Figures[]
 ├─ Results[]
 ├─ Notes[]
 ├─ Reports[]
 ├─ AnalysisThemes[]
 ├─ GlobalSettings
 ├─ GuiMode
 ├─ AutoUpdateMode
 ├─ MessageLog
 ├─ ErrorLog
 ├─ ResultLog
 └─ DirtyFlag
```

## 4.2 SessionModel

```text
SessionModel
 ├─ SessionId
 ├─ DisplayName
 ├─ FolderPath
 ├─ FlightFilePath{1,2}
 ├─ VideoFilePath{1,2}
 ├─ FlightSyncState
 ├─ VideoSyncState{1,2}
 ├─ CurrentIndex{1,2}
 ├─ CurrentFrame{1,2}
 ├─ PlotTabs
 ├─ RoiRows
 ├─ EventMarkers
 ├─ ReviewNotes
 ├─ PanelVisible
 ├─ LayoutState
 ├─ AutoUpdateMode
 ├─ LastDataHash
 ├─ LastSyncHash
 └─ DirtyFlag
```

## 4.3 FigureModel

```text
FigureModel
 ├─ FigureId
 ├─ SourceSessionId
 ├─ FigureType
 │   ├─ Dashboard
 │   ├─ Graph
 │   ├─ ComparisonGraph
 │   ├─ ROIResult
 │   ├─ VideoSnapshot
 │   ├─ Layout
 │   └─ Report
 ├─ Title
 ├─ Layers[]
 ├─ Variables
 ├─ AxisSettings
 ├─ StyleSettings
 ├─ ViewState
 ├─ ExportPath
 ├─ RecalculateMode
 └─ DirtyFlag
```

## 4.4 ReviewResultModel

```text
ReviewResultModel
 ├─ ResultId
 ├─ SessionId
 ├─ ResultType
 │   ├─ ROI
 │   ├─ Event
 │   ├─ SyncCheck
 │   ├─ Snapshot
 │   ├─ Statistics
 │   └─ Comment
 ├─ ChannelIdx
 ├─ TimeRange
 ├─ FrameRange
 ├─ Variables
 ├─ ComputedValues
 ├─ UserComment
 ├─ LinkedFigureId
 ├─ SourceDataHash
 ├─ SyncStateHash
 ├─ AnalysisThemeId
 ├─ RecalculateMode
 ├─ DirtyFlag
 ├─ CreatedAt
 └─ LastCalculatedAt
```

## 4.5 AnalysisThemeModel

OriginPro의 Dialog Theme 개념을 반영한다.

```text
AnalysisThemeModel
 ├─ ThemeId
 ├─ ThemeName
 ├─ AnalysisType
 ├─ InputDefaults
 ├─ Settings
 ├─ OutputOptions
 ├─ CreatedAt
 └─ IsDefault
```

---

# 5. 기존 FlightDataDashboard 필수 수정

## 5.1 Embedded Document화

`FlightDataDashboard`는 standalone과 embedded 양쪽을 모두 지원해야 한다.

```matlab
FlightDataDashboard()
```

기존 단독 실행.

```matlab
flightdash.FlightDataDashboard(parentContainer, sessionId)
```

Studio workspace 탭 내부 실행.

필수 속성:

```matlab
properties
    RootContainer
    IsEmbedded = false
    ProjectId
    SessionId
    WindowId
end
```

필수 변경:

```text
- 생성자에서 parentContainer 수용
- parentContainer가 있으면 uifigure 생성 금지
- createLayout은 RootContainer 기준으로 UI 생성
- delete(app)는 embedded mode에서 parent tab 삭제 금지
- close(findobj(...)) 방식 제거 또는 standalone mode에서만 제한
```

## 5.2 EventBus Session Scope

모든 이벤트는 다음 정보를 포함한다.

```text
ProjectId
SessionId
WindowId
ChannelIdx
Payload
```

모든 listener 최상단:

```matlab
if ~strcmp(eventData.SessionId, obj.SessionId)
    return;
end
```

## 5.3 SharedDecodeService

각 Dashboard가 직접 `parfeval`을 소유하지 않도록 한다.

```text
SharedDecodeService
 ├─ AsyncPool
 ├─ DecodeRequestQueue
 ├─ ActiveSessionPriority
 ├─ LatestFrameOnlyPolicy
 ├─ FutureCancelPolicy
 ├─ WorkerCleanup
 └─ ResultCallbackRouter
```

## 5.4 SharedCacheService

```text
SharedCacheService
 ├─ GlobalBudgetMB
 ├─ SessionBudgetMB
 ├─ ActiveSessionWeight
 ├─ BackgroundEviction
 ├─ FrameCacheRegistry
 └─ MemoryPressureHandler
```

---

# 6. Menu / Toolbar 최종 구성

## 6.1 Menu

```text
File
 ├─ New Project
 ├─ Open Project
 ├─ Save Project
 ├─ Save Project As
 ├─ Pack Project
 ├─ Import Session Config
 ├─ Export Session Config
 └─ Exit

Project
 ├─ Add Review Session
 ├─ Duplicate Session
 ├─ Rename Session
 ├─ Delete Session
 ├─ Find in Project
 ├─ Project Properties
 └─ Cleanup Project Cache

Data
 ├─ Load Flight 1 Data
 ├─ Load Flight 2 Data
 ├─ Load Coastline
 ├─ Column Mapping
 ├─ Validate Data
 ├─ Estimate Data FPS
 └─ Show Data Summary

Video
 ├─ Load Video 1
 ├─ Load Video 2
 ├─ Clear Video
 ├─ Clear Video Cache
 ├─ Snapshot Current Frame
 ├─ Decode Settings
 └─ Video Metadata

Sync
 ├─ Flight Time Sync
 ├─ Video Data Sync
 ├─ Reset Flight Sync
 ├─ Reset Video Sync
 ├─ Sync Offset Editor
 └─ Sync Quality Check

Review
 ├─ Add ROI
 ├─ Add Event Marker
 ├─ Save Review Result
 ├─ Compare Sessions
 ├─ Export Review Table
 └─ Generate Review Report

Analysis
 ├─ ROI Statistics
 ├─ Event Detection
 ├─ Sync Quality Analysis
 ├─ Signal Filtering
 ├─ Smoothing
 ├─ FFT
 ├─ Compare Sessions
 ├─ Analysis Themes
 └─ Recalculate

Plot
 ├─ New Graph
 ├─ New Comparison Graph
 ├─ Add Selected Variable
 ├─ Object Manager
 ├─ Plot Details
 ├─ Axis Settings
 ├─ Link Axes
 ├─ Export Figure
 └─ Copy Figure

Window
 ├─ Tile Horizontally
 ├─ Tile Vertically
 ├─ Cascade
 ├─ Close Active Tab
 ├─ Close All Tabs
 ├─ Show Project Explorer
 ├─ Show Object Manager
 └─ Show Logs

Preferences
 ├─ GUI Mode
 │  ├─ Review Mode
 │  ├─ Analysis Mode
 │  ├─ Plot Mode
 │  ├─ Report Mode
 │  └─ Compact Mode
 ├─ Auto Update Mode
 ├─ Toolbar Customize
 └─ Shortcut Settings

Help
 ├─ Shortcut Guide
 ├─ Learning Samples
 ├─ Error Log
 └─ About
```

## 6.2 Toolbar

```text
[New] [Open] [Save]
[Add Session]
[Load Data] [Load Video]
[Sync] [Sync Quality]
[Play] [Stop] [Prev] [Next]
[ROI] [Marker]
[Analyze] [Recalculate]
[New Graph] [Export]
[Report]
[Explorer] [Object Manager] [Logs]
```

Toolbar 명령은 항상 현재 활성 탭의 `SessionId` 기준으로 실행한다.

---

# 7. Analysis Dialog 설계

## 7.1 공통 구조

```text
Analysis Dialog
 ├─ Input Data
 │  ├─ Session
 │  ├─ Channel
 │  ├─ Source: Full Data / ROI / Selected Range
 │  ├─ Time Range
 │  ├─ Frame Range
 │  └─ Variables
 ├─ Settings
 │  ├─ Analysis Parameters
 │  ├─ Thresholds
 │  ├─ Filter Options
 │  ├─ Sync Options
 │  └─ Plot Options
 ├─ Output
 │  ├─ Create Result Table
 │  ├─ Create Graph
 │  ├─ Add to Result Log
 │  ├─ Add to Report
 │  └─ Export File
 ├─ Recalculate
 │  ├─ Manual
 │  ├─ Auto
 │  └─ Frozen
 └─ Theme
    ├─ Save Theme
    ├─ Load Theme
    └─ Set as Default
```

## 7.2 분석 기능 우선순위

1차 구현:

```text
- ROI Statistics
- Sync Quality Analysis
- Event Marker Summary
- Selected Range Summary
- Session Comparison
```

2차 구현:

```text
- Smoothing
- Filtering
- FFT
- Derivative / Rate of Change
- Outlier Detection
```

3차 구현:

```text
- 자동 이벤트 검출
- 다중 세션 batch 분석
- 리포트 자동 생성
```

---

# 8. Auto Update / Recalculate 설계

## 8.1 Recalculate Mode

```text
Manual
    사용자가 Recalculate를 눌렀을 때만 결과 갱신

Auto
    원본 데이터, ROI, sync, analysis setting 변경 시 자동 갱신

Frozen
    결과 고정
    원본 변경 시 stale warning만 표시
```

## 8.2 Dirty Tracking

변경 감지 대상:

```text
- Flight data path
- Flight data hash
- Video path
- Video metadata
- VideoSyncState
- FlightSyncState
- ROI range
- Analysis settings
- Plot settings
```

Dirty 상태 표시:

```text
Explorer node에 * 표시
Result node에 stale icon 표시
Status bar에 "Result outdated" 표시
```

---

# 9. 로그 시스템 설계

## 9.1 Message Log

기록 대상:

```text
- project open/save
- data load
- video load
- export
- analysis start/end
- recalculate
- snapshot
```

## 9.2 Error Log

기록 대상:

```text
- MATLAB exception
- VideoReader 실패
- parfeval 실패
- sync 복원 실패
- config import 실패
```

필드:

```text
Time
ProjectId
SessionId
Tag
Message
Identifier
Stack
```

## 9.3 Result Log

기록 대상:

```text
- ROI mean/min/max/std
- sync quality score
- detected events
- comparison result
- export path
```

---

# 10. 단계별 마이그레이션 로드맵

## Phase 0: 기존 Dashboard 안정화

Studio 전환 전에 기존 코드의 치명적인 상태 불일치를 먼저 줄인다.

작업:

```text
1. decodeFrameSync의 sequential readFrame path 안전화
2. requestFrame의 IsDecoding 중 pending request 소실 방지
3. restoreVideoSyncStateFromConfig에서 SyncMdl anchor 복원
4. TotalFrames 계산 실패 시 max(1,totalFrames)로 정상화하지 않기
5. cleanupVideoResources에서 VideoFilePath 명확히 초기화
6. silent catch 최소화 및 LogService 연결 준비
```

완료 기준:

```text
- 빠른 video scrubbing 후 label frame과 실제 frame 일치
- config import 후 video-data sync 정상 복원
- close 시 future, VideoReader, worker cache hang 없음
```

## Phase 1: Studio Shell 신설

신규 파일:

```text
FlightReviewStudio.m
+flightdash/+studio/FlightReviewStudioApp.m
+flightdash/+studio/ProjectExplorerPanel.m
+flightdash/+studio/WorkspaceManager.m
+flightdash/+studio/RightDockManager.m
+flightdash/+studio/PropertyInspector.m
+flightdash/+studio/ObjectManagerPanel.m
+flightdash/+studio/StatusBarManager.m
+flightdash/+studio/ToolbarManager.m
+flightdash/+studio/MenuManager.m
```

작업:

```text
- uifigure 생성
- title bar 정보 갱신 구조 준비
- menu/toolbar 생성
- left project explorer 생성
- center workspace tabgroup 생성
- right dock panel 생성
- status bar 생성
```

완료 기준:

```text
FlightReviewStudio() 실행 시 OriginPro식 Shell 표시
Project Explorer, Workspace, Inspector/Object Manager, Status Bar 표시
```

## Phase 2: Project / Session Model 추가

신규 파일:

```text
+flightdash/+project/ProjectModel.m
+flightdash/+project/SessionModel.m
+flightdash/+project/FigureModel.m
+flightdash/+project/ReviewResultModel.m
+flightdash/+project/AnalysisThemeModel.m
```

완료 기준:

```text
Add Session 시 ProjectModel.Sessions에 SessionModel 추가
Explorer tree가 ProjectModel 기준으로 갱신
```

## Phase 3: FlightDataDashboard Embedded화

작업:

```text
- parentContainer, sessionId 생성자 인자 추가
- RootContainer, IsEmbedded, ProjectId, SessionId, WindowId 추가
- standalone mode 유지
- embedded mode에서 uifigure 생성 금지
- embedded mode에서 parent tab 삭제 금지
```

완료 기준:

```text
FlightDataDashboard() 기존 단독 실행 가능
FlightReviewStudio에서 Session tab 안에 Dashboard 삽입 가능
Dashboard tab 2개 이상 열어도 충돌 없음
```

## Phase 4: Event Scope / Session Router

작업:

```text
- AppEventData 확장
- SessionEventRouter 추가
- 모든 publish에 SessionId 포함
- 모든 listener에 SessionId guard 추가
- active tab 기준 command routing
```

완료 기준:

```text
Dashboard_001 Play 시 Dashboard_002 미동작
Sync 변경이 다른 세션에 전파되지 않음
```

## Phase 5: Project Explorer + Object Manager 완성

Project Explorer 기능:

```text
- 세션 추가/삭제/복제/이름 변경
- Graph/Result/Report 표시
- 검색 기능
- node context menu
```

Object Manager 기능:

```text
- active dashboard 내부 객체 표시
- plot/layer/ROI/marker show-hide
- 선택 객체와 Inspector 연동
```

완료 기준:

```text
Explorer는 프로젝트 전체 객체 관리
Object Manager는 현재 활성 창 내부 객체 관리
```

## Phase 6: Toolbar / Menu / Inspector / Mini Toolbar 연결

작업:

```text
- Load Data/Video, Sync, Play, ROI, Analyze, Graph, Export command 연결
- Inspector에서 선택 객체 속성 편집
- MiniToolbarManager 1차 구현
- GUI Mode별 toolbar 표시 변경
```

완료 기준:

```text
Toolbar 명령이 active session에만 적용
선택 객체에 따라 Inspector 내용 변경
Review/Analysis/Plot/Report mode 전환 가능
```

## Phase 7: Analysis Dialog / Theme / Result Model

작업:

```text
- AnalysisDialog 공통 UI 구현
- ROI Statistics Analyzer
- SyncQualityAnalyzer
- AnalysisTheme 저장/불러오기
- AnalysisResult를 ReviewResultModel로 저장
```

완료 기준:

```text
ROI 분석 결과가 Results 아래 저장
분석 테마 저장 후 재사용 가능
Result Log에 수치 결과 기록
```

## Phase 8: Auto Update / Recalculate

작업:

```text
- AutoUpdateService 추가
- SourceDataHash, SyncStateHash 계산
- DirtyFlag 관리
- Manual/Auto/Frozen mode 구현
- stale result 표시
```

완료 기준:

```text
ROI 변경 시 Auto mode 결과 자동 갱신
Frozen 결과는 변경되지 않고 stale warning 표시
```

## Phase 9: Project Save / Load

작업:

```text
- ProjectSerializer 구현
- *.frsproj 저장
- ProjectModel 전체 저장
- Session/Figure/Result/Theme/Log 저장
- 상대 경로 처리
- Pack Project 옵션 준비
```

완료 기준:

```text
프로젝트 저장 후 MATLAB 종료 가능
다시 열면 Explorer, Session, ROI, Graph, Result, Theme 복원
```

## Phase 10: SharedDecodeService / SharedCacheService

작업:

```text
- Dashboard 직접 parfeval 호출 제거
- DecodeRequestQueue 중앙화
- active tab priority 적용
- scrubbing 중 stale future cancel
- Global cache budget 적용
- background session cache 우선 evict
```

완료 기준:

```text
여러 Dashboard가 열려도 parpool 하나만 사용
빠른 scrubbing 중 오래된 요청 cancel
앱 종료 시 worker persistent VideoReader 정리

# 11. 최종 보완 요약

이전 계획서 대비 추가·보완된 핵심은 다음입니다.

```text
1. Project Explorer와 Object Manager를 분리
2. Status Bar를 실시간 요약 통계/상태 대시보드로 확장
3. Analysis Dialog System 추가
4. Analysis Theme 저장/재사용 추가
5. Auto Update / Recalculate / Frozen 결과 개념 추가
6. Message Log / Error Log / Result Log 분리
7. Mini Toolbar 또는 Context Quick Action 추가
8. GUI Mode: Review / Analysis / Plot / Report / Compact 추가
9. ReviewResultModel에 SourceDataHash, SyncStateHash, DirtyFlag 추가
10. Project 저장 범위에 Theme, Log, Result, Report까지 포함
```

최종적으로, 이 전환은 단순히 “GUI를 OriginPro처럼 보이게 바꾸는 작업”이 아니라 다음과 같은 구조적 재설계입니다.

**FlightDataDashboard를 OriginPro의 Workbook/Graph처럼 프로젝트 내부 문서로 격하하고, FlightDataReviewStudio가 프로젝트·창·객체·분석·결과·로그·비디오 디코딩·캐시를 중앙에서 관리하는 과학 데이터 리뷰 플랫폼으로 전환하는 작업입니다.**
