% run_studio_tests.m
% Current Studio compatibility smoke runner.

clc;
rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end
addpath(rootDir);
clear classes;
rehash toolboxcache;

results = runtests('FlightReviewStudioTestSuite');
disp(table(results));

numFailed = sum([results.Failed]);
numIncomplete = sum([results.Incomplete]);
fprintf('Studio smoke tests: total=%d passed=%d failed=%d incomplete=%d\n', ...
    numel(results), sum([results.Passed]), numFailed, numIncomplete);

if numFailed > 0 || numIncomplete > 0
    error('FlightReviewStudio:SmokeTestsFailed', ...
        'Studio smoke tests failed or were incomplete.');
end
