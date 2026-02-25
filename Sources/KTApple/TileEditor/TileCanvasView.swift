import KTAppleCore
import os.log
import SwiftUI

private let log = Logger(subsystem: "com.m96chan.KTApple", category: "TileCanvas")

/// Mutable drag state held as a reference type so mutations
/// do NOT trigger SwiftUI re-renders. Only `renderToken` is
/// published to drive visual updates at controlled points.
final class CanvasDragState: ObservableObject {
    var activeBoundaryID: String?
    var hoveredBoundaryID: String?
    var dragOffset: CGFloat = 0
    var previousPosition: CGFloat?
    var activeBoundary: EditorTileBoundary?

    /// Increment to trigger a re-render.
    @Published var renderToken: Int = 0

    func reset() {
        activeBoundaryID = nil
        dragOffset = 0
        previousPosition = nil
        activeBoundary = nil
    }
}

/// GeometryReader rendering tile rects and boundaries.
///
/// Boundary drag uses NSEvent local monitors instead of SwiftUI
/// DragGesture, because SwiftUI re-renders during @State changes
/// consistently break active gestures.
struct TileCanvasView: View {
    @ObservedObject var viewModel: TileEditorViewModel
    var onBackgroundTap: (() -> Void)?

    @StateObject private var dragState = CanvasDragState()

    var body: some View {
        GeometryReader { geo in
            let screenFrame = viewModel.workingManager.screenFrame
            let scaleX = geo.size.width / screenFrame.width
            let scaleY = geo.size.height / screenFrame.height
            let _ = dragState.renderToken // subscribe to render updates

            ZStack {
                ForEach(viewModel.tileFrames()) { tileFrame in
                    let canDelete = viewModel.tile(withID: tileFrame.id)?.parent != nil
                    TileRectView(
                        tileFrame: tileFrame,
                        scaleX: scaleX,
                        scaleY: scaleY,
                        screenFrameOrigin: screenFrame.origin,
                        canDelete: canDelete,
                        onTap: { onBackgroundTap?() },
                        onSplitH: { viewModel.splitTile(id: tileFrame.id, direction: .horizontal) },
                        onSplitV: { viewModel.splitTile(id: tileFrame.id, direction: .vertical) },
                        onDelete: { viewModel.deleteTile(id: tileFrame.id) }
                    )
                }

                ForEach(viewModel.boundaries()) { boundary in
                    TileBorderDragHandle(
                        boundary: boundary,
                        scaleX: scaleX,
                        scaleY: scaleY,
                        screenFrameOrigin: screenFrame.origin,
                        isActive: dragState.activeBoundaryID == boundary.id,
                        isHovered: dragState.hoveredBoundaryID == boundary.id,
                        dragOffset: dragState.activeBoundaryID == boundary.id ? dragState.dragOffset : 0
                    )
                }
            }
            .coordinateSpace(name: "tileCanvas")
            .background(
                // Invisible helper to install NSEvent monitors
                // and track the canvas frame in screen coordinates.
                CanvasEventOverlay(
                    viewModel: viewModel,
                    dragState: dragState,
                    scaleX: scaleX,
                    scaleY: scaleY,
                    screenFrame: screenFrame
                )
            )
        }
    }
}

// MARK: - NSEvent-based drag handling

/// NSViewRepresentable that installs local NSEvent monitors
/// for mouse drag events on the canvas.
struct CanvasEventOverlay: NSViewRepresentable {
    let viewModel: TileEditorViewModel
    let dragState: CanvasDragState
    let scaleX: CGFloat
    let scaleY: CGFloat
    let screenFrame: CGRect

