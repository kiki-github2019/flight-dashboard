classdef ReviewResultModel
    % flightdash.project.ReviewResultModel
    % Persisted analysis/review output (ROI stats, sync quality, events,
    % comparisons, etc.). Carries DAG metadata used by DirtyTracker
    % (see docs/design-dirty-dag.md).

    properties
        SchemaVersion       uint32   = uint32(1)

        ResultId            char     = ''
        SessionId           char     = ''
        ResultType          char     = 'ROI'   % ROI|Event|SyncCheck|Snapshot|Statistics|Comment
        ChannelIdx          double   = 1

        TimeRange           double   = [NaN NaN]
        FrameRange          double   = [NaN NaN]
        Variables           cell     = {}
        ComputedValues      struct   = struct()
        UserComment         char     = ''
        LinkedFigureId      char     = ''

        % Source-integrity hashes (Phase 8 dirty tracker uses these to
        % detect upstream drift even when DAG is not yet loaded)
        SourceDataHash      char     = ''
        SyncStateHash       char     = ''
        AnalysisThemeId     char     = ''

        % Recalculate / Dirty (per-result mode)
        RecalculateMode     char     = 'Auto'  % Manual|Auto|Frozen
        DirtyFlag           logical  = false

        % --- DAG fields (design-dirty-dag.md §6.1) ---
        DependsOn           cell     = {}      % NodeId list (e.g. 'sess:S001:roi:0')
        NodeKind            char     = 'derived' % source|derived
        DirtyState          char     = 'clean' % clean|dirty|computing|error|stale
        LastError           = []                % MException or empty
        ComputeFnSpec       struct   = struct() % serializable replacement for fn handle

        CreatedAt           char     = ''
        LastCalculatedAt    char     = ''
    end

    methods
        function obj = ReviewResultModel(sessionId, resultType, channelIdx)
            if nargin < 1, sessionId = ''; end
            if nargin < 2, resultType = 'ROI'; end
            if nargin < 3, channelIdx = 1; end

            obj.SessionId   = char(sessionId);
            obj.ResultType  = char(resultType);
            obj.ChannelIdx  = double(channelIdx);
            obj.ResultId    = flightdash.project.ProjectModel.newId('R');
            obj.CreatedAt   = flightdash.project.ProjectModel.nowIso();
        end

        function obj = setComputedValues(obj, values)
            mustBeA(values, 'struct');
            obj.ComputedValues   = values;
            obj.LastCalculatedAt = flightdash.project.ProjectModel.nowIso();
            obj.DirtyState       = 'clean';
            obj.LastError        = [];
            obj.DirtyFlag        = false;
        end

        function obj = markDirty(obj)
            % Frozen results stay 'stale' (data source changed but result
            % preserved); others become 'dirty' awaiting recalculation.
            if strcmp(obj.RecalculateMode, 'Frozen')
                obj.DirtyState = 'stale';
            else
                obj.DirtyState = 'dirty';
            end
            obj.DirtyFlag = true;
        end

        function obj = markComputing(obj)
            obj.DirtyState = 'computing';
        end

        function obj = markError(obj, ME)
            obj.DirtyState = 'error';
            obj.LastError  = ME;
            obj.DirtyFlag  = true;
        end

        function obj = setRecalculateMode(obj, mode)
            valid = {'Manual', 'Auto', 'Frozen'};
            mode = char(mode);
            if ~ismember(mode, valid)
                error('ReviewResultModel:InvalidMode', ...
                    'RecalculateMode must be one of: %s', strjoin(valid, ', '));
            end
            obj.RecalculateMode = mode;
        end

        function obj = setDependencies(obj, depList)
            if ischar(depList), depList = {depList}; end
            mustBeA(depList, 'cell');
            obj.DependsOn = depList;
        end

        function obj = setComputeFn(obj, analyzerName, methodName, inputSnapshot)
            % Analyzer + method + serializable input snapshot replaces
            % function_handle (which does not survive save/load reliably).
            obj.ComputeFnSpec = struct( ...
                'analyzer',      char(analyzerName), ...
                'method',        char(methodName), ...
                'inputSnapshot', inputSnapshot);
        end

        function nid = nodeId(obj)
            % Canonical NodeId per design-dirty-dag.md §2
            nid = sprintf('result:%s:%s', obj.SessionId, obj.ResultId);
        end
    end
end
