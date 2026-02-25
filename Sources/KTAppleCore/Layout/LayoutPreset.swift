import CoreGraphics
import Foundation

/// Built-in layout presets that can be applied to a TileManager.
public enum LayoutPreset: String, CaseIterable, Sendable {
    case halves
    case thirds
    case masterStack
    case grid
    case centerFocus

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .halves: return "Halves"
        case .thirds: return "Thirds"
        case .masterStack: return "Master + Stack"
        case .grid: return "Grid"
        case .centerFocus: return "Center Focus"
        }
    }

    /// Apply this preset to a TileManager, replacing its tile tree.
    public func apply(to manager: TileManager) {
        let root = buildTree()
        manager.replaceRoot(root)
    }

    /// Build the tile tree for this preset.
    public func buildTree() -> Tile {
        switch self {
        case .halves:
            return buildHalves()
        case .thirds:
            return buildThirds()
        case .masterStack:
            return buildMasterStack()
        case .grid:
            return buildGrid()
        case .centerFocus:
            return buildCenterFocus()
        }
    }

    private func buildHalves() -> Tile {
        let root = Tile(proportion: 1.0, layoutDirection: .horizontal)
        root.addChild(Tile(proportion: 0.5))
        root.addChild(Tile(proportion: 0.5))
        return root
    }

    private func buildThirds() -> Tile {
        let root = Tile(proportion: 1.0, layoutDirection: .horizontal)
        let third: CGFloat = 1.0 / 3.0
        root.addChild(Tile(proportion: third))
        root.addChild(Tile(proportion: third))
        root.addChild(Tile(proportion: third))
        return root
    }

    private func buildMasterStack() -> Tile {
        let root = Tile(proportion: 1.0, layoutDirection: .horizontal)
        let master = Tile(proportion: 0.6)
        let stack = Tile(proportion: 0.4, layoutDirection: .vertical)
        stack.addChild(Tile(proportion: 0.5))
        stack.addChild(Tile(proportion: 0.5))
        root.addChild(master)
        root.addChild(stack)
        return root
    }

    private func buildGrid() -> Tile {
        let root = Tile(proportion: 1.0, layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5, layoutDirection: .vertical)
        let right = Tile(proportion: 0.5, layoutDirection: .vertical)
        left.addChild(Tile(proportion: 0.5))
        left.addChild(Tile(proportion: 0.5))
        right.addChild(Tile(proportion: 0.5))
        right.addChild(Tile(proportion: 0.5))
        root.addChild(left)
        root.addChild(right)
        return root
    }

    private func buildCenterFocus() -> Tile {
        let root = Tile(proportion: 1.0, layoutDirection: .horizontal)
        root.addChild(Tile(proportion: 0.2))
        root.addChild(Tile(proportion: 0.6))
        root.addChild(Tile(proportion: 0.2))
        return root
    }
}
