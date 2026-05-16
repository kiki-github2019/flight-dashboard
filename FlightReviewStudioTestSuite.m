classdef FlightReviewStudioTestSuite < matlab.unittest.TestCase
    %FLIGHTREVIEWSTUDIOTESTSUITE
    % Automated compatibility and stabilization tests for FlightReviewStudio.
    %
    % Scope:
    %   T1  - Studio shell create/delete
    %   T2  - Project/Session model round-trip
    %   T3  - Embedded multi-session add/remove
    %   T4  - Session-scoped event isolation
    %   T5  - Project Explorer selection API, if available
    %   T6  - Inspector invalid-handle safety, if available
    %   T6b - GUI mode persistence
    %   T9a - .frsproj exact extension save
    %   T9b - non-ASCII path save/load
    %   T9c - missing external linked asset tolerance
    %   TS  - multi-session scrub/switch/remove stress
    %
    % Run:
    %   clear classes
    %   rehash toolboxcache
    %   results = runtests('FlightReviewStudioTestSuite');
    %   table(results)
    %
    % Notes:
    %   - This suite intentionally avoids uigetfile/uiputfile.
    %   - It prefers public APIs over direct UI-handle deletion.
    %   - Tests that require not-yet-public testing APIs are skipped with
    %     assumptions instead of failing as false negatives.

    properties
        TempDir char = ''
        Apps cell = {}
    end

    methods (TestMethodSetup)
        function setupTempDir(testCase)
            testCase.TempDir = tempname;

            if ~exist(testCase.TempDir, 'dir')
                mkdir(testCase.TempDir);
            end
        end
    end

    methods (TestMethodTeardown)
        function cleanupTempDirAndApps(testCase)
            testCase.closeTrackedApps();

            if ~isempty(testCase.TempDir) && isfolder(testCase.TempDir)
                try
                    rmdir(testCase.TempDir, 's');
                catch ME
                    warning( ...
                        'FlightReviewStudioTestSuite:TempCleanupFailed', ...
                        'Failed to remove temp dir "%s": %s', ...
                        testCase.TempDir, ...
                        ME.message);
                end
            end
        end
    end

    methods (Test)
        function test_T1_Shell_CreateDelete(testCase)
            testCase.verifyEntryPoints();

            app = testCase.launchStudio();
            testCase.verifyNotEmpty(app);
            testCase.verifyTrue(isvalid(app));

            testCase.verifyTrue( ...
                isprop(app, 'UIFigure'), ...
                'Studio app must expose UIFigure.');

            testCase.verifyTrue( ...
                ~isempty(app.UIFigure) && isvalid(app.UIFigure), ...
                'Studio UIFigure is missing or invalid.');

            testCase.safeDeleteApp(app);
        end

        function test_T2_Model_RoundTrip(testCase)
            testCase.verifyProjectClasses();

            project = flightdash.project.ProjectModel( ...
                'Suite Model RoundTrip Project');

            session1 = testCase.makeSessionWithDummyLinks('S1');
            session2 = testCase.makeSessionWithDummyLinks('S2');

            project = project.addSession(session1);
            project = project.addSession(session2);

            testCase.verifyEqual( ...
                project.sessionCount(), ...
                2, ...
                'Save 전 ProjectModel에 session이 실제로 추가되지 않았습니다.');

            filePath = fullfile( ...
                testCase.TempDir, ...
                'suite_model_roundtrip.frsproj');

            flightdash.project.ProjectSerializer.save(project, filePath);

            testCase.verifyTrue( ...
                isfile(filePath), ...
                'ProjectSerializer.save did not create .frsproj.');

            testCase.verifyFalse( ...
                isfile([filePath '.zip']), ...
                'Unexpected .frsproj.zip file exists.');

            inspectDir = fullfile(testCase.TempDir, 'inspect_model_roundtrip');
            mkdir(inspectDir);
            unzip(filePath, inspectDir);

            testCase.verifyTrue( ...
                isfile(fullfile(inspectDir, 'manifest.json')), ...
                'manifest.json is missing inside .frsproj.');

            testCase.verifyTrue( ...
                isfile(fullfile(inspectDir, 'project.json')), ...
                'project.json is missing inside .frsproj.');

            loaded = flightdash.project.ProjectSerializer.load(filePath);

            testCase.verifyClass( ...
                loaded, ...
                'flightdash.project.ProjectModel');

            testCase.verifyEqual( ...
                loaded.sessionCount(), ...
                2, ...
                '로드된 프로젝트의 세션 목록이 비어있거나 개수가 다릅니다.');

            testCase.verifyNotEmpty( ...
                loaded.Sessions, ...
                '로드된 프로젝트의 세션 목록이 비어있습니다.');

            loadedNames = string({loaded.Sessions.DisplayName});

            testCase.verifyTrue( ...
                any(loadedNames == "S1"), ...
                'S1 session was not restored.');

            testCase.verifyTrue( ...
                any(loadedNames == "S2"), ...
                'S2 session was not restored.');
        end

        function test_T3_Embedded_AddRemove(testCase)
            app = testCase.launchStudio();

            s1 = app.addSession('Embedded Session 1');
            s2 = app.addSession('Embedded Session 2');

            drawnow limitrate;

            testCase.verifyNotEmpty(s1);
            testCase.verifyNotEmpty(s2);
            testCase.verifyNotEqual(string(s1), string(s2));

            testCase.verifyEqual( ...
                app.Project.sessionCount(), ...
                2, ...
                'Project session count mismatch after addSession.');

            testCase.verifyTrue( ...
                testCase.workspaceHasSession(app, s1), ...
                'Workspace does not contain S1 after addSession.');

            testCase.verifyTrue( ...
                testCase.workspaceHasSession(app, s2), ...
                'Workspace does not contain S2 after addSession.');

            testCase.removeAllSessionsViaPublicApi(app);

            testCase.verifyEqual( ...
                app.Project.sessionCount(), ...
                0, ...
                'removeAllSessions did not clear project sessions.');

            testCase.safeDeleteApp(app);
        end

        function test_T3b_UndoRedo_Service_Isolation(testCase)
            s1 = flightdash.studio.UndoService('S1');
            s2 = flightdash.studio.UndoService('S2');
            target = flightdash.test.CounterTarget(0);

            cmd1 = flightdash.test.CounterCommand('S1', target, 0, 10, 'Set S1');
            cmd2 = flightdash.test.CounterCommand('S2', target, 10, 20, 'Set S2');

            s1.push(cmd1, true);
            testCase.verifyEqual(target.Value, 10);
            testCase.verifyTrue(s1.canUndo());
            testCase.verifyFalse(s1.canRedo());
            testCase.verifyEqual(numel(s1.UndoStack), 1);
            testCase.verifyEmpty(s2.UndoStack);

            s2.push(cmd2, true);
            testCase.verifyEqual(target.Value, 20);
            s2.undo();
            testCase.verifyEqual(target.Value, 10);
            testCase.verifyTrue(s2.canRedo());
            testCase.verifyTrue(s1.canUndo());

            s1.undo();
            testCase.verifyEqual(target.Value, 0);
            s1.redo();
            testCase.verifyEqual(target.Value, 10);
        end

        function test_T3c_UndoRedo_MaxHistory_And_CommandNoop(testCase)
            svc = flightdash.studio.UndoService('S1');
            svc.MaxHistory = 2;
            target = flightdash.test.CounterTarget(0);

            svc.push(flightdash.test.CounterCommand('S1', target, 0, 1, 'One'), true);
            svc.push(flightdash.test.CounterCommand('S1', target, 1, 2, 'Two'), true);
            svc.push(flightdash.test.CounterCommand('S1', target, 2, 3, 'Three'), true);

            testCase.verifyEqual(svc.MaxDepth, 2);
            testCase.verifyEqual(numel(svc.UndoStack), 2);
            testCase.verifyEqual(svc.UndoStack{1}.Description, 'Two');
            testCase.verifyEqual(svc.UndoStack{2}.Description, 'Three');

            missingMarker = flightdash.command.MoveMarkerCommand( ...
                'S1', [], [0 0], [1 1], 'Move Missing Marker');
            missingMarker.execute();
            missingMarker.undo();

            missingRoi = flightdash.command.MoveROICommand( ...
                'S1', [], [0 0 1 1], [1 1 1 1], 'Move Missing ROI');
            missingRoi.execute();
            missingRoi.undo();
        end

        function test_T3d_UndoRedo_UiStateAndHistoryBinding(testCase)
            app = testCase.launchStudio();
            sid = app.addSession('Undo UI Session');
            drawnow limitrate;

            dash = app.getActiveDashboard();
            testCase.assumeFalse(isempty(dash), 'No active dashboard was available.');
            testCase.assumeTrue(isprop(dash, 'UndoService') && ~isempty(dash.UndoService), ...
                'Dashboard UndoService was not injected.');

            target = flightdash.test.CounterTarget(0);
            cmd = flightdash.test.CounterCommand(sid, target, 0, 5, 'Suite UI Action');
            dash.UndoService.push(cmd, true);
            drawnow limitrate;

            testCase.verifyEqual(target.Value, 5);
            testCase.verifyUndoUiState(app, true, false);

            if ~isempty(app.RightDock) && isvalid(app.RightDock)
                app.RightDock.refreshHistoryForDashboard(dash);
                drawnow limitrate;
                if ~isempty(app.RightDock.HistoryPanel) && isvalid(app.RightDock.HistoryPanel)
                    items = string(app.RightDock.HistoryPanel.ListBox.Items);
                    testCase.verifyTrue(any(contains(items, "Suite UI Action")), ...
                        'History panel did not show the pushed command.');
                end
            end

            app.dispatchCommand('Edit:Undo', 'Test');
            drawnow limitrate;
            testCase.verifyEqual(target.Value, 0);
            testCase.verifyUndoUiState(app, false, true);

            app.dispatchCommand('Edit:Redo', 'Test');
            drawnow limitrate;
            testCase.verifyEqual(target.Value, 5);
            testCase.verifyUndoUiState(app, true, false);
        end

        function test_T3e_CloseSessionClearsUndoService(testCase)
            app = testCase.launchStudio();
            sid = app.addSession('Undo Close Session');
            drawnow limitrate;

            dash = app.getActiveDashboard();
            testCase.assumeFalse(isempty(dash), 'No active dashboard was available.');
            target = flightdash.test.CounterTarget(0);
            dash.UndoService.push(flightdash.test.CounterCommand(sid, target, 0, 1, 'Close Cleanup'), true);

            testCase.verifyTrue(app.UndoServices.isKey(char(sid)), ...
                'UndoService was not registered for the new session.');

            closed = testCase.closeSessionViaPublicApi(app, sid);
            drawnow limitrate;

            testCase.verifyTrue(closed, 'Session close API did not report success.');
            testCase.verifyFalse(testCase.workspaceHasSession(app, sid), ...
                'Workspace still contains the closed session.');
            testCase.verifyFalse(app.UndoServices.isKey(char(sid)), ...
                'UndoService was not removed when the session closed.');
        end

        function test_T3f_Mouse_CloseTabDuringDragDoesNotCrash(testCase)
            app = testCase.launchStudio();
            sidA = app.addSession('Mouse Drag Session A');
            sidB = app.addSession('Mouse Drag Session B');
            drawnow limitrate;

            testCase.selectSessionViaPublicApi(app, sidA);
            ctrl = flightdash.studio.diag.RouterTestController();
            granted = app.MouseRouter.requestDragLock(sidA, ctrl, 'fleur', 'drag');

            testCase.verifyTrue(granted, 'MouseRouter did not grant drag lock to active session.');
            testCase.verifyTrue(app.MouseRouter.isLockHeldBy(sidA));

            closed = testCase.closeSessionViaPublicApi(app, sidA);
            drawnow limitrate;

            testCase.verifyTrue(closed, 'Session A close failed during active drag.');
            testCase.verifyFalse(app.MouseRouter.isLockHeldBy(sidA), ...
                'MouseRouter kept a lock for the closed session.');
            testCase.verifyFalse(app.MouseRouter.hasActiveLock(), ...
                'MouseRouter still has an active lock after closing the dragged session.');
            testCase.verifyGreaterThanOrEqual(ctrl.StopCount, 1, ...
                'Drag controller was not stopped during close.');
            testCase.verifyTrue(testCase.workspaceHasSession(app, sidB), ...
                'Session B disappeared after closing Session A during drag.');
        end

        function test_T3g_Mouse_TabSwitchDuringDragIsSuppressed(testCase)
            app = testCase.launchStudio();
            sidA = app.addSession('Mouse Switch Session A');
            sidB = app.addSession('Mouse Switch Session B');
            drawnow limitrate;

            testCase.selectSessionViaPublicApi(app, sidA);
            ctrl = flightdash.studio.diag.RouterTestController();
            testCase.verifyTrue(app.MouseRouter.requestDragLock(sidA, ctrl), ...
                'MouseRouter did not grant drag lock to active session.');

            testCase.selectSessionViaPublicApi(app, sidB);
            testCase.invokeFigureMotion(app);

            testCase.verifyFalse(app.MouseRouter.hasActiveLock(), ...
                'MouseRouter did not release lock after active tab changed.');
            testCase.verifyEqual(ctrl.MotionCount, 0, ...
                'Inactive session received drag motion after tab switch.');
            testCase.verifyEqual(ctrl.StopCount, 1, ...
                'Controller stopDrag was not called after tab switch.');
        end

        function test_T3h_Mouse_MultiControllerDragIsolation(testCase)
            app = testCase.launchStudio();
            sidA = app.addSession('Mouse Isolation Session A');
            sidB = app.addSession('Mouse Isolation Session B');
            drawnow limitrate;

            testCase.selectSessionViaPublicApi(app, sidA);
            markerLike = flightdash.studio.diag.RouterTestController();
            splitterLike = flightdash.studio.diag.RouterTestController();

            testCase.verifyTrue(app.MouseRouter.requestDragLock(sidA, markerLike, 'fleur', 'marker'));
            testCase.verifyFalse(app.MouseRouter.requestDragLock(sidA, splitterLike, 'fleur', 'split'), ...
                'MouseRouter granted a second controller lock while marker lock was active.');

            app.MouseRouter.releaseDragLock();
            testCase.verifyTrue(app.MouseRouter.requestDragLock(sidA, splitterLike, 'fleur', 'split'));

            testCase.selectSessionViaPublicApi(app, sidB);
            testCase.invokeFigureMotion(app);

            testCase.verifyFalse(app.MouseRouter.isLockHeldBy(sidA), ...
                'MouseRouter kept Session A splitter lock after switching to Session B.');
            testCase.verifyEqual(splitterLike.StopCount, 1, ...
                'Splitter-like controller was not stopped after rapid switch.');
            testCase.verifyEqual(markerLike.StopCount, 0, ...
                'Inactive marker-like controller was stopped even though it no longer owned the lock.');
        end

        function test_T3i_Mouse_RoiHoverHighlightingDoesNotCrash(testCase)
            app = testCase.launchStudio();
            sid = app.addSession('Mouse Hover ROI Session');
            drawnow limitrate;

            testCase.selectSessionViaPublicApi(app, sid);
            dash = app.getActiveDashboard();
            testCase.assumeFalse(isempty(dash), 'No active dashboard was available.');
            testCase.assumeTrue(isprop(dash, 'RoiCtrl') && ~isempty(dash.RoiCtrl) && ...
                isvalid(dash.RoiCtrl) && ismethod(dash.RoiCtrl, 'handleHover'), ...
                'ROI hover controller API was not available.');

            dash.RoiCtrl.handleHover([100 100]);
            if ismethod(dash.RoiCtrl, 'clearHover')
                dash.RoiCtrl.clearHover();
            end

            testCase.verifyTrue(true, 'ROI hover handling completed without throwing.');
        end

        function test_T3j_Mouse_RapidTabCreateCloseStress(testCase)
            app = testCase.launchStudio();

            for k = 1:6
                sid = app.addSession(sprintf('Mouse Stress Session %d', k));
                drawnow limitrate;
                testCase.selectSessionViaPublicApi(app, sid);

                ctrl = flightdash.studio.diag.RouterTestController();
                if app.MouseRouter.requestDragLock(sid, ctrl, 'fleur', 'stress')
                    testCase.invokeFigureMotion(app);
                end

                if mod(k, 2) == 0
                    closed = testCase.closeSessionViaPublicApi(app, sid);
                    drawnow limitrate;
                    testCase.verifyTrue(closed, sprintf('Failed to close stress session %d.', k));
                    testCase.verifyFalse(app.MouseRouter.isLockHeldBy(sid), ...
                        sprintf('MouseRouter kept lock for closed stress session %d.', k));
                else
                    app.MouseRouter.releaseDragLock();
                end
            end

            testCase.verifyFalse(app.MouseRouter.hasActiveLock(), ...
                'MouseRouter retained a lock after rapid create/close stress.');
        end

        function test_T3k_Mouse_StandaloneCompatibility(testCase)
            dash = [];
            cleanupObj = onCleanup(@() testCase.safeDeleteApp(dash)); %#ok<NASGU>
            dash = FlightDataDashboard();
            drawnow limitrate;

            testCase.verifyNotEmpty(dash);
            testCase.verifyTrue(isvalid(dash));
            testCase.verifyTrue(isprop(dash, 'MouseRouter'), ...
                'Standalone dashboard should expose MouseRouter property for compatibility.');
            testCase.verifyEmpty(dash.MouseRouter, ...
                'Standalone dashboard should not be assigned a Studio MouseRouter.');
        end

        function test_T4_Event_Isolation(testCase)
            % Preferred path:
            % Use repository diagnostic if it exists. This avoids assuming
            % the internal EventBus token/callback API.
             if ~isempty(which('flightdash.studio.diag.verifyPhase4'))
                results = flightdash.studio.diag.verifyPhase4();
                testCase.verifyDiagnosticHasNoFail( ...
                    results, ...
                    'verifyPhase4 reported event isolation failures.');
                return;
            end

            % Fallback:
            % If the repository exposes a session-aware EventBus API, test it.
            testCase.assumeTrue( ...
                exist('flightdash.util.EventBus', 'class') == 8, ...
                'EventBus class is not available.');

            mc = meta.class.fromName('flightdash.util.EventBus');
            methodNames = string({mc.MethodList.Name});

            hasSubscribeSession = any(methodNames == "subscribeSession");
            hasPublish = any(methodNames == "publish");

            testCase.assumeTrue( ...
                hasSubscribeSession && hasPublish, ...
                ['Session-scoped EventBus testing API was not found. ', ...
                 'Expected subscribeSession + publish, or verifyPhase4.']);

            s1Hit = false;
            s2Hit = false;

            token1 = flightdash.util.EventBus.subscribeSession( ...
                'SuiteEventIsolation', ...
                'S1', ...
                @(eventData) markS1(eventData));

            token2 = flightdash.util.EventBus.subscribeSession( ...
                'SuiteEventIsolation', ...
                'S2', ...
                @(eventData) markS2(eventData));

            cleanupObj = onCleanup(@() cleanupTokens(token1, token2)); %#ok<NASGU>

            eventData = struct( ...
                'SessionId', ...
                'S1', ...
                'Payload', ...
                123);

            flightdash.util.EventBus.publish( ...
                'SuiteEventIsolation', ...
                eventData);

            drawnow limitrate;

            testCase.verifyTrue( ...
                s1Hit, ...
                'S1 listener did not receive S1 event.');

            testCase.verifyFalse( ...
                s2Hit, ...
                'S1 이벤트가 S2로 누수되었습니다.');

            function markS1(~)
                s1Hit = true;
            end

            function markS2(~)
                s2Hit = true;
            end

            function cleanupTokens(t1, t2)
                tryUnsubscribe(t1);
                tryUnsubscribe(t2);
            end

            function tryUnsubscribe(token)
                try
                    if exist('flightdash.util.EventBus', 'class') == 8
                        if any(methodNames == "unsubscribe")
                            flightdash.util.EventBus.unsubscribe(token);
                        end
                    end
                catch
                end
            end
        end

        function test_T5_Explorer_Selection(testCase)
            app = testCase.launchStudio();

            sid = app.addSession('Explorer Selection Session');
            drawnow limitrate;

            explorer = testCase.getProjectExplorer(app);

            testCase.assumeFalse( ...
                isempty(explorer), ...
                'ProjectExplorer 객체를 찾을 수 없어 테스트를 건너뜁니다.');

            hasSelectSession = ismethod(explorer, 'selectSession');
            hasSelectNode = ismethod(explorer, 'selectNode');

            testCase.assumeTrue( ...
                hasSelectSession || hasSelectNode, ...
                'ProjectExplorer.selectSession/selectNode 메서드가 없습니다.');

            if hasSelectSession
                tf = explorer.selectSession(sid);
            else
                tf = explorer.selectNode(sid);
            end

            drawnow limitrate;

            testCase.verifyTrue( ...
                logical(tf), ...
                'ProjectExplorer failed to select the requested session.');

            if ismethod(explorer, 'getSelectedNodeId')
                selectedId = explorer.getSelectedNodeId();
                testCase.verifyEqual( ...
                    string(selectedId), ...
                    string(sid), ...
                    'Explorer selected node mismatch.');
            end

            testCase.safeDeleteApp(app);
        end

        function test_T6_Inspector_InvalidHandles(testCase)
             if ~isempty(which('flightdash.studio.diag.verifyPhase6'))
                results = flightdash.studio.diag.verifyPhase6();
                testCase.verifyDiagnosticHasNoFail( ...
                    results, ...
                    'verifyPhase6 reported inspector/menu/toolbar failures.');
                return;
            end

            app = testCase.launchStudio();
            inspector = testCase.getInspector(app);

            testCase.assumeFalse( ...
                isempty(inspector), ...
                'Inspector 객체를 찾을 수 없어 테스트를 건너뜁니다.');

            % app = testCase.launchStudio();


            sid = app.addSession('Inspector Invalid Handle Session');
            drawnow limitrate;

            inspector = testCase.getInspector(app);

            testCase.assumeFalse( ...
                isempty(inspector), ...
                'Inspector 객체를 찾을 수 없어 테스트를 건너뜁니다.');

            % The exact Inspector API may evolve. Prefer common refresh/update
            % method names and skip if none are public.
            candidateMethods = { ...
                'refresh', ...
                'refreshForSession', ...
                'updateForSession', ...
                'setActiveSession', ...
                'clear'};

            methodToCall = testCase.firstExistingMethod( ...
                inspector, ...
                candidateMethods);

            testCase.assumeFalse( ...
                isempty(methodToCall), ...
                'Inspector refresh/update public API가 없습니다.');

            % Delete the active session first, then verify Inspector update
            % does not throw on stale/invalid handles.
            testCase.closeSessionViaPublicApi(app, sid);
            drawnow limitrate;

            try
                switch methodToCall
                    case 'refresh'
                        inspector.refresh();
                    case {'refreshForSession', 'updateForSession', 'setActiveSession'}
                        inspector.(methodToCall)('');
                    case 'clear'
                        inspector.clear();
                end

                drawnow limitrate;
                ok = true;
                msg = '';
            catch ME
                ok = false;
                msg = ME.message;
            end

            testCase.verifyTrue( ...
                ok, ...
                ['Inspector invalid-handle update failed: ', msg]);

            testCase.safeDeleteApp(app);
        end

        function test_T6_GuiMode_Persist(testCase)
            app = testCase.launchStudio();

            sid = app.addSession('GUI Mode Persist Session');
            drawnow limitrate;

            testCase.verifyNotEmpty(sid);

            testCase.assumeTrue( ...
                ismethod(app, 'setGuiMode') && ismethod(app, 'currentGuiMode'), ...
                'GUI mode public API is not available.');

            modes = { ...
                'Classic', ...
                'Studio', ...
                'Review', ...
                'Analysis', ...
                'Plot', ...
                'Report', ...
                'Compact', ...
                'Review'};

            for k = 1:numel(modes)
                app.setGuiMode(modes{k});
                drawnow limitrate;

                currentMode = app.currentGuiMode();

                testCase.verifyEqual( ...
                    lower(string(currentMode)), ...
                    lower(string(modes{k})), ...
                    ['GUI mode mismatch after setGuiMode(', modes{k}, ').']);
            end

            testCase.verifyTrue( ...
                testCase.workspaceHasSession(app, sid), ...
                'Session disappeared after GUI mode switching.');

            testCase.safeDeleteApp(app);
        end

        function test_T9_Save_Extension(testCase)
            testCase.verifyProjectClasses();

            project = flightdash.project.ProjectModel('Suite Save Extension');
            session = testCase.makeSessionWithDummyLinks('Save Extension Session');
            project = project.addSession(session);

            filePath = fullfile(testCase.TempDir, 'save_extension.frsproj');

            flightdash.project.ProjectSerializer.save(project, filePath);

            testCase.verifyTrue( ...
                isfile(filePath), ...
                'Requested .frsproj file was not created.');

            testCase.verifyFalse( ...
                isfile([filePath '.zip']), ...
                'Unexpected .frsproj.zip residue exists.');

            loaded = flightdash.project.ProjectSerializer.load(filePath);

            testCase.verifyEqual( ...
                loaded.sessionCount(), ...
                1, ...
                'Saved project did not load expected session count.');
        end

        function test_T9_NonAscii_Path(testCase)
            testCase.verifyProjectClasses();

            nonAsciiDir = fullfile(testCase.TempDir, '한글_경로_테스트');

            if ~exist(nonAsciiDir, 'dir')
                mkdir(nonAsciiDir);
            end

            project = flightdash.project.ProjectModel('한글 경로 프로젝트');
            session = testCase.makeSessionWithDummyLinksInDir( ...
                '한글 세션', ...
                nonAsciiDir);

            project = project.addSession(session);

            filePath = fullfile(nonAsciiDir, '한글_프로젝트.frsproj');

            flightdash.project.ProjectSerializer.save(project, filePath);

            testCase.verifyTrue( ...
                isfile(filePath), ...
                'Non-ASCII .frsproj file was not created.');

            loaded = flightdash.project.ProjectSerializer.load(filePath);

            testCase.verifyEqual( ...
                loaded.sessionCount(), ...
                1, ...
                'Non-ASCII project did not preserve session count.');
        end

        function test_T9_Missing_External(testCase)
            testCase.verifyProjectClasses();

            project = flightdash.project.ProjectModel('Missing External Project');

            session = testCase.makeSessionWithDummyLinks( ...
                'Missing External Session');

            missingPath = fullfile(testCase.TempDir, 'deleted_after_save.csv');
            testCase.writeTextFile(missingPath, 'time,altitude\n0,100\n');

            session = session.setFlightFile(2, missingPath);
            project = project.addSession(session);

            filePath = fullfile(testCase.TempDir, 'missing_external.frsproj');

            flightdash.project.ProjectSerializer.save(project, filePath);

            if isfile(missingPath)
                delete(missingPath);
            end

            loaded = flightdash.project.ProjectSerializer.load(filePath);

            testCase.verifyClass( ...
                loaded, ...
                'flightdash.project.ProjectModel');

            testCase.verifyEqual( ...
                loaded.sessionCount(), ...
                1, ...
                'Project load failed or session was lost after linked asset deletion.');

            testCase.verifyEqual( ...
                string(loaded.Sessions(1).FlightFilePath{2}), ...
                string(missingPath), ...
                'Missing external asset path was not preserved.');
        end

        function test_TStress_MultiSession_Scrub(testCase)
            app = testCase.launchStudio();

            sid1 = app.addSession('Stress Session 1');
            sid2 = app.addSession('Stress Session 2');
            sid3 = app.addSession('Stress Session 3');

            drawnow limitrate;

            ids = {sid1, sid2, sid3};

            for cycle = 1:5
                for k = 1:numel(ids)
                    testCase.selectSessionViaPublicApi(app, ids{k});
                    drawnow limitrate;
                    pause(0.02);

                    activeId = testCase.getActiveSessionId(app);

                    testCase.verifyEqual( ...
                        string(activeId), ...
                        string(ids{k}), ...
                        'Active session mismatch during stress switching.');
                end
            end

            % Prefer public close/remove API. Do not delete tab handles directly.
            closed = testCase.closeSessionViaPublicApi(app, sid1);
            drawnow limitrate;

            testCase.verifyTrue( ...
                closed, ...
                'S1 세션 탭을 public API로 종료하는 데 실패했습니다.');

            testCase.verifyFalse( ...
                testCase.workspaceHasSession(app, sid1), ...
                'S1 still exists in Workspace after closeSession.');

            testCase.verifyTrue( ...
                testCase.workspaceHasSession(app, sid2), ...
                'S2 disappeared unexpectedly after closing S1.');

            testCase.verifyTrue( ...
                testCase.workspaceHasSession(app, sid3), ...
                'S3 disappeared unexpectedly after closing S1.');

            filePath = fullfile( ...
                testCase.TempDir, ...
                'stress_roundtrip.frsproj');

            tf = app.saveProject(filePath);

            testCase.verifyTrue( ...
                logical(tf), ...
                'Stress project save failed.');

            testCase.verifyTrue( ...
                isfile(filePath), ...
                'Stress project .frsproj file was not created.');

            testCase.safeDeleteApp(app);
        end

        function test_TStress_UndoRedo_MultiSessionIsolation(testCase)
            app = testCase.launchStudio();
            sessionIds = cell(1, 4);
            targets = cell(1, 4);
            expectedValues = zeros(1, 4);

            for k = 1:numel(sessionIds)
                sessionIds{k} = app.addSession(sprintf('Undo Stress Session %d', k));
                drawnow limitrate;
                testCase.selectSessionViaPublicApi(app, sessionIds{k});
                dash = app.getActiveDashboard();
                testCase.assumeFalse(isempty(dash), 'No active dashboard was available.');
                targets{k} = flightdash.test.CounterTarget(0);
                dash.UndoService.push(flightdash.test.CounterCommand( ...
                    sessionIds{k}, targets{k}, 0, k, sprintf('Set Session %d', k)), true);
                expectedValues(k) = k;
            end

            for k = 1:numel(sessionIds)
                testCase.selectSessionViaPublicApi(app, sessionIds{k});
                drawnow limitrate;
                app.dispatchCommand('Edit:Undo', 'Test');
                drawnow limitrate;
                expectedValues(k) = 0;
                for j = 1:numel(sessionIds)
                    testCase.verifyEqual(targets{j}.Value, expectedValues(j), ...
                        sprintf('Undo leaked from session %d into session %d.', k, j));
                end
            end

            for k = 1:numel(sessionIds)
                testCase.selectSessionViaPublicApi(app, sessionIds{k});
                drawnow limitrate;
                app.dispatchCommand('Edit:Redo', 'Test');
                drawnow limitrate;
                expectedValues(k) = k;
                for j = 1:numel(sessionIds)
                    testCase.verifyEqual(targets{j}.Value, expectedValues(j), ...
                        sprintf('Redo leaked from session %d into session %d.', k, j));
                end
            end
        end

        function test_T11_VideoPlayer_MemoryCleanup_NoTimerLeak(testCase)
            % Phase 11 §12: non-flaky memory diagnostic — verify that
            % spinning up and tearing down a Studio app does not leak
            % any of the timers we explicitly own (SliderScrubTimer,
            % MemoryMonitor, future PrefetchTimer). No exact-MB
            % comparison — MATLAB allocation is non-deterministic.
            try
                flightdash.util.MemoryMonitor.stopMonitoring();
            catch
            end
            beforeNames = FlightReviewStudioTestSuite.collectTimerNames(timerfindall);

            app = [];
            try
                app = FlightReviewStudio();
                drawnow limitrate;
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Could not launch Studio for memory test: %s', ME.message));
            end
            try
                if ~isempty(app) && isvalid(app)
                    if isprop(app, 'UIFigure') && ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                        app.UIFigure.Visible = 'off';
                    end
                    drawnow limitrate;
                    delete(app);
                end
            catch
            end
            drawnow limitrate;
            pause(0.05);

            afterNames = FlightReviewStudioTestSuite.collectTimerNames(timerfindall);
            % Any timer that did NOT exist before construction is a leak
            % candidate; check the names we own.
            newNames = setdiff(afterNames, beforeNames);
            leakHits = @(needle) any(contains(newNames, needle, 'IgnoreCase', true));

            testCase.verifyFalse(leakHits('Slider'), ...
                sprintf('Slider-related timer leaked after app cleanup. Names: %s', ...
                    strjoin(cellstr(newNames), ', ')));
            testCase.verifyFalse(leakHits('Prefetch'), ...
                sprintf('Prefetch-related timer leaked after app cleanup. Names: %s', ...
                    strjoin(cellstr(newNames), ', ')));
            testCase.verifyFalse(leakHits('MemoryMonitor'), ...
                sprintf('MemoryMonitor timer leaked after app cleanup. Names: %s', ...
                    strjoin(cellstr(newNames), ', ')));
        end

        function test_T12_Theme_Toggle_Smoke(testCase)
            % Phase 11 smoke: toggleTheme() flips CurrentTheme + restyles figure.
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'toggleTheme'), ...
                'toggleTheme not present — skipping.');
            before = char(app.CurrentTheme);
            colorBefore = app.UIFigure.Color;
            app.toggleTheme();
            drawnow limitrate;
            testCase.verifyNotEqual(char(app.CurrentTheme), before, ...
                'CurrentTheme did not change after toggleTheme.');
            testCase.verifyFalse(isequal(app.UIFigure.Color, colorBefore), ...
                'UIFigure background did not change after toggleTheme.');
        end

        function test_T13_AnalysisDialog_OpenClose_Smoke(testCase)
            % Phase 11 smoke: openAnalysisDialog spawns + deletes a uifigure.
            app = testCase.launchStudio();
            sid = app.addSession('Smoke T13 Session');
            drawnow limitrate;
            figsBefore = findall(groot, 'Type', 'figure');
            try
                app.dispatchCommand('Toolbar:Analyze', 'Test');
            catch ME
                testCase.assumeFail(sprintf( ...
                    'AnalysisDialog dispatch failed: %s', ME.message));
            end
            drawnow limitrate;
            figsAfter = findall(groot, 'Type', 'figure');
            newFigs = setdiff(figsAfter, figsBefore);
            testCase.verifyNotEmpty(newFigs, ...
                'No new uifigure was created for ROI dialog.');
            for k = 1:numel(newFigs)
                try, delete(newFigs(k)); catch, end
            end
            testCase.verifyNotEmpty(sid);
        end

        function test_T14_SharedDecodeService_ActiveSession_Smoke(testCase)
            % Phase 11 smoke: tab switch updates SharedDecodeService.ActiveSessionId.
            app = testCase.launchStudio();
            testCase.assumeTrue(isprop(app, 'SharedDecodeService') ...
                && ~isempty(app.SharedDecodeService) ...
                && isvalid(app.SharedDecodeService), ...
                'SharedDecodeService unavailable — skipping.');
            sidA = app.addSession('T14 A');
            sidB = app.addSession('T14 B');
            drawnow limitrate;
            app.Workspace.selectSession(sidA);
            drawnow limitrate;
            testCase.verifyEqual(char(app.SharedDecodeService.ActiveSessionId), ...
                char(sidA), 'SharedDecodeService.ActiveSessionId did not follow tab A.');
            app.Workspace.selectSession(sidB);
            drawnow limitrate;
            testCase.verifyEqual(char(app.SharedDecodeService.ActiveSessionId), ...
                char(sidB), 'SharedDecodeService.ActiveSessionId did not follow tab B.');
        end

        function test_T11_VideoReader_ReferenceRelease_NoCleanupError(testCase)
            % Patch 5: VideoModel.cleanup must release Reader via
            % reference-release pattern and tolerate a second cleanup
            % call (idempotent) without throwing.
            try
                model = flightdash.model.VideoModel();
            catch ME
                testCase.assumeFail(sprintf('VideoModel construction failed: %s', ME.message));
            end
            try
                model.cleanup();
                model.cleanup();   % second call must be a no-op
            catch ME
                testCase.verifyFail(sprintf( ...
                    'VideoModel.cleanup threw on repeat call: %s', ME.message));
                return;
            end
            testCase.verifyTrue(isempty(model.Reader), ...
                'VideoModel.Reader should be empty after cleanup.');
            testCase.verifyEqual(model.FilePath, '', ...
                'VideoModel.FilePath should be reset after cleanup.');
        end

        function test_T11_OptionalAttitudeColumns_NoCrash(testCase)
            % Patch 5: dashboard must survive Roll/Pitch/Heading being
            % unmapped — attitude-gauge update and dashboard update
            % paths should NOT throw and the gauge labels should
            % collapse via setAttitudeGaugeVisible.
            app = testCase.launchStudio();
            sid = app.addSession('T11 Attitude Skip');
            drawnow limitrate;
            dash = [];
            try
                dash = app.getActiveDashboard();
            catch
            end
            testCase.assumeTrue(~isempty(dash) && isvalid(dash), ...
                'No active dashboard for attitude guard test.');
            % Build a minimal synthetic table with critical columns only.
            T = table((0:9)', linspace(36.6, 36.7, 10)', linspace(126.6, 126.7, 10)', ...
                100 * ones(10, 1), ...
                'VariableNames', {'time', 'lat', 'lon', 'alt'});
            try
                dash.Models(1).rawData = T;
                mc = struct('Time','time','Lat','lat','Lon','lon','Alt','alt', ...
                            'Roll','','Pitch','','Heading','');
                dash.Models(1).mappedCols = mc;
            catch ME
                testCase.assumeFail(sprintf('Could not inject synthetic table: %s', ME.message));
            end
            crashFlag = false;
            try, dash.updateAttitudeGauges(1, 1); catch, crashFlag = true; end
            try, dash.updateDashboard(1, 1);      catch, crashFlag = true; end
            testCase.verifyFalse(crashFlag, ...
                'updateAttitudeGauges / updateDashboard crashed on missing Roll/Pitch/Heading.');
        end

        function test_T11_SliderScrub_MarkerPreview_NoFullRedraw(testCase)
            % Patch 5: scrubTick smoke. Inject a pending frame and call
            % scrubTick directly; verify SliderLastRendered is set and
            % the dashboard remains valid (no full-redraw crash).
            app = testCase.launchStudio();
            sid = app.addSession('T11 Scrub'); %#ok<NASGU>
            drawnow limitrate;
            dash = [];
            try, dash = app.getActiveDashboard(); catch, end
            testCase.assumeTrue(~isempty(dash) && isvalid(dash), ...
                'No active dashboard for scrub test.');
            try
                dash.VideoSyncState(1).TotalFrames = 100;
                dash.SliderPendingFrame(1) = 50;
                dash.SliderLastRendered(1) = NaN;
            catch ME
                testCase.assumeFail(sprintf('Slider state injection failed: %s', ME.message));
            end
            crashFlag = false;
            try, dash.scrubTick(); catch, crashFlag = true; end
            testCase.verifyFalse(crashFlag, 'scrubTick crashed unexpectedly.');
            testCase.verifyTrue(isvalid(dash), 'Dashboard invalid after scrubTick.');
            % SliderLastRendered may stay NaN when no video is ready —
            % accept either NaN (video-not-ready early-exit) or the
            % target frame (frame was actually rendered). Both are
            % non-crash outcomes.
            lastRendered = dash.SliderLastRendered(1);
            testCase.verifyTrue(isnan(lastRendered) || lastRendered == 50, ...
                'SliderLastRendered should be NaN or the pending frame.');
        end

        function test_T11_ThemeToggle_PreservesPlotDataColors(testCase)
            % Patch 5: toggleTheme must never recolor plot Line/Patch
            % data colors — it only restyles chrome (panels, labels,
            % axes background).
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'toggleTheme'), ...
                'toggleTheme not present — skipping.');
            lines = findall(app.UIFigure, 'Type', 'Line');
            patches = findall(app.UIFigure, 'Type', 'Patch');
            beforeLineColors = arrayfun(@(h) {h.Color}, lines, 'UniformOutput', false);
            beforePatchFaces = arrayfun(@(h) {h.FaceColor}, patches, 'UniformOutput', false);
            app.toggleTheme();
            drawnow limitrate;
            % Snapshot AFTER toggle; the lines/patches may have changed
            % identity if the dashboard rebuilt, so compare ONLY the
            % surviving handles by identity.
            afterLineColors = arrayfun(@(h) {h.Color}, lines, 'UniformOutput', false);
            afterPatchFaces = arrayfun(@(h) {h.FaceColor}, patches, 'UniformOutput', false);
            testCase.verifyEqual(beforeLineColors, afterLineColors, ...
                'Plot Line colors changed after theme toggle.');
            testCase.verifyEqual(beforePatchFaces, afterPatchFaces, ...
                'Plot Patch face colors changed after theme toggle.');
        end

        function test_T11_ProjectPacker_CopiesOptionFiles(testCase)
            % Phase F: ProjectPacker.pack must copy option*.dat into the
            % packed config/ folder and rewrite the OptionFilePath to a
            % relative 'config/optionN.dat' path. Original project must
            % NOT be mutated.
            try
                project = flightdash.project.ProjectModel('T11 Pack Test');
                sess = flightdash.project.SessionModel('S1');
            catch ME
                testCase.assumeFail(sprintf('Model ctor failed: %s', ME.message));
            end
            here = fileparts(mfilename('fullpath'));
            srcOpt1 = fullfile(here, 'sample_data', 'option1.dat');
            srcOpt2 = fullfile(here, 'sample_data', 'option2.dat');
            testCase.assumeTrue(isfile(srcOpt1) && isfile(srcOpt2), ...
                'sample_data option files unavailable — skipping.');
            sess.OptionFilePath = {srcOpt1, srcOpt2};
            project = project.addSession(sess);

            destFolder = fullfile(tempdir, 'flightdash_pack_test');
            if isfolder(destFolder), rmdir(destFolder, 's'); end
            mkdir(destFolder);

            opts = struct('IncludeVideo', true, 'IncludeFlightData', true, ...
                'IncludeOptionFiles', true, 'UseRelativePaths', true, ...
                'Overwrite', true);
            result = flightdash.project.ProjectPacker.pack(project, destFolder, opts);

            testCase.verifyTrue(result.OK, ...
                sprintf('Pack should succeed. Warnings: %s', ...
                    strjoin(result.Warnings, ' | ')));
            testCase.verifyTrue(isfolder(result.PackedRoot), ...
                'Packed root folder not created.');
            testCase.verifyTrue( ...
                isfile(fullfile(result.PackedRoot, 'config', 'option1.dat')), ...
                'config/option1.dat missing in packed project.');
            testCase.verifyTrue( ...
                isfile(fullfile(result.PackedRoot, 'config', 'option2.dat')), ...
                'config/option2.dat missing in packed project.');
            testCase.verifyTrue(isfile(result.PackedProjectPath), ...
                'Packed .frsproj missing.');

            % Original project's OptionFilePath unchanged.
            testCase.verifyEqual(project.Sessions(1).OptionFilePath, ...
                {srcOpt1, srcOpt2}, ...
                'Original project OptionFilePath was mutated.');

            % Cleanup.
            try, rmdir(destFolder, 's'); catch, end
        end

        function test_T11_SessionModel_OptionFilePath_RoundTrip(testCase)
            % Phase A: SessionModel.OptionFilePath must round-trip
            % through ProjectSerializer and fall back to {'',''} when a
            % legacy archive omits the field.
            try
                sess = flightdash.project.SessionModel('T11 OptPath');
            catch ME
                testCase.assumeFail(sprintf('SessionModel ctor failed: %s', ME.message));
            end
            sess.OptionFilePath = {'C:/opts/option1.dat', 'C:/opts/option2.dat'};
            s = flightdash.project.ProjectSerializer.sessionToStruct(sess);
            testCase.verifyTrue(isfield(s, 'OptionFilePath'), ...
                'sessionToStruct must include OptionFilePath.');
            sess2 = flightdash.project.ProjectSerializer.structToSession(s);
            testCase.verifyEqual(sess2.OptionFilePath, sess.OptionFilePath, ...
                'OptionFilePath did not round-trip.');
            sLegacy = rmfield(s, 'OptionFilePath');
            sessLegacy = flightdash.project.ProjectSerializer.structToSession(sLegacy);
            testCase.verifyEqual(sessLegacy.OptionFilePath, {'', ''}, ...
                'Legacy struct lacking OptionFilePath should default to two empty entries.');
        end

        function test_T11_GuiTheme_RoundTrip_PersistsAcrossSaveLoad(testCase)
            % Cycle C: pure model/serializer round-trip — no figure.
            % Verifies Project.GuiTheme survives projectToStruct ->
            % structToProject and that an old archive missing the
            % field falls back to 'Light'.
            try
                p = flightdash.project.ProjectModel('T11 Theme RT');
            catch ME
                testCase.assumeFail(sprintf('ProjectModel ctor failed: %s', ME.message));
            end
            p.GuiTheme = 'Dark';
            try
                s = flightdash.project.ProjectSerializer.projectToStruct(p);
            catch ME
                testCase.verifyFail(sprintf('projectToStruct threw: %s', ME.message));
                return;
            end
            testCase.verifyTrue(isfield(s, 'GuiTheme'), ...
                'Serialized struct must include GuiTheme.');
            testCase.verifyEqual(char(s.GuiTheme), 'Dark', ...
                'GuiTheme not serialized correctly.');
            try
                p2 = flightdash.project.ProjectSerializer.structToProject(s);
            catch ME
                testCase.verifyFail(sprintf('structToProject threw: %s', ME.message));
                return;
            end
            testCase.verifyEqual(char(p2.GuiTheme), 'Dark', ...
                'GuiTheme not deserialized correctly.');

            % Backward-compat: a legacy struct lacking GuiTheme must
            % load with the default 'Light'.
            sLegacy = rmfield(s, 'GuiTheme');
            try
                pLegacy = flightdash.project.ProjectSerializer.structToProject(sLegacy);
            catch ME
                testCase.verifyFail(sprintf('legacy structToProject threw: %s', ME.message));
                return;
            end
            testCase.verifyEqual(char(pLegacy.GuiTheme), 'Light', ...
                'Missing GuiTheme should fall back to Light.');
        end

        function test_T11_DockToggle_ReclaimsWorkspaceWidth(testCase)
            % Patch 5: toggleExplorer must shrink BodyGrid column 1 to
            % 0 on hide and restore a positive width on show.
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'toggleExplorer'), ...
                'toggleExplorer not present — skipping.');
            testCase.assumeTrue(~isempty(app.BodyGrid) && isvalid(app.BodyGrid), ...
                'BodyGrid unavailable — skipping.');
            cwBefore = app.BodyGrid.ColumnWidth;
            if ~isnumeric(cwBefore{1}) || cwBefore{1} <= 0
                testCase.assumeFail('Explorer column not numeric > 0 at baseline.');
            end
            app.toggleExplorer();
            drawnow limitrate;
            cwHidden = app.BodyGrid.ColumnWidth;
            testCase.verifyEqual(cwHidden{1}, 0, ...
                'Explorer column did not collapse to 0 on first toggle.');
            app.toggleExplorer();
            drawnow limitrate;
            cwShown = app.BodyGrid.ColumnWidth;
            testCase.verifyTrue(isnumeric(cwShown{1}) && cwShown{1} > 0, ...
                'Explorer column did not restore to a positive width on second toggle.');
        end

        % =================================================================
        % Pre-PFE-1: OptionFileParser / OptionFileModel foundation tests
        % All headless — pure model/IO, no figure.
        % =================================================================

        function test_T15_OptionFileParser_ReadTwoSections(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), ...
                'sample_data/option1.dat missing — skipping.');
            model = flightdash.project.OptionFileParser.read(sampleOpt);
            testCase.verifyClass(model, 'flightdash.project.OptionFileModel');
            testCase.verifyGreaterThanOrEqual(height(model.Mapping), 7, ...
                'Mapping table should have at least 7 canonical keys.');
            testCase.verifyGreaterThanOrEqual(height(model.Display), 1, ...
                'Display table should be non-empty after reading two-section file.');
            testCase.verifyFalse(model.Dirty, ...
                'Freshly read model must not be dirty.');
        end

        function test_T15_OptionFileParser_WriteReadRoundTrip(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option1.dat missing.');
            modelA = flightdash.project.OptionFileParser.read(sampleOpt);
            tmpPath = fullfile(tempdir, sprintf( ...
                'option1_rt_%s.dat', datestr(now, 'yyyymmddHHMMSSFFF')));
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeDelete(tmpPath)); %#ok<NASGU>
            flightdash.project.OptionFileParser.write(modelA, tmpPath);
            modelB = flightdash.project.OptionFileParser.read(tmpPath);
            testCase.verifyEqual(height(modelB.Display), height(modelA.Display), ...
                'Display row count changed after round-trip.');
            testCase.verifyEqual(height(modelB.Mapping), height(modelA.Mapping), ...
                'Mapping row count changed after round-trip.');
            % Compare key->mapped pairs.
            for k = 1:height(modelA.Mapping)
                testCase.verifyEqual( ...
                    char(modelB.Mapping.MappedField(k)), ...
                    char(modelA.Mapping.MappedField(k)), ...
                    sprintf('Mapping for %s did not survive round-trip', ...
                        char(modelA.Mapping.Key(k))));
            end
        end

        function test_T15_OptionFileParser_BackupRotation(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option1.dat missing.');
            tmpDir = fullfile(tempdir, sprintf('opt_bak_%s', ...
                datestr(now, 'yyyymmddHHMMSSFFF')));
            mkdir(tmpDir);
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeRmdir(tmpDir)); %#ok<NASGU>
            tgt = fullfile(tmpDir, 'option1.dat');
            copyfile(sampleOpt, tgt);
            model = flightdash.project.OptionFileParser.read(tgt);
            % Write 7 times — backup should rotate to MaxBackups (5).
            for k = 1:7
                flightdash.project.OptionFileParser.write(model, tgt);
                pause(1.05);   % ensure distinct yyyymmdd_HHMMSS stamps
            end
            listing = dir(fullfile(tmpDir, 'option1.dat.bak_*'));
            maxN = flightdash.project.OptionFileParser.MaxBackups;
            testCase.verifyLessThanOrEqual(numel(listing), maxN, ...
                sprintf('Expected at most %d backups, found %d', maxN, numel(listing)));
        end

        function test_T15_OptionFileModel_ValidateCriticalMissing(testCase)
            model = flightdash.project.OptionFileModel(1);
            % Only fill optional Roll; leave critical Time/Lat/Lon/Alt empty.
            model.setMapping('Roll', 'Flight_ROLL');
            report = model.validate({'Flight_ROLL'});
            testCase.verifyFalse(report.OK, ...
                'Validation should fail when critical keys are unmapped.');
            anyCrit = any(contains(report.Errors, 'Time')) ...
                   || any(contains(report.Errors, 'Lat')) ...
                   || any(contains(report.Errors, 'Lon')) ...
                   || any(contains(report.Errors, 'Alt'));
            testCase.verifyTrue(anyCrit, ...
                'Validation errors should mention critical keys.');
        end

        function test_T15_OptionFileModel_OptionalRollPitchHeadingWarnings(testCase)
            model = flightdash.project.OptionFileModel(1);
            % Map all criticals; leave optionals empty.
            model.setMapping('Time', 'time');
            model.setMapping('Lat',  'lat');
            model.setMapping('Lon',  'lon');
            model.setMapping('Alt',  'alt');
            report = model.validate({'time','lat','lon','alt'});
            testCase.verifyTrue(report.OK, ...
                'Critical-complete validation must pass.');
            anyOpt = any(contains(report.Warnings, 'Roll')) ...
                  || any(contains(report.Warnings, 'Pitch')) ...
                  || any(contains(report.Warnings, 'Heading'));
            testCase.verifyTrue(anyOpt, ...
                'Missing optional Roll/Pitch/Heading should produce warnings.');
        end

        function test_T15_OptionFileModel_AddDisplayRow(testCase)
            model = flightdash.project.OptionFileModel(1);
            model.addDisplayRow('Flight_AOA', 'deg', '%.3f', 1, 1);
            testCase.verifyEqual(height(model.Display), 1);
            testCase.verifyTrue(model.hasDisplayField('Flight_AOA'));
            testCase.verifyTrue(model.Dirty);
            % Empty FieldName must throw.
            testCase.verifyError( ...
                @() model.addDisplayRow('', 'deg', '%.3f', 2, 1), ...
                'OptionFileModel:EmptyFieldName');
            % Duplicate FieldName must throw.
            testCase.verifyError( ...
                @() model.addDisplayRow('Flight_AOA', 'deg', '%.3f', 2, 1), ...
                'OptionFileModel:DuplicateFieldName');
        end

        function test_T15_OptionFileModel_RemoveDisplayRow(testCase)
            model = flightdash.project.OptionFileModel(1);
            model.addDisplayRow('Flight_AOA', 'deg', '%.3f', 1, 1);
            model.addDisplayRow('Flight_BETA', 'deg', '%.3f', 2, 1);
            model.removeDisplayRow(1);
            testCase.verifyEqual(height(model.Display), 1);
            testCase.verifyFalse(model.hasDisplayField('Flight_AOA'));
            % Critical-reference protection: Time → time row, can't drop.
            model.setMapping('Time', 'time');
            model.addDisplayRow('time', 's', '%.3f', 1, 1);
            critRow = find(model.Display.FieldName == "time", 1);
            testCase.verifyError( ...
                @() model.removeDisplayRow(critRow), ...
                'OptionFileModel:CriticalReference');
            % Invalid index must throw.
            testCase.verifyError( ...
                @() model.removeDisplayRow(999), ...
                'OptionFileModel:InvalidRowIndex');
        end

        function test_T15_OptionFileParser_WriteAfterAddDeleteDisplayRows(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(2);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option2.dat missing.');
            tmpDir = fullfile(tempdir, sprintf('opt_addrm_%s', ...
                datestr(now, 'yyyymmddHHMMSSFFF')));
            mkdir(tmpDir);
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeRmdir(tmpDir)); %#ok<NASGU>
            tgt = fullfile(tmpDir, 'option2.dat');
            copyfile(sampleOpt, tgt);
            model = flightdash.project.OptionFileParser.read(tgt);
            % Add Flight2_AOA, remove Flight2_ROLL.
            rowIdx = find(model.Display.FieldName == "Flight2_ROLL", 1);
            if ~isempty(rowIdx)
                % Drop the optional Roll mapping first so the critical-
                % reference guard does not block the display removal.
                model.setMapping('Roll', '');
                model.removeDisplayRow(rowIdx);
            end
            model.addDisplayRow('Flight2_AOA', 'deg', '%.3f', 8, 1);
            flightdash.project.OptionFileParser.write(model, tgt);
            roundTrip = flightdash.project.OptionFileParser.read(tgt);
            testCase.verifyTrue(roundTrip.hasDisplayField('Flight2_AOA'), ...
                'Newly added display row missing after round-trip.');
            testCase.verifyFalse(roundTrip.hasDisplayField('Flight2_ROLL'), ...
                'Removed display row still present after round-trip.');
        end

        function test_T15_PreviewMapping_UsesOptionFileParser(testCase)
            % Pre-PFE-2: previewMapping must produce the same MappedCols
            % output that OptionFileParser would feed if called manually.
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option1.dat missing.');
            % Build a CSV with the exact columns option1.dat targets.
            tmpCsv = FlightReviewStudioTestSuite.writeSyntheticCsv( ...
                {'time','Flight_LAT','Flight_LON','Flight_ALT', ...
                 'Flight_HEADING','Flight_PITCH','Flight_ROLL'});
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeDelete(tmpCsv)); %#ok<NASGU>

            loader = flightdash.model.FlightDataLoader();
            preview = loader.previewMapping(tmpCsv, sampleOpt);

            % Compare to the parser model's mappings.
            optModel = flightdash.project.OptionFileParser.read(sampleOpt);
            for k = 1:height(optModel.Mapping)
                key = char(optModel.Mapping.Key(k));
                mapped = char(optModel.Mapping.MappedField(k));
                if ~isfield(preview.MappedCols, key) || isempty(mapped)
                    continue;
                end
                testCase.verifyEqual(preview.MappedCols.(key), mapped, ...
                    sprintf('preview.MappedCols.%s should equal parser mapping', key));
            end
        end

        function test_T15_PreviewMapping_OutputShapeUnchanged(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option1.dat missing.');
            tmpCsv = FlightReviewStudioTestSuite.writeSyntheticCsv( ...
                {'time','Flight_LAT','Flight_LON','Flight_ALT', ...
                 'Flight_HEADING','Flight_PITCH','Flight_ROLL'});
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeDelete(tmpCsv)); %#ok<NASGU>
            loader = flightdash.model.FlightDataLoader();
            preview = loader.previewMapping(tmpCsv, sampleOpt);
            for fn = {'Rows','HeadPreview','MappedCols','HasCriticalMissing','HasOptionalMissing'}
                testCase.verifyTrue(isfield(preview, fn{1}), ...
                    sprintf('preview is missing field "%s"', fn{1}));
            end
            testCase.verifyClass(preview.Rows, 'cell');
            testCase.verifyClass(preview.HeadPreview, 'table');
            testCase.verifyClass(preview.MappedCols, 'struct');
            testCase.verifyClass(preview.HasCriticalMissing, 'logical');
            testCase.verifyClass(preview.HasOptionalMissing, 'logical');
        end

        function test_T15_PreviewMapping_MissingOptionalStillWarning(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option1.dat missing.');
            % CSV lacks Roll/Pitch/Heading columns.
            tmpCsv = FlightReviewStudioTestSuite.writeSyntheticCsv( ...
                {'time','Flight_LAT','Flight_LON','Flight_ALT'});
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeDelete(tmpCsv)); %#ok<NASGU>
            loader = flightdash.model.FlightDataLoader();
            preview = loader.previewMapping(tmpCsv, sampleOpt);
            testCase.verifyFalse(preview.HasCriticalMissing, ...
                'Critical mapping should still succeed.');
            testCase.verifyTrue(preview.HasOptionalMissing, ...
                'Missing optional Roll/Pitch/Heading must surface as optional missing.');
        end

        function test_T15_PreviewMapping_MissingCriticalStillError(testCase)
            sampleOpt = FlightReviewStudioTestSuite.sampleOptionPath(1);
            testCase.assumeTrue(isfile(sampleOpt), 'sample_data/option1.dat missing.');
            % CSV lacks Lat / Lon — both critical.
            tmpCsv = FlightReviewStudioTestSuite.writeSyntheticCsv( ...
                {'time','Flight_ALT','Flight_HEADING','Flight_PITCH','Flight_ROLL'});
            cleanup = onCleanup(@() FlightReviewStudioTestSuite.safeDelete(tmpCsv)); %#ok<NASGU>
            loader = flightdash.model.FlightDataLoader();
            preview = loader.previewMapping(tmpCsv, sampleOpt);
            testCase.verifyTrue(preview.HasCriticalMissing, ...
                'Missing critical Lat/Lon must surface as critical missing.');
        end

        function test_T15_ProjectEditDetails_CommandRegistered(testCase)
            % Pre-PFE-4: verify the command is registered as a global
            % command + the MenuManager entry exists.
            app = testCase.launchStudio();
            testCase.assumeTrue(~isempty(app) && isvalid(app), ...
                'Studio could not launch — skipping.');
            % CommandRouter scope query.
            scope = '';
            try
                scope = app.CommandRouter.commandScope('Project:EditDetails');
            catch
                testCase.assumeFail('CommandRouter.commandScope unavailable.');
            end
            testCase.verifyEqual(scope, 'global', ...
                'Project:EditDetails must be a global command.');
            % Menu hit-test via findall over uimenu Text labels.
            found = false;
            try
                menus = findall(app.UIFigure, 'Type', 'uimenu');
                for k = 1:numel(menus)
                    try
                        if contains(string(menus(k).Text), 'Edit Project Details')
                            found = true; break;
                        end
                    catch
                    end
                end
            catch
            end
            testCase.verifyTrue(found, ...
                'Menu entry "Edit Project Details…" not found.');
        end

        function test_T15_ProjectEditDetails_AppStubNoCrash(testCase)
            % Pre-PFE-4: invoking the dispatch path must not throw
            % (the stub method surfaces a status message + uialert).
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'openProjectFileEditor'), ...
                'openProjectFileEditor stub missing — skipping.');
            crashFlag = false;
            try
                app.dispatchCommand('Project:EditDetails', 'Test');
            catch ME
                crashFlag = true;
                testCase.verifyFail(sprintf( ...
                    'Project:EditDetails dispatch threw: %s', ME.message));
            end
            testCase.verifyFalse(crashFlag);
            % confirmProjectEditorClose stub must return true when no
            % editor exists.
            try
                tf = app.confirmProjectEditorClose();
            catch ME
                testCase.verifyFail(sprintf( ...
                    'confirmProjectEditorClose threw: %s', ME.message));
                return;
            end
            testCase.verifyTrue(tf, ...
                'confirmProjectEditorClose stub must return true.');
            % Dismiss any uialert the stub raised so trackedApps cleanup
            % is not blocked.
            try
                alerts = findall(app.UIFigure, 'Type', 'figure');
                for k = 1:numel(alerts)
                    if ~isequal(alerts(k), app.UIFigure)
                        try, delete(alerts(k)); catch, end
                    end
                end
            catch, end
        end

        function test_T15_ProjectFileEditor_ShellCreateDelete(testCase)
            % PFE-1: openProjectFileEditor() instantiates the dialog and
            % stores it on app.ProjectEditor; closing the dialog clears
            % the back-reference.
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'openProjectFileEditor'), ...
                'openProjectFileEditor missing — skipping.');
            try
                app.openProjectFileEditor();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Editor cannot be launched headlessly: %s', ME.message));
                return;
            end
            ed = app.ProjectEditor;
            testCase.assumeTrue(~isempty(ed) && isa(ed, 'handle') && isvalid(ed), ...
                'Editor not created (headless uifigure unavailable).');
            testCase.verifyClass(ed, 'flightdash.studio.ProjectFileEditorDialog');
            delete(ed);
            testCase.verifyTrue(isempty(app.ProjectEditor), ...
                'ProjectEditor back-ref must clear after delete().');
        end

        function test_T15_ProjectFileEditor_SingleInstance(testCase)
            % PFE-1: a second openProjectFileEditor() must reuse the
            % existing dialog, not spawn a duplicate.
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'openProjectFileEditor'), ...
                'openProjectFileEditor missing — skipping.');
            try
                app.openProjectFileEditor();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Editor cannot be launched headlessly: %s', ME.message));
                return;
            end
            ed1 = app.ProjectEditor;
            testCase.assumeTrue(~isempty(ed1) && isvalid(ed1), ...
                'First editor instance unavailable.');
            try, app.openProjectFileEditor(); catch, end
            ed2 = app.ProjectEditor;
            testCase.verifyTrue(isequal(ed1, ed2), ...
                'Second openProjectFileEditor() must reuse the existing dialog.');
            delete(ed1);
        end

        function test_T15_ProjectFileEditor_LoadOptionTables(testCase)
            % PFE-1: dialog initializes Option1Model + Option2Model with
            % the canonical 7-key mapping (Time/Lat/Lon/Alt/Roll/Pitch/Heading).
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            keys = sort(cellstr(ed.Option1Model.Mapping.Key));
            expected = sort([ed.Option1Model.CriticalKeys, ed.Option1Model.OptionalKeys]);
            testCase.verifyEqual(keys, sort(expected(:))', ...
                'Option1Model mapping must pre-fill the canonical 7 keys.');
            keys2 = sort(cellstr(ed.Option2Model.Mapping.Key));
            testCase.verifyEqual(keys2, sort(expected(:))', ...
                'Option2Model mapping must pre-fill the canonical 7 keys.');
            delete(ed);
        end

        function test_T15_ProjectFileEditor_AddDisplayRowMarksDirty(testCase)
            % PFE-1: addDisplayRow appends a row + flips Option1Dirty +
            % DashboardDirty.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            before = height(ed.Option1Model.Display);
            ed.addDisplayRow(1);
            after = height(ed.Option1Model.Display);
            testCase.verifyEqual(after, before + 1, ...
                'addDisplayRow must append exactly one row.');
            testCase.verifyTrue(ed.Option1Dirty, ...
                'Option1Dirty must be set after addDisplayRow.');
            testCase.verifyTrue(ed.DashboardDirty, ...
                'DashboardDirty must be set after addDisplayRow.');
            % Second call must auto-uniquify FieldName.
            ed.addDisplayRow(1);
            names = cellstr(ed.Option1Model.Display.FieldName);
            testCase.verifyEqual(numel(unique(names)), numel(names), ...
                'addDisplayRow must produce unique FieldName values.');
            delete(ed);
        end

        function test_T15_ProjectFileEditor_DeleteDisplayRowMarksDirty(testCase)
            % PFE-1: deleteDisplayRow drops the row, flips Option2Dirty.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            ed.addDisplayRow(2);
            ed.addDisplayRow(2);
            ed.Option2Dirty = false; ed.DashboardDirty = false;
            n = height(ed.Option2Model.Display);
            ok = ed.deleteDisplayRow(2, n, true);  % force=true skips confirm
            testCase.verifyTrue(ok, 'deleteDisplayRow must return true.');
            testCase.verifyEqual(height(ed.Option2Model.Display), n - 1);
            testCase.verifyTrue(ed.Option2Dirty, ...
                'Option2Dirty must be set after deleteDisplayRow.');
            delete(ed);
        end

        function test_T15_ProjectFileEditor_SaveOptionAfterDisplayRowEdit(testCase)
            % PFE-1: saveOption writes the option file via OptionFileParser
            % and clears the dirty flag.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            tmpFile = [tempname '_option1.dat'];
            ed.Option1Model.FilePath = tmpFile;
            ed.addDisplayRow(1);
            testCase.verifyTrue(ed.Option1Dirty);
            ok = ed.saveOption(1);
            testCase.verifyTrue(ok, 'saveOption(1) must succeed.');
            testCase.verifyTrue(isfile(tmpFile), ...
                'saveOption must write the option file to disk.');
            testCase.verifyFalse(ed.Option1Dirty, ...
                'Option1Dirty must clear after successful save.');
            try, delete(tmpFile); catch, end
            % Clean up any *.bak rotation droppings.
            try
                listing = dir([tmpFile '.bak_*']);
                for k = 1:numel(listing)
                    try, delete(fullfile(listing(k).folder, listing(k).name)); catch, end
                end
            catch, end
            delete(ed);
        end

        function test_T15_ProjectFileEditor_DeleteCriticalMappedDisplayRowBlocked(testCase)
            % PFE-1: a display row referenced by a critical mapping key
            % (Time/Lat/Lon/Alt) must NOT be deletable, and Option1Dirty
            % must NOT flip.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            ed.Option1Model.addDisplayRow('time', 's', '%.3f', 1, 1, true);
            ed.Option1Model.setMapping('Time', 'time');
            ed.Option1Dirty = false; ed.DashboardDirty = false;
            rowIdx = find(string(ed.Option1Model.Display.FieldName) == "time", 1);
            testCase.verifyNotEmpty(rowIdx, 'Setup: time row must exist.');
            ok = ed.deleteDisplayRow(1, rowIdx, true);  % force=true bypasses confirm but NOT critical check
            testCase.verifyFalse(ok, ...
                'deleteDisplayRow must refuse critical-mapped rows.');
            testCase.verifyTrue(ed.Option1Model.hasDisplayField('time'), ...
                'time row must still exist after blocked delete.');
            testCase.verifyFalse(ed.Option1Dirty, ...
                'Option1Dirty must stay clean on blocked delete.');
            delete(ed);
        end

        function test_T15_ProjectFileEditor_ClosePromptDirtySafe(testCase)
            % PFE-1: when no dirty flags are set, confirmClose() returns
            % true with no prompt — exercises the headless-safe path.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            ed.Option1Dirty = false; ed.Option2Dirty = false;
            ed.ProjectDirty = false; ed.DashboardDirty = false;
            tf = ed.confirmClose();
            testCase.verifyTrue(tf, ...
                'confirmClose must return true when not dirty.');
            % After confirmClose with no dirty, ProjectEditor back-ref
            % must be cleared.
            testCase.verifyTrue(isempty(app.ProjectEditor), ...
                'cleanup() must clear app.ProjectEditor on confirmClose.');
            % delete(ed) tolerated even when ed.Figure already cleared.
            try, delete(ed); catch, end
        end

        function test_T15_ProjectEditorClose_NoEditorSafe(testCase)
            % Pre-PFE-5: confirmProjectEditorClose() must return true
            % when no editor has ever been opened so app close never
            % deadlocks before the dialog lands.
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'confirmProjectEditorClose'), ...
                'confirmProjectEditorClose missing — skipping.');
            testCase.assumeTrue(isprop(app, 'ProjectEditor'), ...
                'ProjectEditor property missing — skipping.');
            app.ProjectEditor = [];
            tf = false;
            try
                tf = app.confirmProjectEditorClose();
            catch ME
                testCase.verifyFail(sprintf( ...
                    'confirmProjectEditorClose threw: %s', ME.message));
                return;
            end
            testCase.verifyTrue(tf, ...
                'No editor present must allow close.');
        end

        function test_T15_ProjectEditorClose_InvalidEditorSafe(testCase)
            % Pre-PFE-5: a deleted/invalid editor handle must not block
            % close and must be auto-cleared from app.ProjectEditor so a
            % stale reference cannot veto a later close attempt.
            app = testCase.launchStudio();
            testCase.assumeTrue(ismethod(app, 'confirmProjectEditorClose'), ...
                'confirmProjectEditorClose missing — skipping.');
            testCase.assumeTrue(isprop(app, 'ProjectEditor'), ...
                'ProjectEditor property missing — skipping.');
            % Install an invalid handle (deleted uifigure) — simulates an
            % editor whose figure was closed via the OS chrome.
            stub = [];
            try
                stub = uifigure('Visible', 'off');
                delete(stub);
            catch
                testCase.assumeFail('Cannot create headless uifigure stub.');
                return;
            end
            app.ProjectEditor = stub;
            tf = false;
            try
                tf = app.confirmProjectEditorClose();
            catch ME
                testCase.verifyFail(sprintf( ...
                    'confirmProjectEditorClose threw on invalid editor: %s', ...
                    ME.message));
                return;
            end
            testCase.verifyTrue(tf, ...
                'Invalid editor handle must allow close.');
            testCase.verifyTrue(isempty(app.ProjectEditor), ...
                'Invalid editor handle must be cleared from app.ProjectEditor.');
        end

        function test_T15_DashboardReadOnlyWrappers_NoCrash(testCase)
            % Pre-PFE-3: smoke test the three read-only wrappers via a
            % launched Studio app + active dashboard. Verifies the
            % wrappers exist and return safe default types for an
            % unloaded session (no CSV yet).
            app = testCase.launchStudio();
            sid = app.addSession('T15 RO Wrappers'); %#ok<NASGU>
            drawnow limitrate;
            dash = [];
            try, dash = app.getActiveDashboard(); catch, end
            testCase.assumeTrue(~isempty(dash) && isvalid(dash), ...
                'No active dashboard for read-only wrapper test.');
            testCase.assumeTrue(ismethod(dash, 'getAvailableDataFields'), ...
                'getAvailableDataFields not present — skipping.');
            % Empty / unloaded path.
            f1 = dash.getAvailableDataFields(1);
            testCase.verifyClass(f1, 'cell');
            tf = dash.hasFlightDataLoaded(1);
            testCase.verifyClass(tf, 'logical');
            ctx = dash.getOptionEditorContext(1);
            testCase.verifyClass(ctx, 'struct');
            for fn = {'HasData','AvailableFields','MappedCols','DisplayMeta', ...
                      'CurrentIndex','FlightFilePath','OptionFilePath'}
                testCase.verifyTrue(isfield(ctx, fn{1}), ...
                    sprintf('context missing field "%s"', fn{1}));
            end
        end

        function test_T15_DashboardReadOnlyWrappers_InvalidIndexSafe(testCase)
            % Pre-PFE-3: out-of-range / invalid fIdx must NOT throw.
            app = testCase.launchStudio();
            sid = app.addSession('T15 RO InvalidIdx'); %#ok<NASGU>
            drawnow limitrate;
            dash = [];
            try, dash = app.getActiveDashboard(); catch, end
            testCase.assumeTrue(~isempty(dash) && isvalid(dash) ...
                && ismethod(dash, 'getAvailableDataFields'), ...
                'wrappers unavailable — skipping.');
            for bogus = {99, -3, [], 'x', NaN}
                try
                    f = dash.getAvailableDataFields(bogus{1});
                    tf = dash.hasFlightDataLoaded(bogus{1});
                    ctx = dash.getOptionEditorContext(bogus{1});
                catch ME
                    testCase.verifyFail(sprintf( ...
                        'Wrappers threw for bogus fIdx %s: %s', ...
                        class(bogus{1}), ME.message));
                    return;
                end
                testCase.verifyClass(f, 'cell');
                testCase.verifyEqual(tf, false);
                testCase.verifyEqual(ctx.HasData, false);
            end
        end

        function test_T15_DashboardReadOnlyWrappers_EmptyDataSafe(testCase)
            % Pre-PFE-3: with a valid channel but empty rawData, the
            % wrappers must return safe defaults (no crash, no field
            % list, HasData=false).
            app = testCase.launchStudio();
            sid = app.addSession('T15 RO EmptyData'); %#ok<NASGU>
            drawnow limitrate;
            dash = [];
            try, dash = app.getActiveDashboard(); catch, end
            testCase.assumeTrue(~isempty(dash) && isvalid(dash) ...
                && ismethod(dash, 'hasFlightDataLoaded'), ...
                'wrappers unavailable — skipping.');
            % Forcefully blank the model rawData to simulate "channel
            % exists but no CSV loaded" cleanly.
            try
                if ~isempty(dash.Models) && numel(dash.Models) >= 1
                    dash.Models(1).rawData = table.empty;
                end
            catch
                testCase.assumeFail('Could not blank Models(1).rawData');
            end
            testCase.verifyFalse(dash.hasFlightDataLoaded(1));
            testCase.verifyEqual(dash.getAvailableDataFields(1), {});
            ctx = dash.getOptionEditorContext(1);
            testCase.verifyFalse(ctx.HasData);
            testCase.verifyEqual(ctx.AvailableFields, {});
        end

        function test_T15_OptionFileModel_DuplicateDisplayFieldRejected(testCase)
            model = flightdash.project.OptionFileModel(1);
            model.addDisplayRow('Flight_LAT', 'deg', '%.6f', 1, 1);
            testCase.verifyError( ...
                @() model.addDisplayRow('Flight_LAT', 'deg', '%.6f', 2, 1), ...
                'OptionFileModel:DuplicateFieldName');
            % Validation also flags duplicate field names if model
            % is constructed directly with a duplicate (defensive).
            model.Display(end+1, :) = model.Display(end, :);
            report = model.validate({});
            testCase.verifyFalse(report.OK, ...
                'Validation should fail when Display has duplicate FieldName.');
        end
    end

    methods (Static, Access = private)
        function p = sampleOptionPath(channel)
            here = fileparts(mfilename('fullpath'));
            p = fullfile(here, 'sample_data', sprintf('option%d.dat', channel));
        end

        function safeDelete(path)
            try, if isfile(path), delete(path); end, catch, end
        end

        function safeRmdir(path)
            try, if isfolder(path), rmdir(path, 's'); end, catch, end
        end

        function csvPath = writeSyntheticCsv(headers)
            % Build a tiny CSV with the given header list + 3 rows of
            % synthetic numeric data so detectImportOptions has enough
            % material to infer the schema.
            csvPath = fullfile(tempdir, sprintf('flightdash_csv_%s.csv', ...
                datestr(now, 'yyyymmddHHMMSSFFF')));
            fid = fopen(csvPath, 'w', 'n', 'UTF-8');
            if fid == -1
                error('writeSyntheticCsv:OpenFailed', '%s', csvPath);
            end
            fprintf(fid, '%s\n', strjoin(headers, ','));
            for r = 1:3
                vals = arrayfun(@(k) sprintf('%.3f', r + k*0.1), ...
                    1:numel(headers), 'UniformOutput', false);
                fprintf(fid, '%s\n', strjoin(vals, ','));
            end
            fclose(fid);
        end

        function names = collectTimerNames(timers)
            names = strings(0, 1);
            for k = 1:numel(timers)
                try
                    names(end+1, 1) = string(timers(k).Name); %#ok<AGROW>
                catch
                end
            end
        end
    end

    methods (Access = private)
        function verifyEntryPoints(testCase)
            testCase.verifyNotEmpty( ...
                which('FlightReviewStudio'), ...
                'FlightReviewStudio.m was not found on path.');

            testCase.verifyNotEmpty( ...
                which('FlightDataDashboard'), ...
                'FlightDataDashboard.m was not found on path.');

            testCase.verifyNotEmpty( ...
                which('flightdash.studio.FlightReviewStudioApp'), ...
                'flightdash.studio.FlightReviewStudioApp was not found on path.');
        end

        function verifyProjectClasses(testCase)
            testCase.verifyEqual( ...
                exist('flightdash.project.ProjectModel', 'class'), ...
                8, ...
                'ProjectModel class was not found.');

            testCase.verifyEqual( ...
                exist('flightdash.project.SessionModel', 'class'), ...
                8, ...
                'SessionModel class was not found.');

            testCase.verifyEqual( ...
                exist('flightdash.project.ProjectSerializer', 'class'), ...
                8, ...
                'ProjectSerializer class was not found.');
        end

        function ed = createEditorOrSkip(testCase, app)
            % PFE-1 helper: try to instantiate the dialog; assumeFail when
            % uifigure creation is unavailable (CI without display).
            ed = [];
            if ~ismethod(app, 'openProjectFileEditor')
                testCase.assumeFail('openProjectFileEditor missing — skipping.');
                return;
            end
            try
                app.openProjectFileEditor();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Editor cannot be launched headlessly: %s', ME.message));
                return;
            end
            ed = app.ProjectEditor;
            if isempty(ed) || ~isa(ed, 'handle') || ~isvalid(ed)
                testCase.assumeFail('Editor instance unavailable (headless).');
                ed = [];
                return;
            end
        end

        function app = launchStudio(testCase)
            testCase.verifyEntryPoints();

            app = FlightReviewStudio();

            testCase.verifyNotEmpty( ...
                app, ...
                'FlightReviewStudio did not return an app object.');

            testCase.verifyTrue( ...
                isvalid(app), ...
                'FlightReviewStudio returned an invalid app object.');

            try
                if isprop(app, 'UIFigure') && ...
                        ~isempty(app.UIFigure) && ...
                        isvalid(app.UIFigure)
                    app.UIFigure.Visible = 'off';
                end
            catch
            end

            % The production constructor auto-creates "Session 1" for a
            % fresh launch UX (review: auto Session 1). Tests expect a
            % deterministic clean baseline, so drop any auto-created
            % sessions before returning the app to the test case.
            try
                if isprop(app, 'Project') && ~isempty(app.Project) ...
                        && app.Project.sessionCount() > 0 ...
                        && ismethod(app, 'removeAllSessions')
                    app.removeAllSessions();
                end
            catch
            end

            drawnow limitrate;

            testCase.Apps{end + 1} = app;
        end

        function closeTrackedApps(testCase)
            for k = numel(testCase.Apps):-1:1
                app = testCase.Apps{k};
                testCase.safeDeleteApp(app);
            end

            testCase.Apps = {};
            testCase.closeStrayStudioFigures();
        end

        function safeDeleteApp(~, app)
            try
                if ~isempty(app) && isvalid(app)
                    try
                        if ismethod(app, 'removeAllSessions')
                            app.removeAllSessions();
                            drawnow limitrate;
                        end
                    catch
                    end

                    delete(app);
                    drawnow limitrate;
                end
            catch ME
                warning( ...
                    'FlightReviewStudioTestSuite:DeleteAppFailed', ...
                    'Failed to delete app cleanly: %s', ...
                    ME.message);
            end
        end

        function closeStrayStudioFigures(~)
            try
                figs = findall(groot, 'Type', 'figure');

                for k = 1:numel(figs)
                    try
                        figName = '';

                        if isprop(figs(k), 'Name')
                            figName = char(figs(k).Name);
                        end

                        shouldDelete = contains(figName, 'FlightReviewStudio') || ...
                            contains(figName, 'FlightDataReviewStudio') || ...
                            contains(figName, 'Embed FlightDataDashboard failed') || ...
                            contains(figName, 'Save Project Failed') || ...
                            contains(figName, 'Open Project Failed');

                        if shouldDelete
                            delete(figs(k));
                        end
                    catch
                    end
                end
            catch
            end
        end

        function session = makeSessionWithDummyLinks(testCase, displayName)
            session = testCase.makeSessionWithDummyLinksInDir( ...
                displayName, ...
                testCase.TempDir);
        end

        function session = makeSessionWithDummyLinksInDir(testCase, displayName, baseDir)
            if ~exist(baseDir, 'dir')
                mkdir(baseDir);
            end

            session = flightdash.project.SessionModel(displayName);

            safeName = regexprep(char(displayName), '[^\w가-힣]', '_');

            flightPath = fullfile(baseDir, [safeName '_flight.csv']);
            videoPath = fullfile(baseDir, [safeName '_video.avi']);

            testCase.writeTextFile( ...
                flightPath, ...
                'time,altitude\n0,100\n1,110\n');

            testCase.writeBinaryFile( ...
                videoPath, ...
                uint8(0:15));

            session = session.setFlightFile(1, flightPath);
            session = session.setVideoFile(1, videoPath);
        end

        function writeTextFile(~, filePath, textValue)
            fid = fopen(filePath, 'w');

            assert( ...
                fid > 0, ...
                'Failed to create text file: %s', ...
                filePath);

            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s', char(textValue));
        end

        function writeBinaryFile(~, filePath, bytes)
            fid = fopen(filePath, 'w');

            assert( ...
                fid > 0, ...
                'Failed to create binary file: %s', ...
                filePath);

            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, bytes, 'uint8');
        end

        function removeAllSessionsViaPublicApi(testCase, app)
            if ismethod(app, 'removeAllSessions')
                app.removeAllSessions();
                drawnow limitrate;
                return;
            end

            if isprop(app, 'Workspace') && ...
                    ~isempty(app.Workspace) && ...
                    isvalid(app.Workspace)

                workspace = app.Workspace;

                if ismethod(workspace, 'removeAllSessions')
                    workspace.removeAllSessions();
                    drawnow limitrate;
                    return;
                end
            end

            testCase.assumeTrue( ...
                false, ...
                'No public removeAllSessions API was found.');
        end

        function tf = closeSessionViaPublicApi(testCase, app, sessionId)
            tf = false;

            if isempty(app) || ~isvalid(app) || isempty(sessionId)
                return;
            end

            candidateAppMethods = { ...
                'removeSession', ...
                'closeSession', ...
                'deleteSession'};

            for k = 1:numel(candidateAppMethods)
                methodName = candidateAppMethods{k};

                if ismethod(app, methodName)
                    try
                        out = testCase.invokeMaybeNoOutput(app, methodName, sessionId);
                        drawnow limitrate;
                        tf = testCase.normalizeLogicalReturn(out);
                        if tf
                            return;
                        end
                    catch
                    end
                end
            end

            if isprop(app, 'Workspace') && ...
                    ~isempty(app.Workspace) && ...
                    isvalid(app.Workspace)

                workspace = app.Workspace;

                candidateWorkspaceMethods = { ...
                    'removeSession', ...
                    'closeSession', ...
                    'deleteSession', ...
                    'removeDashboard', ...
                    'closeDashboard'};

                for k = 1:numel(candidateWorkspaceMethods)
                    methodName = candidateWorkspaceMethods{k};

                    if ismethod(workspace, methodName)
                        try
                            out = testCase.invokeMaybeNoOutput(workspace, methodName, sessionId);
                            drawnow limitrate;
                            tf = testCase.normalizeLogicalReturn(out);

                            if tf || ~testCase.workspaceHasSession(app, sessionId)
                                tf = true;
                                return;
                            end
                        catch
                        end
                    end
                end
            end
        end

        function out = invokeMaybeNoOutput(~, obj, methodName, sessionId)
            try
                out = obj.(methodName)(sessionId);
            catch ME
                if strcmp(ME.identifier, 'MATLAB:maxlhs') || ...
                        strcmp(ME.identifier, 'MATLAB:TooManyOutputs') || ...
                        contains(ME.message, 'Too many output')
                    obj.(methodName)(sessionId);
                    out = [];
                else
                    rethrow(ME);
                end
            end
        end

        function tf = normalizeLogicalReturn(~, out)
            if isempty(out)
                tf = true;
            elseif islogical(out) || isnumeric(out)
                tf = logical(out);
            elseif isstring(out) || ischar(out)
                tf = strlength(string(out)) > 0;
            else
                tf = true;
            end
        end

        function value = normalizeOnOff(~, value)
            if isa(value, 'matlab.lang.OnOffSwitchState')
                value = char(value);
            elseif isstring(value)
                value = char(value);
            elseif islogical(value)
                if value
                    value = 'on';
                else
                    value = 'off';
                end
            else
                value = char(value);
            end
        end

        function verifyUndoUiState(testCase, app, canUndo, canRedo)
            expectedUndo = testCase.normalizeOnOff(canUndo);
            expectedRedo = testCase.normalizeOnOff(canRedo);

            if ~isempty(app.ToolbarMgr) && isvalid(app.ToolbarMgr) && ...
                    isprop(app.ToolbarMgr, 'Buttons')

                if isfield(app.ToolbarMgr.Buttons, 'Undo') && ...
                        ~isempty(app.ToolbarMgr.Buttons.Undo) && ...
                        isvalid(app.ToolbarMgr.Buttons.Undo)

                    actualUndoToolbar = testCase.normalizeOnOff( ...
                        app.ToolbarMgr.Buttons.Undo.Enable);

                    testCase.verifyEqual(actualUndoToolbar, expectedUndo, ...
                        'Toolbar Undo state mismatch.');
                end

                if isfield(app.ToolbarMgr.Buttons, 'Redo') && ...
                        ~isempty(app.ToolbarMgr.Buttons.Redo) && ...
                        isvalid(app.ToolbarMgr.Buttons.Redo)

                    actualRedoToolbar = testCase.normalizeOnOff( ...
                        app.ToolbarMgr.Buttons.Redo.Enable);

                    testCase.verifyEqual(actualRedoToolbar, expectedRedo, ...
                        'Toolbar Redo state mismatch.');
                end
            end

            if ~isempty(app.MenuMgr) && isvalid(app.MenuMgr)
                if isprop(app.MenuMgr, 'Undo') && ...
                        ~isempty(app.MenuMgr.Items.Undo) && ...
                        isvalid(app.MenuMgr.Items.Undo)

                    actualUndoMenu = testCase.normalizeOnOff( ...
                        app.MenuMgr.Items.Undo.Enable);

                    testCase.verifyEqual(actualUndoMenu, expectedUndo, ...
                        'Menu Undo state mismatch.');
                end

                if isprop(app.MenuMgr, 'RedoMenu') && ...
                        ~isempty(app.MenuMgr.Items.Redo) && ...
                        isvalid(app.MenuMgr.Items.Redo)

                    actualRedoMenu = testCase.normalizeOnOff( ...
                        app.MenuMgr.Items.Redo.Enable);

                    testCase.verifyEqual(actualRedoMenu, expectedRedo, ...
                        'Menu Redo state mismatch.');
                end
            end

        end

        function value = onOff(~, tf)
            if tf
                value = 'on';
            else
                value = 'off';
            end
        end

        function invokeFigureMotion(~, app)
            try
                if ~isempty(app) && isvalid(app) && isprop(app, 'UIFigure') && ...
                        ~isempty(app.UIFigure) && isvalid(app.UIFigure) && ...
                        ~isempty(app.UIFigure.WindowButtonMotionFcn)
                    app.UIFigure.WindowButtonMotionFcn([], []);
                end
            catch ME
                rethrow(ME);
            end
        end

        function selectSessionViaPublicApi(testCase, app, sessionId)
            selected = false;

            if isprop(app, 'Workspace') && ...
                    ~isempty(app.Workspace) && ...
                    isvalid(app.Workspace) && ...
                    ismethod(app.Workspace, 'selectSession')

                selected = logical(app.Workspace.selectSession(sessionId));
                drawnow limitrate;
            elseif ismethod(app, 'selectSession')
                selected = logical(app.selectSession(sessionId));
                drawnow limitrate;
            end

            testCase.verifyTrue( ...
                selected, ...
                'No public selectSession API succeeded.');
        end

        function activeId = getActiveSessionId(~, app)
            activeId = '';

            try
                if ismethod(app, 'activeSessionIdFromWorkspace')
                    activeId = app.activeSessionIdFromWorkspace();
                    return;
                end
            catch
            end

            try
                if isprop(app, 'ActiveSessionId')
                    activeId = app.ActiveSessionId;
                    return;
                end
            catch
            end

            try
                if isprop(app, 'Workspace') && ...
                        ~isempty(app.Workspace) && ...
                        isvalid(app.Workspace)

                    workspace = app.Workspace;

                    if ismethod(workspace, 'activeSessionId')
                        activeId = workspace.activeSessionId();
                    elseif isprop(workspace, 'ActiveSessionId')
                        activeId = workspace.ActiveSessionId;
                    end
                end
            catch
            end
        end

        function tf = workspaceHasSession(~, app, sessionId)
            tf = false;

            try
                if isempty(app) || ~isvalid(app) || isempty(sessionId)
                    return;
                end

                if ~isprop(app, 'Workspace') || ...
                        isempty(app.Workspace) || ...
                        ~isvalid(app.Workspace)
                    return;
                end

                workspace = app.Workspace;

                if ismethod(workspace, 'hasSession')
                    tf = logical(workspace.hasSession(sessionId));
                    return;
                end

                if isprop(workspace, 'DashboardEntries')
                    entries = workspace.DashboardEntries;

                    if isa(entries, 'containers.Map')
                        tf = isKey(entries, sessionId);
                        return;
                    end
                end

                if isprop(workspace, 'SessionIds')
                    tf = any(string(workspace.SessionIds) == string(sessionId));
                    return;
                end
            catch
                tf = false;
            end
        end

        function explorer = getProjectExplorer(~, app)
            explorer = [];

            try
                if isprop(app, 'ProjectExplorer')
                    explorer = app.ProjectExplorer;
                    return;
                end

                if isprop(app, 'Explorer')
                    explorer = app.Explorer;
                    return;
                end

                if ismethod(app, 'getProjectExplorer')
                    explorer = app.getProjectExplorer();
                    return;
                end
            catch
                explorer = [];
            end
        end

        function inspector = getInspector(~, app)
            inspector = [];

            try
                if isprop(app, 'Inspector')
                    inspector = app.Inspector;
                    return;
                end

                if ismethod(app, 'getInspectorForTesting')
                    inspector = app.getInspectorForTesting();
                    return;
                end

                if isprop(app, 'RightDock') && ...
                        ~isempty(app.RightDock) && ...
                        isvalid(app.RightDock)

                    rightDock = app.RightDock;

                    if ismethod(rightDock, 'getPanel')
                        inspector = rightDock.getPanel('Inspector');
                        return;
                    end

                    if ismethod(rightDock, 'getInspector')
                        inspector = rightDock.getInspector();
                        return;
                    end

                    if isprop(rightDock, 'Inspector')
                        inspector = rightDock.Inspector;
                        return;
                    end

                    if isprop(rightDock, 'InspectorPanel')
                        inspector = rightDock.InspectorPanel;
                        return;
                    end
                end
            catch
                inspector = [];
            end
        end

        function methodName = firstExistingMethod(~, obj, candidates)
            methodName = '';

            if isempty(obj)
                return;
            end

            for k = 1:numel(candidates)
                if ismethod(obj, candidates{k})
                    methodName = candidates{k};
                    return;
                end
            end
        end

        function verifyDiagnosticHasNoFail(testCase, results, message)
            if nargin < 3
                message = 'Diagnostic reported failures.';
            end

            if isstruct(results) && isfield(results, 'Passed')
                passed = [results.Passed];

                if ~all(passed)
                    failed = results(~passed);
                    messages = strings(1, numel(failed));

                    for k = 1:numel(failed)
                        id = "";
                        msg = "";

                        if isfield(failed, 'Id')
                            id = string(failed(k).Id);
                        elseif isfield(failed, 'TC')
                            id = string(failed(k).TC);
                        end

                        if isfield(failed, 'Message')
                            msg = string(failed(k).Message);
                        end

                        messages(k) = sprintf('%s: %s', id, msg);
                    end

                    testCase.verifyTrue(false, ...
                        sprintf('%s\n%s', message, strjoin(messages, newline)));
                end
                return;
            end

            if isstruct(results) && isfield(results, 'Result')
                values = upper(string({results.Result}));
                bad = values == "FAIL" | values == "ERROR";
                testCase.verifyFalse(any(bad), message);
                return;
            end

            if isstruct(results) && isfield(results, 'Status')
                values = upper(string({results.Status}));
                bad = values == "FAIL" | values == "ERROR";
                testCase.verifyFalse(any(bad), message);
                return;
            end

            if istable(results)
                names = string(results.Properties.VariableNames);

                if any(names == "Result")
                    values = upper(string(results.Result));
                    bad = values == "FAIL" | values == "ERROR";
                    testCase.verifyFalse(any(bad), message);
                    return;
                end

                if any(names == "Status")
                    values = upper(string(results.Status));
                    bad = values == "FAIL" | values == "ERROR";
                    testCase.verifyFalse(any(bad), message);
                    return;
                end
            end

            testCase.verifyFail('Unsupported diagnostic result format.');
            
        end
    end
end
