import Foundation

/// Protocol abstracting macOS Spaces (virtual desktops) enumeration and observation.
///
/// On macOS, the concrete implementation uses CGS private API and NSWorkspace notifications.
/// In tests, a mock implementation is used.
public protocol SpaceProvider {
    /// Active space ID for a display (session-unique integer from CGS).
    func activeSpaceID(for displayID: UInt32) -> Int

    /// Ordered list of space IDs for a display.
    func spaceIDs(for displayID: UInt32) -> [Int]

    /// Start observing space changes.
    func startObserving(callback: @escaping () -> Void)

    /// Stop observing space changes.
    func stopObserving()
}
