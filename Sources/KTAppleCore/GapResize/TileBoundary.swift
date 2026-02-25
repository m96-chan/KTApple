import CoreGraphics
import Foundation

/// Represents a boundary between two adjacent tiles that can be dragged to resize.
public struct TileBoundary: Sendable {
    /// The tile on the leading side (left or top).
    public let leadingTileID: UUID

    /// The tile on the trailing side (right or bottom).
    public let trailingTileID: UUID

    /// The axis along which the boundary runs.
    public let axis: LayoutDirection

    /// The position of the boundary line (x for horizontal split, y for vertical split).
    public let position: CGFloat

    /// The full rect of the boundary for hit-testing.
    public let rect: CGRect

    public init(
        leadingTileID: UUID,
        trailingTileID: UUID,
        axis: LayoutDirection,
        position: CGFloat,
        rect: CGRect
    ) {
        self.leadingTileID = leadingTileID
        self.trailingTileID = trailingTileID
        self.axis = axis
        self.position = position
        self.rect = rect
    }
}
