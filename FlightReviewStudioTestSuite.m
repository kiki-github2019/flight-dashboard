classdef FlightReviewStudioTestSuite < matlab.unittest.TestCase
    % Compatibility smoke tests for the current Studio APIs.
    % Phase-specific coverage lives in +flightdash/+studio/+diag.

    properties
        TempDir char = ''
    end

    methods (TestMethodSetup)
        function setupTempDir(testCase)
            testCase.TempDir = tempname;
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function cleanupTempDir(testCase)
            if ~isempty(testCase.TempDir) && isfolder(testCase.TempDir)
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    methods (Test)
        function testEntriesResolve(testCase)
            testCase.verifyNotEmpty(which('FlightReviewStudio'));
            testCase.verifyNotEmpty(which('FlightDataDashboard'));
            testCase.verifyNotEmpty(which('flightdash.studio.FlightReviewStudioApp'));
        end

        function testProjectSerializerFigureRoundTrip(testCase)
            p = flightdash.project.ProjectModel('Suite Project');
            fig = flightdash.project.FigureModel('Graph', 'Suite Figure', 'S_SUITE');
            fig.FigureId = 'FIG_SUITE';
            fig.Variables = {'Roll', 'Pitch'};
            p = p.addFigure(fig);

            filePath = fullfile(testCase.TempDir, 'suite_project.frsproj');
            flightdash.project.ProjectSerializer.save(p, filePath);
            loaded = flightdash.project.ProjectSerializer.load(filePath);

            testCase.verifyTrue(isfile(filePath));
            testCase.verifyFalse(isfile([filePath '.zip']));
            testCase.verifyEqual(numel(loaded.Figures), 1);
            testCase.verifyEqual(loaded.Figures(1).FigureId, 'FIG_SUITE');
        end

        function testPhase9DiagnosticHasNoFailures(testCase)
            results = flightdash.studio.diag.verifyPhase9();
            statuses = {results.Result};
            testCase.verifyFalse(any(strcmp(statuses, 'FAIL')));
        end
    end
end
