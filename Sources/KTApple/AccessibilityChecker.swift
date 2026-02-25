import AppKit
@preconcurrency import ApplicationServices
import KTAppleCore

final class LiveAccessibilityChecker: AccessibilityCheckProvider {
    func isTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
