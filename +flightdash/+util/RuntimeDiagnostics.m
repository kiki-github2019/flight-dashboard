classdef RuntimeDiagnostics
    %RUNTIMEDIAGNOSTICS  First-run environment self-check (Phase C-3).
    %
    %   Read-only. Returns a report struct + optional one-line summary
    %   text suitable for the Start Page footer. No mutations, no
    %   modal dialogs — the caller decides whether to surface failures.
    %
    %   Checks:
    %     - MATLAB release / deployed mode
    %     - prefdir / tempdir writable
    %     - sample_data folder reachable
    %     - option1.dat / option2.dat reachable inside sample_data
    %     - VideoReader smoke (constructor available)

    methods (Static)
        function report = run()
            report = struct();
            report.Items = struct( ...
                'Name',    {}, ...
                'OK',      {}, ...
                'Detail',  {});

            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'MATLAB release', true, version('-release'));
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'Deployed mode', true, ternary(isdeployed(), 'compiled', 'source'));

            % prefdir writable.
            try
                pd = prefdir;
                t  = fullfile(pd, '.flightdash_write_probe');
                fid = fopen(t, 'w');
                ok = (fid ~= -1);
                if ok, fclose(fid); delete(t); end
            catch
                ok = false; pd = '(unknown)';
            end
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'prefdir writable', ok, pd);

            % tempdir writable.
            try
                td = tempdir;
                t  = fullfile(td, '.flightdash_write_probe');
                fid = fopen(t, 'w');
                ok = (fid ~= -1);
                if ok, fclose(fid); delete(t); end
            catch
                ok = false; td = '(unknown)';
            end
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'tempdir writable', ok, td);

            % Sample data + option files.
            try
                here = fileparts(mfilename('fullpath'));
                root = fullfile(here, '..', '..');
                sampleDir = fullfile(root, 'sample_data');
            catch
                sampleDir = '';
            end
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'sample_data folder', isfolder(sampleDir), sampleDir);
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'sample option1.dat', isfile(fullfile(sampleDir, 'option1.dat')), ...
                fullfile(sampleDir, 'option1.dat'));
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'sample option2.dat', isfile(fullfile(sampleDir, 'option2.dat')), ...
                fullfile(sampleDir, 'option2.dat'));

            % VideoReader available.
            report = flightdash.util.RuntimeDiagnostics.append(report, ...
                'VideoReader available', exist('VideoReader', 'class') == 8, '');

            report.AllOK = all([report.Items.OK]);
        end

        function line = summary(report)
            if nargin < 1, report = flightdash.util.RuntimeDiagnostics.run(); end
            n = numel(report.Items);
            okCount = sum([report.Items.OK]);
            mark = '✓'; if okCount < n, mark = '⚠'; end
            line = sprintf('%s Runtime: %d/%d checks OK', mark, okCount, n);
        end
    end

    methods (Static, Access = private)
        function r = append(r, name, ok, detail)
            r.Items(end+1).Name   = char(name);
            r.Items(end).OK       = logical(ok);
            r.Items(end).Detail   = char(detail);
        end
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
