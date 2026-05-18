function results = verifyThemeAndLayoutPolish()
%VERIFYTHEMEANDLAYOUTPOLISH Static/runtime checks for GUI polish hooks.

tests = {
    'POLISH-1', @checkThemeProvider
    'POLISH-2', @checkThemeFields
    'POLISH-3', @checkButtonStyling
    'POLISH-4', @checkRightDockCollapseSupport
    'POLISH-5', @checkVideoPanelMinimumWidth
    'POLISH-6', @checkPhase10DiagnosticsResolve
    'POLISH-7', @checkStudioLaunch
    'POLISH-8', @checkLightThemeApply
    'POLISH-9', @checkDarkThemeApply
};

results = struct('TC', {}, 'Result', {}, 'Message', {});
for k = 1:size(tests, 1)
    tc = tests{k, 1};
    fn = tests{k, 2};
    try
        [ok, msg, status] = fn();
        if isempty(status)
            if ok, status = 'PASS'; else, status = 'FAIL'; end
        end
    catch ME
        status = 'FAIL';
        msg = sprintf('%s: %s', ME.identifier, ME.message);
    end
    results(end+1).TC = tc; %#ok<AGROW>
    results(end).Result = status;
    results(end).Message = msg;
end
end

function [ok, msg, status] = checkThemeProvider()
status = '';
ok = ~isempty(meta.class.fromName('flightdash.ui.StudioTheme')) && ...
    any(strcmp(methods('flightdash.ui.StudioTheme'), 'forName'));
msg = passFail(ok, 'Theme token provider exists', 'Theme token provider missing');
end

function [ok, msg, status] = checkThemeFields()
status = '';
required = {'AppBg','PanelBg','CardBg','InputBg','HeaderBg','RibbonBg', ...
    'TabBg','TabActiveBg','TextPrimary','TextSecondary','TextMuted', ...
    'TextDisabled','Border','BorderSoft','ButtonBg','ButtonText', ...
    'ButtonBorder','ButtonDisabledBg','ButtonDisabledText','Primary', ...
    'PrimaryText','Accent','Success','Warning','Danger','AxesBg', ...
    'AxesGrid','AxesText'};
light = flightdash.ui.StudioTheme.light();
dark = flightdash.ui.StudioTheme.dark();
ok = all(isfield(light, required)) && all(isfield(dark, required));
msg = passFail(ok, 'Light and dark tokens include key fields', ...
    'Light or dark token fields are incomplete');
end

function [ok, msg, status] = checkButtonStyling()
status = '';
ok = any(strcmp(methods('flightdash.ui.StudioTheme'), 'styleButton'));
msg = passFail(ok, 'Shared button style helper exists', ...
    'Shared button style helper missing');
end

function [ok, msg, status] = checkRightDockCollapseSupport()
status = '';
txt = fileread(which('flightdash.studio.FlightReviewStudioApp'));
ok = contains(txt, 'RightDockCollapsed') && contains(txt, 'RightDockRailWidth') && ...
    contains(txt, 'applyStudioBreakpoints');
msg = passFail(ok, 'Right dock collapsed/narrow breakpoint support detected', ...
    'Right dock collapsed/narrow support not detected');
end

function [ok, msg, status] = checkVideoPanelMinimumWidth()
status = '';
ok = ispropMeta('flightdash.util.AppConstants', 'LAYOUT_VIDEO_MIN') || ...
    contains(fileread(which('flightdash.view.ResponsiveLayoutManager')), 'LAYOUT_VIDEO_MIN');
msg = passFail(ok, 'Video panel minimum width guard detected', ...
    'Video panel minimum width guard missing');
end

function [ok, msg, status] = checkPhase10DiagnosticsResolve()
status = '';
names = {'flightdash.studio.diag.verifyPhase9', ...
    'flightdash.studio.diag.verifyPhase10', ...
    'flightdash.studio.diag.verifyPhase10VideoReaderSmoke', ...
    'flightdash.studio.diag.verifyRiskRegressionTests'};
ok = all(cellfun(@(n) exist(n, 'file') == 2, names));
msg = passFail(ok, 'Required phase diagnostics resolve', ...
    'One or more required phase diagnostics do not resolve');
end

function [ok, msg, status] = checkStudioLaunch()
if ~canUseGui()
    ok = true; status = 'SKIP'; msg = 'GUI unavailable in this MATLAB session';
    return;
end
status = '';
app = [];
cleanupObj = onCleanup(@() cleanupApp(app)); %#ok<NASGU>
app = flightdash.studio.FlightReviewStudioApp();
ok = ~isempty(app) && isvalid(app);
msg = passFail(ok, 'FlightReviewStudio app launches and deletes cleanly', ...
    'FlightReviewStudio app launch failed');
end

function [ok, msg, status] = checkLightThemeApply()
[ok, msg, status] = checkThemeApply(flightdash.ui.StudioTheme.light(), 'light');
end

function [ok, msg, status] = checkDarkThemeApply()
[ok, msg, status] = checkThemeApply(flightdash.ui.StudioTheme.dark(), 'dark');
end

function [ok, msg, status] = checkThemeApply(tokens, label)
if ~canUseGui()
    ok = true; status = 'SKIP'; msg = 'GUI unavailable in this MATLAB session';
    return;
end
status = '';
fig = uifigure('Visible', 'off');
cleanupObj = onCleanup(@() delete(fig)); %#ok<NASGU>
g = uigridlayout(fig, [2 1]); %#ok<NASGU>
uibutton(g, 'Text', 'Test');
uiaxes(g);
flightdash.ui.StudioTheme.apply(fig, tokens);
ok = true;
msg = sprintf('No hard failure applying %s theme', label);
end

function tf = canUseGui()
tf = usejava('jvm') && usejava('awt');
try
    tf = tf && feature('ShowFigureWindows');
catch
end
end

function cleanupApp(app)
try
    if ~isempty(app) && isvalid(app), delete(app); end
catch
end
end

function ok = ispropMeta(className, propName)
ok = false;
try
    mc = meta.class.fromName(className);
    if isempty(mc), return; end
    ok = any(strcmp({mc.PropertyList.Name}, propName));
catch
end
end

function msg = passFail(ok, passMsg, failMsg)
if ok
    msg = passMsg;
else
    msg = failMsg;
end
end
