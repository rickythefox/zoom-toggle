# zoom-out

Toggles macOS Accessibility Zoom (full-screen):

- **Zoomed in** on any display: saves each zoomed display's level to `~/.local/state/zoom-out/scales.json`, then resets every display to 1×.
- **Not zoomed**: restores the saved levels, centred on the mouse pointer. The view stays on the screen, so near an edge it shifts only as far as needed. With nothing saved yet, it zooms the display under the pointer to the level set in System Settings > Accessibility > Zoom.

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
zoom-out   # prints e.g. "display 2: 1.42x -> 1x", or "display 2: 1x -> 1.42x"
```

Exit codes: 0 means it worked; 1 means a display couldn't be listed, read, or changed, or the state file couldn't be written (details on stderr); 2 means the API is missing. No Accessibility permission is needed.

## Bind to a key with Karabiner-Elements

Add this rule to `profiles[].complex_modifications.rules` in `~/.config/karabiner/karabiner.json`. Karabiner reloads the file automatically. Replace `YOU` with your username, since `shell_command` needs an absolute path.

```json
{
    "description": "scroll_lock : zoom-out (toggle Accessibility Zoom)",
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

`./make-app.sh` builds `build/ZoomOut.app`, a windowless app that toggles zoom and quits. Use it from launchers that can only open apps: `open build/ZoomOut.app`.

## How it works

No synthetic keyboard or mouse events, and the zoom hotkeys don't need to be enabled. It calls the same private SkyLight functions that the zoom agent (`AXVisualSupportAgent`) uses. These were found by tracing the agent while zooming:

- `SLSGetZoomParametersForDisplay(cid, display, &centre, &scale, &smooth)` reads each display's zoom level. `centre` is the middle of the visible region in global display coordinates.
- `SLSSetZoomParametersForDisplay(cid, display, &centre, smooth, 1, scale, 0)` sets it: scale 1.0 at the display centre to zoom out, or the saved scale at the pointer to zoom in.

The zoom agent stays in sync both ways. After a toggle, Ctrl+scroll (or whatever zoom gesture you use) continues from the current level and doesn't jump.

Caveats:

- These are private APIs. The signatures come from the macOS 27 SkyLight code and can change in any macOS release.
- `UAZoomEnabled()` (it reads `SLSIsZoomed`) keeps returning true after a zoom-out. The app therefore checks each display's scale instead.
- `UAZoomSetScale` from UniversalAccess.framework does not work here. It only writes the `closeViewZoomFactor` preference and the agent does not apply it.
