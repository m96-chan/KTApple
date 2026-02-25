import KTAppleCore
import SwiftUI

/// Draggable boundary handle between two tiles.
///
/// Uses a named coordinate space ("tileCanvas") from the parent TileCanvasView
/// so drag location tracks the mouse correctly.
struct TileBorderDragHandle: View {
    let boundary: EditorTileBoundary
    let scaleX: CGFloat
    let scaleY: CGFloat
    @ObservedObject var viewModel: TileEditorViewModel

    var body: some View {
        let rawRect = CGRect(
            x: boundary.rect.origin.x * scaleX,
            y: boundary.rect.origin.y * scaleY,
            width: boundary.rect.width * scaleX,
            height: boundary.rect.height * scaleY
        )

        // Visible line: thin (2pt) center stripe
        let lineWidth: CGFloat = boundary.axis == .horizontal ? 2 : rawRect.width
        let lineHeight: CGFloat = boundary.axis == .vertical ? 2 : rawRect.height

        // Hit area: wider invisible zone for easier dragging
        let hitWidth: CGFloat = boundary.axis == .horizontal ? 16 : rawRect.width
        let hitHeight: CGFloat = boundary.axis == .vertical ? 16 : rawRect.height

        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: lineWidth, height: lineHeight)
                .allowsHitTesting(false)

            Color.clear
                .frame(width: hitWidth, height: hitHeight)
                .contentShape(Rectangle())
        }
        .position(x: rawRect.midX, y: rawRect.midY)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("tileCanvas"))
                .onChanged { value in
                    let screenFrame = viewModel.workingManager.screenFrame
                    let fraction: CGFloat
                    switch boundary.axis {
                    case .horizontal:
                        fraction = (value.location.x / scaleX) / screenFrame.width
                    case .vertical:
                        fraction = (value.location.y / scaleY) / screenFrame.height
                    }
                    viewModel.resizeBoundary(
                        leftTileID: boundary.leftTileID,
                        rightTileID: boundary.rightTileID,
                        positionFraction: fraction
                    )
                }
        )
    }
}
