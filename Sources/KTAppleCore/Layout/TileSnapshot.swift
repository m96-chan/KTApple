import CoreGraphics
import Foundation

/// Codable DTO mirroring a Tile tree for JSON persistence.
public struct TileSnapshot: Codable, Sendable, Equatable {
    public let id: UUID
    public let proportion: CGFloat
    public let layoutDirection: LayoutDirection
    public let windowIDs: [UInt32]
    public let children: [TileSnapshot]

    public init(
        id: UUID = UUID(),
        proportion: CGFloat = 1.0,
        layoutDirection: LayoutDirection = .horizontal,
        windowIDs: [UInt32] = [],
        children: [TileSnapshot] = []
    ) {
        self.id = id
        self.proportion = proportion
        self.layoutDirection = layoutDirection
        self.windowIDs = windowIDs
        self.children = children
    }

    /// Create a snapshot from a live Tile tree.
    public init(tile: Tile) {
        self.id = tile.id
        self.proportion = tile.proportion
        self.layoutDirection = tile.layoutDirection
        self.windowIDs = Array(tile.windowIDs).sorted()
        self.children = tile.children.map { TileSnapshot(tile: $0) }
    }

    /// Returns a copy of this snapshot with all windowIDs cleared recursively.
    ///
    /// Used when saving layout profiles — window assignments are ephemeral
    /// and should not be stored as part of a reusable profile.
    public func clearingWindowIDs() -> TileSnapshot {
        TileSnapshot(
            id: id,
            proportion: proportion,
            layoutDirection: layoutDirection,
            windowIDs: [],
            children: children.map { $0.clearingWindowIDs() }
        )
    }

    /// Convert this snapshot back to a live Tile tree.
    public func toTile() -> Tile {
        let tile = Tile(id: id, proportion: proportion, layoutDirection: layoutDirection)
        for windowID in windowIDs {
            tile.addWindow(id: windowID)
        }
        for childSnapshot in children {
            tile.addChild(childSnapshot.toTile())
        }
        return tile
    }
}
