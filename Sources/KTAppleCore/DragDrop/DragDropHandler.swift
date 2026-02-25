import CoreGraphics
import Foundation

/// Handles shift+drag window placement onto tiles.
///
/// Monitors mouse events for shift+drag gestures, highlights the target tile
/// via an overlay, and notifies the delegate when a window is dropped.
public final class DragDropHandler {
    private let eventProvider: EventProvider
    private let overlayProvider: OverlayProvider
    private let tileManager: TileManager

    public weak var delegate: DragDropDelegate?

    /// Whether a drag operation is currently in progress.
    public private(set) var isDragging: Bool = false

    /// The tile currently highlighted as a drop target.
    public private(set) var highlightedTileID: UUID?

    /// The window being dragged.
    public private(set) var draggedWindowID: UInt32?

    public init(
        eventProvider: EventProvider,
        overlayProvider: OverlayProvider,
        tileManager: TileManager
    ) {
        self.eventProvider = eventProvider
        self.overlayProvider = overlayProvider
        self.tileManager = tileManager
    }

    /// Start monitoring mouse events for drag-drop.
    public func startMonitoring() {
        eventProvider.startMonitoring { [weak self] event in
            self?.handleMouseEvent(event)
        }
    }

    /// Stop monitoring mouse events.
    public func stopMonitoring() {
        eventProvider.stopMonitoring()
        cancelDrag()
    }

    /// Process a mouse event for drag-drop handling.
    public func handleMouseEvent(_ event: MouseEvent) {
        switch event.phase {
        case .began:
            if event.modifiers.contains(.shift), let windowID = event.windowID {
                beginDrag(windowID: windowID, location: event.location)
            }

        case .changed:
            if isDragging {
                updateDrag(location: event.location)
            }

        case .ended:
            if isDragging {
                endDrag(location: event.location)
            }

        case .moved:
            break
        }
    }

    private func beginDrag(windowID: UInt32, location: CGPoint) {
        isDragging = true
        draggedWindowID = windowID
        updateHighlight(at: location)
    }

    private func updateDrag(location: CGPoint) {
        updateHighlight(at: location)
    }

    private func endDrag(location: CGPoint) {
        if let windowID = draggedWindowID, let tile = tileManager.tileAt(point: location) {
            delegate?.didDropWindow(windowID, onTile: tile.id)
        } else {
            delegate?.didCancelDrop()
        }
        clearDragState()
    }

    private func cancelDrag() {
        if isDragging {
            delegate?.didCancelDrop()
        }
        clearDragState()
    }

    private func clearDragState() {
        isDragging = false
        draggedWindowID = nil
        highlightedTileID = nil
        overlayProvider.hideHighlight()
    }

    private func updateHighlight(at location: CGPoint) {
        if let tile = tileManager.tileAt(point: location) {
            highlightedTileID = tile.id
            let frame = tileManager.frame(for: tile)
            overlayProvider.showHighlight(frame: frame)
        } else {
            highlightedTileID = nil
            overlayProvider.hideHighlight()
        }
    }
}
