function app = FlightDataDashboard()
    % [REFACTOR Step 5-D] 호환성 진입점
    % - 메인 클래스는 +flightdash/FlightDataDashboard.m 로 이동됨
    % - 기존 호출 코드 FlightDataDashboard() 가 그대로 동작하도록 wrapper 제공
    % - 신규 코드는 flightdash.FlightDataDashboard() 사용 권장
    app = flightdash.FlightDataDashboard();
end
