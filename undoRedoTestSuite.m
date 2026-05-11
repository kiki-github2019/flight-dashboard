function tests = undoRedoTestSuite
%UNDOREDOTESTSUITE Session-aware UndoService regression tests.

    tests = functiontests(localfunctions);
end

function setup(~)
    flightdash.util.SessionScope.clear();
end

function teardown(~)
    flightdash.util.SessionScope.clear();
end

function testUndoRedoFunctionality(testCase)
    target = LocalCounterTarget(0);
    svc = flightdash.studio.UndoService('UndoTest');

    cmd = LocalCounterCommand('UndoTest', target, 0, 5, 'Set Value');
    svc.push(cmd, true);

    testCase.verifyEqual(target.Value, 5, ...
        'Command execute did not apply the new value.');
    testCase.verifyTrue(svc.canUndo(), ...
        'Undo stack should not be empty after push.');
    testCase.verifyFalse(svc.canRedo(), ...
        'Redo stack should be empty immediately after push.');

    svc.undo();
    testCase.verifyEqual(target.Value, 0, ...
        'Undo should restore the original value.');
    testCase.verifyFalse(svc.canUndo(), ...
        'Undo stack should be empty after undoing the only command.');
    testCase.verifyTrue(svc.canRedo(), ...
        'Redo stack should contain the undone command.');

    svc.redo();
    testCase.verifyEqual(target.Value, 5, ...
        'Redo should re-apply the command value.');
end

function testUndoRedoCrossSessionIsolation(testCase)
    targetA = LocalCounterTarget(0);
    targetB = LocalCounterTarget(100);
    svcA = flightdash.studio.UndoService('SessionA');
    svcB = flightdash.studio.UndoService('SessionB');

    cmdA = LocalCounterCommand('SessionA', targetA, 0, 10, 'Set A');
    svcA.push(cmdA, true);
    svcB.push(cmdA, true);  % Must be ignored by SessionB service.

    testCase.verifyEqual(targetA.Value, 10);
    testCase.verifyEqual(targetB.Value, 100);
    testCase.verifyEqual(numel(svcA.UndoStack), 1, ...
        'Session A should own exactly one undo command.');
    testCase.verifyEmpty(svcB.UndoStack, ...
        'Session B should reject Session A commands.');
end

function testUndoAfterMultipleOperations(testCase)
    target = LocalCounterTarget(0);
    svc = flightdash.studio.UndoService('MultiOp');

    svc.push(LocalCounterCommand('MultiOp', target, 0, 1, 'One'), true);
    svc.push(LocalCounterCommand('MultiOp', target, 1, 2, 'Two'), true);
    svc.push(LocalCounterCommand('MultiOp', target, 2, 3, 'Three'), true);

    testCase.verifyEqual(target.Value, 3);
    testCase.verifyEqual(numel(svc.UndoStack), 3);

    svc.undo();
    testCase.verifyEqual(target.Value, 2);
    svc.undo();
    testCase.verifyEqual(target.Value, 1);
    svc.undo();
    testCase.verifyEqual(target.Value, 0);

    testCase.verifyFalse(svc.canUndo(), ...
        'All operations should have been undone.');
    testCase.verifyTrue(svc.canRedo(), ...
        'Redo stack should contain undone operations.');
end

function testUndoStackLimit(testCase)
    target = LocalCounterTarget(0);
    svc = flightdash.studio.UndoService('LimitTest');
    svc.MaxHistory = 2;

    svc.push(LocalCounterCommand('LimitTest', target, 0, 1, 'One'), true);
    svc.push(LocalCounterCommand('LimitTest', target, 1, 2, 'Two'), true);
    svc.push(LocalCounterCommand('LimitTest', target, 2, 3, 'Three'), true);

    testCase.verifyEqual(numel(svc.UndoStack), 2, ...
        'UndoService did not enforce MaxHistory/MaxDepth.');
    testCase.verifyEqual(svc.UndoStack{1}.Description, 'Two', ...
        'Oldest command was not trimmed first.');
end

function testUndoStateChangedEventIsSessionScoped(testCase)
    hitsA = 0;
    hitsB = 0;
    target = LocalCounterTarget(0);
    svc = flightdash.studio.UndoService('EventSessionA');

    listenerA = flightdash.util.EventBus.subscribe( ...
        'UndoStateChanged', @(~,~) bumpA(), 'EventSessionA');
    listenerB = flightdash.util.EventBus.subscribe( ...
        'UndoStateChanged', @(~,~) bumpB(), 'EventSessionB');
    cleanupObj = onCleanup(@() deleteListeners(listenerA, listenerB)); %#ok<NASGU>

    svc.push(LocalCounterCommand('EventSessionA', target, 0, 1, 'Event Push'), true);
    drawnow limitrate;

    testCase.verifyGreaterThanOrEqual(hitsA, 1, ...
        'Matching UndoStateChanged listener did not fire.');
    testCase.verifyEqual(hitsB, 0, ...
        'UndoStateChanged leaked to a different session listener.');

    function bumpA()
        hitsA = hitsA + 1;
    end

    function bumpB()
        hitsB = hitsB + 1;
    end
end

function testUndoServiceInjectionViaStudio(testCase)
    app = [];
    cleanupObj = onCleanup(@() safeDelete(app)); %#ok<NASGU>

    app = FlightReviewStudio();
    sid = app.addSession('Undo Injection Session');
    drawnow limitrate;

    dash = app.getActiveDashboard();
    testCase.verifyFalse(isempty(dash), ...
        'No active dashboard was available after adding a session.');
    testCase.verifyTrue(isprop(dash, 'UndoService') && ~isempty(dash.UndoService) && ...
        isvalid(dash.UndoService), ...
        'Embedded dashboard did not receive an UndoService.');
    testCase.verifyEqual(char(dash.UndoService.SessionId), char(sid), ...
        'Injected UndoService session id does not match the dashboard session.');
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

classdef LocalCounterTarget < handle
    properties
        Value double = 0
    end

    methods
        function obj = LocalCounterTarget(value)
            if nargin >= 1
                obj.Value = value;
            end
        end
    end
end

classdef LocalCounterCommand < flightdash.command.Command
    properties
        Target
        OldValue double = 0
        NewValue double = 0
    end

    methods
        function obj = LocalCounterCommand(sessionId, target, oldValue, newValue, description)
            obj@flightdash.command.Command(sessionId, description);
            obj.Target = target;
            obj.OldValue = oldValue;
            obj.NewValue = newValue;
        end

        function execute(obj)
            if ~isempty(obj.Target) && isvalid(obj.Target)
                obj.Target.Value = obj.NewValue;
            end
        end

        function undo(obj)
            if ~isempty(obj.Target) && isvalid(obj.Target)
                obj.Target.Value = obj.OldValue;
            end
        end
    end
end
