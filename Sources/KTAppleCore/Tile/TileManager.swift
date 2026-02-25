import CoreGraphics
import Foundation

/// Manages a tile tree for a single display.
///
/// Handles splitting, removing, resizing tiles, and computing
/// absolute screen-space frames from the relative tile tree.
public final class TileManager {
    /// Minimum proportion a tile can have (prevents zero-size tiles).
    public static let minProportion: CGFloat = 0.05

    /// Display identifier this manager is responsible for.
    public let displayID: UInt32

    /// Screen frame in pixels.
    public var screenFrame: CGRect

    /// Gap size in pixels between tiles and screen edges.
    public var gap: CGFloat

    /// Root tile covering the entire screen.
    public private(set) var root: Tile

    /// Replace the root tile with a new tile tree.
    public func replaceRoot(_ newRoot: Tile) {
        root = newRoot
    }

    public init(displayID: UInt32, screenFrame: CGRect, gap: CGFloat = 8) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.gap = gap
        self.root = Tile(proportion: 1.0, layoutDirection: .horizontal)
    }

    // MARK: - Frame Calculation

    /// Compute the absolute pixel frame for a tile.
    public func frame(for tile: Tile) -> CGRect {
        let rawFrame = rawFrame(for: tile)
        return applyGaps(to: rawFrame, tile: tile)
    }

    /// Compute the raw frame without gap adjustments.
    private func rawFrame(for tile: Tile) -> CGRect {
        if tile === root { return screenFrame }

        guard let parent = tile.parent, let index = tile.siblingIndex else {
            return screenFrame
        }

        let parentFrame = rawFrame(for: parent)
        let siblings = parent.children
        let offsetProportion = siblings[..<index].reduce(CGFloat(0)) { $0 + $1.proportion }

        switch parent.layoutDirection {
        case .horizontal:
            return CGRect(
                x: parentFrame.minX + offsetProportion * parentFrame.width,
                y: parentFrame.minY,
                width: tile.proportion * parentFrame.width,
                height: parentFrame.height
            )
        case .vertical:
            return CGRect(
                x: parentFrame.minX,
                y: parentFrame.minY + offsetProportion * parentFrame.height,
                width: parentFrame.width,
                height: tile.proportion * parentFrame.height
            )
        }
    }

    /// Apply gap insets to a raw frame.
    private func applyGaps(to rawFrame: CGRect, tile: Tile) -> CGRect {
        guard gap > 0 else { return rawFrame }

        let halfGap = gap / 2.0

        // Determine edges: outer edges get full gap, inner edges get half gap
        let isLeftEdge = abs(rawFrame.minX - screenFrame.minX) < 1
        let isRightEdge = abs(rawFrame.maxX - screenFrame.maxX) < 1
        let isTopEdge = abs(rawFrame.minY - screenFrame.minY) < 1
        let isBottomEdge = abs(rawFrame.maxY - screenFrame.maxY) < 1

        let leftInset = isLeftEdge ? gap : halfGap
        let rightInset = isRightEdge ? gap : halfGap
        let topInset = isTopEdge ? gap : halfGap
        let bottomInset = isBottomEdge ? gap : halfGap

        return CGRect(
            x: rawFrame.minX + leftInset,
            y: rawFrame.minY + topInset,
            width: rawFrame.width - leftInset - rightInset,
            height: rawFrame.height - topInset - bottomInset
        )
    }

    // MARK: - Split

    /// Split a leaf tile into two children.
    ///
    /// - Parameters:
    ///   - tile: The leaf tile to split.
    ///   - direction: How to arrange the two new children.
    ///   - ratio: Proportion of the first child (0.0–1.0).
    /// - Returns: The two new child tiles (first, second).
    @discardableResult
    public func split(
        _ tile: Tile,
        direction: LayoutDirection,
        ratio: CGFloat = 0.5
    ) -> (Tile, Tile) {
        let clampedRatio = max(Self.minProportion, min(1.0 - Self.minProportion, ratio))

        tile.layoutDirection = direction

        let first = Tile(proportion: clampedRatio)
        let second = Tile(proportion: 1.0 - clampedRatio)

        // Move windows from split tile to first child
        for windowID in tile.windowIDs {
            first.addWindow(id: windowID)
        }
        tile.windowIDs.forEach { tile.removeWindow(id: $0) }

        tile.addChild(first)
        tile.addChild(second)

        return (first, second)
    }

    // MARK: - Remove

    /// Remove a tile. Its sibling absorbs the freed space.
    /// If removal leaves the parent with a single child, the parent collapses.
    public func remove(_ tile: Tile) {
        guard let parent = tile.parent else { return }  // Can't remove root

        parent.removeChild(tile)

        if parent.children.count == 1 {
            // Collapse: promote the single remaining child
            let remaining = parent.children[0]

            if parent === root {
                // Remaining child becomes the new effective root content
                // Transfer remaining's children and properties to root
                if remaining.isLeaf {
                    parent.removeChild(remaining)
                    for windowID in remaining.windowIDs {
                        parent.addWindow(id: windowID)
                    }
                } else {
                    let grandchildren = remaining.children
                    parent.layoutDirection = remaining.layoutDirection
                    parent.removeChild(remaining)
                    for gc in grandchildren {
                        parent.addChild(gc)
                    }
                }
            } else {
                // Replace parent with remaining in grandparent
                if let grandparent = parent.parent, let parentIndex = parent.siblingIndex {
                    remaining.proportion = parent.proportion
                    grandparent.removeChild(at: parentIndex)
                    grandparent.insertChild(remaining, at: parentIndex)
                }
            }
        } else {
            // Redistribute space among remaining siblings
            let freed = tile.proportion
            let totalRemaining = parent.children.reduce(CGFloat(0)) { $0 + $1.proportion }
            if totalRemaining > 0 {
                for sibling in parent.children {
                    sibling.proportion += freed * (sibling.proportion / totalRemaining)
                }
            }
        }
    }

    // MARK: - Resize

    /// Resize a tile by changing its proportion. Siblings are adjusted to compensate.
    public func resize(_ tile: Tile, newProportion: CGFloat) {
        guard let parent = tile.parent, let index = tile.siblingIndex else { return }

        let siblings = parent.children
        let siblingCount = siblings.count
        guard siblingCount >= 2 else { return }

        let maxProportion = 1.0 - CGFloat(siblingCount - 1) * Self.minProportion
        let clamped = max(Self.minProportion, min(maxProportion, newProportion))
        let delta = clamped - tile.proportion

        // Distribute delta among other siblings proportionally
        let otherTotal = siblings.enumerated()
            .filter { $0.offset != index }
            .reduce(CGFloat(0)) { $0 + $1.element.proportion }

        guard otherTotal > 0 else { return }

        tile.proportion = clamped
        for (i, sibling) in siblings.enumerated() where i != index {
            let share = sibling.proportion / otherTotal
            sibling.proportion = max(Self.minProportion, sibling.proportion - delta * share)
        }

        // Normalize to ensure proportions sum to 1.0
        normalizeSiblings(parent.children)
    }

    /// Ensure siblings' proportions sum to 1.0.
    private func normalizeSiblings(_ siblings: [Tile]) {
        let total = siblings.reduce(CGFloat(0)) { $0 + $1.proportion }
        guard total > 0, abs(total - 1.0) > 0.001 else { return }
        for tile in siblings {
            tile.proportion /= total
        }
    }

    // MARK: - Lookup

    /// Find the leaf tile at a screen-space point.
    public func tileAt(point: CGPoint) -> Tile? {
        guard screenFrame.contains(point) else { return nil }
        return tileAt(point: point, in: root)
    }

    private func tileAt(point: CGPoint, in tile: Tile) -> Tile? {
        let tileFrame = rawFrame(for: tile)
        guard tileFrame.contains(point) else { return nil }

        if tile.isLeaf { return tile }

        for child in tile.children {
            if let found = tileAt(point: point, in: child) {
                return found
            }
        }
        return nil
    }

    /// All leaf tiles in the tree.
    public func leafTiles() -> [Tile] {
        root.leafTiles()
    }

    // MARK: - Adjacent Tile

    /// Find the adjacent leaf tile in a given navigation direction.
    public func adjacentTile(to tile: Tile, direction: NavigationDirection) -> Tile? {
        let tileFrame = rawFrame(for: tile)
        let probePoint: CGPoint

        switch direction {
        case .left:
            probePoint = CGPoint(x: tileFrame.minX - 1, y: tileFrame.midY)
        case .right:
            probePoint = CGPoint(x: tileFrame.maxX + 1, y: tileFrame.midY)
        case .up:
            probePoint = CGPoint(x: tileFrame.midX, y: tileFrame.minY - 1)
        case .down:
            probePoint = CGPoint(x: tileFrame.midX, y: tileFrame.maxY + 1)
        }

        return tileAt(point: probePoint)
    }
}
