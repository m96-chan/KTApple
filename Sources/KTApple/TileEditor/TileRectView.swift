import KTAppleCore
import SwiftUI

/// Individual tile view with inline action buttons (KDE Plasma style).
struct TileRectView: View {
    let tileFrame: TileFrame
    let scaleX: CGFloat
    let scaleY: CGFloat
    let canDelete: Bool
    let onBackgroundTap: () -> Void
    let onSplitH: () -> Void
    let onSplitV: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let scaledFrame = CGRect(
            x: tileFrame.frame.origin.x * scaleX,
            y: tileFrame.frame.origin.y * scaleY,
            width: tileFrame.frame.width * scaleX,
            height: tileFrame.frame.height * scaleY
        )

        ZStack {
            // Background — tapping outside buttons saves & closes
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture { onBackgroundTap() }

            // Inline action buttons
            VStack(spacing: 6) {
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
