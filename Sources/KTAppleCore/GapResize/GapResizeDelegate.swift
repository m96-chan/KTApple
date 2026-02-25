import Foundation

/// Delegate notified of boundary resize events.
public protocol GapResizeDelegate: AnyObject {
    func didResize(_ boundary: TileBoundary, affectedTiles: [UUID])
}
