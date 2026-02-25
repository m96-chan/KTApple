import KTAppleCore
import SwiftUI

/// Visual-only boundary line between two tiles.
/// No gesture — drag is handled at the canvas level.
struct TileBorderDragHandle: View {
    let boundary: EditorTileBoundary
    let scaleX: CGFloat
    let scaleY: CGFloat
    let screenFrameOrigin: CGPoint
    let isActive: Bool
    let dragOffset: CGFloat

    var body: some View {
        let rawRect = CGRect(
            x: (boundary.rect.origin.x - screenFrameOrigin.x) * scaleX,
            y: (boundary.rect.origin.y - screenFrameOrigin.y) * scaleY,
            width: boundary.rect.width * scaleX,
            height: boundary.rect.height * scaleY
        )

        let lineWidth: CGFloat = boundary.axis == .horizontal ? 2 : rawRect.width
        let lineHeight: CGFloat = boundary.axis == .vertical ? 2 : rawRect.height

        Rectangle()
            .fill(isActive ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.4))
            .frame(width: lineWidth, height: lineHeight)
            .position(
                x: rawRect.midX + (boundary.axis == .horizontal ? dragOffset : 0),
                y: rawRect.midY + (boundary.axis == .vertical ? dragOffset : 0)
            )
            .allowsHitTesting(false)
    }
}
