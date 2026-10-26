// Toggles macOS Accessibility Zoom (full-screen).
//
// If any display is zoomed in: remember each zoomed display's scale, then reset all to 1x.
// If nothing is zoomed: restore the remembered scales, centred on the mouse pointer.
// With nothing remembered yet, zooms the display under the pointer to the Zoom
// preference's level (closeViewDesiredZoomFactor).
//
// Uses the private SkyLight calls the Accessibility zoom agent (AXVisualSupportAgent)
// itself uses, so no synthetic keyboard/mouse events and no zoom hotkeys are needed.
// Signatures were recovered from the macOS 27 SkyLight disassembly and a live trace
// of AXVisualSupportAgent; they are private and may change between macOS releases.

import CoreGraphics
import Foundation

private typealias MainConnectionID = @convention(c) () -> Int32
/// (connection, display, centre out, scale out, smoothImages out) -> CGError
private typealias GetZoomParameters = @convention(c) (
    Int32, CGDirectDisplayID, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Bool>
) -> Int32
/// (connection, display, centre or nil, smoothImages, flag, scale, velocity) -> CGError
private typealias SetZoomParameters = @convention(c) (
    Int32, CGDirectDisplayID, UnsafePointer<CGPoint>?, Int32, Int32, Double, Double
) -> Int32

/// The zoom centre is the middle of the visible region, in global display coordinates.
private struct Zoom {
    var scale: Double
    var centre: CGPoint
    var smooth: Bool
}

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

    func zoom(of display: CGDirectDisplayID) throws -> Zoom {
        var centre = CGPoint.zero
        var scale = 0.0
        var smooth = false
        let error = getParameters(connection, display, &centre, &scale, &smooth)
        guard error == 0 else { throw ZoomError("display \(display): SLSGetZoomParametersForDisplay failed (CGError \(error))") }
        return Zoom(scale: scale, centre: centre, smooth: smooth)
    }

    func set(_ zoom: Zoom, on display: CGDirectDisplayID) throws {
        var centre = zoom.centre
        // flag = 1 and velocity = 0 match what AXVisualSupportAgent passes.
        let error = setParameters(connection, display, &centre, zoom.smooth ? 1 : 0, 1, zoom.scale, 0)
        guard error == 0 else { throw ZoomError("display \(display): SLSSetZoomParametersForDisplay failed (CGError \(error))") }
    }
}

private struct ZoomError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Scales saved at the last zoom-out, keyed by display ID.
private enum SavedScales {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/zoom-out/scales.json")

    static func load() -> [CGDirectDisplayID: Double] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, scale in
            CGDirectDisplayID(key).map { ($0, scale) }
        })
    }

    static func save(_ scales: [CGDirectDisplayID: Double]) throws {
        let raw = Dictionary(uniqueKeysWithValues: scales.map { (String($0.key), $0.value) })
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(raw).write(to: url, options: .atomic)
    }
}

private func onlineDisplays() throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { throw ZoomError("could not enumerate displays") }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success, count > 0 else { throw ZoomError("could not enumerate displays") }
    return Array(ids.prefix(Int(count)))
}

/// Zoom level from System Settings > Accessibility > Zoom, used when nothing was saved.
private func preferredScale() -> Double {
    let value = CFPreferencesCopyAppValue("closeViewDesiredZoomFactor" as CFString, "com.apple.universalaccess" as CFString)
    let scale = (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 2.0
    return scale > 1.0 ? scale : 2.0
}

/// Centre the zoomed region on `point`, shifted only as far as needed to keep it on `bounds`.
private func centre(on point: CGPoint, in bounds: CGRect, scale: Double) -> CGPoint {
    let halfWidth = bounds.width / scale / 2
    let halfHeight = bounds.height / scale / 2
    return CGPoint(
        x: min(max(point.x, bounds.minX + halfWidth), bounds.maxX - halfWidth),
        y: min(max(point.y, bounds.minY + halfHeight), bounds.maxY - halfHeight)
    )
}

private func zoomOut(_ zoomed: [(CGDirectDisplayID, Zoom)], with skyLight: SkyLightZoom) throws {
    try SavedScales.save(Dictionary(uniqueKeysWithValues: zoomed.map { ($0.0, $0.1.scale) }))
    for (display, zoom) in zoomed {
        var reset = zoom
        reset.scale = 1.0
        reset.centre = CGPoint(x: CGDisplayBounds(display).midX, y: CGDisplayBounds(display).midY)
        try skyLight.set(reset, on: display)
        print("display \(display): \(zoom.scale)x -> 1x")
    }
}

private func zoomIn(_ current: [(CGDirectDisplayID, Zoom)], with skyLight: SkyLightZoom) throws {
    let mouse = CGEvent(source: nil)?.location ?? .zero
    var targets = SavedScales.load().filter { saved in current.contains { $0.0 == saved.key } }
    if targets.isEmpty, let underMouse = current.first(where: { CGDisplayBounds($0.0).contains(mouse) }) {
        targets = [underMouse.0: preferredScale()]
    }
    guard !targets.isEmpty else { throw ZoomError("no display to zoom in on") }

    for (display, zoom) in current {
        guard let scale = targets[display] else { continue }
        let bounds = CGDisplayBounds(display)
        let focus = bounds.contains(mouse) ? mouse : CGPoint(x: bounds.midX, y: bounds.midY)
        try skyLight.set(Zoom(scale: scale, centre: centre(on: focus, in: bounds, scale: scale), smooth: zoom.smooth), on: display)
        print("display \(display): 1x -> \(scale)x")
    }
}

guard let skyLight = SkyLightZoom() else {
    fputs("zoom-out: SkyLight zoom API not found on this macOS version\n", stderr)
    exit(2)
}

do {
    let current = try onlineDisplays().map { ($0, try skyLight.zoom(of: $0)) }
    let zoomed = current.filter { $0.1.scale > 1.0 }
    if zoomed.isEmpty {
        try zoomIn(current, with: skyLight)
    } else {
        try zoomOut(zoomed, with: skyLight)
    }
} catch {
    fputs("zoom-out: \(error)\n", stderr)
    exit(1)
}
