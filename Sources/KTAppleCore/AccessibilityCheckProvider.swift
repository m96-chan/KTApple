import Foundation

/// Protocol abstracting accessibility permission checks for testability.
public protocol AccessibilityCheckProvider {
    func isTrusted(promptIfNeeded: Bool) -> Bool
}
