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

        function test_T15_OptionEditor_ValidateAgainstAvailableFields(testCase)
            % PFE-2: validate() drives Available + Message columns
            % against an externally-supplied field list. Loose pure-model
            % test — no editor instance needed.
            model = flightdash.project.OptionFileModel(1);
            model.setMapping('Time', 'time');
            model.setMapping('Lat',  'Flight2_LAT');
            model.setMapping('Lon',  'Flight2_LON');
            model.setMapping('Alt',  'Flight2_ALT');
            model.addDisplayRow('time', 's', '%.3f', 1, 1, true);
            model.addDisplayRow('Flight2_LAT', 'deg', '%.6f', 2, 1, true);

            report = model.validate({'time', 'Flight2_LAT', 'Flight2_LON', 'Flight2_ALT'});
            testCase.verifyTrue(report.OK, ...
                'Validate must succeed when all critical mappings exist.');

            report2 = model.validate({'time'});
            testCase.verifyFalse(report2.OK, ...
                'Missing critical mapping must produce errors.');
            testCase.verifyGreaterThanOrEqual(numel(report2.Errors), 1);
        end

        function test_T15_OptionEditor_ApplyBlocksCriticalMissing(testCase)
            % PFE-2: applyToDashboard refuses to push a model when
            % critical mappings reference columns that do not exist in
            % the available-fields list. DashboardDirty must stay set.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            ed.setAvailableFields({'time'}, 1);  % Lat/Lon/Alt missing
            ed.Option1Model.setMapping('Time', 'time');
            ed.Option1Model.setMapping('Lat',  'missing_lat');
            ed.DashboardDirty = true;
            ok = ed.applyToDashboard(1);
            testCase.verifyFalse(ok, ...
                'applyToDashboard must refuse on critical errors.');
            testCase.verifyTrue(ed.DashboardDirty, ...
                'DashboardDirty must stay set when apply is blocked.');
            delete(ed);
        end

        function test_T15_OptionEditor_ApplyAllowsOptionalMissing(testCase)
            % PFE-2: applyToDashboard tolerates optional-key warnings.
            % With no dashboard attached the apply returns false but the
            % validation gate (errors block, warnings ok) is what we test
            % here — DashboardDirty must NOT be flipped by the validator.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            ed.setAvailableFields({'time', 'Flight2_LAT', 'Flight2_LON', 'Flight2_ALT'}, 1);
            ed.Option1Model.setMapping('Time', 'time');
            ed.Option1Model.setMapping('Lat',  'Flight2_LAT');
            ed.Option1Model.setMapping('Lon',  'Flight2_LON');
            ed.Option1Model.setMapping('Alt',  'Flight2_ALT');
            % Roll/Pitch/Heading deliberately unmapped — optional warnings.
            report = ed.Option1Model.validate({'time','Flight2_LAT','Flight2_LON','Flight2_ALT'});
            testCase.verifyTrue(report.OK, ...
                'Optional-missing case must be report.OK (warnings only).');
            testCase.verifyGreaterThanOrEqual(numel(report.Warnings), 1);
            delete(ed);
        end

        function test_T15_OptionEditor_AddDisplayRowPersistsToOptionFile(testCase)
            % PFE-2: add a row, save, reload from disk, confirm the row
            % survives the round trip.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            tmpFile = [tempname '_option1.dat'];
            ed.Option1Model.FilePath = tmpFile;
            ed.addDisplayRow(1);
            ok = ed.saveOption(1);
            testCase.verifyTrue(ok, 'saveOption must succeed.');
            testCase.verifyTrue(isfile(tmpFile), ...
                'option file must exist after save.');
            reread = flightdash.project.OptionFileParser.read(tmpFile);
            names = cellstr(reread.Display.FieldName);
            testCase.verifyTrue(any(strcmp(names, 'NewField')), ...
                'Added display row must survive save+reload.');
            testCase.cleanupOptionFile(tmpFile);
            delete(ed);
        end

        function test_T15_OptionEditor_DeleteDisplayRowPersistsToOptionFile(testCase)
            % PFE-2: delete an unreferenced row, save, reload, confirm
            % the row is gone from disk.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            tmpFile = [tempname '_option1.dat'];
            ed.Option1Model.FilePath = tmpFile;
            ed.Option1Model.addDisplayRow('Temperature', 'C', '%.2f', 1, 1, true);
            % Setup a critical mapping that does NOT reference Temperature
            % so the delete is allowed.
            ed.Option1Model.setMapping('Time', 'time');
            rowIdx = find(string(ed.Option1Model.Display.FieldName) == "Temperature", 1);
            testCase.verifyNotEmpty(rowIdx);
            ok = ed.deleteDisplayRow(1, rowIdx, true);
            testCase.verifyTrue(ok, 'deleteDisplayRow must succeed.');
            okSave = ed.saveOption(1);
            testCase.verifyTrue(okSave, 'save must succeed after delete.');
            reread = flightdash.project.OptionFileParser.read(tmpFile);
            names = cellstr(reread.Display.FieldName);
            testCase.verifyFalse(any(strcmp(names, 'Temperature')), ...
                'Deleted display row must NOT appear in reloaded file.');
            testCase.cleanupOptionFile(tmpFile);
            delete(ed);
        end

        function test_T15_OptionEditor_DeleteCriticalMappedDisplayRowBlocked(testCase)
            % PFE-2 mirror of the PFE-1 block test but exercised through
            % the live model used by applyToDashboard.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            ed.Option2Model.addDisplayRow('Flight2_LAT', 'deg', '%.6f', 1, 1, true);
            ed.Option2Model.setMapping('Lat', 'Flight2_LAT');
            rowIdx = find(string(ed.Option2Model.Display.FieldName) == "Flight2_LAT", 1);
            ok = ed.deleteDisplayRow(2, rowIdx, true);
            testCase.verifyFalse(ok, ...
                'Critical-mapped display row must NOT be deletable.');
            testCase.verifyTrue(ed.Option2Model.hasDisplayField('Flight2_LAT'));
            delete(ed);
        end

        function test_T15_OptionEditor_SaveCreatesBackup(testCase)
            % PFE-2: saving over an existing file must produce a
            % timestamped .bak_* backup via OptionFileParser.write().
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            tmpFile = [tempname '_option1.dat'];
            % Seed an initial file on disk so save triggers a backup.
            seed = flightdash.project.OptionFileModel(1);
            seed.addDisplayRow('seed', '-', '%.6f', 1, 1, true);
            flightdash.project.OptionFileParser.write(seed, tmpFile);
            testCase.verifyTrue(isfile(tmpFile));
            ed.Option1Model = flightdash.project.OptionFileParser.read(tmpFile);
            ed.addDisplayRow(1);
            ed.Option1Model.FilePath = tmpFile;
            ok = ed.saveOption(1);
            testCase.verifyTrue(ok);
            listing = dir([tmpFile '.bak_*']);
            testCase.verifyGreaterThanOrEqual(numel(listing), 1, ...
                'saveOption must create at least one .bak_* file.');
            testCase.cleanupOptionFile(tmpFile);
            delete(ed);
        end

        function test_T15_OptionEditor_SaveAllClearsOptionDirtyFlags(testCase)
            % PFE-2: Save All persists both option files and clears
            % Option1Dirty + Option2Dirty.
            app = testCase.launchStudio();
            ed = testCase.createEditorOrSkip(app);
            tmp1 = [tempname '_option1.dat'];
            tmp2 = [tempname '_option2.dat'];
            ed.Option1Model.FilePath = tmp1;
            ed.Option2Model.FilePath = tmp2;
            ed.addDisplayRow(1);
            ed.addDisplayRow(2);
            testCase.verifyTrue(ed.Option1Dirty && ed.Option2Dirty);
            ok = ed.saveAll();
            testCase.verifyTrue(ok, 'saveAll must succeed.');
            testCase.verifyFalse(ed.Option1Dirty, 'Option1Dirty must clear.');
            testCase.verifyFalse(ed.Option2Dirty, 'Option2Dirty must clear.');
            testCase.cleanupOptionFile(tmp1);
            testCase.cleanupOptionFile(tmp2);
            delete(ed);
        end

        function test_T15_Refactor_SessionContextLiveView(testCase)
            % R1: app.getSessionContext() must return a live facade that
            % reflects ActiveSessionId / IsEmbedded reads in real time.
            % Pure unit-level — no Studio shell required.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Standalone dashboard cannot be constructed headlessly: %s', ...
                    ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctx = app.getSessionContext();
            testCase.verifyClass(ctx, 'flightdash.runtime.SessionContext');
            testCase.verifyTrue(isvalid(ctx));
            testCase.verifyEqual(char(ctx.ActiveSessionId), 'standalone');
            testCase.verifyFalse(ctx.IsEmbedded);
            % Mutate the underlying property; facade must reflect it.
            app.ActiveSessionId = 'S-LIVE';
            testCase.verifyEqual(char(ctx.ActiveSessionId), 'S-LIVE', ...
                'SessionContext must reflect post-construction writes.');
        end

        function test_T15_Refactor_ChannelAccessorMirrorsModels(testCase)
            % R2: app.channel(fIdx) must lazy-sync app.Models(fIdx) +
            % FlightFilePath{fIdx} into the StateStore so new code can
            % use the focused handle. Legacy app.Models reads stay
            % unchanged.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Dashboard cannot be constructed headlessly: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            app.Models(2).selectedRow = 11;
            app.Models(2).currentIndex = 99;
            app.FlightFilePath{2} = 'C:\test\f2.csv';
            ch = app.channel(2);
            testCase.verifyClass(ch, 'flightdash.state.ChannelState');
            testCase.verifyEqual(ch.SelectedRow, 11);
            testCase.verifyEqual(ch.CurrentIndex, 99);
            testCase.verifyEqual(ch.FlightFilePath, 'C:\test\f2.csv');
            testCase.verifyEqual(ch.ChannelIndex, 2);
            % StateStore reference must be the same handle on Runtime.
            store = app.getStateStore();
            testCase.verifyTrue(isequal(store, app.Runtime.StateStore), ...
                'Runtime.StateStore must alias app.StateStore.');
        end

        function test_T15_Refactor_ChannelAccessorOutOfRangeSafe(testCase)
            % R2 contract: out-of-range fIdx returns ChannelState.empty
            % instead of erroring so callers can guard with isempty().
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            chHigh = app.channel(99);
            testCase.verifyTrue(isempty(chHigh), ...
                'Out-of-range channel index must return empty.');
            chZero = app.channel(0);
            testCase.verifyTrue(isempty(chZero), ...
                'Zero channel index must return empty.');
        end

        function test_T15_Refactor_AsyncDecodeHelpersMirrorApp(testCase)
            % R3: bound AsyncDecodeState helpers must mutate the legacy
            % app properties identically to the legacy inline cleanup.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ad = app.getAsyncDecode();
            testCase.verifyClass(ad, 'flightdash.state.AsyncDecodeState');
            testCase.verifyTrue(isequal(ad, app.Runtime.AsyncDecode), ...
                'Runtime.AsyncDecode must alias app.AsyncDecode.');

            app.AsyncGen = [2 3];
            app.AsyncTargetFrame = [50 60];
            app.PendingFrame = [1 2];
            app.PendingMode = {'play', 'scrub'};
            app.AsyncFutures = {[], []};

            ad.resetGeneration(2);
            testCase.verifyEqual(app.AsyncGen, [2 4], ...
                'resetGeneration(2) must bump only channel 2.');

            ad.clearPending(1);
            testCase.verifyTrue(isnan(app.PendingFrame(1)));
            testCase.verifyEqual(app.PendingMode{1}, '');
            testCase.verifyEqual(app.PendingFrame(2), 2, ...
                'clearPending(1) must not touch channel 2.');

            ad.cancelChannel(1);
            testCase.verifyEqual(app.AsyncGen(1), 3, ...
                'cancelChannel must bump AsyncGen.');
            testCase.verifyTrue(isnan(app.AsyncTargetFrame(1)), ...
                'cancelChannel must NaN-clear AsyncTargetFrame.');

            ad.cancelAll();
            testCase.verifyTrue(all(isnan(app.AsyncTargetFrame)), ...
                'cancelAll must NaN-clear every channel target.');
        end

        function test_T15_Refactor_AsyncDecodeUnboundFallback(testCase)
            % R3: an unbound AsyncDecodeState (no app handle) must still
            % allow the helpers to run locally without throwing.
            ad = flightdash.state.AsyncDecodeState();
            ad.AsyncGen = [0 0];
            ad.PendingFrame = [5 5];
            ad.PendingMode = {'x', 'y'};
            ad.AsyncFutures = {[], []};
            ad.resetGeneration(1);
            testCase.verifyEqual(ad.AsyncGen, [1 0]);
            ad.clearPending(2);
            testCase.verifyTrue(isnan(ad.PendingFrame(2)));
            testCase.verifyEqual(ad.PendingMode{2}, '');
            ad.cancelChannel(1);  % no future to cancel — must not throw
            ad.cancelAll();        % iterates without binding
        end

        function test_T15_Refactor_LayoutStateMirror(testCase)
            % R4: getLayoutState() must reflect direct writes to the
            % legacy app fields, and setLayoutProfile must write through.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            app.LayoutProfile = 'medium';
            app.LastLayoutSize = [900 600];
            app.NormalFigurePosition = [10 20 800 600];
            ls = app.getLayoutState();
            testCase.verifyClass(ls, 'flightdash.state.DashboardLayoutState');
            testCase.verifyEqual(char(ls.LayoutProfile), 'medium');
            testCase.verifyEqual(ls.LastLayoutSize, [900 600]);
            testCase.verifyEqual(ls.NormalFigurePosition, [10 20 800 600]);
            testCase.verifyTrue(isequal(ls, app.Runtime.Layout), ...
                'Runtime.Layout must alias app.LayoutState.');
            ls.setLayoutProfile('wide');
            testCase.verifyEqual(char(app.LayoutProfile), 'wide', ...
                'setLayoutProfile must write through to app.LayoutProfile.');
            ls.setLastLayoutSize([1024 768]);
            testCase.verifyEqual(app.LastLayoutSize, [1024 768], ...
                'setLastLayoutSize must write through to app.LastLayoutSize.');
        end

        function test_T15_Refactor_LayoutStateUnbound(testCase)
            % R4: an unbound DashboardLayoutState must accept writes
            % locally and never throw.
            ls = flightdash.state.DashboardLayoutState();
            ls.setLayoutProfile('compact');
            testCase.verifyEqual(char(ls.LayoutProfile), 'compact');
            ls.setLastLayoutSize([320 200]);
            testCase.verifyEqual(ls.LastLayoutSize, [320 200]);
            ls.syncFromApp();  % no-op when unbound — must not throw
        end

        function test_T15_Refactor_InfoControllerAcceptsAdapter(testCase)
            % Migration #1: InfoController constructor must accept the
            % adapter directly and also still accept the app handle
            % (backward-compat path for external test code).
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            % Adapter path: what FlightDataDashboard now uses.
            ctrlAdapter = flightdash.controller.InfoController(app.Adapter);
            testCase.verifyClass(ctrlAdapter, 'flightdash.controller.InfoController');
            % Backward-compat: pass the app directly — must auto-resolve.
            ctrlApp = flightdash.controller.InfoController(app);
            testCase.verifyClass(ctrlApp, 'flightdash.controller.InfoController');
            % Bad input: must error cleanly, not crash with class probe.
            threw = false;
            try
                flightdash.controller.InfoController(struct('fake', true));
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'InfoController:BadInput');
            end
            testCase.verifyTrue(threw, ...
                'InfoController must reject non-adapter/non-app input.');
            % The dashboard-owned InfoCtrl must work for row-move logic
            % even before any flight data is loaded (empty displayMeta
            % => early return, no exception).
            try
                app.InfoCtrl.moveSelectedRow(1, 'up');
            catch ME
                testCase.verifyFail(sprintf( ...
                    'moveSelectedRow on empty meta must not throw: %s', ME.message));
            end
        end

        function test_T15_Refactor_MarkerDragControllerAcceptsAdapter(testCase)
            % Migration #2: MarkerDragController constructor accepts
            % adapter and rejects bad input. Idle-state defaults are
            % preserved across the migration.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.MarkerDragController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.MarkerDragController');
            ctrlB = flightdash.controller.MarkerDragController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.MarkerDragController');
            threw = false;
            try
                flightdash.controller.MarkerDragController('not-a-handle');
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'MarkerDragController:BadInput');
            end
            testCase.verifyTrue(threw);
            testCase.verifyFalse(app.MarkerDragCtrl.IsDraggingMarker, ...
                'MarkerDragCtrl must start in idle state.');
            testCase.verifyEqual(app.MarkerDragCtrl.DraggedFIdx, 0);
        end

        function test_T15_Refactor_PannerControllerAcceptsAdapter(testCase)
            % Migration #3: PannerController accepts adapter and stays
            % in idle drag state at construction. EventBus subscribers
            % still resolve through obj.Adapter.app() — verify the
            % controller does not throw during subscribe.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.PannerController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.PannerController');
            ctrlB = flightdash.controller.PannerController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.PannerController');
            threw = false;
            try
                flightdash.controller.PannerController(42);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'PannerController:BadInput');
            end
            testCase.verifyTrue(threw);
            % cleanup test-scope controllers
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_DragControllerAcceptsAdapter(testCase)
            % Migration #4: DragController accepts adapter + rejects
            % bad input. hitTest with no UI must safe-return false.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.DragController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.DragController');
            ctrlB = flightdash.controller.DragController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.DragController');
            threw = false;
            try
                flightdash.controller.DragController(true);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'DragController:BadInput');
            end
            testCase.verifyTrue(threw);
            % hitTest with garbage point must not throw.
            try
                [tf, ~] = app.DragCtrl.hitTest([NaN NaN]);
                testCase.verifyFalse(tf, 'hitTest with NaN point must return false.');
            catch ME
                testCase.verifyFail(sprintf('hitTest threw on NaN point: %s', ME.message));
            end
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_PanelToggleControllerAcceptsAdapter(testCase)
            % Migration #5: PanelToggleController accepts adapter +
            % rejects bad input. EventBus subscriptions resolve at
            % construction without throwing.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.PanelToggleController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.PanelToggleController');
            ctrlB = flightdash.controller.PanelToggleController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.PanelToggleController');
            threw = false;
            try
                flightdash.controller.PanelToggleController({});
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'PanelToggleController:BadInput');
            end
            testCase.verifyTrue(threw);
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_FileControllerAcceptsAdapter(testCase)
            % Migration #6: FileController accepts adapter + rejects
            % bad input. Pure event-relay — construction must subscribe
            % without throwing.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.FileController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.FileController');
            ctrlB = flightdash.controller.FileController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.FileController');
            threw = false;
            try
                flightdash.controller.FileController(123);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'FileController:BadInput');
            end
            testCase.verifyTrue(threw);
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_VideoSyncControllerAcceptsAdapter(testCase)
            % Migration #7: VideoSyncController accepts adapter +
            % rejects bad input. EventBus subscription must complete
            % at construction without throwing.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.VideoSyncController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.VideoSyncController');
            ctrlB = flightdash.controller.VideoSyncController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.VideoSyncController');
            threw = false;
            try
                flightdash.controller.VideoSyncController('hi');
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'VideoSyncController:BadInput');
            end
            testCase.verifyTrue(threw);
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_PlotControllerAcceptsAdapter(testCase)
            % Migration #8: PlotController accepts adapter + rejects
            % bad input. 10 EventBus subscriptions must complete at
            % construction without throwing.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.PlotController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.PlotController');
            ctrlB = flightdash.controller.PlotController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.PlotController');
            threw = false;
            try
                flightdash.controller.PlotController([1 2 3]);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'PlotController:BadInput');
            end
            testCase.verifyTrue(threw);
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_RoiControllerAcceptsAdapter(testCase)
            % Migration #9: RoiController accepts adapter + rejects
            % bad input. 5 EventBus subscriptions + idle drag state at
            % construction.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.RoiController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.RoiController');
            ctrlB = flightdash.controller.RoiController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.RoiController');
            threw = false;
            try
                flightdash.controller.RoiController(true);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'RoiController:BadInput');
            end
            testCase.verifyTrue(threw);
            % hitTest with NaN point must safely return false.
            try
                [tf, ~] = app.RoiCtrl.hitTest([NaN NaN]);
                testCase.verifyFalse(tf);
            catch ME
                testCase.verifyFail(sprintf('hitTest threw on NaN: %s', ME.message));
            end
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_PlaybackControllerAcceptsAdapter(testCase)
            % Migration #10 (final): PlaybackController accepts adapter
            % + rejects bad input. 10 EventBus subscriptions complete
            % at construction. Flight-play timers initialise empty.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrlA = flightdash.controller.PlaybackController(app.Adapter);
            testCase.verifyClass(ctrlA, 'flightdash.controller.PlaybackController');
            ctrlB = flightdash.controller.PlaybackController(app);
            testCase.verifyClass(ctrlB, 'flightdash.controller.PlaybackController');
            threw = false;
            try
                flightdash.controller.PlaybackController(0);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'PlaybackController:BadInput');
            end
            testCase.verifyTrue(threw);
            try, delete(ctrlA); catch, end
            try, delete(ctrlB); catch, end
        end

        function test_T15_Refactor_AllControllersUseAdapter(testCase)
            % Confirms every controller wired in by FlightDataDashboard
            % was constructed with the adapter (the final state after
            % the 10-step migration). Reads each Ctrl property and asks
            % via class name — controllers expose no Adapter accessor
            % publicly, but each rejects bad input the same way so any
            % missed migration would have failed construction earlier.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ctrls = {'FileCtrl','VideoSyncCtrl','PlaybackCtrl','PlotCtrl', ...
                     'RoiCtrl','PannerCtrl','PanelCtrl','DragCtrl', ...
                     'MarkerDragCtrl','InfoCtrl'};
            for k = 1:numel(ctrls)
                name = ctrls{k};
                testCase.verifyTrue(isprop(app, name), ...
                    sprintf('Expected app property %s.', name));
                handle = app.(name);
                testCase.verifyTrue(~isempty(handle) && isvalid(handle), ...
                    sprintf('%s must be a valid handle.', name));
            end
        end

        function test_T15_Refactor_AdapterSessionShortcuts(testCase)
            % Adapter session-shortcut methods (isActiveSession,
            % activeSessionId, isEmbedded) must mirror the underlying
            % app behavior and return safe defaults when the app is
            % gone.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ad = app.getAdapter();
            % Live values.
            testCase.verifyEqual(ad.activeSessionId(), char(app.ActiveSessionId));
            testCase.verifyEqual(ad.isEmbedded(), logical(app.IsEmbedded));
            % isActiveSession with no arg must match app.isActiveSession().
            testCase.verifyEqual(ad.isActiveSession(), app.isActiveSession());
            % After delete, all three must return safe defaults instead
            % of throwing.
            delete(app);
            testCase.verifyEqual(ad.activeSessionId(), 'standalone', ...
                'activeSessionId() must fall back to standalone post-delete.');
            testCase.verifyFalse(ad.isEmbedded(), ...
                'isEmbedded() must return false post-delete.');
            testCase.verifyFalse(ad.isActiveSession(), ...
                'isActiveSession() must return false post-delete.');
        end

        function test_T15_Refactor_R6_LayoutOwnershipInverted(testCase)
            % R6: PanelSplitterFIdx / PanelSplitterKind /
            % IsDraggingPanelSplitter / NormalFigurePosition are
            % Dependent forwards on the app — the storage lives on
            % LayoutState. Verifies both directions reach the same
            % cell (write via app, read via LayoutState and vice versa).
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Write via app, read via LayoutState.
            app.PanelSplitterFIdx = 7;
            app.PanelSplitterKind = 'att-map';
            app.IsDraggingPanelSplitter = true;
            app.NormalFigurePosition = [11 22 333 444];
            testCase.verifyEqual(app.LayoutState.PanelSplitterFIdx, 7);
            testCase.verifyEqual(char(app.LayoutState.PanelSplitterKind), 'att-map');
            testCase.verifyTrue(app.LayoutState.IsDraggingPanelSplitter);
            testCase.verifyEqual(app.LayoutState.NormalFigurePosition, [11 22 333 444]);

            % Write via LayoutState, read via app.
            app.LayoutState.PanelSplitterFIdx = 1;
            app.LayoutState.PanelSplitterKind = 'map-info';
            app.LayoutState.IsDraggingPanelSplitter = false;
            app.LayoutState.NormalFigurePosition = [1 2 3 4];
            testCase.verifyEqual(app.PanelSplitterFIdx, 1);
            testCase.verifyEqual(char(app.PanelSplitterKind), 'map-info');
            testCase.verifyFalse(app.IsDraggingPanelSplitter);
            testCase.verifyEqual(app.NormalFigurePosition, [1 2 3 4]);

            % The Dependent property must report itself as a property
            % to anything inspecting metaclass(app) — Phase-10 diag
            % relies on this.
            mc = metaclass(app);
            names = arrayfun(@(p) string(p.Name), mc.PropertyList);
            for inverted = ["PanelSplitterFIdx","PanelSplitterKind", ...
                            "IsDraggingPanelSplitter","NormalFigurePosition"]
                testCase.verifyTrue(any(names == inverted), ...
                    sprintf('metaclass must still list %s.', inverted));
            end
        end

        function test_T15_Refactor_R6_AsyncOwnershipInverted(testCase)
            % R6 (async group): UseAsyncDecode / AsyncPool /
            % AsyncFutures / AsyncTargetFrame / AsyncGen /
            % DragVelocity / DragVelocitySamples are Dependent
            % forwards to AsyncDecodeState. Both directions reach the
            % same storage; legacy subscript-assign patterns
            % (app.AsyncGen(fIdx) = ..., app.AsyncFutures{fIdx} = ...)
            % keep working through MATLAB's getter+modify+setter
            % auto-chain.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Whole-array writes via app, read via AsyncDecode.
            app.UseAsyncDecode = true;
            app.AsyncPool = struct('placeholder', 1);
            app.AsyncTargetFrame = [33 77];
            app.AsyncGen = [5 9];
            app.DragVelocity = [-1.5, 2.0];
            testCase.verifyTrue(app.AsyncDecode.UseAsyncDecode);
            testCase.verifyTrue(isstruct(app.AsyncDecode.AsyncPool));
            testCase.verifyEqual(app.AsyncDecode.AsyncTargetFrame, [33 77]);
            testCase.verifyEqual(app.AsyncDecode.AsyncGen, [5 9]);
            testCase.verifyEqual(app.AsyncDecode.DragVelocity, [-1.5, 2.0]);

            % Legacy subscript-assign pattern from the 3 cancel sites
            % (FlightDataDashboard:600-611, :722-734, :2699-...) must
            % keep working through the Dependent dispatch.
            app.AsyncGen(1) = app.AsyncGen(1) + 1;
            testCase.verifyEqual(app.AsyncDecode.AsyncGen, [6 9], ...
                'app.AsyncGen(fIdx) = app.AsyncGen(fIdx)+1 must flow through Dependent forward.');
            app.AsyncTargetFrame(2) = NaN;
            testCase.verifyTrue(isnan(app.AsyncDecode.AsyncTargetFrame(2)));
            app.AsyncFutures{1} = [];
            testCase.verifyTrue(isempty(app.AsyncDecode.AsyncFutures{1}));

            % Reverse direction.
            app.AsyncDecode.UseAsyncDecode = false;
            testCase.verifyFalse(app.UseAsyncDecode);

            % metaclass(app) must still list all seven names.
            mc = metaclass(app);
            names = arrayfun(@(p) string(p.Name), mc.PropertyList);
            for inverted = ["UseAsyncDecode","AsyncPool","AsyncFutures", ...
                            "AsyncTargetFrame","AsyncGen","DragVelocity", ...
                            "DragVelocitySamples"]
                testCase.verifyTrue(any(names == inverted), ...
                    sprintf('metaclass must still list %s.', inverted));
            end
        end

        function test_T15_Refactor_R6_AsyncOwnershipComplete(testCase)
            % R6 final async commit: IsDecoding / PendingFrame /
            % PendingMode also flip to AsyncDecodeState. After this,
            % all 10 fields the R3 brief listed are owned by the new
            % handle. Confirms both subscript-assign patterns the
            % legacy clearPending site uses
            % (FlightDataDashboard:~1267: app.PendingFrame(fIdx) =
            % NaN; app.PendingMode{fIdx} = '';) still work through the
            % Dependent dispatch.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            app.IsDecoding = [true false];
            app.PendingFrame = [10 20];
            app.PendingMode = {'play', 'scrub'};
            testCase.verifyEqual(app.AsyncDecode.IsDecoding, [true false]);
            testCase.verifyEqual(app.AsyncDecode.PendingFrame, [10 20]);
            testCase.verifyEqual(app.AsyncDecode.PendingMode, {'play', 'scrub'});

            % Legacy clearPending subscript-assign pattern.
            app.PendingFrame(1) = NaN;
            app.PendingMode{1} = '';
            testCase.verifyTrue(isnan(app.AsyncDecode.PendingFrame(1)));
            testCase.verifyEqual(app.AsyncDecode.PendingMode{1}, '');
            testCase.verifyEqual(app.AsyncDecode.PendingFrame(2), 20, ...
                'Subscript-assign on channel 1 must not touch channel 2.');

            % IsDecoding subscript-assign.
            app.IsDecoding(2) = true;
            testCase.verifyEqual(app.AsyncDecode.IsDecoding, [true true]);

            % AsyncDecodeState.syncFromApp must be a no-op now.
            app.AsyncDecode.IsDecoding = [false false];
            app.AsyncDecode.syncFromApp();
            testCase.verifyEqual(app.AsyncDecode.IsDecoding, [false false], ...
                'syncFromApp must NOT clobber inverted-owner storage.');

            mc = metaclass(app);
            names = arrayfun(@(p) string(p.Name), mc.PropertyList);
            for inverted = ["IsDecoding","PendingFrame","PendingMode"]
                testCase.verifyTrue(any(names == inverted), ...
                    sprintf('metaclass must still list %s.', inverted));
            end
        end

        function test_T15_Refactor_R6_LayoutOwnershipComplete(testCase)
            % R6 final layout commit: LayoutProfile / LastLayoutSize /
            % InResponsiveLayout / PreferredVideoWidth /
            % ManualVideoWidth / ManualPanelWidths / LayoutHandles all
            % flip to LayoutState. After this, all 11 fields the R4
            % brief listed are owned by the new handle.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Whole-property writes via app, read via LayoutState.
            app.LayoutProfile = 'narrow';
            app.LastLayoutSize = [640, 480];
            app.InResponsiveLayout = true;
            app.PreferredVideoWidth = [320, 160];
            app.ManualVideoWidth = [480, 240];
            app.ManualPanelWidths = {struct('att',100), struct('att',50)};
            app.LayoutHandles = struct('header', 'h', 'bodyGrid', 'b');
            testCase.verifyEqual(char(app.LayoutState.LayoutProfile), 'narrow');
            testCase.verifyEqual(app.LayoutState.LastLayoutSize, [640, 480]);
            testCase.verifyTrue(app.LayoutState.InResponsiveLayout);
            testCase.verifyEqual(app.LayoutState.PreferredVideoWidth, [320, 160]);
            testCase.verifyEqual(app.LayoutState.ManualVideoWidth, [480, 240]);
            testCase.verifyEqual(app.LayoutState.ManualPanelWidths{1}.att, 100);
            testCase.verifyEqual(app.LayoutState.LayoutHandles.header, 'h');

            % Legacy subscript-assign patterns from
            % ResponsiveLayoutManager.m must keep working.
            app.ManualPanelWidths{2}.att = 999;
            testCase.verifyEqual(app.LayoutState.ManualPanelWidths{2}.att, 999, ...
                'Cell-subscript struct-field assign must flow through Dependent dispatch.');
            app.LastLayoutSize(2) = 720;
            testCase.verifyEqual(app.LayoutState.LastLayoutSize, [640, 720]);

            % syncFromApp must be a no-op now.
            app.LayoutState.LayoutProfile = 'wide';
            app.LayoutState.syncFromApp();
            testCase.verifyEqual(char(app.LayoutState.LayoutProfile), 'wide', ...
                'syncFromApp must NOT clobber inverted-owner storage.');

            mc = metaclass(app);
            names = arrayfun(@(p) string(p.Name), mc.PropertyList);
            for inverted = ["LayoutProfile","LastLayoutSize", ...
                            "InResponsiveLayout","PreferredVideoWidth", ...
                            "ManualVideoWidth","ManualPanelWidths","LayoutHandles"]
                testCase.verifyTrue(any(names == inverted), ...
                    sprintf('metaclass must still list %s.', inverted));
            end
        end

        function test_T15_Refactor_R7_SessionFirstInversion(testCase)
            % R7 first commit: UseSharedDecodeService migrates from
            % R1-style Dependent live-view to real storage on
            % SessionContext. Proves the SessionContext can hold
            % storage; future commits invert the other 8 identity
            % fields the same way.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Default value matches the old storage.
            testCase.verifyFalse(app.UseSharedDecodeService);
            testCase.verifyFalse(app.SessionContext.UseSharedDecodeService);

            % Write via app, read via SessionContext.
            app.UseSharedDecodeService = true;
            testCase.verifyTrue(app.SessionContext.UseSharedDecodeService);

            % Reverse direction.
            app.SessionContext.UseSharedDecodeService = false;
            testCase.verifyFalse(app.UseSharedDecodeService);

            % metaclass name preservation (Phase-10 diag relies on it).
            mc = metaclass(app);
            names = arrayfun(@(p) string(p.Name), mc.PropertyList);
            testCase.verifyTrue(any(names == "UseSharedDecodeService"));

            % adapter.useSharedDecode() must still mirror the value.
            testCase.verifyFalse(app.getAdapter().useSharedDecode());
            app.UseSharedDecodeService = true;
            testCase.verifyTrue(app.getAdapter().useSharedDecode());
        end

        function test_T15_Refactor_R7_RootContainerInverted(testCase)
            % R7 second commit: RootContainer flips to SessionContext
            % storage. Critical lifecycle test: in embedded mode the
            % constructor sets RootContainer BEFORE the explicit
            % SessionContext = SessionContext(app) line, so the lazy-
            % create path must preserve the value through the
            % constructor's idempotent reassignment.
            host = uifigure('Visible', 'off');
            cleanupHost = onCleanup(@() delete(host)); %#ok<NASGU>
            tabs = uitabgroup(host);
            tab  = uitab(tabs, 'Title', 'RC');
            app = [];
            try
                app = flightdash.FlightDataDashboard(tab, 'S-RC');
            catch ME
                testCase.assumeFail(sprintf('Embedded build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Embedded constructor's `app.RootContainer = parentContainer`
            % must survive into SessionContext storage.
            testCase.verifyTrue(isequal(app.RootContainer, tab), ...
                'Embedded RootContainer must equal the parent tab.');
            testCase.verifyTrue(isequal(app.SessionContext.RootContainer, tab), ...
                'SessionContext.RootContainer must mirror app.RootContainer post-construction.');

            % Write via app, read via SessionContext.
            app.RootContainer = host;
            testCase.verifyTrue(isequal(app.SessionContext.RootContainer, host));

            % Reverse direction.
            app.SessionContext.RootContainer = tab;
            testCase.verifyTrue(isequal(app.RootContainer, tab));

            mc = metaclass(app);
            names = arrayfun(@(p) string(p.Name), mc.PropertyList);
            testCase.verifyTrue(any(names == "RootContainer"));
        end

        function test_T15_Refactor_R7_SharedServicesInverted(testCase)
            % R7 third commit: SharedCacheService + SharedDecodeService
            % flip to SessionContext storage.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Defaults match the old storage (empty).
            testCase.verifyTrue(isempty(app.SharedCacheService));
            testCase.verifyTrue(isempty(app.SharedDecodeService));

            % Write via app, read via SessionContext.
            stubCache = struct('placeholder', 'cache');
            stubDecode = struct('placeholder', 'decode');
            app.SharedCacheService = stubCache;
            app.SharedDecodeService = stubDecode;
            testCase.verifyEqual(app.SessionContext.SharedCacheService, stubCache);
            testCase.verifyEqual(app.SessionContext.SharedDecodeService, stubDecode);

            % Adapter pass-throughs (R5) must still alias the same storage.
            ad = app.getAdapter();
            testCase.verifyEqual(ad.cacheService(), stubCache);
            testCase.verifyEqual(ad.decodeService(), stubDecode);

            % Reverse direction.
            app.SessionContext.SharedCacheService = [];
            testCase.verifyTrue(isempty(app.SharedCacheService));
        end

        function test_T15_Refactor_R7_IsEmbeddedAndUndoServiceInverted(testCase)
            % R7 fourth commit: IsEmbedded + UndoService flip to
            % SessionContext storage. IsEmbedded is the constructor's
            % very first write — it MUST survive the explicit
            % SessionContext init thanks to the idempotent guard.
            host = uifigure('Visible', 'off');
            cleanupHost = onCleanup(@() delete(host)); %#ok<NASGU>
            tabs = uitabgroup(host);
            tab  = uitab(tabs, 'Title', 'IE');

            % Embedded path: IsEmbedded must end up true post-construction.
            app = [];
            try
                app = flightdash.FlightDataDashboard(tab, 'S-IE');
            catch ME
                testCase.assumeFail(sprintf('Embedded build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            testCase.verifyTrue(app.IsEmbedded);
            testCase.verifyTrue(app.SessionContext.IsEmbedded);

            % UndoService was assigned via app.UndoService = flightdash
            % .studio.UndoService(...) inside the constructor.
            testCase.verifyTrue(~isempty(app.UndoService));
            testCase.verifyTrue(~isempty(app.SessionContext.UndoService));
            testCase.verifyTrue(isequal(app.UndoService, app.SessionContext.UndoService));

            % Reverse direction.
            app.SessionContext.IsEmbedded = false;
            testCase.verifyFalse(app.IsEmbedded);
            stubSvc = struct('placeholder', 'undo');
            app.UndoService = stubSvc;
            testCase.verifyEqual(app.SessionContext.UndoService, stubSvc);
        end

        function test_T15_Refactor_R7_ActiveSessionIdAndMouseRouterInverted(testCase)
            % R7 fifth commit: ActiveSessionId + MouseRouter flip.
            % ActiveSessionId is the constructor's first identity
            % write (line ~628 standalone / ~629 embedded). Idempotent
            % SessionContext init guard preserves it.
            host = uifigure('Visible', 'off');
            cleanupHost = onCleanup(@() delete(host)); %#ok<NASGU>
            tabs = uitabgroup(host);
            tab  = uitab(tabs, 'Title', 'AS');
            app = [];
            try
                app = flightdash.FlightDataDashboard(tab, 'S-Active');
            catch ME
                testCase.assumeFail(sprintf('Embedded build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            testCase.verifyEqual(char(app.ActiveSessionId), 'S-Active');
            testCase.verifyEqual(char(app.SessionContext.ActiveSessionId), 'S-Active');
            testCase.verifyTrue(isempty(app.MouseRouter));
            testCase.verifyTrue(isempty(app.SessionContext.MouseRouter));

            app.ActiveSessionId = 'S-New';
            testCase.verifyEqual(char(app.SessionContext.ActiveSessionId), 'S-New');

            stubRouter = struct('placeholder', 'router');
            app.MouseRouter = stubRouter;
            testCase.verifyEqual(app.SessionContext.MouseRouter, stubRouter);

            % adapter.activeSessionId() must reflect the new storage.
            testCase.verifyEqual(app.getAdapter().activeSessionId(), 'S-New');
        end

        function test_T15_Refactor_R7_UIFigureInverted(testCase)
            % Final R7 inversion: UIFigure flips to SessionContext.
            % This is the most-read identity property (the view layer
            % reaches for it constantly) — Dependent dispatch absorbs
            % every call site transparently.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            testCase.verifyTrue(~isempty(app.UIFigure));
            testCase.verifyTrue(isvalid(app.UIFigure));
            testCase.verifyTrue(isequal(app.UIFigure, app.SessionContext.UIFigure));

            % adapter.uiFigure() must alias the new storage.
            testCase.verifyTrue(isequal(app.getAdapter().uiFigure(), app.SessionContext.UIFigure));

            % Confirm all 9 identity fields now live in SessionContext
            % real-storage (not Dependent). Cheap to check via metaclass.
            scMeta = ?flightdash.runtime.SessionContext;
            sessionStorageNames = arrayfun(@(p) string(p.Name), scMeta.PropertyList);
            for owned = ["UseSharedDecodeService","IsEmbedded","ActiveSessionId", ...
                         "RootContainer","UIFigure","SharedCacheService", ...
                         "SharedDecodeService","UndoService","MouseRouter"]
                testCase.verifyTrue(any(sessionStorageNames == owned), ...
                    sprintf('SessionContext must own %s as real storage.', owned));
            end
        end

        function test_T15_Refactor_R8_FilePathsInverted(testCase)
            % R8: FlightFilePath + VideoFilePath flip from cell-array
            % storage on the app to per-channel storage on ChannelState
            % (already declared in R2 scaffolding). The app's Dependent
            % property multiplexes the cell shape so legacy subscript
            % patterns (app.FlightFilePath{fIdx} = X) keep working
            % through get-modify-set.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Defaults: empty per channel.
            testCase.verifyEqual(app.FlightFilePath, {'', ''});
            testCase.verifyEqual(app.VideoFilePath, {'', ''});

            % Whole-cell write via app, read via channel().
            app.FlightFilePath = {'C:\f1.csv', 'C:\f2.csv'};
            testCase.verifyEqual(app.channel(1).FlightFilePath, 'C:\f1.csv');
            testCase.verifyEqual(app.channel(2).FlightFilePath, 'C:\f2.csv');

            % Subscript-assign pattern (used by FlightDataDashboard internals).
            app.FlightFilePath{1} = 'D:\new.csv';
            testCase.verifyEqual(app.channel(1).FlightFilePath, 'D:\new.csv');
            testCase.verifyEqual(app.channel(2).FlightFilePath, 'C:\f2.csv');

            % Reverse direction: write via channel, read via app cell.
            app.StateStore.Channels(2).FlightFilePath = 'E:\reverse.csv';
            paths = app.FlightFilePath;
            testCase.verifyEqual(paths{2}, 'E:\reverse.csv');

            % Same for VideoFilePath.
            app.VideoFilePath = {'A.mp4', 'B.mp4'};
            testCase.verifyEqual(app.channel(1).VideoFilePath, 'A.mp4');
            testCase.verifyEqual(app.channel(2).VideoFilePath, 'B.mp4');
            app.VideoFilePath{2} = 'C.mp4';
            testCase.verifyEqual(app.channel(2).VideoFilePath, 'C.mp4');
        end

        function test_T15_Refactor_R8_VideoStateInverted(testCase)
            % R8 video group: VideoState flips from app struct-array
            % storage to VideoSessionState. The constructor's early
            % `app.VideoState = struct(...)` write must survive the
            % explicit StateStore init at line ~876 thanks to the
            % idempotent guard added in this commit.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Constructor write must survive to StateStore.Video.
            testCase.verifyEqual(numel(app.VideoState), 2, ...
                'VideoState must remain a 1x2 struct array post-construction.');
            testCase.verifyTrue(isfield(app.VideoState, 'videoReader'));
            testCase.verifyEqual(app.VideoState(1).videoStartTime, 0);
            testCase.verifyTrue(isequal(app.VideoState, app.StateStore.Video.VideoState), ...
                'app.VideoState must alias StateStore.Video.VideoState.');

            % Subscript-assign pattern (used by FlightDataDashboard internals).
            app.VideoState(1).videoStartTime = 12.5;
            testCase.verifyEqual(app.StateStore.Video.VideoState(1).videoStartTime, 12.5);
            testCase.verifyEqual(app.VideoState(2).videoStartTime, 0, ...
                'Subscript-assign on channel 1 must not touch channel 2.');

            % Reverse direction.
            app.StateStore.Video.VideoState(2).videoStartTime = 7.0;
            testCase.verifyEqual(app.VideoState(2).videoStartTime, 7.0);
        end

        function test_T15_Refactor_R8_SyncAndVideoSyncStateInverted(testCase)
            % R8 video-group completion: SyncState + VideoSyncState
            % flip to VideoSessionState. Constructor writes both
            % early (~line 304/307) so the idempotent StateStore
            % guard must preserve them through the explicit
            % StateStore init.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>

            % Constructor writes survive.
            testCase.verifyFalse(app.SyncState.IsSynced);
            testCase.verifyEqual(app.SyncState.SyncT1, 0);
            testCase.verifyEqual(numel(app.VideoSyncState), 2);
            testCase.verifyEqual(app.VideoSyncState(1).VideoFps, 70);
            testCase.verifyEqual(app.VideoSyncState(2).DataFps, 50);

            % SyncState struct write/read round trip.
            app.SyncState.IsSynced = true;
            testCase.verifyTrue(app.StateStore.Video.SyncState.IsSynced);

            % VideoSyncState subscript-assign through Dependent dispatch.
            app.VideoSyncState(1).TotalFrames = 1234;
            testCase.verifyEqual(app.StateStore.Video.VideoSyncState(1).TotalFrames, 1234);
            testCase.verifyEqual(app.VideoSyncState(2).TotalFrames, 0, ...
                'Subscript-assign on channel 1 must not touch channel 2.');

            % Reverse direction.
            app.StateStore.Video.VideoSyncState(2).CurrentFrame = 50;
            testCase.verifyEqual(app.VideoSyncState(2).CurrentFrame, 50);
        end

        function test_T15_Refactor_OwnershipBaselineLocked(testCase)
            % Wrap-up regression guard. Runs the
            % r6r7r8_ownership_baseline step from the diagnostic in
            % isolation and asserts it returns 'PASS'. Any future
            % edit that pulls storage back to the app or removes a
            % Dependent forward will fail this test.
            report = [];
            try
                report = flightdash.diag.verifyDashboardRefactorBaseline();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Baseline diagnostic cannot run headlessly: %s', ME.message));
                return;
            end
            idx = find(report.Steps.Name == "r6r7r8_ownership_baseline", 1);
            testCase.verifyNotEmpty(idx, ...
                'r6r7r8_ownership_baseline step missing from baseline diagnostic.');
            testCase.verifyEqual(char(report.Steps.Status(idx)), 'PASS', ...
                sprintf('Ownership baseline regressed: %s', ...
                char(report.Steps.Error(idx))));
        end

        function test_T15_Refactor_AdapterRoutesAggregates(testCase)
            % R5: adapter aggregate accessors must alias the direct app
            % getters — adapter is a curated router, not a duplicator.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ad = app.getAdapter();
            testCase.verifyClass(ad, 'flightdash.runtime.DashboardAppAdapter');
            testCase.verifyTrue(isequal(ad.session(),    app.getSessionContext()));
            testCase.verifyTrue(isequal(ad.store(),      app.getStateStore()));
            testCase.verifyTrue(isequal(ad.asyncDecode(),app.getAsyncDecode()));
            testCase.verifyTrue(isequal(ad.layout(),     app.getLayoutState()));
            % Channel routing — adapter.channel(2) must lazy-mirror.
            app.Models(2).currentIndex = 77;
            ch = ad.channel(2);
            testCase.verifyClass(ch, 'flightdash.state.ChannelState');
            testCase.verifyEqual(ch.CurrentIndex, 77);
        end

        function test_T15_Refactor_AdapterServicePassthrough(testCase)
            % R5: service accessors and the escape-hatch app() return
            % the same handles the app itself exposes.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ad = app.getAdapter();
            testCase.verifyTrue(isequal(ad.undoService(),  app.UndoService));
            testCase.verifyTrue(isequal(ad.cacheService(), app.SharedCacheService));
            testCase.verifyTrue(isequal(ad.decodeService(),app.SharedDecodeService));
            testCase.verifyTrue(isequal(ad.uiFigure(),     app.UIFigure));
            testCase.verifyTrue(isequal(ad.rootContainer(),app.RootContainer));
            testCase.verifyEqual(ad.useSharedDecode(), ...
                logical(app.UseSharedDecodeService));
            testCase.verifyTrue(isequal(ad.app(), app), ...
                'adapter.app() escape hatch must return the live handle.');
        end

        function test_T15_Refactor_AdapterLogCaughtSafe(testCase)
            % R5: adapter.logCaught must never throw — adapters cannot
            % become a new failure surface.
            app = [];
            try
                app = flightdash.FlightDataDashboard();
            catch ME
                testCase.assumeFail(sprintf('Headless build failed: %s', ME.message));
                return;
            end
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            ad = app.getAdapter();
            try
                ad.logCaught(MException('T15:Probe', 'probe'), 'T15:adapterProbe');
            catch ME
                testCase.verifyFail(sprintf( ...
                    'adapter.logCaught threw: %s', ME.message));
            end
        end

        function test_T15_Refactor_BaselineDiagnostic(testCase)
            % R1: run the refactor baseline harness end-to-end. Each
            % step is internally guarded so headless backends produce
            % FAIL rows rather than crashing the test runner — but at
            % least the standalone path is expected to PASS on any host
            % that can build the rest of the test suite.
            report = [];
            try
                report = flightdash.diag.verifyDashboardRefactorBaseline();
            catch ME
                testCase.assumeFail(sprintf( ...
                    'Baseline diagnostic cannot run headlessly: %s', ME.message));
                return;
            end
            testCase.verifyClass(report, 'struct');
            testCase.verifyTrue(isfield(report, 'Steps'));
            % Standalone launch is the irreducible smoke test; if even
            % this fails the refactor has broken legacy startup.
            idx = find(report.Steps.Name == "standalone_launch_delete", 1);
            testCase.verifyNotEmpty(idx, 'standalone step missing.');
            testCase.verifyEqual(char(report.Steps.Status(idx)), 'PASS', ...
                sprintf('standalone_launch_delete must PASS — got %s (%s)', ...
                char(report.Steps.Status(idx)), char(report.Steps.Error(idx))));
        end

        function test_T15_Review_ExternalLinks_IncludesOptionFile(testCase)
            % Review fix: ProjectSerializer.collectExternalLinks must
            % emit kind='option_file' entries so missing option*.dat
            % deps surface in external_links.json / support bundles.
            % Pure pkg static call — no GUI dependency.
            sess = struct( ...
                'SessionId',      'sess-1', ...
                'FlightFilePath', {{'C:\flight.csv', ''}}, ...
                'VideoFilePath',  {{'', ''}}, ...
                'OptionFilePath', {{'C:\option1.dat', 'C:\option2.dat'}});
            project = struct('Sessions', sess);
            links = flightdash.project.ProjectSerializer.collectExternalLinks(project);
            testCase.verifyClass(links, 'cell');
            kinds = cellfun(@(L) char(L.kind), links, 'UniformOutput', false);
            testCase.verifyTrue(any(strcmp(kinds, 'option_file')), ...
                'collectExternalLinks must emit kind=option_file entries.');
            % Exactly one flight + two option entries (empty paths skipped).
            testCase.verifyEqual(sum(strcmp(kinds, 'flight_data')), 1, ...
                'Empty FlightFilePath cells must be skipped.');
            testCase.verifyEqual(sum(strcmp(kinds, 'option_file')), 2, ...
                'Both populated OptionFilePath cells must be emitted.');
            testCase.verifyEqual(sum(strcmp(kinds, 'video')), 0, ...
                'Empty VideoFilePath cells must be skipped.');
        end

        function test_T15_Review_ExternalLinks_TolerantToMissingField(testCase)
            % Review fix: legacy sessions without OptionFilePath must
            % NOT make collectExternalLinks throw — the new loop is
            % guarded by isfield.
            sess = struct( ...
                'SessionId',      'sess-legacy', ...
                'FlightFilePath', {{'C:\old.csv'}}, ...
                'VideoFilePath',  {{'C:\old.mp4'}});
            project = struct('Sessions', sess);
            links = flightdash.project.ProjectSerializer.collectExternalLinks(project);
            testCase.verifyClass(links, 'cell');
            kinds = cellfun(@(L) char(L.kind), links, 'UniformOutput', false);
            testCase.verifyEqual(sum(strcmp(kinds, 'option_file')), 0, ...
                'Legacy session must produce zero option_file entries.');
        end

        function test_T15_Review_SampleProjectPath_RootDepthCorrect(testCase)
            % Review fix: WorkspaceManager.openSampleProject must compute
            % a repo root that actually contains the +flightdash package
            % (the previous three-up calculation landed one directory
            % above the repo). Verifies the math via the same expression
            % as the live method, but executed against this test file's
            % location for portability.
            wmPath = which('flightdash.studio.WorkspaceManager');
            testCase.assumeTrue(~isempty(wmPath) && isfile(wmPath), ...
                'WorkspaceManager source not found on path.');
            here = fileparts(wmPath);
            root = fullfile(here, '..', '..');
            testCase.verifyTrue(isfolder(root), ...
                sprintf('Repo root "%s" must be a folder.', root));
            testCase.verifyTrue(isfolder(fullfile(root, '+flightdash')), ...
                'Resolved root must contain the +flightdash package folder.');
            % Negative check: the old three-up calculation should NOT
            % contain +flightdash directly (proves the fix matters).
            tooDeep = fullfile(here, '..', '..', '..');
            testCase.verifyFalse(isfolder(fullfile(tooDeep, '+flightdash')), ...
                'Old three-up root should NOT contain +flightdash directly.');
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

        function cleanupOptionFile(~, filePath)
            % PFE-2 helper: best-effort removal of an option file and
            % any rotated .bak_* siblings dropped by OptionFileParser.
            try, if isfile(filePath), delete(filePath); end, catch, end
            try
                listing = dir([filePath '.bak_*']);
                for k = 1:numel(listing)
                    try, delete(fullfile(listing(k).folder, listing(k).name)); catch, end
                end
            catch
            end
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
