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

        function test_T4_Event_Isolation(testCase)
            % Preferred path:
            % Use repository diagnostic if it exists. This avoids assuming
            % the internal EventBus token/callback API.
            if exist('flightdash.studio.diag.verifyPhase4', 'file') == 2
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
            app = testCase.launchStudio();

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
                        out = app.(methodName)(sessionId);
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
                            out = workspace.(methodName)(sessionId);
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

        function verifyDiagnosticHasNoFail(testCase, results, failMessage)
            testCase.verifyNotEmpty(results, 'Diagnostic returned empty result.');

            if istable(results)
                if any(strcmpi(results.Properties.VariableNames, 'Result'))
                    statuses = string(results.Result);
                elseif any(strcmpi(results.Properties.VariableNames, 'Status'))
                    statuses = string(results.Status);
                else
                    testCase.verifyFail( ...
                        'Diagnostic table has no Result/Status column.');
                    return;
                end
            elseif isstruct(results)
                if isfield(results, 'Result')
                    statuses = string({results.Result});
                elseif isfield(results, 'Status')
                    statuses = string({results.Status});
                elseif isfield(results, 'Checks') && istable(results.Checks)
                    checks = results.Checks;

                    if any(strcmpi(checks.Properties.VariableNames, 'Status'))
                        statuses = string(checks.Status);
                    elseif any(strcmpi(checks.Properties.VariableNames, 'Result'))
                        statuses = string(checks.Result);
                    else
                        testCase.verifyFail( ...
                            'Diagnostic Checks table has no Status/Result column.');
                        return;
                    end
                else
                    testCase.verifyFail( ...
                        'Unsupported diagnostic result format.');
                    return;
                end
            else
                testCase.verifyFail( ...
                    'Unsupported diagnostic result type.');
                return;
            end

            testCase.verifyFalse( ...
                any(upper(statuses) == "FAIL"), ...
                failMessage);
        end
    end
end