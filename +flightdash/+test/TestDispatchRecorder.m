classdef TestDispatchRecorder < handle
    %TESTDISPATCHRECORDER  Records dispatchCommand calls for tests.
    %
    %   Used by the ribbon click-dispatch assertion so the test can
    %   verify the button actually fired rather than silently no-op'd.

    properties (Access = public)
        Count       double = 0
        LastCmd     char   = ''
        LastSource  char   = ''
        History     cell   = {}
    end

    methods
        function record(obj, cmdId, source)
            obj.Count = obj.Count + 1;
            obj.LastCmd = char(cmdId);
            if nargin >= 3, obj.LastSource = char(source); end
            obj.History{end+1} = struct('cmd', obj.LastCmd, 'source', obj.LastSource);
        end
    end
end
