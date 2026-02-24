import Foundation

/// Delegate for display configuration change events.
public protocol DisplayObserverDelegate: AnyObject {
    func displayDidConnect(_ display: DisplayInfo)
    func displayDidDisconnect(displayID: UInt32)
    func displayDidResize(_ display: DisplayInfo)
}
