import CoreGraphics
import Foundation

/// A node in the tile tree representing a region of the screen.
///
/// Leaf tiles can hold windows. Non-leaf tiles define how their children
/// are arranged (horizontally or vertically).
public final class Tile: Identifiable {
    public let id: UUID

    /// Fraction of parent's space this tile occupies along the split axis (0.0–1.0).
    public var proportion: CGFloat

    /// How child tiles are arranged. Only meaningful for non-leaf tiles.
    public var layoutDirection: LayoutDirection

    /// Parent tile. `nil` for the root tile.
    public weak var parent: Tile?

    /// Child tiles. Empty for leaf tiles.
    public private(set) var children: [Tile]

    /// Window IDs assigned to this tile (only meaningful for leaf tiles).
    public private(set) var windowIDs: Set<UInt32>

    /// Whether this tile is a leaf (has no children and can hold windows).
    public var isLeaf: Bool { children.isEmpty }

    /// Depth of this tile in the tree (root = 0).
    public var depth: Int {
        var d = 0
        var current = parent
        while let p = current {
            d += 1
            current = p.parent
        }
        return d
    }

    /// Index of this tile among its parent's children. `nil` if no parent.
    public var siblingIndex: Int? {
        parent?.children.firstIndex(where: { $0 === self })
    }

    /// The previous sibling in the parent's children array.
    public var previousSibling: Tile? {
        guard let index = siblingIndex, index > 0 else { return nil }
        return parent?.children[index - 1]
    }

    /// The next sibling in the parent's children array.
    public var nextSibling: Tile? {
        guard let parent, let index = siblingIndex, index < parent.children.count - 1 else { return nil }
        return parent.children[index + 1]
    }

    public init(
        id: UUID = UUID(),
        proportion: CGFloat = 1.0,
        layoutDirection: LayoutDirection = .horizontal
    ) {
        self.id = id
        self.proportion = proportion
        self.layoutDirection = layoutDirection
        self.children = []
        self.windowIDs = []
    }

    // MARK: - Child Management

    public func addChild(_ child: Tile) {
        child.parent = self
        children.append(child)
    }

    public func insertChild(_ child: Tile, at index: Int) {
        child.parent = self
        children.insert(child, at: index)
    }

    public func removeChild(_ child: Tile) {
        child.parent = nil
        children.removeAll(where: { $0 === child })
    }

    public func removeChild(at index: Int) {
        let child = children[index]
        child.parent = nil
        children.remove(at: index)
    }

    // MARK: - Window Management

    public func addWindow(id: UInt32) {
        windowIDs.insert(id)
    }

    public func removeWindow(id: UInt32) {
        windowIDs.remove(id)
    }

    // MARK: - Traversal

    /// All descendant tiles (not including self).
    public func descendants() -> [Tile] {
        var result: [Tile] = []
        for child in children {
            result.append(child)
            result.append(contentsOf: child.descendants())
        }
        return result
    }

    /// All leaf tiles in this subtree (including self if leaf).
    public func leafTiles() -> [Tile] {
        if isLeaf { return [self] }
        return children.flatMap { $0.leafTiles() }
    }
}
