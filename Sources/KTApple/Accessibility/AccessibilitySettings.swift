import AppKit
@preconcurrency import ApplicationServices
import Foundation
import KTAppleCore

/// Routes the user to the Accessibility permission UI.
///
/// The `x-apple.systempreferences:` deep link is not API — its anchors have
/// changed between macOS releases, and `NSWorkspace.open` reports failure by
/// returning `false`, which the previous code discarded. A silently ignored
/// return value is exactly how "the app opened nothing and never explained
/// itself" happens after an OS upgrade. See issue #37.
///
/// The system prompt is preferred wherever possible: macOS renders it itself,
/// so it cannot fall out of date the way a hardcoded URL can.
enum AccessibilitySettings {
    private static let log = AppLog.logger(for: "AccessibilitySettings")

    /// Deep links to the Accessibility pane, most specific first.
    ///
    /// Verified working on macOS 26.6.2; the rest are fallbacks for releases
    /// where the first anchor stops resolving.
    private static let paneURLs = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy",
        "x-apple.systempreferences:com.apple.preference.security",
    ]

    /// Ask macOS to show its own "grant accessibility access" prompt.
    ///
    /// Returns the current trust state. When untrusted, the system displays a
    /// dialog with a working button into the right Settings pane — no URL of
    /// ours involved.
    @discardableResult
    static func requestViaSystemPrompt() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the Accessibility settings pane, trying each known deep link and
    /// finally System Settings itself.
    ///
    /// Returns `false` only if nothing could be opened at all.
    @discardableResult
    static func openPane() -> Bool {
        for candidate in paneURLs {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                log.info("opened settings pane via \(candidate, privacy: .public)")
                return true
            }
            log.notice("settings URL rejected: \(candidate, privacy: .public)")
        }

        // Last resort: the app itself, so the user at least lands in Settings.
        let settingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if FileManager.default.fileExists(atPath: settingsApp.path) {
            NSWorkspace.shared.openApplication(at: settingsApp, configuration: .init())
            log.notice("fell back to launching System Settings directly")
            return true
        }

        log.error("could not open the Accessibility settings pane by any known route")
        return false
    }
}
