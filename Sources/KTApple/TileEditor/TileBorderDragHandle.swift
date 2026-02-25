import KTAppleCore
import SwiftUI

/// Draggable boundary handle between two tiles.
///
/// Uses `@GestureState` for visual drag feedback so that the ViewModel
/// is NOT updated during the drag. This prevents parent re-renders from
/// interrupting the active DragGesture. The ViewModel is updated once
/// on `onEnded` with the final position.
struct TileBorderDragHandle: View {
    let boundary: EditorTileBoundary
    let scaleX: CGFloat
    let scaleY: CGFloat
    let screenFrameOrigin: CGPoint
    let onDragEnd: (CGFloat) -> Void

    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        let rawRect = CGRect(
            x: (boundary.rect.origin.x - screenFrameOrigin.x) * scaleX,
            y: (boundary.rect.origin.y - screenFrameOrigin.y) * scaleY,
            width: boundary.rect.width * scaleX,
            height: boundary.rect.height * scaleY
        )

        let lineWidth: CGFloat = boundary.axis == .horizontal ? 2 : rawRect.width
        let lineHeight: CGFloat = boundary.axis == .vertical ? 2 : rawRect.height
        let hitWidth: CGFloat = boundary.axis == .horizontal ? 16 : rawRect.width
        let hitHeight: CGFloat = boundary.axis == .vertical ? 16 : rawRect.height

        ZStack {
            // Active drag indicator (highlight when dragging)
            if dragTranslation != .zero {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: lineWidth, height: lineHeight)
                    .allowsHitTesting(false)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: lineWidth, height: lineHeight)
                    .allowsHitTesting(false)
            }

            Color.clear
                .frame(width: hitWidth, height: hitHeight)
                .contentShape(Rectangle())
        }
        .position(x: rawRect.midX, y: rawRect.midY)
        .offset(
            x: boundary.axis == .horizontal ? dragTranslation.width : 0,
            y: boundary.axis == .vertical ? dragTranslation.height : 0
        )
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("tileCanvas"))
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let screenPos: CGFloat
                    switch boundary.axis {
                    case .horizontal:
                        screenPos = value.location.x / scaleX + screenFrameOrigin.x
                    case .vertical:
                        screenPos = value.location.y / scaleY + screenFrameOrigin.y
                    }
                    onDragEnd(screenPos)
                }
        )
    }
}
