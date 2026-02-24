import Foundation

/// Protocol abstracting the system hotkey registration mechanism.
///
/// On macOS, the concrete implementation uses Carbon HIToolbox.
/// In tests, a mock implementation is used.
public protocol HotkeyProvider {
    func register(_ binding: HotkeyBinding)
    func unregister(action: HotkeyAction)
}
