import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import KTAppleCore

/// Live implementation of EventProvider using NSEvent global monitors.
///
/// Monitors left mouse down/drag/up events system-wide and converts
/// them to MouseEvent values in Quartz screen coordinates (origin top-left).
final class LiveEventProvider: EventProvider {
    private var monitors: [Any] = []

    func startMonitoring(handler: @escaping (MouseEvent) -> Void) {
        stopMonitoring()

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { nsEvent in
            let location = Self.quartzMouseLocation()
            let windowID = Self.windowAtPoint(location)
            let modifiers = Self.convertModifiers(nsEvent.modifierFlags)
            handler(MouseEvent(location: location, phase: .began, modifiers: modifiers, windowID: windowID))
        }) {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { nsEvent in
            let location = Self.quartzMouseLocation()
            let modifiers = Self.convertModifiers(nsEvent.modifierFlags)
            handler(MouseEvent(location: location, phase: .changed, modifiers: modifiers))
        }) {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { nsEvent in
            let location = Self.quartzMouseLocation()
            let modifiers = Self.convertModifiers(nsEvent.modifierFlags)
            handler(MouseEvent(location: location, phase: .ended, modifiers: modifiers))
        }) {
            monitors.append(monitor)
        }
    }

    func stopMonitoring() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }

    // MARK: - Private

    /// Convert Cocoa mouse location (bottom-left origin) to Quartz coordinates (top-left origin).
    private static func quartzMouseLocation() -> CGPoint {
        let cocoaLocation = NSEvent.mouseLocation
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: cocoaLocation.x, y: primaryHeight - cocoaLocation.y)
    }

    /// Find the topmost window at a Quartz screen point using the Accessibility API.
    ///
    /// Uses AXUIElementCopyElementAtPosition which correctly resolves the
    /// frontmost element regardless of CGWindowList z-order timing.
    private static func windowAtPoint(_ point: CGPoint) -> UInt32? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &element
        ) == .success, let element else {
            return windowAtPointFallback(point)
        }

        // Walk up the hierarchy to find the window element
        var current: AXUIElement = element
        for _ in 0..<10 {  // guard against infinite loops
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
               let roleStr = role as? String, roleStr == (kAXWindowRole as String) {
                var pid: pid_t = 0
                AXUIElementGetPid(current, &pid)
                if pid == ProcessInfo.processInfo.processIdentifier { return nil }

                var windowID: CGWindowID = 0
                if _AXUIElementGetWindow(current, &windowID) == .success {
                    return windowID
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parentEl = parent else { break }
            current = (parentEl as! AXUIElement)
        }

        return windowAtPointFallback(point)
    }

    /// Fallback: scan CGWindowList (used when Accessibility API fails).
    private static func windowAtPointFallback(_ point: CGPoint) -> UInt32? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for dict in windowList {
            guard let windowID = dict[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }

            if let pid = dict[kCGWindowOwnerPID as String] as? Int32, pid == ownPID {
                continue
            }

            let bounds = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )

            if bounds.contains(point) {
                return windowID
            }
        }

        return nil
    }

    private static func convertModifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifier {
        var modifiers: KeyModifier = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
