function tests = eventSystemTestSuite
%EVENTSYSTEMTESTSUITE Phase 4 session-scoped EventBus tests.
%   Uses known EventBus events so this suite runs against the current
%   repository without requiring test-only event names.

    tests = functiontests(localfunctions);
end

function setup(~)
    flightdash.util.SessionScope.clear();
end

function teardown(~)
    flightdash.util.SessionScope.clear();
end

function testSessionScopedEventsDoNotLeak(testCase)
    receivedA = false;
    receivedB = false;

    listenerA = flightdash.util.EventBus.subscribe( ...
        'FlightStopRequested', @(~,~) markA(), 'SessionA');
    listenerB = flightdash.util.EventBus.subscribe( ...
        'FlightStopRequested', @(~,~) markB(), 'SessionB');
    cleanupObj = onCleanup(@() deleteListeners(listenerA, listenerB)); %#ok<NASGU>

    flightdash.util.EventBus.publish( ...
        'FlightStopRequested', struct('Data', 42), 'SessionA');
    drawnow limitrate;

    testCase.verifyTrue(receivedA, ...
        'Session A listener did not receive its own event.');
    testCase.verifyFalse(receivedB, ...
        'Session A event leaked into Session B listener.');

    function markA()
        receivedA = true;
    end

    function markB()
        receivedB = true;
    end
end

function testBroadcastEventsReachAllSessions(testCase)
    count = 0;

    flightdash.util.SessionScope.clear();
    listenerA = flightdash.util.EventBus.subscribe( ...
        'FlightStopRequested', @(~,~) increment(), 'SessionA');
    listenerB = flightdash.util.EventBus.subscribe( ...
        'FlightStopRequested', @(~,~) increment(), 'SessionB');
    cleanupObj = onCleanup(@() deleteListeners(listenerA, listenerB)); %#ok<NASGU>

    flightdash.util.EventBus.publish('FlightStopRequested', struct());
    drawnow limitrate;

    testCase.verifyEqual(count, 2, ...
        'Broadcast event should reach all session-scoped listeners.');

    function increment()
        count = count + 1;
    end
end

function testEventAfterSessionListenerCleanupIsIgnored(testCase)
    app = [];
    received = false;

    cleanupApp = onCleanup(@() safeDelete(app)); %#ok<NASGU>
    app = FlightReviewStudio();
    sid = app.addSession('ClosingSession');
    drawnow limitrate;

    owner = flightdash.event.SessionScopedListener( ...
        sid, [], 'FlightStopRequested', @(~,~) markReceived());

    app.removeSession(sid);
    drawnow limitrate;
    delete(owner);

    flightdash.util.EventBus.publish( ...
        'FlightStopRequested', struct(), sid);
    drawnow limitrate;

    testCase.verifyFalse(received, ...
        'Late event was delivered after session listener cleanup.');

    function markReceived()
        received = true;
    end
end

function testSubscribeForAppUsesEmbeddedSession(testCase)
    received = false;
    fakeApp = struct('ActiveSessionId', 'AppSession');

    listener = flightdash.util.EventBus.subscribeForApp( ...
        fakeApp, 'FlightStopRequested', @(~,~) markReceived());
    cleanupObj = onCleanup(@() deleteListeners(listener)); %#ok<NASGU>

    flightdash.util.EventBus.publish( ...
        'FlightStopRequested', struct(), 'OtherSession');
    flightdash.util.EventBus.publish( ...
        'FlightStopRequested', struct(), 'AppSession');
    drawnow limitrate;

    testCase.verifyTrue(received, ...
        'subscribeForApp listener did not receive its matching session event.');

    function markReceived()
        received = true;
    end
end

function testAcceptsSessionSemantics(testCase)
    testCase.verifyTrue(flightdash.util.EventBus.acceptsSession('', 'SessionA'));
    testCase.verifyTrue(flightdash.util.EventBus.acceptsSession('SessionA', ''));
    testCase.verifyTrue(flightdash.util.EventBus.acceptsSession('SessionA', 'SessionA'));
    testCase.verifyFalse(flightdash.util.EventBus.acceptsSession('SessionA', 'SessionB'));
end

function deleteListeners(varargin)
    for k = 1:nargin
        try
            listener = varargin{k};
            if ~isempty(listener) && isvalid(listener)
                delete(listener);
            end
        catch
        end
    end
end

function safeDelete(obj)
    try
        if ~isempty(obj) && isvalid(obj)
            delete(obj);
        end
    catch
    end
end
