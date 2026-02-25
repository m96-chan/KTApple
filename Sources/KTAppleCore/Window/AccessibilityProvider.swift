import CoreGraphics
import Foundation

/// Protocol abstracting macOS Accessibility API calls for testability.
///
/// On macOS, the concrete implementation uses `AXUIElement`.
/// In tests, a mock implementation is used.
public protocol AccessibilityProvider {
    func discoverWindows() -> [WindowInfo]
    func moveWindow(id: UInt32, to position: CGPoint)
    func resizeWindow(id: UInt32, to size: CGSize)
    func windowFrame(id: UInt32) -> CGRect?
}
