import Foundation

/// Protocol abstracting window lifecycle event monitoring.
///
/// On macOS, the concrete implementation polls for window changes.
/// In tests, a mock implementation is used.
public protocol WindowLifecycleProvider {
    /// Start monitoring. Callbacks fire on the main thread.
    func startMonitoring(
        onWindowCreated: @escaping (WindowInfo) -> Void,
        onWindowDestroyed: @escaping (UInt32) -> Void
    )
    /// Stop monitoring.
    func stopMonitoring()
}
