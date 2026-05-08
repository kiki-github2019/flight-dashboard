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
            obj.FlightFilePath{channelIdx} = char(path);
            obj = obj.touch();
        end

        function obj = setVideoFile(obj, channelIdx, path)
            obj.VideoFilePath{channelIdx} = char(path);
            obj = obj.touch();
        end

        function obj = setRoiRows(obj, channelIdx, rows)
            obj.RoiRows{channelIdx} = rows;
            obj = obj.touch();
        end

        function obj = setDisplayName(obj, name)
            obj.DisplayName = char(name);
            obj = obj.touch();
        end

        function tf = hasFlightData(obj, channelIdx)
            tf = ~isempty(obj.FlightFilePath{channelIdx});
        end

        function tf = hasVideo(obj, channelIdx)
            tf = ~isempty(obj.VideoFilePath{channelIdx});
        end

        function obj = touch(obj)
            obj.ModifiedAt = flightdash.project.ProjectModel.nowIso();
            obj.DirtyFlag  = true;
        end
    end
end
