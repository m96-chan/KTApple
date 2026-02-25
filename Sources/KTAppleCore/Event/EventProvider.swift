import Foundation

/// Protocol abstracting mouse event monitoring for testability.
public protocol EventProvider: AnyObject {
    func startMonitoring(handler: @escaping (MouseEvent) -> Void)
    func stopMonitoring()
}
