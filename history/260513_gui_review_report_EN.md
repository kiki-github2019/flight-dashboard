# Review Report for `260513_gui(1).log`

> Structure: The original statements from `260513_gui(1).log` are preserved as much as possible in English translation, and **Review Result / Response** is added directly below each sentence or meaning block.

---

## 1. Flight 1 data loading / `option1.dat` mapping

**Original**  
When I press the Flight 1 button and select a CSV file to load flight data, the following message appears in an error dialog after some time.

**Review Result / Response**  
This appears to be a failure in the column-mapping validation stage after reading the CSV file, rather than a simple click-event failure of the Flight 1 button. In other words, the GUI event starts correctly, but the process stops when required flight-data columns cannot be mapped.

**Original**  
Error : Required flight-data columns were not mapped : Roll, Pitch, Check option1.dat or file headers.

**Review Result / Response**  
`Roll` and `Pitch` are required columns, but the current CSV header or `option1.dat` configuration does not map them correctly. The recommended improvement direction is as follows.

```text
1. Analyze the actual operational option1.dat file format.
2. Compare the test option1.dat format with the actual option1.dat format.
3. Add CSV header normalization.
   - Ignore case
   - Remove spaces
   - Remove parentheses / unit strings
   - Remove special characters
4. Add alias tables for Roll / Pitch / Heading / Altitude / Lat / Lon / Time.
5. If required columns are missing, show a mapping confirmation dialog instead of only showing an error dialog.
```

Example alias table:

```matlab
aliases.Roll    = {'Roll','roll','ROLL','Roll(deg)','roll_deg','Phi','phi'};
aliases.Pitch   = {'Pitch','pitch','PITCH','Pitch(deg)','pitch_deg','Theta','theta'};
aliases.Heading = {'Heading','heading','Yaw','yaw','Psi','psi','Azimuth'};
```

**Original**  
-> The existing `option1.dat` file needs to be uploaded and analyzed again.

**Review Result / Response**  
Agreed. The parser and mapping logic should be reviewed using the actual `option1.dat` file currently used in operation. If the implementation is based only on the test configuration file, the same mapping error is likely to occur repeatedly with real flight-data files.

**Original**  
-> The format is different from the `option1.dat` used for test data.

**Review Result / Response**  
In this case, the `option1.dat` parser should not assume only one fixed format. At minimum, one of the following approaches is needed.

```text
A. Version-aware parser
   - Separately recognize old / test / operational formats.

B. Flexible parser
   - Flexibly recognize line patterns, delimiters, and key-value formats.
```

---

## 2. Initial launch / Project Explorer display

**Original**  
1. Initial launch:

**Review Result / Response**  
This item concerns whether the default workspace and dock layout are opened in the expected Studio-style layout when `FlightReviewStudio` is first launched.

**Original**  
Project explore does not appear. Only the "Welcome" tab appears. Is this because not all phases have been completed?

**Review Result / Response**  
This is more likely an issue with the default GUI mode or dock visibility setting than with phase incompletion. If the target is an OriginPro-style Studio, Project Explorer should normally be visible by default.

Recommended initial state:

```text
When FlightReviewStudio first launches:
- Left Dock: Project Explorer visible
- Center Workspace: Welcome tab visible
- Right Dock: Object Manager / Inspector visible or collapsed
- Status Bar: Current project/session status displayed
```

Items to check:

```text
1. Whether the ProjectExplorerPanel object is actually created
2. Whether the LeftDock column width starts at 0
3. Whether Compact mode is applied by default and hides Project Explorer
4. Whether the Window > Show Project Explorer menu state is synchronized with the actual visibility state
```

---

## 3. Behavior after AVI file loading before synchronization

**Original**  
After opening an AVI file,

**Review Result / Response**  
Immediately after loading an AVI file, video metadata, FPS, duration, and total frame count should be read correctly and displayed in the GUI. At this point, there is no synchronization relationship between the flight data and the video frame, so it can be normal that dragging a flight-data marker does not change the video frame.

