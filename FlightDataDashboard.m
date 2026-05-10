function app = FlightDataDashboard()
    % Compatibility entry point.
    % The implementation lives in +flightdash/FlightDataDashboard.m.
    % Existing calls to FlightDataDashboard() continue to work, while new
    % code can call flightdash.FlightDataDashboard() directly.
    app = flightdash.FlightDataDashboard();
end
