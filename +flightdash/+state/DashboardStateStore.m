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
    end
end
