import KTAppleCore
import SwiftUI

/// Individual tile view with inline action buttons (KDE Plasma style).
struct TileRectView: View {
    /// Tahoe's Liquid Glass favours a larger corner radius than the pre-26 flat rects.
    static let cornerRadius: CGFloat = 8

    let tileFrame: TileFrame
    let scaleX: CGFloat
    let scaleY: CGFloat
    let screenFrameOrigin: CGPoint
    let canDelete: Bool
    let thumbnail: NSImage?
    let onTap: () -> Void
    let onSplitH: () -> Void
    let onSplitV: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let scaledFrame = CGRect(
            x: (tileFrame.frame.origin.x - screenFrameOrigin.x) * scaleX,
            y: (tileFrame.frame.origin.y - screenFrameOrigin.y) * scaleY,
            width: tileFrame.frame.width * scaleX,
            height: tileFrame.frame.height * scaleY
        )

        ZStack {
            // Background — tapping closes the editor.
            // Liquid Glass on Tahoe lets the desktop read through the tile;
            // macOS 15 gets the previous translucent white fill.
            Color.clear
                .glassSurface(
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius),
                    clear: true,
                    fallback: Color.white.opacity(0.08)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                .onTapGesture { onTap() }

            // App icon thumbnail for the first assigned window
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.25)
                    .padding(scaledFrame.width > 80 ? 16 : 8)
                    .allowsHitTesting(false)
            }

            // Grouped so Tahoe merges the adjacent glass capsules into one pass.
            GlassContainer(spacing: 6) {
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
                        icon: "rectangle.split.2x1",
                        action: onSplitH
                    )
                    tileButton(
                        label: "Split V",
                        icon: "rectangle.split.1x2",
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
            .glassSurface(
                in: .capsule,
                interactive: true,
                fallback: Color.white.opacity(0.15)
            )
        }
        .buttonStyle(.plain)
    }
}
