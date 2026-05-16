classdef VersionInfo
    %VERSIONINFO  Static product identity for About dialog + Support Bundle.
    %
    %   Single source of truth — bump `current()` when cutting a release.

    methods (Static)
        function s = current()
            s = struct();
            s.ProductName  = 'Flight Review Studio';
            s.Version      = '0.13.0';
            s.BuildDate    = '2026-05-16';
            s.SupportEmail = 'jungsub99@gmail.com';
            s.Copyright    = sprintf('© %s', datestr(now, 'yyyy'));
            s.MatlabRelease = version('-release');
            s.IsDeployed   = isdeployed();
        end

        function txt = aboutText()
            s = flightdash.util.VersionInfo.current();
            deploy = 'Source';
            if s.IsDeployed, deploy = 'Compiled (MATLAB Runtime)'; end
            txt = sprintf(['%s\nVersion %s   |   Build %s\n', ...
                'MATLAB R%s   |   Runtime: %s\n\n', ...
                'License: Unlicensed (placeholder)\n', ...
                'Support: %s\n\n%s'], ...
                s.ProductName, s.Version, s.BuildDate, ...
                s.MatlabRelease, deploy, s.SupportEmail, s.Copyright);
        end
    end
end
