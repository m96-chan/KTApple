import Foundation

/// Cursor styles for resize feedback.
public enum CursorStyle: Sendable {
    case arrow
    case resizeHorizontal
    case resizeVertical
}

/// Protocol abstracting cursor appearance changes for testability.
public protocol CursorProvider: AnyObject {
    func setCursor(_ style: CursorStyle)
}
