import AppKit
import CoreGraphics
import Foundation
import KTAppleCore
import os.log

final class LiveDisplayProvider: DisplayProvider {
    fileprivate static let log = AppLog.logger(for: "LiveDisplayProvider")
    fileprivate var callback: (() -> Void)?

    func connectedDisplays() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)

        let screens = NSScreen.screens
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

        return displayIDs.map { id in
            // Find matching NSScreen to get visible frame (excludes menu bar & dock)
            if let screen = screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            }) {
                let cocoa = screen.visibleFrame
                // Convert Cocoa (bottom-left origin) → Quartz (top-left origin)
                let quartzFrame = CGRect(
                    x: cocoa.origin.x,
                    y: primaryHeight - cocoa.origin.y - cocoa.height,
                    width: cocoa.width,
                    height: cocoa.height
                )
                return DisplayInfo(id: id, frame: quartzFrame, name: "Display \(id)")
            }
            // Fallback to full bounds
            let bounds = CGDisplayBounds(id)
            return DisplayInfo(id: id, frame: bounds, name: "Display \(id)")
        }
    }

    func startObserving(callback: @escaping () -> Void) {
        self.callback = callback
        CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func stopObserving() {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        callback = nil
    }
}

private func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    // Skip the "begin" phase; act on the "end" phase
    if flags.contains(.beginConfigurationFlag) { return }
    let provider = Unmanaged<LiveDisplayProvider>.fromOpaque(userInfo).takeUnretainedValue()
    LiveDisplayProvider.log.debug("displayReconfigurationCallback: display=\(display) flags=\(flags.rawValue)")
    // CG display reconfiguration callback fires on an arbitrary thread.
    // Capture the callback and dispatch to main to avoid data races.
    nonisolated(unsafe) let callback = provider.callback
    DispatchQueue.main.async {
        callback?()
    }
}
