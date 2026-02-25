import AppKit
import KTAppleCore

final class LiveCursorProvider: CursorProvider {
    func setCursor(_ style: CursorStyle) {
        switch style {
        case .arrow:
            NSCursor.arrow.set()
        case .resizeHorizontal:
            NSCursor.resizeLeftRight.set()
        case .resizeVertical:
            NSCursor.resizeUpDown.set()
        }
    }
}