**Original**  
Even if I drag the flight-data item or the star marker in the altitude information, the video player screen does not change.

**Review Result / Response**  
This is normal before synchronization. The conversion relationship between data time/index and video frame has not yet been configured.

**Original**  
-> Normal

**Review Result / Response**  
Agreed. However, it would be helpful to display a GUI status message such as:

```text
Video/Data sync is not configured.
Drag marker updates data view only.
```

---

## 4. Real-time update of the video slider

**Original**  
When dragging the video player slider bar, the screen freezes, and the screen changes only after dragging stops.

**Review Result / Response**  
The current implementation likely updates the final frame only through `ValueChangedFcn` after mouse release, without performing frame preview during slider drag. From a usability perspective, video frames should update periodically during dragging.

**Original**  
-> Real-time update is needed.

**Review Result / Response**  
This should be implemented. Recommended direction:

```text
During dragging:
- Use uislider.ValueChangingFcn.
- Apply throttling to approximately 10–20 FPS.
- Perform video frame preview only.
- Skip heavy plot redraw, ROI recalculation, and sync-quality calculations.

After drag release:
- Finalize the exact frame in ValueChangedFcn.
- Synchronize marker, plot, status bar, and synced data index.
```

Example structure:

```matlab
slider.ValueChangingFcn = @(src, evt) app.onVideoSliderChanging(fIdx, evt.Value);
slider.ValueChangedFcn  = @(src, evt) app.onVideoSliderChanged(fIdx, src.Value);
```

---

## 5. Behavior after video/flight-data synchronization

**Original**  
After synchronizing the video and flight data,

**Review Result / Response**  
After synchronization, the relationship between flight-data time/index and video frame is established. From this point on, marker dragging and video-frame movement should be linked.

**Original**  
When I drag the flight-data item or the star marker in the altitude information, the video player screen changes together.

**Review Result / Response**  
This is normal behavior. This feature should be preserved. If frame updates during dragging are too heavy, throttling should be applied.

**Original**  
-> ok

**Review Result / Response**  
Agreed. Marker drag → video frame update after synchronization is a core feature.

**Original**  
When dragging the video player slider bar, the screen freezes, and the screen changes only after dragging stops.

**Review Result / Response**  
Because the same issue occurs after synchronization, the slider preview path itself is likely insufficient.

**Original**  
-> Real-time update is needed.

**Review Result / Response**  
After synchronization, the following should also be updated during video slider dragging.

```text
- Video frame preview
- Synced flight-data index
- Data plot marker position
- Current-value label
```

However, redrawing all plots on every slider movement may be slow, so the preview stage and final commit stage should be separated.

---

## 6. Coastline information input / map range

**Original**  
Select coastline information input file.

**Review Result / Response**  
After loading a coastline file, coast-data lon/lat bounds, flight-data bounds, and fixed-area bounds should be managed separately.

**Original**  
Y-axis: lat

**Review Result / Response**  
This is correct. Latitude should be displayed on the Y-axis.

**Original**  
X-axis: lon

**Review Result / Response**  
This is correct. Longitude should be displayed on the X-axis.

**Original**  
The maximum range of X-axis and Y-axis is ignored, and only part of the data is displayed.

**Review Result / Response**  
This needs to be fixed. Possible causes include:

```text
1. option_flight_area.dat or FixedAreaBounds is forcibly applied.
2. axis auto mode is applied again after xlim/ylim are set.
3. Flight-data bounds are used instead of coastline bounds.
4. Bounds become reduced while removing NaN or zero coordinates.
5. axis equal or aspect-ratio settings are applied in the wrong order.
```

**Original**  
-> Needs correction.

**Review Result / Response**  
Recommended correction direction:

```text
1. Calculate Coastline bounds, Flight bounds, and FixedArea bounds separately.
2. If only coastline data is loaded, display the full coastline range by default.
3. If flight data is also loaded, provide a union-bounds option.
4. If FixedAreaBounds is applied, show “Fixed Area mode” in the GUI.
5. Finalize xlim/ylim in the last step of the drawing process.
```

---

