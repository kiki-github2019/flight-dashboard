==================================================
  FlightReviewStudio ALL TEST CODES WITH CLEANUP
==================================================


--- RUN: FlightReviewStudioTestSuite/test_T1_Shell_CreateDelete [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T1_Shell_CreateDelete ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T2_Model_RoundTrip [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T2_Model_RoundTrip ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3_Embedded_AddRemove [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3_Embedded_AddRemove ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3b_UndoRedo_Service_Isolation [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3b_UndoRedo_Service_Isolation ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3c_UndoRedo_MaxHistory_And_CommandNoop [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3c_UndoRedo_MaxHistory_And_CommandNoop ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3d_UndoRedo_UiStateAndHistoryBinding [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_T3d_UndoRedo_UiStateAndHistoryBinding이(가) 필터링되었습니다.
    테스트 진단: Dashboard UndoService was not injected.
세부 정보
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                                    Failed  Incomplete  이유
    ================================================================================================================================
     FlightReviewStudioTestSuite/test_T3d_UndoRedo_UiStateAndHistoryBinding              X       가정(Assumption)별로 필터링되었습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_T3d_UndoRedo_UiStateAndHistoryBinding ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3e_CloseSessionClearsUndoService [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_T3e_CloseSessionClearsUndoService에서 오류가 발생함. 그 결과, 실행이 완료되지 못했습니다.
    --------
    오류 ID:
    --------
    'MATLAB:noSuchMethodOrField'
    -------------
    오류 세부 정보:
    -------------
    'flightdash.FlightDataDashboard' 클래스에 대한 인식할 수 없는 메서드, 속성 또는 필드 'UndoService'입니다.
    
    오류 발생: FlightReviewStudioTestSuite/test_T3e_CloseSessionClearsUndoService (286번 라인)
                dash.UndoService.push(flightdash.test.CounterCommand(sid, target, 0, 1, 'Close Cleanup'), true);
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                                Failed  Incomplete  이유
    ===========================================================================================================
     FlightReviewStudioTestSuite/test_T3e_CloseSessionClearsUndoService    X         X       오류가 발생했습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_T3e_CloseSessionClearsUndoService ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3f_Mouse_CloseTabDuringDragDoesNotCrash [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3f_Mouse_CloseTabDuringDragDoesNotCrash ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3g_Mouse_TabSwitchDuringDragIsSuppressed [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3g_Mouse_TabSwitchDuringDragIsSuppressed ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3h_Mouse_MultiControllerDragIsolation [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3h_Mouse_MultiControllerDragIsolation ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3i_Mouse_RoiHoverHighlightingDoesNotCrash [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3i_Mouse_RoiHoverHighlightingDoesNotCrash ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3j_Mouse_RapidTabCreateCloseStress [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T3j_Mouse_RapidTabCreateCloseStress ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T3k_Mouse_StandaloneCompatibility [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_T3k_Mouse_StandaloneCompatibility에서 검증이 실패함.
    -----------
    테스트 진단:
    -----------
    Standalone dashboard should expose MouseRouter property for compatibility.
    --------------
    프레임워크 진단:
    --------------
    verifyTrue 결과: 실패.
    --> 테스트 결과값은 "true"여야 합니다.
    
    실제 값:
      logical
    
       0
    ---------
    스택 정보:
    ---------
    /MATLAB Drive/flightdashboard/FlightReviewStudioTestSuite.m의 434번 라인(FlightReviewStudioTestSuite.test_T3k_Mouse_StandaloneCompatibility)에서
================================================================================

================================================================================
FlightReviewStudioTestSuite/test_T3k_Mouse_StandaloneCompatibility에서 오류가 발생함. 그 결과, 실행이 완료되지 못했습니다.
    --------
    오류 ID:
    --------
    'MATLAB:noSuchMethodOrField'
    -------------
    오류 세부 정보:
    -------------
    'flightdash.FlightDataDashboard' 클래스에 대한 인식할 수 없는 메서드, 속성 또는 필드 'MouseRouter'입니다.
    
    오류 발생: FlightReviewStudioTestSuite/test_T3k_Mouse_StandaloneCompatibility (436번 라인)
                testCase.verifyEmpty(dash.MouseRouter, ...
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                                Failed  Incomplete  이유
    ===========================================================================================================================
     FlightReviewStudioTestSuite/test_T3k_Mouse_StandaloneCompatibility    X         X       검증(Verification)에서 실패했습니다.
                                                                                             오류가 발생했습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_T3k_Mouse_StandaloneCompatibility ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 
경고: "flightdash.FlightDataDashboard" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T4_Event_Isolation [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_T4_Event_Isolation이(가) 필터링되었습니다.
    테스트 진단: Session-scoped EventBus testing API was not found. Expected subscribeSession + publish, or verifyPhase4.
세부 정보
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                 Failed  Incomplete  이유
    =============================================================================================================
     FlightReviewStudioTestSuite/test_T4_Event_Isolation              X       가정(Assumption)별로 필터링되었습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_T4_Event_Isolation ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T5_Explorer_Selection [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_T5_Explorer_Selection이(가) 필터링되었습니다.
    테스트 진단: ProjectExplorer.selectSession/selectNode 메서드가 없습니다.
세부 정보
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                    Failed  Incomplete  이유
    ================================================================================================================
     FlightReviewStudioTestSuite/test_T5_Explorer_Selection              X       가정(Assumption)별로 필터링되었습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_T5_Explorer_Selection ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T6_Inspector_InvalidHandles [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_T6_Inspector_InvalidHandles이(가) 필터링되었습니다.
    테스트 진단: Inspector 객체를 찾을 수 없어 테스트를 건너뜁니다.
세부 정보
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                          Failed  Incomplete  이유
    ======================================================================================================================
     FlightReviewStudioTestSuite/test_T6_Inspector_InvalidHandles              X       가정(Assumption)별로 필터링되었습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_T6_Inspector_InvalidHandles ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T6_GuiMode_Persist [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T6_GuiMode_Persist ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T9_Save_Extension [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T9_Save_Extension ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T9_NonAscii_Path [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T9_NonAscii_Path ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_T9_Missing_External [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_T9_Missing_External ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_TStress_MultiSession_Scrub [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중
.
FlightReviewStudioTestSuite 완료
__________

--- CLEANUP after FlightReviewStudioTestSuite/test_TStress_MultiSession_Scrub ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: FlightReviewStudioTestSuite/test_TStress_UndoRedo_MultiSessionIsolation [FlightReviewStudioTestSuite] ---
FlightReviewStudioTestSuite 실행 중

================================================================================
FlightReviewStudioTestSuite/test_TStress_UndoRedo_MultiSessionIsolation에서 오류가 발생함. 그 결과, 실행이 완료되지 못했습니다.
    --------
    오류 ID:
    --------
    'MATLAB:noSuchMethodOrField'
    -------------
    오류 세부 정보:
    -------------
    'flightdash.FlightDataDashboard' 클래스에 대한 인식할 수 없는 메서드, 속성 또는 필드 'UndoService'입니다.
    
    오류 발생: FlightReviewStudioTestSuite/test_TStress_UndoRedo_MultiSessionIsolation (845번 라인)
                    dash.UndoService.push(flightdash.test.CounterCommand( ...
================================================================================
.
FlightReviewStudioTestSuite 완료
__________

실패 요약:

     Name                                                                     Failed  Incomplete  이유
    ================================================================================================================
     FlightReviewStudioTestSuite/test_TStress_UndoRedo_MultiSessionIsolation    X         X       오류가 발생했습니다.
--- CLEANUP after FlightReviewStudioTestSuite/test_TStress_UndoRedo_MultiSessionIsolation ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (30번 라인)에서 

--- RUN: flightdash.studio.FlightReviewStudioStressTests/testHighVolumeTabCreationAndDrag [FlightReviewStudioStressTests] ---
flightdash.studio.FlightReviewStudioStressTests 실행 중
.
flightdash.studio.FlightReviewStudioStressTests 완료
__________

--- CLEANUP after flightdash.studio.FlightReviewStudioStressTests/testHighVolumeTabCreationAndDrag ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (34번 라인)에서 

--- RUN: flightdash.studio.FlightReviewStudioStressTests/testRapidTabSwitchWhileDragging [FlightReviewStudioStressTests] ---
flightdash.studio.FlightReviewStudioStressTests 실행 중
.
flightdash.studio.FlightReviewStudioStressTests 완료
__________

--- CLEANUP after flightdash.studio.FlightReviewStudioStressTests/testRapidTabSwitchWhileDragging ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (34번 라인)에서 

--- RUN: flightdash.studio.FlightReviewStudioStressTests/testRandomMouseOperationsAcrossSessions [FlightReviewStudioStressTests] ---
flightdash.studio.FlightReviewStudioStressTests 실행 중
.
flightdash.studio.FlightReviewStudioStressTests 완료
__________

--- CLEANUP after flightdash.studio.FlightReviewStudioStressTests/testRandomMouseOperationsAcrossSessions ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (34번 라인)에서 

--- RUN: flightdash.studio.FlightReviewStudioStressTests/testDragAfterStudioCloseRequest [FlightReviewStudioStressTests] ---
flightdash.studio.FlightReviewStudioStressTests 실행 중
.
flightdash.studio.FlightReviewStudioStressTests 완료
__________

--- CLEANUP after flightdash.studio.FlightReviewStudioStressTests/testDragAfterStudioCloseRequest ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (34번 라인)에서 

--- RUN: flightdash.studio.FlightReviewStudioStressTests/testMouseRouterCleanupOnStudioDelete [FlightReviewStudioStressTests] ---
flightdash.studio.FlightReviewStudioStressTests 실행 중
.
flightdash.studio.FlightReviewStudioStressTests 완료
__________

--- CLEANUP after flightdash.studio.FlightReviewStudioStressTests/testMouseRouterCleanupOnStudioDelete ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (34번 라인)에서 

--- RUN: flightdash.studio.FlightReviewStudioStressTests/testHoverDuringAsyncOperation [FlightReviewStudioStressTests] ---
flightdash.studio.FlightReviewStudioStressTests 실행 중
.
flightdash.studio.FlightReviewStudioStressTests 완료
__________

--- CLEANUP after flightdash.studio.FlightReviewStudioStressTests/testHoverDuringAsyncOperation ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (34번 라인)에서 

--- RUN: eventSystemTestSuite/testSessionScopedEventsDoNotLeak [eventSystemTestSuite] ---
eventSystemTestSuite 실행 중
.
eventSystemTestSuite 완료
__________

--- CLEANUP after eventSystemTestSuite/testSessionScopedEventsDoNotLeak ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (38번 라인)에서 

--- RUN: eventSystemTestSuite/testBroadcastEventsReachAllSessions [eventSystemTestSuite] ---
eventSystemTestSuite 실행 중
.
eventSystemTestSuite 완료
__________

--- CLEANUP after eventSystemTestSuite/testBroadcastEventsReachAllSessions ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (38번 라인)에서 

--- RUN: eventSystemTestSuite/testEventAfterSessionListenerCleanupIsIgnored [eventSystemTestSuite] ---
eventSystemTestSuite 실행 중
.
eventSystemTestSuite 완료
__________

--- CLEANUP after eventSystemTestSuite/testEventAfterSessionListenerCleanupIsIgnored ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (38번 라인)에서 

--- RUN: eventSystemTestSuite/testSubscribeForAppUsesEmbeddedSession [eventSystemTestSuite] ---
eventSystemTestSuite 실행 중
.
eventSystemTestSuite 완료
__________

--- CLEANUP after eventSystemTestSuite/testSubscribeForAppUsesEmbeddedSession ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (38번 라인)에서 

--- RUN: eventSystemTestSuite/testAcceptsSessionSemantics [eventSystemTestSuite] ---
eventSystemTestSuite 실행 중
.
eventSystemTestSuite 완료
__________

--- CLEANUP after eventSystemTestSuite/testAcceptsSessionSemantics ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (38번 라인)에서 

--- RUN: undoRedoTestSuite/testUndoRedoFunctionality [undoRedoTestSuite] ---
undoRedoTestSuite 실행 중
.
undoRedoTestSuite 완료
__________

--- CLEANUP after undoRedoTestSuite/testUndoRedoFunctionality ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 

--- RUN: undoRedoTestSuite/testUndoRedoCrossSessionIsolation [undoRedoTestSuite] ---
undoRedoTestSuite 실행 중
.
undoRedoTestSuite 완료
__________

--- CLEANUP after undoRedoTestSuite/testUndoRedoCrossSessionIsolation ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 

--- RUN: undoRedoTestSuite/testUndoAfterMultipleOperations [undoRedoTestSuite] ---
undoRedoTestSuite 실행 중
.
undoRedoTestSuite 완료
__________

--- CLEANUP after undoRedoTestSuite/testUndoAfterMultipleOperations ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 

--- RUN: undoRedoTestSuite/testUndoStackLimit [undoRedoTestSuite] ---
undoRedoTestSuite 실행 중
.
undoRedoTestSuite 완료
__________

--- CLEANUP after undoRedoTestSuite/testUndoStackLimit ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 

--- RUN: undoRedoTestSuite/testUndoStateChangedEventIsSessionScoped [undoRedoTestSuite] ---
undoRedoTestSuite 실행 중
.
undoRedoTestSuite 완료
__________

--- CLEANUP after undoRedoTestSuite/testUndoStateChangedEventIsSessionScoped ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 

--- RUN: undoRedoTestSuite/testUndoServiceInjectionViaStudio [undoRedoTestSuite] ---
undoRedoTestSuite 실행 중

================================================================================
undoRedoTestSuite/testUndoServiceInjectionViaStudio에서 검증이 실패함.
    -----------
    테스트 진단:
    -----------
    Embedded dashboard did not receive an UndoService.
    --------------
    프레임워크 진단:
    --------------
    verifyTrue 결과: 실패.
    --> 테스트 결과값은 "true"여야 합니다.
    
    실제 값:
      logical
    
       0
    ---------
    스택 정보:
    ---------
    /MATLAB Drive/flightdashboard/undoRedoTestSuite.m의 142번 라인(testUndoServiceInjectionViaStudio)에서
================================================================================
.
undoRedoTestSuite 완료
__________

실패 요약:

     Name                                                 Failed  Incomplete  이유
    ============================================================================================================
     undoRedoTestSuite/testUndoServiceInjectionViaStudio    X                 검증(Verification)에서 실패했습니다.
--- CLEANUP after undoRedoTestSuite/testUndoServiceInjectionViaStudio ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 
경고: "flightdash.FlightDataDashboard" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup>runSuiteElements (91번 라인)에서
runAllTestCodesWithCleanup (42번 라인)에서 

--- RUN: verifyPhase0_5 [diagnostic] ---

=== Phase 0.5 verification: Encoding / Formatting Stabilization ===

TC       Result        Message
-------  ------------  -------
P0.5-1   PASS          Repository root resolved and 5 key files exist
P0.5-2   PASS          Root entry files are readable
P0.5-3   PASS          92 package .m files are readable
P0.5-4   PASS          No obvious one-line/comment-swallow formatting risk in key files
P0.5-5   PASS          9 key MATLAB files passed parse-smoke checkcode scan
P0.5-6   PASS          .gitattributes contains MATLAB text/LF normalization rule
P0.5-7   PASS          No common mojibake markers detected in 60 scanned .m files
P0.5-8   PASS          Entries resolved: FlightReviewStudio -> /MATLAB Drive/flightdashboard/FlightReviewStudio.m; FlightDataDashboard -> /MATLAB Drive/flightdashboard/FlightDataDashboard.m

8 / 8 Phase 0.5 checks passed.
--- CLEANUP after verifyPhase0_5 ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup (63번 라인)에서 

--- RUN: verifyPhase1 [diagnostic] ---

=== Phase 1 verification: Studio Shell ===

TC      Result        Message
------  ------------  -------
P1-1    PASS          flightdash.studio.FlightReviewStudioApp resolved
P1-2    PASS          FlightReviewStudioApp constructed successfully
P1-3    PASS          Top-level shell graphics handles exist
P1-4    PASS          Studio managers exist
P1-5    PASS          MenuManager created root menus: Help, Preferences, Window, Plot, Analysis, Review, Sync, Video, Data, Project, Edit, File
P1-6    PASS          ToolbarManager initialized; detected 23 uibutton objects
P1-7    PASS          ProjectExplorer initialized; detected 2 uitree objects
P1-8    PASS          Workspace initialized; detected 3 uitabgroup objects
P1-9    PASS          RightDock initialized; tabgroups=3, trees=2
P1-10   PASS          StatusBar initialized; detected 23 uilabel objects
P1-11   PASS          Studio MouseRouter exists
P1-12   PASS          Studio delete closes UIFigure cleanly

12 / 12 Phase 1 checks passed.
--- CLEANUP after verifyPhase1 ---
경고: "onCleanup" 클래스의 객체가 존재합니다.  이 클래스 또는 이 클래스의 슈퍼클래스를 지울 수 없습니다. 
> runAllTestCodesWithCleanup>cleanupEnvironment (243번 라인)
runAllTestCodesWithCleanup>runEntry (121번 라인)에서
runAllTestCodesWithCleanup (63번 라인)에서 
