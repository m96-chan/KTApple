import CoreGraphics
import Foundation

/// Boundary between two adjacent tiles in the editor canvas.
///
/// The `id` is deterministic (derived from the two tile IDs) so that
/// SwiftUI's `ForEach` preserves view identity across re-renders,
/// keeping active `DragGesture`s alive.
public struct EditorTileBoundary: Identifiable, Sendable {
    public var id: String { "\(leftTileID)_\(rightTileID)" }
    public let leftTileID: UUID
    public let rightTileID: UUID
    public let axis: LayoutDirection
    public let position: CGFloat
    public let rect: CGRect

    public init(
        leftTileID: UUID,
        rightTileID: UUID,
        axis: LayoutDirection,
        position: CGFloat,
        rect: CGRect
    ) {
        self.leftTileID = leftTileID
        self.rightTileID = rightTileID
        self.axis = axis
        self.position = position
        self.rect = rect
    }
}

/// Frame information for a tile in the editor canvas.
public struct TileFrame: Identifiable, Sendable {
    public let id: UUID
    public let frame: CGRect
    public let isLeaf: Bool
    public let windowIDs: Set<UInt32>
}

/// ViewModel for the visual tile layout editor.
///
/// Operates on a deep copy of the live TileManager so changes
/// can be previewed and either applied or cancelled.
public final class TileEditorViewModel: ObservableObject {
    private let liveTileManager: TileManager
    private let layoutStore: LayoutStore?
    private let layoutKey: LayoutKey?

    /// Working copy used for editing.
    @Published public var workingManager: TileManager

    /// Whether the working copy differs from the live state.
    @Published public var isDirty: Bool = false

    /// Currently hovered tile ID.
    @Published public var hoveredTileID: UUID?

    /// Currently selected tile ID.
    @Published public var selectedTileID: UUID?

    /// Whether undo is available.
    @Published public var canUndo: Bool = false

    /// Whether redo is available.
    @Published public var canRedo: Bool = false

    /// Called after apply() replaces the live tile tree (e.g. to reflow windows).
    public var onApply: (() -> Void)?

    /// Undo history (snapshots of root tile tree).
    private var undoStack: [Tile] = []
    private var redoStack: [Tile] = []
    private static let maxUndoDepth = 20

    /// Minimum gap used in the editor so boundaries remain visible and draggable.
    static let editorMinGap: CGFloat = 4

    public init(tileManager: TileManager, layoutStore: LayoutStore? = nil, layoutKey: LayoutKey? = nil) {
        self.liveTileManager = tileManager
        let copy = tileManager.deepCopy()
        copy.gap = max(Self.editorMinGap, copy.gap)
        self.workingManager = copy
        self.layoutStore = layoutStore
        self.layoutKey = layoutKey
    }

    // MARK: - Undo / Redo

    private func saveSnapshot() {
        undoStack.append(workingManager.root.deepCopy())
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    /// Undo the last editing operation.
    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(workingManager.root.deepCopy())
        workingManager.replaceRoot(snapshot)
        isDirty = !undoStack.isEmpty
        canUndo = !undoStack.isEmpty
        canRedo = true
    }

    /// Redo the last undone operation.
    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(workingManager.root.deepCopy())
        workingManager.replaceRoot(snapshot)
        isDirty = true
        canUndo = true
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Tile Operations

    /// Split a leaf tile into two children.
    @discardableResult
    public func splitTile(id: UUID, direction: LayoutDirection, ratio: CGFloat = 0.5) -> Bool {
        guard let tile = workingManager.root.find(id: id), tile.isLeaf else { return false }
        saveSnapshot()
        workingManager.split(tile, direction: direction, ratio: ratio)
        isDirty = true
        return true
    }

    /// Delete a leaf tile.
    @discardableResult
    public func deleteTile(id: UUID) -> Bool {
        guard let tile = workingManager.root.find(id: id) else { return false }
        guard tile.parent != nil else { return false }  // Can't delete root
        guard tile.isLeaf else { return false }
        saveSnapshot()
        workingManager.remove(tile)
        isDirty = true
        if selectedTileID == id { selectedTileID = nil }
        if hoveredTileID == id { hoveredTileID = nil }
        return true
    }

    /// Resize a tile to a new proportion.
    @discardableResult
    public func resizeTile(id: UUID, newProportion: CGFloat) -> Bool {
        guard let tile = workingManager.root.find(id: id) else { return false }
        guard tile.parent != nil else { return false }
        saveSnapshot()
        workingManager.resize(tile, newProportion: newProportion)
        isDirty = true
        return true
    }

    /// Resize by dragging a boundary between two adjacent tiles.
    @discardableResult
    public func resizeBoundary(leftTileID: UUID, rightTileID: UUID, positionFraction: CGFloat) -> Bool {
        guard let leftTile = workingManager.root.find(id: leftTileID),
              let rightTile = workingManager.root.find(id: rightTileID),
              let parent = leftTile.parent,
              rightTile.parent === parent else { return false }

        saveSnapshot()
        let total = leftTile.proportion + rightTile.proportion
        let newLeft = max(TileManager.minProportion, min(total - TileManager.minProportion, positionFraction * total))
        let newRight = total - newLeft

        leftTile.proportion = newLeft
        rightTile.proportion = newRight
        isDirty = true
        return true
    }

