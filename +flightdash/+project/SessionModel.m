classdef SessionModel
    % flightdash.project.SessionModel
    % One review session = up to 2 flight channels (data + video) plus
    % their dashboard state (plot tabs, ROI rows, sync state, etc.).
    %
    % Phase 2: data structure + basic CRUD only. Live state from a
    % running FlightDataDashboard syncs into this model in Phase 3+.

    properties
        SchemaVersion       uint32   = uint32(1)

        SessionId           char     = ''
        DisplayName         char     = ''
        FolderPath          char     = ''      % session-relative folder for assets

        % Per-channel paths (cell{1,2})
        FlightFilePath      cell     = {'', ''}
        VideoFilePath       cell     = {'', ''}
        % Phase A: option*.dat is now a first-class per-channel asset
        % (column-mapping config). Tracked alongside flight/video paths
        % so Health Check, Pack Project, and Support Bundle workflows
        % treat option files as core project assets.
        OptionFilePath      cell     = {'', ''}

        % Sync state snapshots (struct mirrors of app.SyncState etc.)
        FlightSyncState     struct   = struct('IsSynced', false, 'SyncT1', 0, 'SyncT2', 0)
        VideoSyncState      struct   = struct('IsSynced', {false, false}, ...
                                              'AnchorFrame', {0, 0}, ...
                                              'AnchorOffset', {0, 0}, ...
                                              'AnchorTime', {0, 0}, ...
                                              'VideoFps', {70, 70}, ...
                                              'DataFps', {50, 50}, ...
                                              'TotalFrames', {0, 0}, ...
                                              'CurrentFrame', {1, 1})

        CurrentIndex        double   = [1 1]
        CurrentFrame        double   = [1 1]

        % Plot/ROI snapshots (Phase 3 sync)
        PlotTabs            struct   = struct('Tabs', {{}})
        RoiRows             cell     = {cell(0, 5), cell(0, 5)}
        EventMarkers        struct   = struct('Markers', {{}})
        ReviewNotes         char     = ''

        PanelVisible        struct   = struct()
        LayoutState         struct   = struct()

        % Per-session preferences (overrides project-level when not 'Inherit')
        AutoUpdateMode      char     = 'Inherit'   % Inherit|Manual|Auto|Frozen

        % Source-data integrity tracking (used by DirtyTracker, Phase 8)
        LastDataHash        cell     = {'', ''}
        LastSyncHash        cell     = {'', ''}

        DirtyFlag           logical  = false
        CreatedAt           char     = ''
        ModifiedAt          char     = ''
    end

    properties (Dependent)
        FlightFiles
        VideoFiles
        FlightFilePaths
        VideoFilePaths
    end

    methods
        function obj = SessionModel(displayName)
            if nargin < 1 || isempty(displayName)
                displayName = 'New Session';
            end
            obj.DisplayName = char(displayName);
            obj.SessionId   = flightdash.project.ProjectModel.newId('SESS');
            obj.CreatedAt   = flightdash.project.ProjectModel.nowIso();
            obj.ModifiedAt  = obj.CreatedAt;
        end

        function obj = setFlightFile(obj, channelIdx, path)
            flightdash.project.SessionModel.validateChannelIdx(channelIdx);
            obj.FlightFilePath{channelIdx} = flightdash.project.SessionModel.coercePath(path);
            obj = obj.touch();
        end

        function obj = setVideoFile(obj, channelIdx, path)
            flightdash.project.SessionModel.validateChannelIdx(channelIdx);
            obj.VideoFilePath{channelIdx} = flightdash.project.SessionModel.coercePath(path);
            obj = obj.touch();
        end

        function obj = setRoiRows(obj, channelIdx, rows)
            flightdash.project.SessionModel.validateChannelIdx(channelIdx);
            obj.RoiRows{channelIdx} = rows;
            obj = obj.touch();
        end

        function obj = setDisplayName(obj, name)
            name = flightdash.project.SessionModel.coerceName(name);
            if isempty(name)
                error('SessionModel:EmptyName', 'DisplayName cannot be empty.');
            end
            obj.DisplayName = name;
            obj = obj.touch();
        end

        function tf = hasFlightData(obj, channelIdx)
            flightdash.project.SessionModel.validateChannelIdx(channelIdx);
            tf = ~isempty(obj.FlightFilePath{channelIdx});
        end

        function tf = hasVideo(obj, channelIdx)
            flightdash.project.SessionModel.validateChannelIdx(channelIdx);
            tf = ~isempty(obj.VideoFilePath{channelIdx});
        end

        function obj = touch(obj)
            obj.ModifiedAt = flightdash.project.ProjectModel.nowIso();
            obj.DirtyFlag  = true;
        end

        function v = get.FlightFiles(obj)
            v = obj.FlightFilePath;
        end

        function obj = set.FlightFiles(obj, value)
            obj.FlightFilePath = flightdash.project.SessionModel.coercePathPair(value);
            obj = obj.touch();
        end

        function v = get.VideoFiles(obj)
            v = obj.VideoFilePath;
        end

        function obj = set.VideoFiles(obj, value)
            obj.VideoFilePath = flightdash.project.SessionModel.coercePathPair(value);
            obj = obj.touch();
        end

        function v = get.FlightFilePaths(obj)
            v = obj.FlightFilePath;
        end

        function obj = set.FlightFilePaths(obj, value)
            obj.FlightFilePath = flightdash.project.SessionModel.coercePathPair(value);
            obj = obj.touch();
        end

        function v = get.VideoFilePaths(obj)
            v = obj.VideoFilePath;
        end

        function obj = set.VideoFilePaths(obj, value)
            obj.VideoFilePath = flightdash.project.SessionModel.coercePathPair(value);
            obj = obj.touch();
        end
    end

    methods (Static, Access = private)
        function validateChannelIdx(channelIdx)
            % [PHASE 4 review] Reject non-integer / out-of-range channel
            % indices early instead of letting cell indexing die with a
            % cryptic error 200ms later.
            validateattributes(channelIdx, {'numeric'}, ...
                {'scalar', 'integer', 'finite', '>=', 1, '<=', 2}, ...
                '', 'channelIdx');
        end

        function s = coercePath(path)
            if isstring(path)
                if isscalar(path)
                    s = char(path);
                else
                    s = '';
                end
            elseif ischar(path)
                s = path;
            elseif isempty(path)
                s = '';
            else
                error('SessionModel:InvalidPath', ...
                'path must be a char vector or string scalar.');
            end
        end

        function out = coercePathPair(value)
            out = {'', ''};
            if isempty(value)
                return;
            elseif iscell(value)
                for k = 1:min(2, numel(value))
                    out{k} = flightdash.project.SessionModel.coercePath(value{k});
                end
            elseif isstring(value)
                for k = 1:min(2, numel(value))
                    out{k} = flightdash.project.SessionModel.coercePath(value(k));
                end
            elseif ischar(value)
                out{1} = value;
            else
                error('SessionModel:InvalidPathPair', ...
                    'path pair must be a cell, string array, char vector, or empty.');
            end
        end

        function s = coerceName(name)
            if isstring(name)
                if isscalar(name)
                    s = strtrim(char(name));
                else
                    s = '';
                end
            elseif ischar(name)
                s = strtrim(name);
            elseif isempty(name)
                s = '';
            else
                s = '';
            end
        end
    end
end
