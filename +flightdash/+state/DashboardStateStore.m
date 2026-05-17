classdef DashboardStateStore < handle
    %DASHBOARDSTATESTORE  Aggregate of per-channel + video state (R2 prep).
    %
    %   Holds the eventual destination for app.Models / app.VideoState /
    %   app.VideoSyncState / app.FlightFilePath / app.VideoFilePath. R1
    %   declares the container; R2 will introduce app.channel(fIdx) and
    %   begin mirroring writes into Channels(fIdx).
    %
    %   Channels is a 1x2 array of ChannelState handles matching the
    %   existing two-flight layout. The app keeps the legacy
    %   app.Models(fIdx) struct as the read source until R5.

    properties (Access = public)
        Channels      flightdash.state.ChannelState
        Video         flightdash.state.VideoSessionState = ...
            flightdash.state.VideoSessionState.empty
    end

    methods
        function obj = DashboardStateStore(numChannels)
            if nargin < 1 || isempty(numChannels) || numChannels < 1
                numChannels = 2;
            end
            ch(1, numChannels) = flightdash.state.ChannelState();
            for k = 1:numChannels
                ch(k) = flightdash.state.ChannelState(k);
            end
            obj.Channels = ch;
            obj.Video = flightdash.state.VideoSessionState();
        end

        function ch = channel(obj, fIdx)
            % Bounds-checked accessor. Returns empty when fIdx is out of
            % range so callers can guard with isempty().
            ch = flightdash.state.ChannelState.empty;
            if nargin < 2 || isempty(fIdx) || ~isnumeric(fIdx), return; end
            fIdx = double(fIdx);
            if fIdx < 1 || fIdx > numel(obj.Channels), return; end
            ch = obj.Channels(fIdx);
        end

        function ch = setCurrentIndex(obj, fIdx, idx)
            ch = obj.channel(fIdx);
            if isempty(ch), return; end
            ch.setCurrentIndex(idx);
        end

        function applyModelState(obj, fIdx, modelState)
            ch = obj.channel(fIdx);
            if isempty(ch), return; end
            ch.applyModelState(modelState);
            ch.ChannelIndex = double(fIdx);
        end

        function s = channelStruct(obj, fIdx)
            s = struct();
            ch = obj.channel(fIdx);
            if ~isempty(ch)
                s = ch.toStruct();
            end
        end

        function mirrorChannelToApp(obj, app, fIdx)
            ch = obj.channel(fIdx);
            if isempty(ch), return; end
            if isprop(app, 'Models') && numel(app.Models) >= fIdx
                app.Models(fIdx) = ch.toStruct();
            end
        end

        function syncFromApp(obj, app, fIdx)
            % R2 mirror: refresh either a single channel or all channels
            % from the legacy app.Models / FlightFilePath / VideoFilePath
            % properties. Called from app.channel(fIdx) right before the
            % handle is returned to a caller.
            if nargin < 3 || isempty(fIdx)
                for k = 1:numel(obj.Channels)
                    obj.Channels(k).syncFromApp(app, k);
                end
                return;
            end
            ch = obj.channel(fIdx);
            if ~isempty(ch)
                ch.syncFromApp(app, fIdx);
            end
        end

        function syncVideoFromApp(obj, app)
            % R2 mirror for the video aggregate. Tolerant of partial
            % construction (VideoState may not exist yet on a freshly
            % built app).
            if isempty(obj.Video), return; end
            try
                if isprop(app, 'VideoState'),     obj.Video.VideoState     = app.VideoState;     end
                if isprop(app, 'VideoSyncState'), obj.Video.VideoSyncState = app.VideoSyncState; end
                if isprop(app, 'SyncState') && isstruct(app.SyncState)
                    obj.Video.SyncState = app.SyncState;
                end
            catch
            end
        end
    end
end
