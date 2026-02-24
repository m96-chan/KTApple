import Foundation

/// Snapshot of a display's properties.
public struct DisplayInfo: Sendable {
    /// Display identifier (maps to CGDirectDisplayID on macOS).
    public let id: UInt32

    /// Screen frame in global coordinate space.
    public let frame: CGRect

    /// Human-readable display name.
    public let name: String

    public init(id: UInt32, frame: CGRect, name: String) {
        self.id = id
        self.frame = frame
        self.name = name
    }
}
