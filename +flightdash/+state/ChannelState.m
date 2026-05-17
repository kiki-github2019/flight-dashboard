classdef ChannelState < handle
    %CHANNELSTATE  Per-channel (per-flight) state scaffold for the R2 refactor.
    %
    %   Mirrors the fields of the legacy app.Models(fIdx) struct that
    %   createEmptyModel builds (FlightDataDashboard:708). For R1 this
    %   class exists only as a declaration — the app continues to use
    %   app.Models(fIdx) as the source of truth. R2 introduces
    %   DashboardStateStore + app.channel(fIdx) which return a live view
    %   that proxies these fields.
    %
    %   Field order matches the legacy struct exactly so a future
    %   migration can use fromStruct/toStruct round-tripping with no
    %   data loss.
    %
    %   Lifetime: owned by DashboardStateStore (R2). One instance per
    %   channel (the app currently has two: Flight 1 / Flight 2).

    properties (Access = public)
        ChannelIndex     double  = 0                % 1 or 2
        RawData          table   = table()
        MappedCols       struct  = struct()
        DisplayMeta      struct  = struct()
        Bounds           struct  = struct('minLat', 0, 'maxLat', 0, ...
                                          'minLon', 0, 'maxLon', 0, ...
                                          'isValid', false)
        AltBounds        struct  = struct('minAlt', 0, 'maxAlt', 0)
        CurrentIndex     double  = 1
        SelectedRow      double  = 1
        IsMockData       logical = false
        FlightFilePath   char    = ''
        VideoFilePath    char    = ''
    end

    methods
        function obj = ChannelState(channelIdx)
            if nargin >= 1 && ~isempty(channelIdx)
                obj.ChannelIndex = double(channelIdx);
            end
        end

        function s = toStruct(obj)
            % Convert to the legacy Models(fIdx) struct shape so
            % existing reads can be served unchanged during R2.
            s = struct( ...
                'rawData',      obj.RawData, ...
                'mappedCols',   obj.MappedCols, ...
                'displayMeta',  obj.DisplayMeta, ...
                'bounds',       obj.Bounds, ...
                'altBounds',    obj.AltBounds, ...
                'currentIndex', obj.CurrentIndex, ...
                'selectedRow',  obj.SelectedRow, ...
                'isMockData',   obj.IsMockData);
        end

        function setCurrentIndex(obj, idx)
            if nargin < 2 || isempty(idx) || ~isnumeric(idx), return; end
            idx = double(idx(1));
            if ~isfinite(idx), return; end
            obj.CurrentIndex = max(1, round(idx));
        end

        function applyModelState(obj, s)
            obj.copyFromStruct(s);
        end

        function syncFromApp(obj, app, fIdx)
            % R2 mirror for fields the app still owns. R8 inverted
            % FlightFilePath + VideoFilePath so they are NOT pulled
            % here — this handle IS their storage (the app's Dependent
            % forward multiplexes the cell array through us). The R2
            % brief's other targets (Models struct fields) still
            % mirror through the app.
            if nargin < 3 || isempty(fIdx), return; end
            try
                if ~isnumeric(fIdx), return; end
                fIdx = double(fIdx);
                if fIdx < 1, return; end
                if isprop(app, 'Models') && numel(app.Models) >= fIdx
                    s = app.Models(fIdx);
                    if isstruct(s)
                        obj.copyFromStruct(s);
                    end
                end
                obj.ChannelIndex = fIdx;
            catch
                % Lazy-mirror is best-effort by design. A broken sync
                % must never break legacy reads — callers can fall back
                % to app.Models(fIdx) directly during the migration.
            end
        end

        function copyFromStruct(obj, s)
            if ~isstruct(s) && ~isobject(s), return; end
            if obj.hasFieldOrProp(s, 'rawData'),      obj.RawData      = s.rawData;      end
            if obj.hasFieldOrProp(s, 'mappedCols'),   obj.MappedCols   = s.mappedCols;   end
            if obj.hasFieldOrProp(s, 'displayMeta'),  obj.DisplayMeta  = s.displayMeta;  end
            if obj.hasFieldOrProp(s, 'bounds'),       obj.Bounds       = s.bounds;       end
            if obj.hasFieldOrProp(s, 'altBounds'),    obj.AltBounds    = s.altBounds;    end
            if obj.hasFieldOrProp(s, 'currentIndex'), obj.setCurrentIndex(s.currentIndex); end
            if obj.hasFieldOrProp(s, 'selectedRow'),  obj.SelectedRow  = s.selectedRow;  end
            if obj.hasFieldOrProp(s, 'isMockData'),   obj.IsMockData   = s.isMockData;   end
        end
    end

    methods (Access = private)
        function tf = hasFieldOrProp(~, s, name)
            tf = (isstruct(s) && isfield(s, name)) || ...
                 (isobject(s) && isprop(s, name));
        end
    end

    methods (Static)
        function obj = fromStruct(channelIdx, s)
            obj = flightdash.state.ChannelState(channelIdx);
            obj.copyFromStruct(s);
        end
    end
end
