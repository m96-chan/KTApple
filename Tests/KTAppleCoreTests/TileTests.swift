import Testing
import Foundation
@testable import KTAppleCore

@Suite("Tile")
struct TileTests {

    // MARK: - Initialization

    @Test func initDefaults() {
        let tile = Tile()
        #expect(tile.proportion == 1.0)
        #expect(tile.layoutDirection == .horizontal)
        #expect(tile.children.isEmpty)
        #expect(tile.parent == nil)
        #expect(tile.windowIDs.isEmpty)
        #expect(tile.isLeaf)
    }

    @Test func initWithCustomValues() {
        let tile = Tile(proportion: 0.6, layoutDirection: .vertical)
        #expect(tile.proportion == 0.6)
        #expect(tile.layoutDirection == .vertical)
    }

    // MARK: - Tree Structure

    @Test func addChildUpdatesParent() {
        let parent = Tile()
        let child = Tile(proportion: 0.5)
        parent.addChild(child)

        #expect(parent.children.count == 1)
        #expect(child.parent === parent)
        #expect(!parent.isLeaf)
    }

    @Test func addMultipleChildren() {
        let parent = Tile(layoutDirection: .horizontal)
        let child1 = Tile(proportion: 0.6)
        let child2 = Tile(proportion: 0.4)
        parent.addChild(child1)
        parent.addChild(child2)

        #expect(parent.children.count == 2)
        #expect(parent.children[0] === child1)
        #expect(parent.children[1] === child2)
    }

    @Test func removeChildUpdatesParent() {
        let parent = Tile()
        let child = Tile(proportion: 1.0)
        parent.addChild(child)
        parent.removeChild(child)

        #expect(parent.children.isEmpty)
        #expect(child.parent == nil)
        #expect(parent.isLeaf)
    }

    @Test func removeChildByIndex() {
        let parent = Tile(layoutDirection: .horizontal)
        let child1 = Tile(proportion: 0.5)
        let child2 = Tile(proportion: 0.5)
        parent.addChild(child1)
        parent.addChild(child2)

        parent.removeChild(at: 0)
        #expect(parent.children.count == 1)
        #expect(parent.children[0] === child2)
        #expect(child1.parent == nil)
    }

    @Test func insertChildAtIndex() {
        let parent = Tile(layoutDirection: .horizontal)
        let child1 = Tile(proportion: 0.5)
        let child2 = Tile(proportion: 0.5)
        parent.addChild(child1)
        parent.addChild(child2)

        let inserted = Tile(proportion: 0.3)
        parent.insertChild(inserted, at: 1)
        #expect(parent.children.count == 3)
        #expect(parent.children[1] === inserted)
        #expect(inserted.parent === parent)
    }

    // MARK: - Sibling Navigation

    @Test func siblingIndex() {
        let parent = Tile(layoutDirection: .horizontal)
        let child1 = Tile(proportion: 0.5)
        let child2 = Tile(proportion: 0.5)
        parent.addChild(child1)
        parent.addChild(child2)

        #expect(child1.siblingIndex == 0)
        #expect(child2.siblingIndex == 1)
    }

    @Test func nextAndPreviousSibling() {
        let parent = Tile(layoutDirection: .horizontal)
        let a = Tile(proportion: 0.33)
        let b = Tile(proportion: 0.34)
        let c = Tile(proportion: 0.33)
        parent.addChild(a)
        parent.addChild(b)
        parent.addChild(c)

        #expect(a.previousSibling == nil)
        #expect(a.nextSibling === b)
        #expect(b.previousSibling === a)
        #expect(b.nextSibling === c)
        #expect(c.previousSibling === b)
        #expect(c.nextSibling == nil)
    }

    // MARK: - Window Assignment

    @Test func addAndRemoveWindow() {
        let tile = Tile()
        tile.addWindow(id: 100)
        tile.addWindow(id: 200)

        #expect(tile.windowIDs.count == 2)
        #expect(tile.windowIDs.contains(100))
        #expect(tile.windowIDs.contains(200))

        tile.removeWindow(id: 100)
        #expect(tile.windowIDs.count == 1)
        #expect(!tile.windowIDs.contains(100))
    }

    @Test func addDuplicateWindowIgnored() {
        let tile = Tile()
        tile.addWindow(id: 100)
        tile.addWindow(id: 100)

        #expect(tile.windowIDs.count == 1)
    }

    // MARK: - Descendants

    @Test func leafTiles() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5, layoutDirection: .vertical)
        let right = Tile(proportion: 0.5)
        let topLeft = Tile(proportion: 0.5)
        let bottomLeft = Tile(proportion: 0.5)

        root.addChild(left)
        root.addChild(right)
        left.addChild(topLeft)
        left.addChild(bottomLeft)

        let leaves = root.leafTiles()
        #expect(leaves.count == 3)
        #expect(leaves.contains { $0 === topLeft })
        #expect(leaves.contains { $0 === bottomLeft })
        #expect(leaves.contains { $0 === right })
    }

    @Test func allDescendants() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5)
        let right = Tile(proportion: 0.5)
        root.addChild(left)
        root.addChild(right)

        let descendants = root.descendants()
        #expect(descendants.count == 2)
    }

    // MARK: - Find by ID

    @Test func findByIDReturnsMatchingTile() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5)
        let right = Tile(proportion: 0.5, layoutDirection: .vertical)
        let topRight = Tile(proportion: 0.5)
        let bottomRight = Tile(proportion: 0.5)
        root.addChild(left)
        root.addChild(right)
        right.addChild(topRight)
        right.addChild(bottomRight)

        #expect(root.find(id: root.id) === root)
        #expect(root.find(id: left.id) === left)
        #expect(root.find(id: topRight.id) === topRight)
        #expect(root.find(id: bottomRight.id) === bottomRight)
    }

    @Test func findByIDReturnsNilForUnknown() {
        let root = Tile()
        #expect(root.find(id: UUID()) == nil)
    }

    // MARK: - Find by Window ID

    @Test func findByWindowIDReturnsCorrectLeaf() {
        let root = Tile(layoutDirection: .horizontal)
        let left = Tile(proportion: 0.5)
        let right = Tile(proportion: 0.5)
        root.addChild(left)
        root.addChild(right)
        left.addWindow(id: 42)
        right.addWindow(id: 99)

        #expect(root.findTile(containingWindow: 42) === left)
        #expect(root.findTile(containingWindow: 99) === right)
    }

    @Test func findByWindowIDReturnsNilWhenNotFound() {
        let root = Tile()
        root.addWindow(id: 1)
        #expect(root.findTile(containingWindow: 999) == nil)
    }

    // MARK: - Depth

    @Test func depth() {
        let root = Tile()
        let child = Tile(proportion: 1.0)
        let grandchild = Tile(proportion: 1.0)
        root.addChild(child)
        child.addChild(grandchild)

        #expect(root.depth == 0)
        #expect(child.depth == 1)
        #expect(grandchild.depth == 2)
    }
}
