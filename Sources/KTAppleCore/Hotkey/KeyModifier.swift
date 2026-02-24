import Foundation

/// Modifier keys for hotkey bindings.
public struct KeyModifier: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = KeyModifier(rawValue: 1 << 0)
    public static let option  = KeyModifier(rawValue: 1 << 1)
    public static let shift   = KeyModifier(rawValue: 1 << 2)
    public static let command = KeyModifier(rawValue: 1 << 3)
}
