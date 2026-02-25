import Foundation

/// Delegate notified of drag-and-drop window placement events.
public protocol DragDropDelegate: AnyObject {
    func didDropWindow(_ windowID: UInt32, onTile tileID: UUID)
    func didCancelDrop()
    /// Called when a window is dragged without Shift (normal drag), indicating
    /// the user wants to move it freely — should unassign from tile if tiled.
    func didDragWindowFromTile(_ windowID: UInt32)
}
