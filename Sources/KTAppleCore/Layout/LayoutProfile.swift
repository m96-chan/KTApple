import CoreGraphics
import Foundation

/// A named snapshot of tile layouts for all connected displays.
///
/// Window IDs are intentionally omitted — window assignments are ephemeral
/// and should not be captured as part of a reusable layout profile.
public struct LayoutProfile: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String

    /// Tile tree snapshots keyed by display ID (e.g. "1", "69734849").
    /// Window IDs are always empty in stored snapshots.
    public var displaySnapshots: [String: TileSnapshot]

    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        displaySnapshots: [String: TileSnapshot] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displaySnapshots = displaySnapshots
        self.createdAt = createdAt
    }
}
