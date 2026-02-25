import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("TileSnapshot")
struct TileSnapshotTests {

    @Test func snapshotFromLeafTile() {
        let tile = Tile(proportion: 0.7, layoutDirection: .vertical)
        tile.addWindow(id: 42)
        tile.addWindow(id: 99)

        let snapshot = TileSnapshot(tile: tile)

        #expect(snapshot.id == tile.id)
        #expect(snapshot.proportion == 0.7)
        #expect(snapshot.layoutDirection == .vertical)
        #expect(snapshot.windowIDs.contains(42))
        #expect(snapshot.windowIDs.contains(99))
        #expect(snapshot.children.isEmpty)
    }

    @Test func snapshotFromTreePreservesStructure() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.6, layoutDirection: .vertical)
        let right = Tile(proportion: 0.4)
        root.addChild(left)
        root.addChild(right)
        right.addWindow(id: 10)

        let snapshot = TileSnapshot(tile: root)

        #expect(snapshot.children.count == 2)
        #expect(snapshot.children[0].proportion == 0.6)
        #expect(snapshot.children[0].layoutDirection == .vertical)
        #expect(snapshot.children[1].proportion == 0.4)
        #expect(snapshot.children[1].windowIDs == [10])
    }

    @Test func snapshotToTile() {
        let snapshot = TileSnapshot(
            proportion: 0.5,
            layoutDirection: .vertical,
            windowIDs: [1, 2],
            children: []
        )

        let tile = snapshot.toTile()

        #expect(tile.proportion == 0.5)
        #expect(tile.layoutDirection == .vertical)
        #expect(tile.windowIDs.contains(1))
        #expect(tile.windowIDs.contains(2))
        #expect(tile.isLeaf)
    }

    @Test func snapshotToTilePreservesTree() {
        let snapshot = TileSnapshot(
            layoutDirection: .horizontal,
            children: [
                TileSnapshot(proportion: 0.5),
                TileSnapshot(proportion: 0.5, windowIDs: [42]),
            ]
        )

        let tile = snapshot.toTile()

        #expect(tile.children.count == 2)
        #expect(tile.children[0].parent === tile)
        #expect(tile.children[1].windowIDs.contains(42))
    }

    @Test func roundTripTileToSnapshotToTile() {
        let original = Tile(proportion: 0.6, layoutDirection: .horizontal)
        let child1 = Tile(proportion: 0.3, layoutDirection: .vertical)
        let child2 = Tile(proportion: 0.7)
        original.addChild(child1)
        original.addChild(child2)
        child2.addWindow(id: 5)

        let restored = TileSnapshot(tile: original).toTile()

        #expect(restored.proportion == 0.6)
        #expect(restored.layoutDirection == .horizontal)
        #expect(restored.children.count == 2)
        #expect(restored.children[0].proportion == 0.3)
        #expect(restored.children[0].layoutDirection == .vertical)
        #expect(restored.children[1].proportion == 0.7)
        #expect(restored.children[1].windowIDs.contains(5))
    }

    @Test func jsonEncodeDecode() throws {
        let snapshot = TileSnapshot(
            proportion: 0.5,
            layoutDirection: .horizontal,
            windowIDs: [1, 2],
            children: [
                TileSnapshot(proportion: 0.5),
                TileSnapshot(proportion: 0.5),
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TileSnapshot.self, from: data)

        #expect(decoded.proportion == 0.5)
        #expect(decoded.layoutDirection == .horizontal)
        #expect(decoded.windowIDs == [1, 2])
        #expect(decoded.children.count == 2)
    }

    @Test func snapshotEquality() {
        let id = UUID()
        let a = TileSnapshot(id: id, proportion: 0.5, layoutDirection: .horizontal)
        let b = TileSnapshot(id: id, proportion: 0.5, layoutDirection: .horizontal)

        #expect(a == b)
    }

    @Test func windowIDsAreSorted() {
        let tile = Tile()
        tile.addWindow(id: 99)
        tile.addWindow(id: 1)
        tile.addWindow(id: 50)

        let snapshot = TileSnapshot(tile: tile)

        #expect(snapshot.windowIDs == [1, 50, 99])
    }
}
