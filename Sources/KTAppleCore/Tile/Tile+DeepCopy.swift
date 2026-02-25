import Foundation

extension Tile {
    /// Create a recursive deep copy of this tile tree with new UUIDs.
    public func deepCopy() -> Tile {
        deepCopyWithMapping().copy
    }

    /// Create a recursive deep copy with a mapping from original UUIDs to new UUIDs.
    public func deepCopyWithMapping() -> (copy: Tile, mapping: [UUID: UUID]) {
        var mapping: [UUID: UUID] = [:]
        let copy = deepCopyRecursive(mapping: &mapping)
        return (copy, mapping)
    }

    private func deepCopyRecursive(mapping: inout [UUID: UUID]) -> Tile {
        let copy = Tile(proportion: proportion, layoutDirection: layoutDirection)
        mapping[id] = copy.id

        for windowID in windowIDs {
            copy.addWindow(id: windowID)
        }

        for child in children {
            let childCopy = child.deepCopyRecursive(mapping: &mapping)
            copy.addChild(childCopy)
        }

        return copy
    }
}
