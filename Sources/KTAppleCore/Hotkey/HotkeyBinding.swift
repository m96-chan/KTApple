import Foundation

/// A keyboard shortcut bound to an action.
public struct HotkeyBinding: Sendable {
    public let action: HotkeyAction

    /// Virtual key code (matches macOS kVK_ constants).
    public let keyCode: UInt32

    /// Modifier keys required.
    public let modifiers: KeyModifier

    public init(action: HotkeyAction, keyCode: UInt32, modifiers: KeyModifier) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
