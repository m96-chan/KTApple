import Foundation

/// Actions that can be triggered by keyboard shortcuts.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable, Hashable {
    case openEditor
    case focusLeft
    case focusRight
    case focusUp
    case focusDown
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case toggleFloating
    case toggleMaximize
    case expandTile
    case shrinkTile
}