## 7. Mismatch between standalone FlightDataDashboard and Studio embedded Dashboard

**Original**  
When running FligthDashBoard.m standalone, the screen looks completely different. Even if I press the Flight 1 button and select a CSV file, it does not process it.

**Review Result / Response**  
This is an important structural issue. The standalone execution path and Studio embedded execution path may be using different UI/initialization logic. Standalone mode should go through the same controller/view/model initialization as embedded mode.

**Original**  
It is completely different from the FlightDashBoard that appears when adding a session in FlightReviewStudio.m.

**Review Result / Response**  
The intended structure should use the same Dashboard class for both standalone and embedded modes. The differences should be limited to the following.

```text
Standalone:
- Create its own uifigure.
- RootContainer = UIFigure.
- Own CloseRequestFcn / SizeChangedFcn directly.

Embedded:
- Render inside the Studio tab/panel.
- RootContainer = parentContainer.
- MouseRouter / shared services / UndoService are injected by Studio.
```

**Original**  
Can FligthDashBoard.m be modified so that it can run standalone and also be used as the tab GUI when FlightReviewStudio.m is executed?

**Review Result / Response**  
Yes, it is possible. The key is to make `createLayout()` build the UI based on `RootContainer`, not directly on `UIFigure`.

Recommended structure:

```matlab
function app = FlightDataDashboard(parentContainer, sessionId)
    if nargin >= 1 && ~isempty(parentContainer)
        app.IsEmbedded = true;
        app.RootContainer = parentContainer;
        app.UIFigure = ancestor(parentContainer, 'figure');
    else
        app.IsEmbedded = false;
        app.UIFigure = uifigure(...);
        app.RootContainer = app.UIFigure;
    end

    app.createModels();
    app.createControllers();
    app.createLayout(app.RootContainer);
end
```

---

## 8. Button / editbox size issue when maximizing the screen

**Original**  
When the screen is enlarged, the horizontal widths of the "Import CFG", "Rst", and "Sync Time" buttons increase.

**Review Result / Response**  
The button columns in `uigridlayout.ColumnWidth` are likely set to `'1x'` or another proportional width. Buttons should use fixed widths, and only a spacer should absorb remaining space.

**Original**  
-> Needs correction.

**Review Result / Response**  
Example correction:

```matlab
grid.ColumnWidth = {80, 60, 90, 80, '1x'};
```

Button columns should be fixed in pixels, and only the final blank/spacer column should be `'1x'`.

**Original**  
When the screen is enlarged, the editbox to the left of the "Sync Time" button also becomes longer.

**Review Result / Response**  
The editbox also needs a maximum or fixed width. Since it is a time-input field, there is no reason for it to become excessively long.

**Original**  
-> Needs correction.

**Review Result / Response**  
A recommended width is approximately 80–120 px.

```matlab
grid.ColumnWidth = {..., 100, 80, '1x'};
```

---

## 9. Initial display after adding a session

**Original**  
When Session1 is added, modify the initial screen so that only "Current Flight Information" and "H: Data View Panel" are visible, and the rest are shown only after pressing buttons.

**Review Result / Response**  
This is a good direction. If too many panels are shown from the beginning, the screen becomes cluttered on a 15-inch laptop or MATLAB Online.

Recommended default layout:

```text
When a session is first created:
- Show Current Flight Information.
- Show H: Data View Panel.
- Collapse Video panel.
- Collapse Map / Manager / Detail / Analyzer.
- Show ROI / Analyzer only when needed through buttons.
```

It is also reasonable to automatically expand the Video panel when a video file is loaded.

---

## 10. Auxiliary figures for Manager / Detail / +ROI / Analyzer

**Original**  
The behavior of the figures that appear when pressing "Manager", "Detail", "+ROI", and "Analyzer" buttons needs improvement.

**Review Result / Response**  
These features currently appear to lack clear behavior definitions and context display. In the long term, integrating them into Studio RightDock tabs or Workspace tabs would be more stable than using independent figures.

**Original**  
Please review the following opinions and improvement plans.

