import KTAppleCore
import SwiftUI

/// Individual tile view with inline action buttons (KDE Plasma style).
struct TileRectView: View {
    let tileFrame: TileFrame
    let scaleX: CGFloat
    let scaleY: CGFloat
    let screenFrameOrigin: CGPoint
    let canDelete: Bool
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onSplitH: () -> Void
    let onSplitV: () -> Void
    let onDelete: () -> Void

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if isHovered { return Color.white.opacity(0.5) }
        return Color.white.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    var body: some View {
        let scaledFrame = CGRect(
            x: (tileFrame.frame.origin.x - screenFrameOrigin.x) * scaleX,
            y: (tileFrame.frame.origin.y - screenFrameOrigin.y) * scaleY,
            width: tileFrame.frame.width * scaleX,
            height: tileFrame.frame.height * scaleY
        )

        ZStack {
            // Background — tapping selects the tile
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture { onSelect() }

            VStack(spacing: 6) {
                // Window count indicator
                if !tileFrame.windowIDs.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 9))
                        Text("\(tileFrame.windowIDs.count)")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }

                // Inline action buttons
                tileButton(
                    label: "Split H",
                    icon: "rectangle.split.1x2",
                    action: onSplitH
                )
                tileButton(
                    label: "Split V",
                    icon: "rectangle.split.2x1",
                    action: onSplitV
                )
                if canDelete {
                    tileButton(
                        label: "Delete",
                        icon: "xmark",
                        isDestructive: true,
                        action: onDelete
                    )
                }
            }
        }
        .frame(width: scaledFrame.width, height: scaledFrame.height)
        .position(x: scaledFrame.midX, y: scaledFrame.midY)
    }

    private func tileButton(
        label: String,
        icon: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isDestructive ? .red : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}
