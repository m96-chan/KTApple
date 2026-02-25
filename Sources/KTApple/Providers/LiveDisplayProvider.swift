import CoreGraphics
import Foundation
import KTAppleCore

final class LiveDisplayProvider: DisplayProvider {
    fileprivate var callback: (() -> Void)?

    func connectedDisplays() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)

        return displayIDs.map { id in
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
    provider.callback?()
}
