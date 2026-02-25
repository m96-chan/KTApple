import CoreGraphics
import Foundation

/// Phase of a mouse interaction.
public enum MousePhase: Sendable {
    case began
    case changed
    case ended
    case moved
}

/// A mouse event with location, phase, and modifier state.
public struct MouseEvent: Sendable {
    public let location: CGPoint
    public let phase: MousePhase
    public let modifiers: KeyModifier
    public let windowID: UInt32?

    public init(
        location: CGPoint,
        phase: MousePhase,
        modifiers: KeyModifier = [],
        windowID: UInt32? = nil
    ) {
        self.location = location
        self.phase = phase
        self.modifiers = modifiers
        self.windowID = windowID
    }
}
