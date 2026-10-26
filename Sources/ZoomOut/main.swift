// Resets macOS Accessibility Zoom (full-screen) to 1x on every display that is zoomed in.
//
// Uses the private SkyLight calls the Accessibility zoom agent (AXVisualSupportAgent)
// itself uses, so no synthetic keyboard/mouse events and no zoom hotkeys are needed.
// Signatures were recovered from the macOS 27 SkyLight disassembly and a live trace
// of AXVisualSupportAgent; they are private and may change between macOS releases.

import CoreGraphics
import Darwin

private typealias MainConnectionID = @convention(c) () -> Int32
/// (connection, display, origin out, scale out, smoothImages out) -> CGError
private typealias GetZoomParameters = @convention(c) (
    Int32, CGDirectDisplayID, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Bool>
) -> Int32
/// (connection, display, origin or nil, smoothImages, flag, scale, velocity) -> CGError
private typealias SetZoomParameters = @convention(c) (
    Int32, CGDirectDisplayID, UnsafePointer<CGPoint>?, Int32, Int32, Double, Double
) -> Int32

private struct SkyLightZoom {
    let connection: Int32
    let getParameters: GetZoomParameters
    let setParameters: SetZoomParameters

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let get = dlsym(handle, "SLSGetZoomParametersForDisplay"),
              let set = dlsym(handle, "SLSSetZoomParametersForDisplay")
        else { return nil }
        connection = unsafeBitCast(main, to: MainConnectionID.self)()
        getParameters = unsafeBitCast(get, to: GetZoomParameters.self)
        setParameters = unsafeBitCast(set, to: SetZoomParameters.self)
    }

    /// Current zoom scale and smoothing for a display, plus the CGError (0 = success).
    func zoom(of display: CGDirectDisplayID) -> (error: Int32, scale: Double, smooth: Bool) {
        var origin = CGPoint.zero
        var scale = 0.0
        var smooth = false
        let error = getParameters(connection, display, &origin, &scale, &smooth)
        return (error, scale, smooth)
    }

    /// Sets the display back to 1x, keeping its image-smoothing setting. Returns the CGError.
    func resetScale(of display: CGDirectDisplayID, smooth: Bool) -> Int32 {
        // flag = 1 and velocity = 0 match what AXVisualSupportAgent passes.
        setParameters(connection, display, nil, smooth ? 1 : 0, 1, 1.0, 0)
    }
}

/// Online displays, or nil if CoreGraphics cannot enumerate any.
private func onlineDisplays() -> [CGDirectDisplayID]? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success, count > 0 else { return nil }
    return Array(ids.prefix(Int(count)))
}

guard let skyLight = SkyLightZoom() else {
    fputs("zoom-out: SkyLight zoom API not found on this macOS version\n", stderr)
    exit(2)
}

guard let displays = onlineDisplays() else {
    fputs("zoom-out: could not enumerate displays\n", stderr)
    exit(1)
}

var zoomedOut = 0
var failed = false
for display in displays {
    let zoom = skyLight.zoom(of: display)
    guard zoom.error == 0 else {
        fputs("zoom-out: display \(display): SLSGetZoomParametersForDisplay failed (CGError \(zoom.error))\n", stderr)
        failed = true
        continue
    }
    guard zoom.scale > 1.0 else { continue }
    let error = skyLight.resetScale(of: display, smooth: zoom.smooth)
    if error == 0 {
        print("display \(display): \(zoom.scale)x -> 1x")
        zoomedOut += 1
    } else {
        fputs("zoom-out: display \(display): SLSSetZoomParametersForDisplay failed (CGError \(error))\n", stderr)
        failed = true
    }
}
if zoomedOut == 0 && !failed { print("not zoomed in") }
exit(failed ? 1 : 0)