    /// Resize by dragging a boundary to an absolute screen position.
    @discardableResult
    public func resizeBoundaryAtScreenPosition(leftTileID: UUID, rightTileID: UUID, axis: LayoutDirection, screenPosition: CGFloat) -> Bool {
        guard let leftTile = workingManager.root.find(id: leftTileID),
              let rightTile = workingManager.root.find(id: rightTileID),
              let parent = leftTile.parent,
              rightTile.parent === parent else { return false }

        let leftFrame = workingManager.rawFrame(for: leftTile)
        let rightFrame = workingManager.rawFrame(for: rightTile)

        let combinedStart: CGFloat
        let combinedEnd: CGFloat
        switch axis {
        case .horizontal:
            combinedStart = leftFrame.minX
            combinedEnd = rightFrame.maxX
        case .vertical:
            combinedStart = leftFrame.minY
            combinedEnd = rightFrame.maxY
        }

        let combinedSize = combinedEnd - combinedStart
        guard combinedSize > 0 else { return false }

        saveSnapshot()
        let fraction = (screenPosition - combinedStart) / combinedSize
        let total = leftTile.proportion + rightTile.proportion
        let newLeft = max(TileManager.minProportion, min(total - TileManager.minProportion, fraction * total))
        let newRight = total - newLeft

        leftTile.proportion = newLeft
        rightTile.proportion = newRight
        isDirty = true
        return true
    }

    // MARK: - Apply / Cancel

    /// Apply the working copy's tile tree to the live TileManager.
    public func apply() {
        liveTileManager.replaceRoot(workingManager.root.deepCopy())
        if let layoutStore, let layoutKey {
            layoutStore.save(tileManager: liveTileManager, for: layoutKey)
        }
        isDirty = false
        onApply?()
    }

    /// Cancel editing and reset the working copy from the live state.
    public func cancel() {
        let copy = liveTileManager.deepCopy()
        copy.gap = max(Self.editorMinGap, copy.gap)
        workingManager = copy
        isDirty = false
        selectedTileID = nil
        hoveredTileID = nil
        undoStack.removeAll()
        redoStack.removeAll()
        canUndo = false
        canRedo = false
    }

    // MARK: - Presets

    /// Apply a layout preset to the working copy.
    public func applyPreset(_ preset: LayoutPreset) {
        saveSnapshot()
        preset.apply(to: workingManager)
        isDirty = true
        selectedTileID = nil
    }

    // MARK: - Hover / Selection

    /// Update the hovered tile based on a point in the canvas.
    public func hoverAtPoint(_ point: CGPoint) {
        hoveredTileID = workingManager.tileAt(point: point)?.id
    }

    /// Select a tile by ID.
    public func selectTile(id: UUID?) {
        selectedTileID = id
    }

    // MARK: - Canvas Data

    /// Get frame information for all leaf tiles.
    public func tileFrames() -> [TileFrame] {
        workingManager.leafTiles().map { tile in
            TileFrame(
                id: tile.id,
                frame: workingManager.frame(for: tile),
                isLeaf: tile.isLeaf,
                windowIDs: tile.windowIDs
            )
        }
    }

    /// Get all boundaries between sibling tiles.
    public func boundaries() -> [EditorTileBoundary] {
        var result: [EditorTileBoundary] = []
        collectBoundaries(tile: workingManager.root, result: &result)
        return result
    }

    /// Find a tile by ID in the working tree.
    public func tile(withID id: UUID) -> Tile? {
        workingManager.root.find(id: id)
    }

    // MARK: - Private

    private func collectBoundaries(tile: Tile, result: inout [EditorTileBoundary]) {
        guard !tile.isLeaf else { return }
        let children = tile.children
        for i in 0..<(children.count - 1) {
            let leading = children[i]
            let trailing = children[i + 1]
            let leadingFrame = workingManager.frame(for: leading)
            let trailingFrame = workingManager.frame(for: trailing)

            switch tile.layoutDirection {
            case .horizontal:
                let x = (leadingFrame.maxX + trailingFrame.minX) / 2
                result.append(EditorTileBoundary(
                    leftTileID: leading.id,
                    rightTileID: trailing.id,
                    axis: .horizontal,
                    position: x,
                    rect: CGRect(x: x - 2, y: leadingFrame.minY, width: 4, height: leadingFrame.height)
                ))
            case .vertical:
                let y = (leadingFrame.maxY + trailingFrame.minY) / 2
                result.append(EditorTileBoundary(
                    leftTileID: leading.id,
                    rightTileID: trailing.id,
                    axis: .vertical,
                    position: y,
                    rect: CGRect(x: leadingFrame.minX, y: y - 2, width: leadingFrame.width, height: 4)
                ))
            }
        }
        for child in children {
            collectBoundaries(tile: child, result: &result)
        }
    }
}
