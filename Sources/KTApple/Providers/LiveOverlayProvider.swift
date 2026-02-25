import AppKit
import CoreGraphics
import KTAppleCore

/// Live implementation of OverlayProvider using a borderless NSWindow overlay.
///
/// Shows a semi-transparent blue highlight rectangle at the target tile position.
/// Frames are expected in Quartz screen coordinates (origin top-left).
///
/// All NSWindow operations must happen on the main thread.
/// Dispatches to main queue to ensure thread safety regardless of caller context.
final class LiveOverlayProvider: OverlayProvider, @unchecked Sendable {
    private var overlayWindow: NSWindow?

    func showHighlight(frame: CGRect) {
        let cocoaFrame = Self.quartzToCocoa(frame)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.overlayWindow == nil {
                let window = NSWindow(
                    contentRect: cocoaFrame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.level = .floating
                window.isOpaque = false
                window.hasShadow = false
                window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3)
                window.ignoresMouseEvents = true
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                self.overlayWindow = window
            }

            self.overlayWindow?.setFrame(cocoaFrame, display: true)
            self.overlayWindow?.orderFront(nil)
        }
    }

    func hideHighlight() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayWindow?.orderOut(nil)
        }
    }

    // MARK: - Private

    /// Convert Quartz coordinates (origin top-left) to Cocoa coordinates (origin bottom-left).
    private static func quartzToCocoa(_ quartzFrame: CGRect) -> NSRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(
            x: quartzFrame.origin.x,
            y: primaryHeight - quartzFrame.origin.y - quartzFrame.height,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }
}