**Review Result / Response**  
Improvement directions for each item are provided below.

**Original**  
-> It should be identifiable whether it corresponds to Flight 1 or Flight 2.

**Review Result / Response**  
This is essential. Every Manager / Detail / ROI / Analyzer UI should display active session and channel context.

Example:

```text
ROI Manager - Session 1 / Flight 1
Plot Detail - Session 2 / Flight 2 / Altitude
Analyzer - Session 1 / Flight 1 / H Panel
```

**Original**  
-> Tab1, Tab2, Tab3, etc. should be distinguishable.

**Review Result / Response**  
Each auxiliary UI should clearly display which workspace tab, plot tab, or data panel it is connected to. Internally, a context object should be used.

```text
SessionId
ChannelIdx
PanelId
TabId
ObjectId
```

**Original**  
    Each figure should also have tabs and should be synchronized with the "H: Data View Panel" tab.

**Review Result / Response**  
Agreed. If possible, these should be converted from independent figures into RightDock or Workspace internal tabs. If independent figures remain, they should refresh automatically when the active tab changes.

**Original**  
-> When pressing the ROI button, the entire plot background becomes orange, and it is unclear what action should be taken next.

**Review Result / Response**  
The ROI mode lacks clear guidance. Instead of changing the entire plot background color, status display and instructions are needed.

Recommended UX:

```text
StatusBar: ROI mode - drag over Data View Panel to select range. Esc to cancel.
Cursor: crosshair
Plot overlay: semi-transparent selection guide
Toolbar ROI button: active state display
```

**Original**  
    -> After this state, dragging the star marker in the "H: Data View Panel" is not smooth.

**Review Result / Response**  
ROI selection mode and marker drag mode appear to be conflicting. The interaction state machine should be separated.

```text
InteractionMode:
- normal
- markerDrag
- roiSelect
- pan
- splitterDrag
```

In ROI mode, marker drag should either be disabled or marker drag should take priority only when hovering over the marker.

**Original**  
-> When pressing a button and then clicking the session GUI, the figure disappears. If the "Manager", "Detail", "+ROI", or "Analyzer" button is pressed again, the corresponding figure should become active in front of the session GUI.

**Review Result / Response**  
Correct. Auxiliary figures should not be recreated repeatedly. If an existing figure is available, it should be brought to the front.

```matlab
if isempty(fig) || ~isvalid(fig)
    fig = uifigure(...);
else
    figure(fig);
end
```

For `uifigure`, focus and visibility behavior can be limited, so `Visible`, `WindowState`, and `drawnow` may need to be used together.

**Original**  
-> Many detailed buttons under "Manager", "Detail", "+ROI", and "Analyzer" do not work. Specific implementation and planning are needed.

**Review Result / Response**  
Unimplemented buttons should be hidden or disabled. If a button appears clickable but does nothing, users will interpret it as a bug.

Policy:

```text
Implemented: enabled
Planned: disabled + tooltip
To be removed: remove from UI
```

**Original**  
    For example, when pressing the "Detail" button, it is unclear which tab’s graph it belongs to, and checking the Show checkbox does not change anything.

**Review Result / Response**  
The Detail panel must be connected to the selected graphics object or active plot tab. The Show checkbox should directly control the target object's `Visible` property.

Example:

```matlab
target.Visible = matlab.lang.OnOffSwitchState(showCheckBox.Value);
```

Or:

```matlab
target.Visible = onOff(showCheckBox.Value);
```

**Original**  
    Please improve it by referring to the component property inspector GUI used when coding with MATLAB App Designer.

**Review Result / Response**  
This is a good reference direction. A structure similar to MATLAB App Designer’s Component Browser, separating object tree and property inspector, is appropriate.

Recommended structure:

```text
Object Manager:
- Session
- Flight 1 / Flight 2
- Data panels
- Plot lines
- ROI objects
- Markers

Property Inspector:
- Selected object name
- Visible
- Color
- LineWidth
- Marker
- Axis binding
```

**Original**  
    https://kr.mathworks.com/help/matlab/creating_guis/app-designer-code-generation.html component browser

