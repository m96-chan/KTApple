import Foundation
import KTAppleCore

/// Polls for window creation/destruction by comparing snapshots.
final class LiveWindowLifecycleProvider: WindowLifecycleProvider {
    private let accessibilityProvider: AccessibilityProvider
    private var timer: Timer?
    private var knownWindowIDs: Set<UInt32> = []
    private let interval: TimeInterval

    init(accessibilityProvider: AccessibilityProvider, interval: TimeInterval = 3.0) {
        self.accessibilityProvider = accessibilityProvider
        self.interval = interval
    }

    func startMonitoring(
        onWindowCreated: @escaping (WindowInfo) -> Void,
        onWindowDestroyed: @escaping (UInt32) -> Void
    ) {
        // Seed with current windows
        let current = accessibilityProvider.discoverWindows()
        knownWindowIDs = Set(current.map(\.id))

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let windows = self.accessibilityProvider.discoverWindows()
            let currentIDs = Set(windows.map(\.id))

            // Detect new windows
            for window in windows {
                if !self.knownWindowIDs.contains(window.id) {
                    onWindowCreated(window)
                }
            }

            // Detect destroyed windows
            for oldID in self.knownWindowIDs {
                if !currentIDs.contains(oldID) {
                    onWindowDestroyed(oldID)
                }
            }

            self.knownWindowIDs = currentIDs
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
