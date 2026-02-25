import CoreGraphics
import Foundation

extension TileManager {
    /// Create a deep copy of this TileManager with a fully independent tile tree.
    public func deepCopy() -> TileManager {
        let copy = TileManager(displayID: displayID, screenFrame: screenFrame, gap: gap)
        copy.replaceRoot(root.deepCopy())
        return copy
    }
}