**Review Result / Response**  
It would be good to use the Component Browser concept to distinguish the current Studio’s Project Explorer and Object Manager.

```text
Project Explorer:
- Project / session / result centered

Object Manager:
- Current session’s graphics/UI objects centered
```

---

## 11. Add a slider to the flight-data plot

**Original**  
Please add a slider for the plot in the flight-data tab in the same format as the video player. Place it in the blank area where "Real-time current value:" is displayed.

**Review Result / Response**  
This should be implemented. A data plot slider can become the main UX for directly controlling the current data index/time.

Recommended behavior:

```text
DataSlider.ValueChangingFcn:
- Move marker preview.
- Update current-value label.
- Request synced video frame preview.

DataSlider.ValueChangedFcn:
- Confirm final data index.
- Apply plot x-window follow.
- Synchronize video frame.
- Update status bar.
```

The requested position next to the “Real-time current value:” area is appropriate.

---

## 12. Display loaded file names

**Original**  
Please display the loaded flight-data filenames for flight 1 and flight 2 in an appropriate location in the GUI.

**Review Result / Response**  
This should definitely be implemented. In a structure that handles multiple flights, sessions, and videos, users can easily become confused if file names are not displayed.

Recommended display:

```text
Flight 1 Data: xxx.csv
Flight 1 Video: xxx.avi
Flight 2 Data: yyy.csv
Flight 2 Video: yyy.avi
```

For long paths, show only the basename and provide the full path as a tooltip.

```matlab
[~, name, ext] = fileparts(filePath);
label.Text = [name ext];
label.Tooltip = filePath;
```

---

## 13. Readability of panel titles / frame numbers

**Original**  
Panel titles and frame numbers above the video player slider have poor readability because the background and font colors do not harmonize. Please inspect all of them and improve readability.

**Review Result / Response**  
The overall UI theme needs to be organized. If arbitrary RGB values are used across individual components, readability will break depending on screen size or background.

Recommended theme:

```text
Panel header:
- Background: #F3F4F6
- Text: #111827
- FontWeight: bold

Readout label:
- Background: white or transparent
- Text: #1F2937

Active/warning mode:
- Background: #FEF3C7
- Text: #92400E

Video frame label:
- Background: #111827
- Text: #F9FAFB
```

A centralized helper such as `flightdash.ui.Theme` or `flightdash.util.UIColors` should be introduced.

---

## 14. AVI FPS display issue

**Original**  
When opening an AVI file in flight 1, FPS is always 230, and when opening an AVI file in flight 2, FPS is always 830. This needs to be checked.

**Review Result / Response**  
This is highly suspicious. It may not be the actual FPS, but rather a frame count, duration, anchor frame, or incorrect channel-specific value being displayed in the FPS field.

The normal calculation should be:

```matlab
vr = VideoReader(filePath);
fps = vr.FrameRate;
duration = vr.Duration;
totalFrames = floor(duration * fps);
```

Items to check:

```text
1. Whether VideoReader.FrameRate is read directly
2. Whether incorrect values are stored in VideoSyncState(fIdx).VideoFps
3. Whether default FPS values are hardcoded for Flight 1 / Flight 2
4. Whether TotalFrames or AnchorFrame is displayed in the FPS label
5. Whether fallback values are applied incorrectly when metadata reading fails
```

---

## 15. Range button

**Original**  
When pressing the "Range" button, nothing appears.

**Review Result / Response**  
A button that does nothing significantly reduces UX quality.

**Original**  
-> If there is no implementation plan, please delete it.

**Review Result / Response**  
Agreed. There are two options.

```text
A. Implement the feature
- Current plot x-range input dialog
- Zoom to ROI range
- Full range reset

B. Keep it unimplemented
- Disable the button
- Tooltip: Range tool is planned
```

At the current stage, disabling it with a tooltip is the safest option.

---

## 16. Crosshair cursor stuck / operation freeze

**Original**  
After loading flight1 and flight2 data, adjusting panel spacing, and repeatedly pushing/releasing the left mouse button while dragging the star marker in the flight-data display left and right,

