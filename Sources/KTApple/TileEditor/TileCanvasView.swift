import KTAppleCore
import SwiftUI

/// GeometryReader rendering tile rects and boundaries.
struct TileCanvasView: View {
    @ObservedObject var viewModel: TileEditorViewModel
    var onBackgroundTap: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let screenFrame = viewModel.workingManager.screenFrame
            let scaleX = geo.size.width / screenFrame.width
            let scaleY = geo.size.height / screenFrame.height

            ZStack {
                ForEach(viewModel.tileFrames()) { tileFrame in
                    let canDelete = viewModel.tile(withID: tileFrame.id)?.parent != nil
                    TileRectView(
                        tileFrame: tileFrame,
                        scaleX: scaleX,
                        scaleY: scaleY,
                        screenFrameOrigin: screenFrame.origin,
                        canDelete: canDelete,
                        onBackgroundTap: { onBackgroundTap?() },
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
                        onDragEnd: { screenPos in
                            viewModel.resizeBoundaryAtScreenPosition(
                                leftTileID: boundary.leftTileID,
                                rightTileID: boundary.rightTileID,
                                axis: boundary.axis,
                                screenPosition: screenPos
                            )
                        }
                    )
                }
            }
            .coordinateSpace(name: "tileCanvas")
        }
    }
}
