function report = verifyCallbackSafety(rootDir)
%VERIFYCALLBACKSAFETY  Static scan + light runtime checks for callback /
%   EventBus listener safety. Reports findings as WARN unless a proven
%   runtime failure exists (then ERROR). Never throws.
%
%   Patterns flagged (WARN by default):
%     - `@app.<method>` or `@obj.App.<method>` direct method bindings
%       attached to UI callbacks where MATLAB passes (src,event); the
%       method usually expects no args and silently breaks.
%     - `ButtonPushedFcn=` / `MenuSelectedFcn=` / `ValueChangedFcn=` /
%       `SelectionChangedFcn=` / `CellEditCallback=` /
%       `CellSelectionCallback=` / `ButtonDownFcn=` set to a non-
%       anonymous handle (no `@(`).
%     - Controllers subclassing ControllerBase that re-declare a
%       `Listeners` property or override `delete` without forwarding
%       to `obj.cleanup()`.
%
%   Lightweight runtime check (when a dashboard can be constructed
%   headlessly):
%     - Counts EventBus subscriber slots before and after a
%       construct+delete round-trip of FlightDataDashboard; reports
%       FAIL if any subscriber survives.
%
%   Usage:
%     report = flightdash.studio.diag.verifyCallbackSafety();
%     disp(struct2table(report.Findings))
%
%   Output:
%     report.Findings : struct array (File, Line, Severity, Pattern, Snippet)
%     report.Summary  : struct (WarnCount, ErrCount, ScannedFiles)
%     report.Runtime  : struct (Performed, Survived, Status)

    if nargin < 1 || isempty(rootDir)
        here = fileparts(mfilename('fullpath'));
        rootDir = fullfile(here, '..', '..', '..');  % repo root
    end
    rootDir = char(rootDir);

    report = struct( ...
        'Findings', repmat(struct('File','','Line',0,'Severity','', ...
                                  'Pattern','','Snippet',''), 0, 1), ...
        'Summary',  struct('WarnCount',0,'ErrCount',0,'ScannedFiles',0), ...
        'Runtime',  struct('Performed',false,'Survived',NaN,'Status',''));

    %% Static scan ---------------------------------------------------------
    pkgRoot = fullfile(rootDir, '+flightdash');
    if ~isfolder(pkgRoot)
        report.Runtime.Status = sprintf('package root not found: %s', pkgRoot);
        return;
    end
    files = localListMFiles(pkgRoot);
    report.Summary.ScannedFiles = numel(files);

    patterns = {
        '\bButtonPushedFcn\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'ButtonPushedFcn raw handle';
        '\bMenuSelectedFcn\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'MenuSelectedFcn raw handle';
        '\bValueChangedFcn\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'ValueChangedFcn raw handle';
        '\bSelectionChangedFcn\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'SelectionChangedFcn raw handle';
        '\bCellEditCallback\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'CellEditCallback raw handle';
        '\bCellSelectionCallback\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'CellSelectionCallback raw handle';
        '\bButtonDownFcn\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'ButtonDownFcn raw handle';
        '\bCloseRequestFcn\b\s*[,=]\s*@(?!\()[\w\.]+', 'WARN', 'CloseRequestFcn raw handle';
    };

    for fIdx = 1:numel(files)
        f = files{fIdx};
        try
            txt = fileread(f);
        catch
            continue;
        end
        if isempty(txt), continue; end
        for pIdx = 1:size(patterns, 1)
            re = patterns{pIdx, 1};
            sev = patterns{pIdx, 2};
            pname = patterns{pIdx, 3};
            tokens = regexp(txt, re, 'match', 'lineanchors');
            for ti = 1:numel(tokens)
                snippet = strtrim(tokens{ti});
                lineNo = localLineNumber(txt, snippet);
                report.Findings(end+1, 1) = struct( ...
                    'File', f, 'Line', lineNo, 'Severity', sev, ...
                    'Pattern', pname, 'Snippet', snippet);
                report.Summary.WarnCount = report.Summary.WarnCount + 1;
            end
        end
    end

    % Controller-specific: any subclass of ControllerBase that has its
    % own `Listeners` property or its own `delete` that does NOT call
    % obj.cleanup() risks leaving live EventBus listeners after teardown.
    ctrlDir = fullfile(pkgRoot, '+controller');
    if isfolder(ctrlDir)
        ctrlFiles = localListMFiles(ctrlDir);
        for k = 1:numel(ctrlFiles)
            f = ctrlFiles{k};
            try, txt = fileread(f); catch, continue; end
            if isempty(txt), continue; end
            if ~contains(txt, 'flightdash.controller.ControllerBase'), continue; end
            if regexp(txt, '\n\s*Listeners\s+cell\s*=', 'once')
                report.Findings(end+1, 1) = struct( ...
                    'File', f, 'Line', 0, 'Severity', 'WARN', ...
                    'Pattern', 'Subclass redeclares Listeners', ...
                    'Snippet', 'Use inherited Listeners + trackListener');
                report.Summary.WarnCount = report.Summary.WarnCount + 1;
            end
            % Subclass delete() that does not call cleanup().
            delMatch = regexp(txt, 'function\s+delete\s*\(\s*obj\s*\)[^\n]*([\s\S]*?)\bend\b', ...
                'tokens', 'once');
            if ~isempty(delMatch) && ~contains(delMatch{1}, 'cleanup')
                report.Findings(end+1, 1) = struct( ...
                    'File', f, 'Line', 0, 'Severity', 'WARN', ...
                    'Pattern', 'Subclass delete() without cleanup()', ...
                    'Snippet', 'forward to obj.cleanup() to release listeners');
                report.Summary.WarnCount = report.Summary.WarnCount + 1;
            end
        end
    end

    %% Lightweight runtime probe -----------------------------------------
    report.Runtime = localRuntimeProbe();
    if isfield(report.Runtime, 'Status') && contains(lower(report.Runtime.Status), 'fail')
        report.Findings(end+1, 1) = struct( ...
            'File', 'flightdash.util.EventBus', 'Line', 0, ...
            'Severity', 'ERROR', 'Pattern', 'EventBus listener leak', ...
            'Snippet', report.Runtime.Status);
        report.Summary.ErrCount = report.Summary.ErrCount + 1;
    end
