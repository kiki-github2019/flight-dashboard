function results = benchmarkResizePerformance(app, iterations)
%BENCHMARKRESIZEPERFORMANCE Lightweight resize benchmark for dashboard figures.
%
% Usage:
%   results = benchmarkResizePerformance();
%   results = benchmarkResizePerformance(app, 80);

    if nargin < 2 || isempty(iterations)
        iterations = 12;
    end
    iterations = max(1, round(double(iterations)));

    ownApp = false;
    if nargin < 1 || isempty(app)
        try
            app = flightdash.FlightDataDashboard();
            ownApp = true;
        catch ME
            results = makeResult('SKIP', sprintf('Could not create dashboard: %s', ME.message), []);
            printResult(results);
            return;
        end
    end
    cleanupObj = onCleanup(@() cleanupBenchmark(app, ownApp)); %#ok<NASGU>

    fig = [];
    try
        if isprop(app, 'UIFigure')
            fig = app.UIFigure;
        end
    catch
        fig = [];
    end
    if isempty(fig) || ~isvalid(fig)
        results = makeResult('SKIP', 'App has no valid UIFigure.', []);
        printResult(results);
        return;
    end

    oldPos = fig.Position;
    times = zeros(iterations, 1);
    try
        for i = 1:iterations
            newPos = oldPos;
            newPos(3) = max(900, oldPos(3) + 20 * mod(i, 4));
            newPos(4) = max(650, oldPos(4) + 15 * mod(i, 3));
            tStart = tic;
            fig.Position = newPos;
            drawnow limitrate;
            times(i) = toc(tStart);
        end
        fig.Position = oldPos;
        drawnow limitrate;
    catch ME
        results = makeResult('FAIL', sprintf('Resize benchmark failed: %s', ME.message), times);
        printResult(results);
        return;
    end

    avgMs = mean(times) * 1000;
    maxMs = max(times) * 1000;
    if avgMs <= 120
        status = 'PASS';
    else
        status = 'WARN';
    end
    msg = sprintf('Average %.2f ms, max %.2f ms over %d resize updates.', ...
        avgMs, maxMs, iterations);
    results = makeResult(status, msg, times);
    printResult(results);
end

function results = makeResult(status, message, times)
    results = struct('TC', 'BENCH-RESIZE', ...
        'Result', char(status), ...
        'Message', char(message), ...
        'AvgTimeMs', NaN, ...
        'MaxTimeMs', NaN, ...
        'Iterations', 0);
    if ~isempty(times)
        times = times(times > 0);
        results.Iterations = numel(times);
        if ~isempty(times)
            results.AvgTimeMs = mean(times) * 1000;
            results.MaxTimeMs = max(times) * 1000;
        end
    end
end

function printResult(results)
    try
        fprintf('Resize benchmark: %s - %s\n', results.Result, results.Message);
    catch
    end
end

function cleanupBenchmark(app, ownApp)
    if ~ownApp
        return;
    end
    try
        if ~isempty(app) && isvalid(app)
            delete(app);
        end
    catch
    end
end
