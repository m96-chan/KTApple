import Foundation

/// Protocol abstracting display enumeration and reconfiguration observation.
///
/// On macOS, the concrete implementation uses CGDisplay APIs.
/// In tests, a mock implementation is used.
public protocol DisplayProvider {
    func connectedDisplays() -> [DisplayInfo]
    func startObserving(callback: @escaping () -> Void)
    func stopObserving()
}
