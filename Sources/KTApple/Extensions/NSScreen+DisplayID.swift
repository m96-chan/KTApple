import AppKit
import CoreGraphics

extension NSScreen {
    /// The CGDirectDisplayID for this screen, if available.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Find the NSScreen for a given CGDirectDisplayID.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }
}
