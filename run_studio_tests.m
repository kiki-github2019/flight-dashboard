% run_studio_tests.m
% FlightDataReviewStudio 통합 테스트 스위트를 실행하는 스크립트입니다.
% 이 스크립트를 프로젝트 루트 디렉토리 또는 tests 폴더에 두고 실행하세요.

clc;
disp('==================================================');
disp('   FlightDataReviewStudio 통합 테스트 스위트 실행 시작');
disp('==================================================');

% 1. 필요한 경로 추가 (프로젝트 구조에 맞게 수정 가능)
% 현재 폴더 및 하위 폴더를 매트랩 경로에 추가하여 클래스들을 인식하게 합니다.
addpath(genpath(pwd));

% 2. 테스트 실행
try
    % 진행 상황을 콘솔에 출력하며 테스트 실행
    results = runtests('FlightReviewStudioTestSuite');
    
    % 3. 결과 요약 테이블 출력
    disp(' ');
    disp('==================================================');
    disp('                 테스트 실행 결과 요약');
    disp('==================================================');
    disp(table(results));
    
    % 4. 최종 결과 판별
    numFailed = sum([results.Failed]);
    numIncomplete = sum([results.Incomplete]);
    numPassed = sum([results.Passed]);
    
    disp('--------------------------------------------------');
    fprintf('총 테스트: %d | 성공: %d | 실패: %d | 미완료: %d\n', ...
        length(results), numPassed, numFailed, numIncomplete);
    disp('--------------------------------------------------');
    
    if numFailed > 0 || numIncomplete > 0
        warning('일부 테스트가 실패했거나 완료되지 않았습니다. 상세 로그를 확인해주세요.');
    else
        disp('🎉 모든 테스트가 성공적으로 통과되었습니다! 코드를 병합해도 안전합니다.');
    end
    
catch ME
    warning('테스트 환경을 구성하거나 실행하는 중 치명적인 오류가 발생했습니다:');
    disp(ME.message);
    % 에러 스택(상세 경로) 출력
    for i = 1:length(ME.stack)
        fprintf('  파일: %s, 라인: %d, 함수: %s\n', ME.stack(i).file, ME.stack(i).line, ME.stack(i).name);
    end
end