    func makeNSView(context: Context) -> NSView {
        let view = CanvasTrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.dragState = dragState
        context.coordinator.scaleX = scaleX
        context.coordinator.scaleY = scaleY
        context.coordinator.screenFrame = screenFrame
        context.coordinator.canvasView = nsView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, dragState: dragState,
                    scaleX: scaleX, scaleY: scaleY, screenFrame: screenFrame)
    }

    @MainActor final class Coordinator {
        var viewModel: TileEditorViewModel
        var dragState: CanvasDragState
        var scaleX: CGFloat
        var scaleY: CGFloat
        var screenFrame: CGRect
        weak var canvasView: NSView?

        private let snapDistance: CGFloat = 30

        init(viewModel: TileEditorViewModel, dragState: CanvasDragState,
             scaleX: CGFloat, scaleY: CGFloat, screenFrame: CGRect) {
            self.viewModel = viewModel
            self.dragState = dragState
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.screenFrame = screenFrame
        }

        func mouseDown(at windowPoint: CGPoint) {
            guard let canvasView else { return }
            let local = canvasView.convert(windowPoint, from: nil)
            // isFlipped = true → origin is already top-left, matching SwiftUI
            let canvasPoint = local

            let boundaries = viewModel.boundaries()
            dragState.reset()

            for boundary in boundaries {
                let bx = (boundary.rect.midX - screenFrame.origin.x) * scaleX
                let by = (boundary.rect.midY - screenFrame.origin.y) * scaleY

                let distance: CGFloat
                switch boundary.axis {
                case .horizontal: distance = abs(canvasPoint.x - bx)
                case .vertical: distance = abs(canvasPoint.y - by)
                }

                if distance < snapDistance {
                    dragState.activeBoundaryID = boundary.id
                    dragState.activeBoundary = boundary
                    switch boundary.axis {
                    case .horizontal: dragState.previousPosition = canvasPoint.x
                    case .vertical: dragState.previousPosition = canvasPoint.y
                    }
                    dragState.renderToken += 1
                    log.warning("mouseDown: found boundary axis=\(boundary.axis == .horizontal ? "H" : "V")")
                    return
                }
            }
        }

        func mouseDragged(at windowPoint: CGPoint) {
            guard dragState.activeBoundaryID != nil,
                  let boundary = dragState.activeBoundary,
                  let canvasView else { return }

            let local = canvasView.convert(windowPoint, from: nil)
            let canvasPoint = local

            let currentPos: CGFloat
            switch boundary.axis {
            case .horizontal: currentPos = canvasPoint.x
            case .vertical: currentPos = canvasPoint.y
            }

            if let prev = dragState.previousPosition {
                dragState.dragOffset += currentPos - prev
            }
            dragState.previousPosition = currentPos
            dragState.renderToken += 1
        }

        func mouseMoved(at windowPoint: CGPoint) {
            guard dragState.activeBoundaryID == nil,
                  let canvasView else { return }
            let canvasPoint = canvasView.convert(windowPoint, from: nil)
            let boundaries = viewModel.boundaries()

            var found: EditorTileBoundary?
            for boundary in boundaries {
                let bx = (boundary.rect.midX - screenFrame.origin.x) * scaleX
                let by = (boundary.rect.midY - screenFrame.origin.y) * scaleY
                let distance: CGFloat
                switch boundary.axis {
                case .horizontal: distance = abs(canvasPoint.x - bx)
                case .vertical: distance = abs(canvasPoint.y - by)
                }
                if distance < snapDistance {
                    found = boundary
                    break
                }
            }

            if dragState.hoveredBoundaryID != found?.id {
                dragState.hoveredBoundaryID = found?.id
                dragState.renderToken += 1
            }

            if let boundary = found {
                switch boundary.axis {
                case .horizontal: NSCursor.resizeLeftRight.set()
                case .vertical: NSCursor.resizeUpDown.set()
                }
            } else {
                NSCursor.arrow.set()
            }
        }

        func mouseUp(at windowPoint: CGPoint) {
            guard dragState.activeBoundaryID != nil,
                  let boundary = dragState.activeBoundary,
                  let canvasView else {
                dragState.reset()
                return
            }

            let local = canvasView.convert(windowPoint, from: nil)
            let canvasPoint = local

            let screenPos: CGFloat
            switch boundary.axis {
            case .horizontal:
                screenPos = canvasPoint.x / scaleX + screenFrame.origin.x
            case .vertical:
                screenPos = canvasPoint.y / scaleY + screenFrame.origin.y
            }

            log.warning("mouseUp: axis=\(boundary.axis == .horizontal ? "H" : "V") screenPos=\(screenPos)")
            viewModel.resizeBoundaryAtScreenPosition(
                leftTileID: boundary.leftTileID,
                rightTileID: boundary.rightTileID,
                axis: boundary.axis,
                screenPosition: screenPos
            )

            dragState.reset()
            dragState.hoveredBoundaryID = nil
            dragState.renderToken += 1
            NSCursor.arrow.set()
        }

    }
}

/// NSView subclass that overrides mouse events for boundary dragging
/// and key events for tile operations.
final class CanvasTrackingView: NSView {
    weak var coordinator: CanvasEventOverlay.Coordinator?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator?.mouseMoved(at: event.locationInWindow)
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.mouseDown(at: event.locationInWindow)
        // If not on a boundary, let the event pass through
        if coordinator?.dragState.activeBoundaryID == nil {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if coordinator?.dragState.activeBoundaryID != nil {
            coordinator?.mouseDragged(at: event.locationInWindow)
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if coordinator?.dragState.activeBoundaryID != nil {
            coordinator?.mouseUp(at: event.locationInWindow)
        } else {
            super.mouseUp(with: event)
        }
    }
}
