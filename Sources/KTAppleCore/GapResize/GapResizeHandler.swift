import CoreGraphics
import Foundation

/// Handles dragging tile boundaries to resize adjacent tiles.
///
/// Detects when the cursor is near a boundary, changes the cursor
/// to a resize cursor, and processes drag gestures to resize tiles.
public final class GapResizeHandler {
    private let eventProvider: EventProvider
    private let cursorProvider: CursorProvider
    private let tileManager: TileManager

    /// Threshold in pixels for boundary hit-testing.
    public let boundaryThreshold: CGFloat

    public weak var delegate: GapResizeDelegate?

    /// Whether a resize drag is in progress.
    public private(set) var isResizing: Bool = false

    /// The boundary currently being dragged.
    public private(set) var activeBoundary: TileBoundary?

    /// The starting mouse position of the drag.
    private var dragStartPosition: CGFloat = 0

    /// The original boundary position when drag started.
    private var originalPosition: CGFloat = 0

    public init(
        eventProvider: EventProvider,
        cursorProvider: CursorProvider,
        tileManager: TileManager,
        boundaryThreshold: CGFloat = 6
    ) {
        self.eventProvider = eventProvider
        self.cursorProvider = cursorProvider
        self.tileManager = tileManager
        self.boundaryThreshold = boundaryThreshold
    }

    /// Start monitoring mouse events for resize.
    public func startMonitoring() {
        eventProvider.startMonitoring { [weak self] event in
            self?.handleMouseEvent(event)
        }
    }

    /// Stop monitoring mouse events.
    public func stopMonitoring() {
        eventProvider.stopMonitoring()
        if isResizing {
            isResizing = false
            activeBoundary = nil
        }
        cursorProvider.setCursor(.arrow)
    }

    /// Process a mouse event for boundary resize.
    public func handleMouseEvent(_ event: MouseEvent) {
        switch event.phase {
        case .moved:
            handleHover(at: event.location)

        case .began:
            if let boundary = boundaryAt(point: event.location) {
                beginResize(boundary: boundary, location: event.location)
            }

        case .changed:
            if isResizing {
                updateResize(location: event.location)
            }

        case .ended:
            if isResizing {
                endResize(location: event.location)
            }
        }
    }

    // MARK: - Boundary Detection

    /// Compute all boundaries between sibling tiles in the tree.
    public func tileBoundaries() -> [TileBoundary] {
        var boundaries: [TileBoundary] = []
        collectBoundaries(tile: tileManager.root, boundaries: &boundaries)
        return boundaries
    }

    /// Find the boundary at a screen point, if any.
    public func boundaryAt(point: CGPoint) -> TileBoundary? {
        for boundary in tileBoundaries() {
            let expandedRect = boundary.rect.insetBy(dx: -boundaryThreshold, dy: -boundaryThreshold)
            if expandedRect.contains(point) {
                return boundary
            }
        }
        return nil
    }

    /// Pure function to calculate new proportions after a resize drag.
    ///
    /// - Parameters:
    ///   - leadingProportion: Current proportion of leading tile.
    ///   - trailingProportion: Current proportion of trailing tile.
    ///   - delta: Normalized delta (-1...1 range relative to parent space).
    ///   - minProportion: Minimum allowed proportion.
    /// - Returns: New (leading, trailing) proportions.
    public static func calculateResize(
        leadingProportion: CGFloat,
        trailingProportion: CGFloat,
        delta: CGFloat,
        minProportion: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat) {
        let total = leadingProportion + trailingProportion
        var newLeading = leadingProportion + delta
        var newTrailing = trailingProportion - delta

        // Clamp to minimum proportions
        if newLeading < minProportion {
            newLeading = minProportion
            newTrailing = total - minProportion
        }
        if newTrailing < minProportion {
            newTrailing = minProportion
            newLeading = total - minProportion
        }

        return (newLeading, newTrailing)
    }

