import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        if !AccessibilityChecker.isTrusted(promptIfNeeded: true) {
            NSLog("KTApple: Accessibility permission not granted")
        }
    }
}
