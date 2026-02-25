import Foundation

/// Delegate notified of drag-and-drop window placement events.
public protocol DragDropDelegate: AnyObject {
    func didDropWindow(_ windowID: UInt32, onTile tileID: UUID)
    func didCancelDrop()
}