**Review Result / Response**  
The interaction state may become inconsistent when panel splitter drag and marker drag are repeatedly mixed. In particular, if an exception occurs during mouse down/up events, `WindowButtonUpFcn` or drag-lock release may be skipped.

**Original**  
At some point, the crosshair mouse cursor does not disappear, and the operation stops.

**Review Result / Response**  
This is an important stability issue. A fail-safe is needed to forcibly restore cursor and drag state in every drag termination path.

Recommended helper:

```matlab
function forceEndAllDrag(app, reason)
    try, app.State = 'IDLE'; catch, end
    try, app.IsDraggingSplitter = false; catch, end
    try, app.IsDraggingPanelSplitter = false; catch, end
    try, app.IsDraggingPanner = false; catch, end

    try
        if ~isempty(app.MouseRouter) && isvalid(app.MouseRouter)
            app.MouseRouter.releaseDragLock();
        end
    catch
    end

    try
        if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
            app.UIFigure.Pointer = 'arrow';
        end
    catch
    end
end
```

This helper should be called from:

```text
- WindowButtonUpFcn
- WindowKeyPressFcn when Esc is pressed
- tab switch
- tab close
- figure close
- catch block of drag motion callback
```

**Original**  
Refer to separate error message.

**Review Result / Response**  
If the corresponding error message is available, additional analysis is needed. In particular, a callback stack trace can identify which drag controller failed to release the state.

---

## 17. Pitch / Roll / Heading circular gauge

**Original**  
The triangular indicator displayed along the circular gauge line for Pitch, Roll, and Heading is too small, so its movement is hard to recognize. The size and color of the triangular indicator need to be made clearer.

**Review Result / Response**  
This should be improved. The triangle indicator size should be calculated dynamically based on the gauge radius.

Recommended calculation:

```matlab
needleSize = max(8, round(radius * 0.08));
```

Colors should have high contrast against the background.

```text
Roll: orange/red
Pitch: blue
Heading: green
```

**Original**  
However, it should change synchronously when the overall GUI size changes.

**Review Result / Response**  
Correct. The gauge indicator should not use only a fixed pixel size. It should be recalculated based on the panel radius during resize.

Recommended structure:

```text
onPanelResize or refreshLayout:
- Recalculate gauge radius.
- Recalculate triangle size.
- Recalculate indicator position.
- Redraw.
```

---

## Overall Priority

### P0: Immediate fixes recommended

```text
1. Compatibility with actual option1.dat / CSV header mapping
2. Unification of standalone FlightDataDashboard and Studio embedded Dashboard UI
3. Stabilization of cleanupHandleProperty syntax and handle-array cleanup
4. Add forceEndAllDrag to prevent mouse drag/cursor lock
```

### P1: Core UX improvements

```text
5. Real-time preview based on video slider ValueChangingFcn
6. Add data plot slider
7. Organize synced data/video frame conversion
8. Verify FPS metadata calculation/display error
```

### P2: Layout / readability

```text
9. Apply fixed width to buttons/editboxes
10. Simplify initial session panel display
11. Display loaded file names
12. Organize panel title/frame label color theme
13. Improve gauge indicator size/color
```

### P3: Tool window / analysis feature refinement

```text
14. Organize Manager/Detail/ROI/Analyzer around RightDock tabs
15. Implement auxiliary figure bring-to-front policy
16. Prevent ROI mode guidance/state-machine conflicts
17. Implement or disable the Range button
```

---

## Final Conclusion

If all automated tests pass, the structural stability has improved significantly. However, the contents of `260513_gui(1).log` show UX and data-compatibility problems that appear during real usage.

The first four items to fix are:

```text
1. Actual option1.dat and CSV header mapping issue
2. UI mismatch between standalone Dashboard and Studio embedded Dashboard
3. Lack of real-time frame preview during video slider drag
4. Mouse drag/cursor stuck issue
```

After stabilizing these four items first, it is safest to proceed with Manager/Detail/ROI/Analyzer cleanup and readability improvements.