    // MARK: - Private

    private func collectBoundaries(tile: Tile, boundaries: inout [TileBoundary]) {
        guard !tile.isLeaf else { return }

        let children = tile.children
        for i in 0..<(children.count - 1) {
            let leading = children[i]
            let trailing = children[i + 1]
            let leadingFrame = tileManager.frame(for: leading)
            let trailingFrame = tileManager.frame(for: trailing)

            let boundary: TileBoundary
            switch tile.layoutDirection {
            case .horizontal:
                let x = (leadingFrame.maxX + trailingFrame.minX) / 2
                boundary = TileBoundary(
                    leadingTileID: leading.id,
                    trailingTileID: trailing.id,
                    axis: .horizontal,
                    position: x,
                    rect: CGRect(x: x - 1, y: leadingFrame.minY, width: 2, height: leadingFrame.height)
                )
            case .vertical:
                let y = (leadingFrame.maxY + trailingFrame.minY) / 2
                boundary = TileBoundary(
                    leadingTileID: leading.id,
                    trailingTileID: trailing.id,
                    axis: .vertical,
                    position: y,
                    rect: CGRect(x: leadingFrame.minX, y: y - 1, width: leadingFrame.width, height: 2)
                )
            }
            boundaries.append(boundary)
        }

        for child in children {
            collectBoundaries(tile: child, boundaries: &boundaries)
        }
    }

    private func handleHover(at location: CGPoint) {
        guard !isResizing else { return }
        if let boundary = boundaryAt(point: location) {
            switch boundary.axis {
            case .horizontal:
                cursorProvider.setCursor(.resizeHorizontal)
            case .vertical:
                cursorProvider.setCursor(.resizeVertical)
            }
        } else {
            cursorProvider.setCursor(.arrow)
        }
    }

    private func beginResize(boundary: TileBoundary, location: CGPoint) {
        isResizing = true
        activeBoundary = boundary
        originalPosition = boundary.position

        switch boundary.axis {
        case .horizontal:
            dragStartPosition = location.x
        case .vertical:
            dragStartPosition = location.y
        }
    }

    private func updateResize(location: CGPoint) {
        guard let boundary = activeBoundary else { return }

        let currentPosition: CGFloat
        let parentSize: CGFloat

        switch boundary.axis {
        case .horizontal:
            currentPosition = location.x
            parentSize = tileManager.screenFrame.width
        case .vertical:
            currentPosition = location.y
            parentSize = tileManager.screenFrame.height
        }

        guard parentSize > 0 else { return }

        let pixelDelta = currentPosition - dragStartPosition
        let normalizedDelta = pixelDelta / parentSize

        // Find the tiles
        guard let leadingTile = findTile(id: boundary.leadingTileID),
              let trailingTile = findTile(id: boundary.trailingTileID) else { return }

        let (newLeading, newTrailing) = Self.calculateResize(
            leadingProportion: leadingTile.proportion,
            trailingProportion: trailingTile.proportion,
            delta: normalizedDelta,
            minProportion: TileManager.minProportion
        )

        leadingTile.proportion = newLeading
        trailingTile.proportion = newTrailing

        // Update drag start to current position for incremental deltas
        dragStartPosition = currentPosition
    }

    private func endResize(location: CGPoint) {
        updateResize(location: location)

        if let boundary = activeBoundary {
            delegate?.didResize(boundary, affectedTiles: [boundary.leadingTileID, boundary.trailingTileID])
        }

        isResizing = false
        activeBoundary = nil
        handleHover(at: location)
    }

    private func findTile(id: UUID) -> Tile? {
        findTile(id: id, in: tileManager.root)
    }

    private func findTile(id: UUID, in tile: Tile) -> Tile? {
        if tile.id == id { return tile }
        for child in tile.children {
            if let found = findTile(id: id, in: child) { return found }
        }
        return nil
    }
}
