classdef AsyncDecodeState < handle
    %ASYNCDECODESTATE  Async-decode state container + helper API (R3).
    %
    %   Mirrors the 10 properties listed in the refactor brief for the
    %   parfeval-based async video decode path on FlightDataDashboard.
    %
    %   Two operating modes:
    %     - Unbound (constructor with no app): a pure value container.
    %       The helper methods only update the local fields. Useful for
    %       isolated unit tests.
    %     - App-bound (constructor with app handle): every helper also
    %       mutates the matching app property so the helpers are drop-in
    %       replacements for the legacy inline cleanup code. R3 wires
    %       this mode through FlightDataDashboard.getAsyncDecode().
    %
    %   Owner: DashboardRuntime (after R3 wiring) — co-owned with the
    %   FlightDataDashboard app, both holding the same handle.

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

    properties (Constant, Access = private)
        CancelWaitTimeoutSec = 0.5
    end

    properties (Access = private)
        AppRef
    end

    methods
        function obj = AsyncDecodeState(app)
            if nargin >= 1 && ~isempty(app) && isa(app, 'handle')
                obj.AppRef = app;
            end
        end

        function tf = isBound(obj)
            tf = ~isempty(obj.AppRef) && isa(obj.AppRef, 'handle') ...
                && isvalid(obj.AppRef);
        end

        function syncFromApp(obj)
            % R3 lazy mirror for properties the app still owns. R6
            % inverted 7 of the 10 fields (UseAsyncDecode / AsyncPool /
            % AsyncFutures / AsyncTargetFrame / AsyncGen / DragVelocity
            % / DragVelocitySamples) so they are NOT synced here —
            % their storage IS this handle. IsDecoding / PendingFrame
            % / PendingMode still mirror through the app until their
            % external read counts also drop to zero.
            if ~obj.isBound(), return; end
            a = obj.AppRef;
            try
                if isprop(a, 'IsDecoding'),         obj.IsDecoding         = a.IsDecoding;       end
                if isprop(a, 'PendingFrame'),       obj.PendingFrame       = a.PendingFrame;     end
                if isprop(a, 'PendingMode'),        obj.PendingMode        = a.PendingMode;      end
            catch
                % Lazy mirror is best-effort — never throw out of a
                % bound sync.
            end
        end

        function cancelChannel(obj, fIdx)
            % Drop-in replacement for the legacy inline cancel pattern
            % at FlightDataDashboard.cleanupVideoResources / channel
            % cancel sites:
            %   AsyncGen(fIdx) = AsyncGen(fIdx) + 1
            %   AsyncTargetFrame(fIdx) = NaN
            %   if valid future: cancel + wait(0.5) + clear
            %
            % Bumps generation BEFORE issuing cancel so any worker
            % result that races in is discarded as stale. The wait is
            % bounded by CancelWaitTimeoutSec so a stuck worker cannot
            % hold the caller indefinitely.
            if nargin < 2 || isempty(fIdx) || ~isnumeric(fIdx), return; end
            fIdx = double(fIdx);
            if fIdx < 1, return; end
            obj.resetGeneration(fIdx);
            obj.setAsyncTargetFrame(fIdx, NaN);
            futures = obj.currentFutures();
            if fIdx > numel(futures), return; end
            fut = futures{fIdx};
            try
                if ~isempty(fut) && isvalid(fut)
                    cancel(fut);
                    try
                        wait(fut, 'finished', obj.CancelWaitTimeoutSec);
                    catch ME_wait
                        obj.logIfBound(ME_wait, 'AsyncDecode:cancelChannel:wait');
                    end
                end
            catch ME
                obj.logIfBound(ME, 'AsyncDecode:cancelChannel');
            end
            obj.clearFutureSlot(fIdx);
        end

        function cancelAll(obj)
            % Cancel every per-channel future. Iterates by current
            % future-cell length so a 1- or 2-channel deployment both
            % work without code change.
            futures = obj.currentFutures();
            for k = 1:numel(futures)
                obj.cancelChannel(k);
            end
        end

        function resetGeneration(obj, fIdx)
            % Bump the per-channel generation counter so any in-flight
            % worker result is discarded as stale on arrival. Mirrors to
            % app.AsyncGen when bound.
            if nargin < 2 || isempty(fIdx) || ~isnumeric(fIdx), return; end
            fIdx = double(fIdx);
            if fIdx < 1, return; end
            % Operate on the live source (app when bound, else local).
            if obj.isBound() && isprop(obj.AppRef, 'AsyncGen')
                a = obj.AppRef;
                if fIdx <= numel(a.AsyncGen)
                    a.AsyncGen(fIdx) = a.AsyncGen(fIdx) + 1;
                    obj.AsyncGen = a.AsyncGen;
                    return;
                end
            end
            if fIdx <= numel(obj.AsyncGen)
                obj.AsyncGen(fIdx) = obj.AsyncGen(fIdx) + 1;
            end
        end

        function clearPending(obj, fIdx)
            % Clear the per-channel pending frame + mode. Mirrors to
            % app.PendingFrame / app.PendingMode when bound.
            if nargin < 2 || isempty(fIdx) || ~isnumeric(fIdx), return; end
            fIdx = double(fIdx);
            if fIdx < 1, return; end
            if obj.isBound()
                a = obj.AppRef;
                try
                    if isprop(a, 'PendingFrame') && fIdx <= numel(a.PendingFrame)
                        a.PendingFrame(fIdx) = NaN;
                        obj.PendingFrame = a.PendingFrame;
                    end
                    if isprop(a, 'PendingMode') && fIdx <= numel(a.PendingMode)
                        a.PendingMode{fIdx} = '';
                        obj.PendingMode = a.PendingMode;
                    end
                catch ME
                    obj.logIfBound(ME, 'AsyncDecode:clearPending');
                end
                return;
            end
            if fIdx <= numel(obj.PendingFrame)
                obj.PendingFrame(fIdx) = NaN;
            end
            if fIdx <= numel(obj.PendingMode)
                obj.PendingMode{fIdx} = '';
            end
        end
    end

    % ---------- private helpers ----------
    methods (Access = private)
        function futures = currentFutures(obj)
            futures = obj.AsyncFutures;
            if obj.isBound() && isprop(obj.AppRef, 'AsyncFutures')
                try, futures = obj.AppRef.AsyncFutures; catch, end
            end
        end

        function setAsyncTargetFrame(obj, fIdx, val)
            if obj.isBound() && isprop(obj.AppRef, 'AsyncTargetFrame')
                a = obj.AppRef;
                if fIdx <= numel(a.AsyncTargetFrame)
                    a.AsyncTargetFrame(fIdx) = val;
                    obj.AsyncTargetFrame = a.AsyncTargetFrame;
                    return;
                end
            end
            if fIdx <= numel(obj.AsyncTargetFrame)
                obj.AsyncTargetFrame(fIdx) = val;
            end
        end

        function clearFutureSlot(obj, fIdx)
            if obj.isBound() && isprop(obj.AppRef, 'AsyncFutures')
                a = obj.AppRef;
                try
                    if fIdx <= numel(a.AsyncFutures)
                        a.AsyncFutures{fIdx} = [];
                        obj.AsyncFutures = a.AsyncFutures;
                    end
                catch
                end
                return;
            end
            if fIdx <= numel(obj.AsyncFutures)
                obj.AsyncFutures{fIdx} = [];
            end
        end

        function logIfBound(obj, ME, tag)
            try
                if obj.isBound() && ismethod(obj.AppRef, 'logCaught')
                    obj.AppRef.logCaught(ME, tag);
                end
            catch
            end
        end
    end
end
