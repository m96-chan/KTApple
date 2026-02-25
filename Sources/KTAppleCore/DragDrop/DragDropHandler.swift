import CoreGraphics
import Foundation

/// Resolves which TileManager owns a given screen point.
public typealias TileManagerResolver = (CGPoint) -> TileManager?

/// Returns the current screen position of a window, or nil if unknown.
public typealias WindowPositionProvider = (UInt32) -> CGPoint?

/// Handles shift+drag window placement onto tiles.
///
/// Monitors mouse events for shift+drag gestures, highlights the target tile
/// via an overlay, and notifies the delegate when a window is dropped.
public final class DragDropHandler {
    private let eventProvider: EventProvider
    private let overlayProvider: OverlayProvider
    private let resolveTileManager: TileManagerResolver
    private let windowPosition: WindowPositionProvider?

    public weak var delegate: DragDropDelegate?

    /// Whether a drag operation is currently in progress.
    public private(set) var isDragging: Bool = false

    /// The tile currently highlighted as a drop target.
    public private(set) var highlightedTileID: UUID?

    /// The window being dragged.
    public private(set) var draggedWindowID: UInt32?

    /// Window ID from the last mouseDown, held until Shift is detected or mouseUp.
    private var pendingWindowID: UInt32?

    /// Whether we already notified the delegate about a non-shift drag this gesture.
    private var didNotifyUntile: Bool = false

    /// Window position recorded at mouseDown, used to detect actual window movement.
    private var mouseDownWindowPosition: CGPoint?

    public init(
        eventProvider: EventProvider,
        overlayProvider: OverlayProvider,
        tileManagerResolver: @escaping TileManagerResolver,
        windowPositionProvider: WindowPositionProvider? = nil
    ) {
        self.eventProvider = eventProvider
        self.overlayProvider = overlayProvider
        self.resolveTileManager = tileManagerResolver
        self.windowPosition = windowPositionProvider
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
            // Always remember which window was clicked, even without Shift
            pendingWindowID = event.windowID
            // Record window position at mouseDown for move detection
            if let wid = event.windowID {
                mouseDownWindowPosition = windowPosition?(wid)
            } else {
                mouseDownWindowPosition = nil
            }
            if event.modifiers.contains(.shift), let windowID = event.windowID {
                beginDrag(windowID: windowID, location: event.location)
            }

        case .changed:
            if isDragging {
                updateDrag(location: event.location)
            } else if event.modifiers.contains(.shift), let windowID = pendingWindowID {
                // Shift pressed mid-drag → start drag with the window from mouseDown
                beginDrag(windowID: windowID, location: event.location)
            } else if !event.modifiers.contains(.shift), !didNotifyUntile, let windowID = pendingWindowID {
                // Normal drag (no Shift) → unassign from tile only if window actually moved
                if windowDidMove(windowID) {
                    didNotifyUntile = true
                    delegate?.didDragWindowFromTile(windowID)
                }
            }

        case .ended:
            if isDragging {
                endDrag(location: event.location)
            }
            pendingWindowID = nil
            didNotifyUntile = false
            mouseDownWindowPosition = nil

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
        if let windowID = draggedWindowID,
           let manager = resolveTileManager(location),
           let tile = manager.tileAt(point: location) {
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
        pendingWindowID = nil
        didNotifyUntile = false
        mouseDownWindowPosition = nil
        highlightedTileID = nil
        overlayProvider.hideHighlight()
    }

    /// Check if the window has actually moved from its mouseDown position.
    /// If no position provider is set, assumes the window moved (backwards-compatible).
    private func windowDidMove(_ windowID: UInt32) -> Bool {
        guard let provider = windowPosition else { return true }
        guard let startPos = mouseDownWindowPosition,
              let currentPos = provider(windowID) else { return true }
        return startPos != currentPos
    }

    private func updateHighlight(at location: CGPoint) {
        if let manager = resolveTileManager(location),
           let tile = manager.tileAt(point: location) {
            highlightedTileID = tile.id
            let frame = manager.frame(for: tile)
            overlayProvider.showHighlight(frame: frame)
        } else {
            highlightedTileID = nil
            overlayProvider.hideHighlight()
        }
    }
}
