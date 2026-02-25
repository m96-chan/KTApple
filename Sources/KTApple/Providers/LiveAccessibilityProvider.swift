@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import KTAppleCore

// Private API used by all major macOS tiling WMs (yabai, AeroSpace, Amethyst)
// to map between AXUIElement and CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

final class LiveAccessibilityProvider: AccessibilityProvider {

    func discoverWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { dict in
            guard let windowID = dict[kCGWindowNumber as String] as? UInt32,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                return nil
            }

            let frame = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )

            let title = dict[kCGWindowName as String] as? String ?? ""

            let app = AXUIElementCreateApplication(pid)
            let attrs = axWindowAttributes(app: app, targetWindowID: windowID)

            return WindowInfo(
                id: windowID,
                pid: pid,
                title: title,
                frame: frame,
                isResizable: attrs.isResizable,
                isMinimized: attrs.isMinimized,
                isFullscreen: attrs.isFullscreen,
                subrole: attrs.subrole
            )
        }
    }

    func moveWindow(id: UInt32, to position: CGPoint) {
        guard let element = axElement(for: id) else { return }
        var pos = position
        guard let value = AXValueCreate(.cgPoint, &pos) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func resizeWindow(id: UInt32, to size: CGSize) {
        guard let element = axElement(for: id) else { return }
        var sz = size
        guard let value = AXValueCreate(.cgSize, &sz) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    func focusWindow(id: UInt32) {
        guard let element = axElement(for: id) else { return }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        // Also raise the owning application
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let dict = windowList.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }),
              let pid = dict[kCGWindowOwnerPID as String] as? Int32 else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    func windowFrame(id: UInt32) -> CGRect? {
        guard let element = axElement(for: id) else { return nil }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    // MARK: - Private

    /// Find the AXUIElement for a given CGWindowID.
    private func axElement(for windowID: CGWindowID) -> AXUIElement? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        guard let dict = windowList.first(where: {
            ($0[kCGWindowNumber as String] as? UInt32) == windowID
        }),
              let pid = dict[kCGWindowOwnerPID as String] as? Int32 else {
            return nil
        }

        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(window, &wid) == .success, wid == windowID {
                return window
            }
        }

        return nil
    }

    private struct WindowAttributes {
        var isResizable: Bool = true
        var isMinimized: Bool = false
        var isFullscreen: Bool = false
        var subrole: WindowSubrole = .unknown
    }

    private func axWindowAttributes(app: AXUIElement, targetWindowID: UInt32) -> WindowAttributes {
        var attrs = WindowAttributes()

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return attrs
        }

        for window in windows {
            var wid: CGWindowID = 0
            guard _AXUIElementGetWindow(window, &wid) == .success,
                  wid == targetWindowID else {
                continue
            }

            // Subrole
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subroleStr = subroleRef as? String {
                attrs.subrole = WindowSubrole(rawValue: subroleStr) ?? .unknown
            }

            // Resizable
            var isSettable: DarwinBoolean = true
            if AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &isSettable) == .success {
                attrs.isResizable = isSettable.boolValue
            }

            // Minimized
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success {
                attrs.isMinimized = (minimizedRef as? Bool) ?? false
            }

            // Fullscreen
            var fullscreenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenRef) == .success {
                attrs.isFullscreen = (fullscreenRef as? Bool) ?? false
            }

            break
        }

        return attrs
    }
}
