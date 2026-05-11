classdef FlightReviewStudioStressTests < matlab.unittest.TestCase
    %FLIGHTREVIEWSTUDIOSTRESSTESTS Phase 3 mouse stress tests.
    %   These tests exercise the public Studio API plus the public
    %   StudioMouseRouter lock surface. They intentionally avoid reaching
    %   into router private callbacks; motion/up are triggered through the
    %   UIFigure callback slots that the router owns.

    properties
        Studio = []
    end

    methods (TestMethodSetup)
        function setupStudio(testCase)
            testCase.Studio = FlightReviewStudio();
            testCase.hideStudioFigure();
            testCase.addTeardown(@() testCase.deleteStudio());
        end
    end

    methods (Test)
        function testHighVolumeTabCreationAndDrag(testCase)
            rng(3007, 'twister');
            nTabs = 8;
            sessionIds = cell(1, nTabs);
            alive = true(1, nTabs);

            for k = 1:nTabs
                sessionIds{k} = testCase.Studio.addSession(sprintf('StressTab%03d', k));
                drawnow limitrate;
            end

            for iter = 1:15
                idx = randi(nTabs);
                if ~alive(idx) || ~testCase.workspaceHasSession(sessionIds{idx})
                    sessionIds{idx} = testCase.Studio.addSession( ...
                        sprintf('StressTab%03d_re%d', idx, iter));
                    alive(idx) = true;
                    drawnow limitrate;
                end

                sid = sessionIds{idx};
                testCase.selectSession(sid);

                ctrl = flightdash.studio.diag.RouterTestController();
                if testCase.Studio.MouseRouter.requestDragLock(sid, ctrl, 'fleur', 'stress')
                    for m = 1:5
                        testCase.invokeMotion();
                    end
                    testCase.invokeMouseUp();
                end

                testCase.verifyFalse(testCase.Studio.MouseRouter.hasActiveLock(), ...
                    'MouseRouter leaked a lock after a high-volume stress drag.');

                if rand() < 0.3
                    testCase.closeSession(sid);
                    alive(idx) = false;
                    testCase.verifyFalse(testCase.Studio.MouseRouter.isLockHeldBy(sid), ...
                        'MouseRouter kept a lock for a closed stress session.');
                end
            end
        end

        function testRapidTabSwitchWhileDragging(testCase)
            sidA = testCase.Studio.addSession('RapidA');
            sidB = testCase.Studio.addSession('RapidB');
            drawnow limitrate;

            for k = 1:20
                testCase.selectSession(sidA);
                ctrl = flightdash.studio.diag.RouterTestController();
                testCase.verifyTrue( ...
                    testCase.Studio.MouseRouter.requestDragLock(sidA, ctrl, 'fleur', 'rapid'), ...
                    sprintf('Router did not grant drag lock on rapid iteration %d.', k));

                testCase.invokeMotion();
                testCase.selectSession(sidB);
                testCase.invokeMotion();

                testCase.verifyFalse(testCase.Studio.MouseRouter.hasActiveLock(), ...
                    'MouseRouter did not cancel drag after rapid tab switch.');
                testCase.verifyEqual(ctrl.StopCount, 1, ...
                    'Controller stopDrag was not called after rapid tab switch.');
            end
        end

        function testRandomMouseOperationsAcrossSessions(testCase)
            rng(4203, 'twister');
            nSessions = 5;
            sessionIds = cell(1, nSessions);
            alive = true(1, nSessions);
            gestures = {'marker', 'split', 'roi', 'pan'};

            for k = 1:nSessions
                sessionIds{k} = testCase.Studio.addSession(sprintf('RandSession%02d', k));
                drawnow limitrate;
            end

            for step = 1:35
                idx = randi(nSessions);
                if ~alive(idx) || ~testCase.workspaceHasSession(sessionIds{idx})
                    sessionIds{idx} = testCase.Studio.addSession( ...
                        sprintf('RandSession%02d_re%d', idx, step));
                    alive(idx) = true;
                    drawnow limitrate;
                end

                sid = sessionIds{idx};
                testCase.selectSession(sid);

                ctrl = flightdash.studio.diag.RouterTestController();
                gesture = gestures{randi(numel(gestures))};
                granted = testCase.Studio.MouseRouter.requestDragLock(sid, ctrl, 'fleur', gesture);

                if granted
                    if rand() < 0.25
                        other = find(alive & ~strcmp(sessionIds, sid), 1, 'first');
                        if ~isempty(other)
                            testCase.selectSession(sessionIds{other});
                        end
                    end

                    for n = 1:randi(4)
                        testCase.invokeMotion();
                    end

                    if testCase.Studio.MouseRouter.hasActiveLock()
                        testCase.invokeMouseUp();
                    end
                end

                testCase.verifyFalse(testCase.Studio.MouseRouter.hasActiveLock(), ...
                    'MouseRouter leaked a lock during randomized operations.');

                if rand() < 0.2
                    testCase.closeSession(sid);
                    alive(idx) = false;
                end
            end
        end

        function testDragAfterStudioCloseRequest(testCase)
            sid = testCase.Studio.addSession('CloseTest');
            drawnow limitrate;
            testCase.selectSession(sid);

            router = testCase.Studio.MouseRouter;
            ctrl = flightdash.studio.diag.RouterTestController();
            testCase.verifyTrue(router.requestDragLock(sid, ctrl, 'fleur', 'close'), ...
                'Router did not grant drag lock before close request.');

            testCase.Studio.onCloseRequest();
            testCase.Studio = [];

            testCase.verifyFalse(isvalid(router), ...
                'MouseRouter should be deleted by Studio close request.');
        end

        function testMouseRouterCleanupOnStudioDelete(testCase)
            router = testCase.Studio.MouseRouter;
            testCase.verifyTrue(isvalid(router), ...
                'MouseRouter was not valid before Studio deletion.');

            delete(testCase.Studio);
            testCase.Studio = [];

            testCase.verifyFalse(isvalid(router), ...
                'MouseRouter should be cleaned up on Studio delete.');
        end

        function testHoverDuringAsyncOperation(testCase)
            sid = testCase.Studio.addSession('HoverTest');
            drawnow limitrate;
            testCase.selectSession(sid);

            dash = testCase.Studio.getActiveDashboard();
            testCase.assumeFalse(isempty(dash), 'No active dashboard was available.');
            testCase.assumeTrue(isprop(dash, 'RoiCtrl') && ~isempty(dash.RoiCtrl) && ...
                isvalid(dash.RoiCtrl) && ismethod(dash.RoiCtrl, 'handleHover'), ...
                'ROI hover controller API is not available.');

            for k = 1:30
                point = [50 + rand() * 200, 60 + rand() * 100];
                dash.RoiCtrl.handleHover(point);
                pause(0.001);
            end

            if ismethod(dash.RoiCtrl, 'clearHover')
                dash.RoiCtrl.clearHover();
            end
            testCase.verifyTrue(isvalid(testCase.Studio), ...
                'Studio became invalid during hover stress.');
        end
    end

    methods (Access = private)
        function hideStudioFigure(testCase)
            try
                if ~isempty(testCase.Studio) && isvalid(testCase.Studio) && ...
                        isprop(testCase.Studio, 'UIFigure') && ...
                        ~isempty(testCase.Studio.UIFigure) && ...
                        isvalid(testCase.Studio.UIFigure)
                    testCase.Studio.UIFigure.Visible = 'off';
                end
            catch
            end
        end

        function deleteStudio(testCase)
            try
                if ~isempty(testCase.Studio) && isvalid(testCase.Studio)
                    delete(testCase.Studio);
                end
            catch
            end
            testCase.Studio = [];
        end

        function selectSession(testCase, sessionId)
            selected = false;
            try
                if ~isempty(testCase.Studio) && isvalid(testCase.Studio) && ...
                        isprop(testCase.Studio, 'Workspace') && ...
                        ~isempty(testCase.Studio.Workspace) && ...
                        isvalid(testCase.Studio.Workspace) && ...
                        ismethod(testCase.Studio.Workspace, 'selectSession')
                    selected = logical(testCase.Studio.Workspace.selectSession(sessionId));
                    drawnow limitrate;
                end
            catch
                selected = false;
            end
            testCase.verifyTrue(selected, ...
                sprintf('Failed to select session %s.', char(sessionId)));
        end

        function closeSession(testCase, sessionId)
            try
                if ~isempty(testCase.Studio) && isvalid(testCase.Studio)
                    testCase.Studio.removeSession(sessionId);
                    drawnow limitrate;
                end
            catch ME
                testCase.verifyTrue(false, sprintf('Failed to close session %s: %s', ...
                    char(sessionId), ME.message));
            end
        end

        function tf = workspaceHasSession(testCase, sessionId)
            tf = false;
            try
                if isempty(testCase.Studio) || ~isvalid(testCase.Studio) || ...
                        ~isprop(testCase.Studio, 'Workspace') || ...
                        isempty(testCase.Studio.Workspace) || ...
                        ~isvalid(testCase.Studio.Workspace) || ...
                        ~isprop(testCase.Studio.Workspace, 'DashboardEntries')
                    return;
                end

                entries = testCase.Studio.Workspace.DashboardEntries;
                tf = isa(entries, 'containers.Map') && isKey(entries, char(sessionId));
            catch
                tf = false;
            end
        end

        function invokeMotion(testCase)
            fig = testCase.activeFigure();
            if isempty(fig) || isempty(fig.WindowButtonMotionFcn)
                return;
            end
            fig.WindowButtonMotionFcn([], []);
        end

        function invokeMouseUp(testCase)
            fig = testCase.activeFigure();
            if isempty(fig) || isempty(fig.WindowButtonUpFcn)
                return;
            end
            fig.WindowButtonUpFcn([], []);
        end

        function fig = activeFigure(testCase)
            fig = [];
            try
                if ~isempty(testCase.Studio) && isvalid(testCase.Studio) && ...
                        isprop(testCase.Studio, 'UIFigure') && ...
                        ~isempty(testCase.Studio.UIFigure) && ...
                        isvalid(testCase.Studio.UIFigure)
                    fig = testCase.Studio.UIFigure;
                end
            catch
                fig = [];
            end
        end
    end
end
