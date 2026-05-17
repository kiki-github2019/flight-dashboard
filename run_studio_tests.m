% run_studio_tests.m
% Compatibility smoke runner; FlightReviewStudioTestSuite is canonical.

repoRoot = fileparts(mfilename('fullpath'));
addpath(repoRoot);
clear classes;
rehash toolboxcache;

results = FlightReviewStudioTestSuite();
statuses = string({results.Status});
numFailed = sum(statuses == "FAIL");
fprintf('Studio smoke tests: total=%d failed=%d\n', numel(results), numFailed);

if numFailed > 0
    error('FlightReviewStudio:SmokeTestsFailed', 'Studio smoke tests failed.');
end
