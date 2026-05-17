function results = runFullStabilizationTests()
%RUNFULLSTABILIZATIONTESTS Compatibility wrapper for the canonical runner.

    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    results = FlightReviewStudioTestSuite();
end
