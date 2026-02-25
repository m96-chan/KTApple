import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("Tile Deep Copy")
struct TileDeepCopyTests {

    // MARK: - Tile.deepCopy()

    @Test func deepCopyLeafTile() {
        let tile = Tile(proportion: 0.6, layoutDirection: .vertical)
        tile.addWindow(id: 42)
        tile.addWindow(id: 99)

        let copy = tile.deepCopy()

        #expect(copy.id != tile.id)
        #expect(copy.proportion == 0.6)
        #expect(copy.layoutDirection == .vertical)
        #expect(copy.windowIDs == [42, 99])
        #expect(copy.isLeaf)
        #expect(copy.parent == nil)
    }

    @Test func deepCopyPreservesTreeStructure() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5, layoutDirection: .vertical)
        let right = Tile(proportion: 0.5)
        let topLeft = Tile(proportion: 0.4)
        let bottomLeft = Tile(proportion: 0.6)
        root.addChild(left)
        root.addChild(right)
        left.addChild(topLeft)
        left.addChild(bottomLeft)
        topLeft.addWindow(id: 1)
        right.addWindow(id: 2)

        let copy = root.deepCopy()

        #expect(copy.children.count == 2)
        #expect(copy.layoutDirection == .horizontal)
        let copyLeft = copy.children[0]
        let copyRight = copy.children[1]
        #expect(copyLeft.children.count == 2)
        #expect(copyLeft.layoutDirection == .vertical)
        #expect(copyLeft.proportion == 0.5)
        #expect(copyRight.isLeaf)
        #expect(copyRight.proportion == 0.5)
        #expect(copyRight.windowIDs == [2])

        let copyTopLeft = copyLeft.children[0]
        let copyBottomLeft = copyLeft.children[1]
        #expect(copyTopLeft.proportion == 0.4)
        #expect(copyBottomLeft.proportion == 0.6)
        #expect(copyTopLeft.windowIDs == [1])
    }

    @Test func deepCopyGeneratesNewUUIDs() {
        let root = Tile(layoutDirection: .horizontal)
        let child = Tile(proportion: 1.0)
        root.addChild(child)

        let copy = root.deepCopy()

        #expect(copy.id != root.id)
        #expect(copy.children[0].id != child.id)
    }

    @Test func deepCopySetsParentReferences() {
        let root = Tile(layoutDirection: .horizontal)
        let child1 = Tile(proportion: 0.5)
        let child2 = Tile(proportion: 0.5)
        root.addChild(child1)
        root.addChild(child2)

        let copy = root.deepCopy()

        #expect(copy.parent == nil)
        #expect(copy.children[0].parent === copy)
        #expect(copy.children[1].parent === copy)
    }

    @Test func deepCopyIsIndependent() {
        let root = Tile(layoutDirection: .horizontal)
        let child = Tile(proportion: 0.5)
        root.addChild(child)

        let copy = root.deepCopy()
        copy.children[0].proportion = 0.9
        copy.layoutDirection = .vertical

        #expect(child.proportion == 0.5)
        #expect(root.layoutDirection == .horizontal)
    }

    // MARK: - Tile.deepCopyWithMapping()

    @Test func deepCopyWithMappingReturnsCorrectMapping() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5)
        let right = Tile(proportion: 0.5)
        root.addChild(left)
        root.addChild(right)

        let (copy, mapping) = root.deepCopyWithMapping()

        #expect(mapping.count == 3)
        #expect(mapping[root.id] == copy.id)
        #expect(mapping[left.id] == copy.children[0].id)
        #expect(mapping[right.id] == copy.children[1].id)
    }

    // MARK: - TileManager.replaceRoot()

    @Test func replaceRootSwapsTree() {
        let manager = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let newRoot = Tile(proportion: 1.0, layoutDirection: .vertical)
        let child = Tile(proportion: 1.0)
        newRoot.addChild(child)

        manager.replaceRoot(newRoot)

        #expect(manager.root === newRoot)
        #expect(manager.root.layoutDirection == .vertical)
        #expect(manager.root.children.count == 1)
    }

    // MARK: - TileManager.deepCopy()

    @Test func tileManagerDeepCopy() {
        let manager = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: 12)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.6)
        left.addWindow(id: 10)
        right.addWindow(id: 20)

        let copy = manager.deepCopy()

        #expect(copy.displayID == 1)
        #expect(copy.screenFrame == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(copy.gap == 12)
        #expect(copy.root.id != manager.root.id)
        #expect(copy.root.children.count == 2)
        #expect(copy.root.children[0].windowIDs == [10])
        #expect(copy.root.children[1].windowIDs == [20])
    }

    @Test func tileManagerDeepCopyIsIndependent() {
        let manager = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let copy = manager.deepCopy()
        copy.gap = 20
        copy.root.layoutDirection = .vertical

        #expect(manager.gap == 8)
        #expect(manager.root.layoutDirection == .horizontal)
    }
}
