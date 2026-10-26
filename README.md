# ZoomOut

Resets macOS Accessibility Zoom (full-screen) to 1× on every display that is zoomed in. Does nothing when no display is zoomed.

## Download

Every push to `main` publishes a universal (arm64 + x86_64) binary on the [releases page](https://github.com/rickythefox/zoom-out/releases/latest):

```sh
mkdir -p ~/.local/bin
curl -fsSL https://github.com/rickythefox/zoom-out/releases/latest/download/zoom-out-macos-universal.tar.gz | tar -xz -C ~/.local/bin
```

`curl` doesn't add the quarantine flag. If you download with a browser instead, run `xattr -d com.apple.quarantine ~/.local/bin/zoom-out`.

## Build from source

```sh
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/ZoomOut ~/.local/bin/zoom-out
zoom-out   # prints e.g. "display 2: 1.42x -> 1x", or "not zoomed in"
```

Exit codes: 0 means it worked or there was nothing to do; 1 means a display couldn't be listed, read, or reset (details on stderr); 2 means the API is missing. No Accessibility permission is needed.

## Bind to a key with Karabiner-Elements

Add this rule to `profiles[].complex_modifications.rules` in `~/.config/karabiner/karabiner.json`. Karabiner reloads the file automatically. Replace `YOU` with your username, since `shell_command` needs an absolute path.

```json
{
    "description": "scroll_lock : zoom-out (reset Accessibility Zoom)",
    "manipulators": [
        {
            "type": "basic",
            "from": { "key_code": "scroll_lock", "modifiers": { "optional": ["any"] } },
            "to": [{ "shell_command": "/Users/YOU/.local/bin/zoom-out" }]
        }
    ]
}
```

Many Mac keyboards send Scroll Lock as `f14`. Check with Karabiner-EventViewer and change `key_code` if needed.

## Optional: app bundle

`./make-app.sh` builds `build/ZoomOut.app`, a windowless app that zooms out and quits. Use it from launchers that can only open apps: `open build/ZoomOut.app`.

## How it works

No synthetic keyboard or mouse events, and the zoom hotkeys don't need to be enabled. It calls the same private SkyLight functions that the zoom agent (`AXVisualSupportAgent`) uses. These were found by tracing the agent while zooming:

- `SLSGetZoomParametersForDisplay(cid, display, &origin, &scale, &smooth)` reads each display's zoom level.
- `SLSSetZoomParametersForDisplay(cid, display, NULL, smooth, 1, 1.0, 0)` sets scale 1.0 on any display above 1×.

Caveats:

- These are private APIs. The signatures come from the macOS 27 SkyLight code and can change in any macOS release.
- `UAZoomEnabled()` (it reads `SLSIsZoomed`) keeps returning true after this reset. The app therefore checks the per-display scale instead.
- `UAZoomSetScale` from UniversalAccess.framework does not work here. It only writes the `closeViewZoomFactor` preference and the agent does not apply it.
