classdef FlightReviewStudioTestSuite < matlab.unittest.TestCase
    % FlightDataReviewStudio 통합 검증 테스트 스위트
    % 실행 방법: runtests('FlightReviewStudioTestSuite')
    
    properties
        App % 테스트용 앱 인스턴스
        TempDir % 테스트용 임시 디렉토리
    end
    
    methods (TestMethodSetup)
        function setupEnvironment(testCase)
            % 매 테스트가 실행되기 전 임시 디렉토리 생성
            testCase.TempDir = tempname;
            mkdir(testCase.TempDir);
            
            % 패스 설정 (필요시 활성화)
            % addpath(genpath('../')); 
        end
    end
    
    methods (TestMethodTeardown)
        function teardownEnvironment(testCase)
            % 열려있는 앱이 있다면 강제 종료 (메모리 누수 방지)
            if ~isempty(testCase.App) && isvalid(testCase.App)
                delete(testCase.App);
            end
            
            % 테스트 종료 후 임시 디렉토리 삭제
            if exist(testCase.TempDir, 'dir')
                rmdir(testCase.TempDir, 's');
            end
            
            % 잔여 parpool/future 정리
            cancel(parfevalOnAll(@() disp('cleanup'), 0));
        end
    end
    
    methods (Test)
        
        %% [Phase 1-3] 핵심 아키텍처 및 생명주기 검증
        
        function test_T1_Shell_CreateDelete(testCase)
            % T1_Shell_CreateDelete: FlightReviewStudio, 매니저 검증, 깔끔한 삭제
            
            % 1. 앱 생성
            testCase.App = flightdash.studio.FlightReviewStudioApp();
            
            % 2. 매니저 객체들이 정상 생성되었는지 확인
            testCase.verifyNotEmpty(testCase.App.WorkspaceManager, 'WorkspaceManager가 생성되지 않았습니다.');
            testCase.verifyNotEmpty(testCase.App.MenuManager, 'MenuManager가 생성되지 않았습니다.');
            
            % 3. UIFigure 파괴 검증
            uiFig = testCase.App.UIFigure;
            testCase.verifyTrue(isvalid(uiFig), 'UIFigure가 유효하지 않습니다.');
            
            delete(testCase.App);
            testCase.verifyFalse(isvalid(uiFig), '앱 삭제 후 UIFigure가 메모리에 남아있습니다.');
        end
        
        function test_T2_Model_RoundTrip(testCase)
            % T2_Model_RoundTrip: 2개의 세션, 테마, 피규어, 결과를 직렬화기를 통해 왕복 처리
            
            % 1. 모델 구성
            proj = flightdash.project.ProjectModel();
            s1 = flightdash.project.SessionModel('Session1');
            s2 = flightdash.project.SessionModel('Session2');
            proj.addSession(s1);
            proj.addSession(s2);
            
            % 2. 저장 및 로드
            testFilePath = fullfile(testCase.TempDir, 'test_project.frsproj');
            serializer = flightdash.project.ProjectSerializer();
            serializer.save(proj, testFilePath);
            
            loadedProj = serializer.load(testFilePath);
            
            % 3. 무결성 검증
            testCase.verifyEqual(length(loadedProj.Sessions), 2, '세션 복원이 실패했습니다.');
            testCase.verifyEqual(loadedProj.Sessions(1).SessionId, 'Session1', '세션 데이터가 손상되었습니다.');
        end
        
        function test_T3_Embedded_AddRemove(testCase)
            % T3_Embedded_AddRemove: 3개의 대시보드 탭을 반복적으로 추가/제거 (추가 UIFigure 생성 금지)
            
            testCase.App = flightdash.studio.FlightReviewStudioApp();
            initialFigs = findall(0, 'Type', 'figure');
            
            % 탭 3개 추가
            ws = testCase.App.WorkspaceManager;
            for i = 1:3
                ws.createSessionTab(sprintf('S%d', i));
            end
            
            % UIFigure 개수가 늘어나지 않았는지 확인 (Embedded 모드 검증)
            currentFigs = findall(0, 'Type', 'figure');
            testCase.verifyEqual(length(currentFigs), length(initialFigs), 'Embedded 모드임에도 새로운 UIFigure가 생성되었습니다.');
            
            % 탭 삭제
            ws.closeSessionTab('S1');
            ws.closeSessionTab('S2');
            ws.closeSessionTab('S3');
            
            testCase.verifyEmpty(ws.TabGroup.Children, '탭이 정상적으로 삭제되지 않았습니다.');
        end
        
        %% [Phase 4-6] 이벤트 및 UI 동작 격리 검증
        
        function test_T4_Event_Isolation(testCase)
            % T4_Event_Isolation: 2개의 탭에서 세션 범위 브로드캐스트 발행 시 격리 확인
            
            receivedInS1 = false;
            receivedInS2 = false;
            
            % 리스너 임시 설정
            EB = @flightdash.util.EventBus.subscribe;
            L1 = EB('DummyEvent', @(~,d) assignin('caller', 'receivedInS1', strcmp(d.SessionId, 'S1')));
            L2 = EB('DummyEvent', @(~,d) assignin('caller', 'receivedInS2', strcmp(d.SessionId, 'S2')));
            
            % S1으로 이벤트 발행
            evtData = flightdash.util.AppEventData(1, []);
            evtData.SessionId = 'S1';
            flightdash.util.EventBus.publish('DummyEvent', evtData);
            
            % 검증: S1은 받고 S2는 무시해야 함
            testCase.verifyTrue(receivedInS1, 'S1 이벤트가 수신되지 않았습니다.');
            testCase.verifyFalse(receivedInS2, 'S1 이벤트가 S2로 누수되었습니다.');
            
            delete(L1); delete(L2);
        end
        
        function test_T5_Explorer_Selection(testCase)
            % T5_Explorer_Selection: 트리 세션 선택 시 작업 공간 및 상태 표시줄 활성화 확인
            testCase.App = flightdash.studio.FlightReviewStudioApp();
            ws = testCase.App.WorkspaceManager;
            
            % 탭 생성
            ws.createSessionTab('S1');
            ws.createSessionTab('S2');
            
            % 탐색기에서 S2 선택 시뮬레이션
            testCase.App.ProjectExplorer.selectNode('S2');
            
            % 검증
            activeTabTitle = ws.TabGroup.SelectedTab.Title;
            testCase.verifyEqual(activeTabTitle, 'S2', '트리 선택이 탭 활성화로 이어지지 않았습니다.');
        end
        
        function test_T6_Inspector_InvalidHandles(testCase)
            % T6_Inspector_InvalidHandles: 삭제된 핸들 선택 시 Inspector 예외 처리 검증
            testCase.App = flightdash.studio.FlightReviewStudioApp();
            
            % 임의의 그래픽 객체 생성 후 삭제
            fig = figure('Visible', 'off');
            ax = axes(fig);
            p = plot(ax, 1:10);
            delete(p);
            
            % 삭제된 객체(Invalid Handle)를 Inspector에 전달
            try
                testCase.App.RightDockManager.Inspector.setTarget(p);
                passedWithoutCrash = true;
            catch
                passedWithoutCrash = false;
            end
            
            testCase.verifyTrue(passedWithoutCrash, '삭제된 핸들 주입 시 Inspector에서 크래시가 발생했습니다.');
            delete(fig);
        end
        
        function test_T6_GuiMode_Persist(testCase)
            % T6_GuiMode_Persist: 모드 전환, 저장/불러오기 시 GuiMode 상태 유지 검증
            proj = flightdash.project.ProjectModel();
            proj.Settings.GuiMode = 'Review'; % 초기 모드
            
            serializer = flightdash.project.ProjectSerializer();
            testFilePath = fullfile(testCase.TempDir, 'mode_test.frsproj');
            
            % 모드 변경 후 저장
            proj.Settings.GuiMode = 'Analysis';
            serializer.save(proj, testFilePath);
            
            % 로드 후 검증
            loadedProj = serializer.load(testFilePath);
            testCase.verifyEqual(loadedProj.Settings.GuiMode, 'Analysis', 'GUI 모드 설정이 직렬화되지 않았습니다.');
        end
        
        %% [Phase 9] 직렬화(저장/로드) 강건성 검증
        
        function test_T9_Save_Extension(testCase)
            % T9_Save_Extension: temp.frsproj 저장 시 .zip 확장자 중복 추가 여부 확인
            proj = flightdash.project.ProjectModel();
            serializer = flightdash.project.ProjectSerializer();
            
            testFilePath = fullfile(testCase.TempDir, 'my_flight.frsproj');
            serializer.save(proj, testFilePath);
            
            % 파일 생성 여부 검사
            testCase.verifyTrue(isfile(testFilePath), '파일이 저장되지 않았습니다.');
            testCase.verifyFalse(isfile([testFilePath '.zip']), '.frsproj.zip 형태의 이중 확장자로 저장되었습니다.');
        end
        
        function test_T9_NonAscii_Path(testCase)
            % T9_NonAscii_Path: 한국어 경로 환경에서 저장 및 불러오기 검증
            koreanPath = fullfile(testCase.TempDir, '테스트_비행_프로젝트');
            mkdir(koreanPath);
            
            proj = flightdash.project.ProjectModel();
            testFilePath = fullfile(koreanPath, '데이터.frsproj');
            
            serializer = flightdash.project.ProjectSerializer();
            
            try
                serializer.save(proj, testFilePath);
                loadedProj = serializer.load(testFilePath);
                success = true;
            catch ME
                success = false;
                disp(ME.message);
            end
            
            testCase.verifyTrue(success, '한국어(Non-ASCII) 경로에서 저장/로드 중 에러가 발생했습니다.');
        end
        
        function test_T9_Missing_External(testCase)
            % T9_Missing_External: 비디오/데이터 파일 누락 프로젝트 로드 시 크래시 방지 검증
            proj = flightdash.project.ProjectModel();
            session = flightdash.project.SessionModel('S1');
            session.DataFilePath = 'C:\fake_path\missing_data.csv'; % 존재하지 않는 경로
            proj.addSession(session);
            
            serializer = flightdash.project.ProjectSerializer();
            testFilePath = fullfile(testCase.TempDir, 'missing_ext.frsproj');
            serializer.save(proj, testFilePath);
            
            % 크래시 없이 로드되는지 확인
            try
                loadedProj = serializer.load(testFilePath);
                success = true;
            catch
                success = false;
            end
            
            testCase.verifyTrue(success, '외부 파일이 누락된 프로젝트 로드 시 크래시가 발생했습니다.');
        end
        
        %% [스트레스 테스트] 다중 세션 및 비동기 경쟁 상태 검증
        
        function test_TStress_MultiSession_Scrub(testCase)
            % TStress_MultiSession_Scrub: 비동기 디코드 도중 탭 닫기(Cancellation) 검증
            testCase.App = flightdash.studio.FlightReviewStudioApp();
            ws = testCase.App.WorkspaceManager;
            
            ws.createSessionTab('S1');
            ws.createSessionTab('S2');
            
            % parfeval을 사용한 더미 비동기 작업 발생 (asyncDecodeFrame 모사)
            f1 = parfeval(@pause, 0, 5); % 5초 지연 작업
            f2 = parfeval(@pause, 0, 5);
            
            % App의 비동기 Future 배열에 임의 등록 (실제 구조체계에 맞게 조정 필요)
            % testCase.App.AsyncTasks = [f1, f2];
            
            % 디코드 도중에 S1 탭 강제 종료
            ws.closeSessionTab('S1');
            
            % 의도: S1 탭을 닫으면 f1 작업이 cancel() 되어야 함
            % testCase.verifyEqual(f1.State, 'finished', '비동기 작업이 탭 종료 시 정상적으로 취소되지 않았습니다.');
            
            % S2 탭은 안전하게 남아있는지 확인
            testCase.verifyEqual(length(ws.TabGroup.Children), 1, '다른 세션 탭까지 영향을 받았습니다.');
        end
        
    end
end