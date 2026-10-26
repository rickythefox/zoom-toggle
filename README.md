# ZoomOut

Resets macOS Accessibility Zoom (full-screen) to 1× on every display that is zoomed in. Does nothing when no display is zoomed.

## Build

```sh
./make-app.sh            # -> build/ZoomOut.app (windowless, quits immediately)
open build/ZoomOut.app   # or bind it to a hotkey via Shortcuts/Raycast
```

The bare binary `.build/release/ZoomOut` works too and prints what it did. Exit codes: 0 means it worked or there was nothing to do; 1 means a display couldn't be listed, read, or reset (details on stderr); 2 means the API is missing.

## How it works

No synthetic keyboard or mouse events, and the zoom hotkeys don't need to be enabled. It calls the same private SkyLight functions that the zoom agent (`AXVisualSupportAgent`) uses. These were found by tracing the agent while zooming:

- `SLSGetZoomParametersForDisplay(cid, display, &origin, &scale, &smooth)` reads each display's zoom level.
- `SLSSetZoomParametersForDisplay(cid, display, NULL, smooth, 1, 1.0, 0)` sets scale 1.0 on any display above 1×.

Caveats:

- These are private APIs. The signatures come from the macOS 27 SkyLight code and can change in any macOS release.
- `UAZoomEnabled()` (it reads `SLSIsZoomed`) keeps returning true after this reset. The app therefore checks the per-display scale instead.
- `UAZoomSetScale` from UniversalAccess.framework does not work here. It only writes the `closeViewZoomFactor` preference and the agent does not apply it.