end

%% ===== helpers =====

function files = localListMFiles(root)
    files = {};
    try
        entries = dir(fullfile(root, '**', '*.m'));
    catch
        entries = [];
    end
    for k = 1:numel(entries)
        if entries(k).isdir, continue; end
        files{end+1, 1} = fullfile(entries(k).folder, entries(k).name); %#ok<AGROW>
    end
end

function ln = localLineNumber(txt, snippet)
    ln = 0;
    try
        idx = strfind(txt, snippet);
        if isempty(idx), return; end
        ln = 1 + sum(txt(1:idx(1)-1) == sprintf('\n'));
    catch
    end
end

function runtime = localRuntimeProbe()
    runtime = struct('Performed', false, 'Survived', NaN, 'Status', '');
    try
        if exist('flightdash.util.EventBus', 'class') ~= 8
            runtime.Status = 'EventBus class not on path';
            return;
        end
        % Snapshot any subscriber count surface the EventBus exposes.
        before = localEventBusCount();
        % Try to instantiate a dashboard headlessly. If uifigure is
        % unavailable (e.g. nojvm), skip silently.
        app = [];
        try
            app = flightdash.FlightDataDashboard();
        catch
            runtime.Status = 'dashboard build skipped (no display)';
            return;
        end
        runtime.Performed = true;
        try, delete(app); catch, end
        after = localEventBusCount();
        if isnan(before) || isnan(after)
            runtime.Status = 'EventBus does not expose subscriber count';
            return;
        end
        runtime.Survived = max(0, after - before);
        if runtime.Survived > 0
            runtime.Status = sprintf('FAIL: %d EventBus subscriber(s) survived dashboard delete', ...
                runtime.Survived);
        else
            runtime.Status = 'PASS: no surviving subscribers';
        end
    catch ME
        runtime.Status = sprintf('runtime probe error: %s', ME.message);
    end
end

function n = localEventBusCount()
    n = NaN;
    try
        % Prefer the explicit static method (added alongside this
        % diagnostic). Fallback via metaclass keeps the probe useful
        % on older EventBus builds that did not expose the count.
        meta = ?flightdash.util.EventBus;
        if isempty(meta), return; end
        names = arrayfun(@(m) string(m.Name), meta.MethodList);
        if any(names == "subscriberCount")
            n = flightdash.util.EventBus.subscriberCount();
        end
    catch
    end
end
