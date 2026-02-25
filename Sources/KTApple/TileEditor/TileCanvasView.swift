import KTAppleCore
import os.log
import SwiftUI

private let log = AppLog.logger(for: "TileCanvas")

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

                // Pixel dimension label shown during boundary drag
                if let activeBoundary = dragState.activeBoundary {
                    DimensionOverlay(
                        boundary: activeBoundary,
                        dragOffset: dragState.dragOffset,
                        workingManager: viewModel.workingManager,
                        scaleX: scaleX,
                        scaleY: scaleY,
                        screenFrameOrigin: screenFrame.origin
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
                    log.debug("mouseDown: found boundary axis=\(boundary.axis == .horizontal ? "H" : "V")")
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

            let newID = found?.id
            if dragState.hoveredBoundaryID != newID {
                dragState.hoveredBoundaryID = newID
                dragState.renderToken += 1

                if let boundary = found {
                    switch boundary.axis {
                    case .horizontal: NSCursor.resizeLeftRight.set()
                    case .vertical: NSCursor.resizeUpDown.set()
                    }
                } else {
                    NSCursor.arrow.set()
                }
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

            log.debug("mouseUp: axis=\(boundary.axis == .horizontal ? "H" : "V") screenPos=\(screenPos)")
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
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator?.mouseMoved(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        guard let dragState = coordinator?.dragState,
              dragState.activeBoundaryID == nil else { return }
        if dragState.hoveredBoundaryID != nil {
            dragState.hoveredBoundaryID = nil
            dragState.renderToken += 1
        }
        NSCursor.arrow.set()
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

// MARK: - Dimension Overlay

/// Displays pixel dimensions of both adjacent tiles while a boundary is being dragged.
///
/// Uses raw (pre-gap) tile frames and adjusts by the current dragOffset to give
/// real-time feedback on how the resize will affect each tile slot.
private struct DimensionOverlay: View {
    let boundary: EditorTileBoundary
    let dragOffset: CGFloat
    let workingManager: TileManager
    let scaleX: CGFloat
    let scaleY: CGFloat
    let screenFrameOrigin: CGPoint

    private struct Info {
        let text: String
        let x: CGFloat
        let y: CGFloat
    }

    private var info: Info? {
        guard let leading = workingManager.root.find(id: boundary.leftTileID),
              let trailing = workingManager.root.find(id: boundary.rightTileID) else { return nil }

        let lRaw = workingManager.rawFrame(for: leading)
        let tRaw = workingManager.rawFrame(for: trailing)

        let canvasX = (boundary.rect.midX - screenFrameOrigin.x) * scaleX
        let canvasY = (boundary.rect.midY - screenFrameOrigin.y) * scaleY

        switch boundary.axis {
        case .horizontal:
            let screenDelta = dragOffset / scaleX
            let lw = Int(max(0, lRaw.width + screenDelta).rounded())
            let tw = Int(max(0, tRaw.width - screenDelta).rounded())
            let h  = Int(lRaw.height.rounded())
            return Info(text: "\(lw) × \(h)  |  \(tw) × \(h)",
                        x: canvasX + dragOffset,
                        y: canvasY)
        case .vertical:
            let screenDelta = dragOffset / scaleY
            let lh = Int(max(0, lRaw.height + screenDelta).rounded())
            let th = Int(max(0, tRaw.height - screenDelta).rounded())
            let w  = Int(lRaw.width.rounded())
            return Info(text: "\(w) × \(lh)  |  \(w) × \(th)",
                        x: canvasX,
                        y: canvasY + dragOffset)
        }
    }

    var body: some View {
        if let i = info {
            Text(i.text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.75)))
                .position(x: i.x, y: i.y)
                .allowsHitTesting(false)
        }
    }
}
