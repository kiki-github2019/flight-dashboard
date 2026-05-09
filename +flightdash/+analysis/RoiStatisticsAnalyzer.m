classdef RoiStatisticsAnalyzer
    % flightdash.analysis.RoiStatisticsAnalyzer
    % Thin Phase 7 facade over the existing ROI calculation engine.

    methods (Static)
        function rows = compute(times, rawData, rows)
            rows = flightdash.model.RoiAnalyzer.computeStats(times, rawData, rows);
        end
    end
end
