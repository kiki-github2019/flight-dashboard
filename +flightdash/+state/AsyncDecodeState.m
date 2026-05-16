classdef AsyncDecodeState < handle
    %ASYNCDECODESTATE  Async decode state scaffold (R3 prep).
    %
    %   Mirrors the 10 properties listed in the refactor brief for the
    %   parfeval-based async video decode path on FlightDataDashboard.
    %   R1 ships declarations only; R3 will move state ownership here
    %   and replace cleanup code with the helper methods below.
    %
    %   The cleanup helpers (cancelChannel / cancelAll / resetGeneration
    %   / clearPending) are no-ops until R3 wires them. They are present
    %   now so call sites can reference the eventual API without churn.
    %
    %   Owner: DashboardRuntime.

    properties (Access = public)
        UseAsyncDecode        logical = false
        AsyncPool                     = []
        AsyncFutures          cell    = {[], []}
        AsyncTargetFrame      double  = [NaN, NaN]
        AsyncGen              double  = [0, 0]
        IsDecoding            logical = [false, false]
        PendingFrame          double  = [NaN, NaN]
        PendingMode           cell    = {'', ''}
        DragVelocity          double  = [0, 0]
        DragVelocitySamples   cell    = {[], []}
    end

    methods
        function obj = AsyncDecodeState()
        end

        function cancelChannel(obj, fIdx) %#ok<INUSD>
            % R3 will move the parfeval cancel + future-clear logic here.
            % No-op in R1: existing FlightDataDashboard cleanup remains
            % the source of truth.
        end

        function cancelAll(obj) %#ok<MANU>
            % R3 entry point — see cancelChannel.
        end

        function resetGeneration(obj, fIdx)
            % Increment the per-channel generation counter so any
            % in-flight worker result is discarded as stale on arrival.
            % Implementation is local-only in R1; R3 will route the app
            % through this helper.
            if nargin < 2 || isempty(fIdx) || fIdx < 1 || fIdx > numel(obj.AsyncGen)
                return;
            end
            obj.AsyncGen(fIdx) = obj.AsyncGen(fIdx) + 1;
        end

        function clearPending(obj, fIdx)
            if nargin < 2 || isempty(fIdx) || fIdx < 1 || fIdx > numel(obj.PendingFrame)
                return;
            end
            obj.PendingFrame(fIdx) = NaN;
            obj.PendingMode{fIdx} = '';
        end
    end
end
