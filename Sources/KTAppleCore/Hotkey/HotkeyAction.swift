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
    case switchProfile1
    case switchProfile2
    case switchProfile3
    case switchProfile4
    case switchProfile5
    case switchProfile6
    case switchProfile7
    case switchProfile8
    case switchProfile9
    case cycleWindowNext
    case cycleWindowPrev

    /// The 0-based profile index for `switchProfileN` actions, or nil for other actions.
    public var profileIndex: Int? {
        switch self {
        case .switchProfile1: return 0
        case .switchProfile2: return 1
        case .switchProfile3: return 2
        case .switchProfile4: return 3
        case .switchProfile5: return 4
        case .switchProfile6: return 5
        case .switchProfile7: return 6
        case .switchProfile8: return 7
        case .switchProfile9: return 8
        default: return nil
        }
    }
}
