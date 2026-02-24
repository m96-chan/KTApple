import Testing
import Foundation
@testable import KTAppleCore

@Suite("TileManager")
struct TileManagerTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Initialization

    @Test func initCreatesRootTile() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        #expect(manager.root.isLeaf)
        #expect(manager.root.proportion == 1.0)
    }

    // MARK: - Frame Calculation

    @Test func rootFrameCoversScreen() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let frame = manager.frame(for: manager.root)
        #expect(frame.origin.x == 0)
        #expect(frame.origin.y == 0)
        #expect(frame.width == 1920)
        #expect(frame.height == 1080)
    }

    @Test func childFramesHorizontalSplit() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.6)

        let leftFrame = manager.frame(for: left)
        let rightFrame = manager.frame(for: right)

        #expect(isApprox(leftFrame.origin.x, 0))
        #expect(isApprox(leftFrame.width, 1920 * 0.6))
        #expect(isApprox(leftFrame.height, 1080))

        #expect(isApprox(rightFrame.origin.x, 1920 * 0.6))
        #expect(isApprox(rightFrame.width, 1920 * 0.4))
        #expect(isApprox(rightFrame.height, 1080))
    }

    @Test func childFramesVerticalSplit() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (top, bottom) = manager.split(manager.root, direction: .vertical, ratio: 0.5)

        let topFrame = manager.frame(for: top)
        let bottomFrame = manager.frame(for: bottom)

        #expect(isApprox(topFrame.origin.y, 0))
        #expect(isApprox(topFrame.height, 540))
        #expect(isApprox(topFrame.width, 1920))

        #expect(isApprox(bottomFrame.origin.y, 540))
        #expect(isApprox(bottomFrame.height, 540))
    }

    @Test func nestedSplit() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let (topLeft, bottomLeft) = manager.split(left, direction: .vertical, ratio: 0.5)

        let tlFrame = manager.frame(for: topLeft)
        let blFrame = manager.frame(for: bottomLeft)
        let rFrame = manager.frame(for: right)

        #expect(isApprox(tlFrame.width, 960))
        #expect(isApprox(tlFrame.height, 540))
        #expect(isApprox(tlFrame.origin.x, 0))
        #expect(isApprox(tlFrame.origin.y, 0))

        #expect(isApprox(blFrame.width, 960))
        #expect(isApprox(blFrame.height, 540))
        #expect(isApprox(blFrame.origin.x, 0))
        #expect(isApprox(blFrame.origin.y, 540))

        #expect(isApprox(rFrame.width, 960))
        #expect(isApprox(rFrame.height, 1080))
        #expect(isApprox(rFrame.origin.x, 960))
    }

    // MARK: - Gaps

    @Test func frameWithGaps() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 10)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let leftFrame = manager.frame(for: left)
        let rightFrame = manager.frame(for: right)

        // Outer gap on left edge + half gap on inner edge
        #expect(leftFrame.origin.x == 10)
        #expect(isApprox(leftFrame.width, 960 - 10 - 5))  // outer left gap - half inner gap
        #expect(leftFrame.origin.y == 10)
        #expect(isApprox(leftFrame.height, 1080 - 20))  // top + bottom outer gap

        #expect(isApprox(rightFrame.origin.x, 960 + 5))  // half inner gap
        #expect(isApprox(rightFrame.width, 960 - 5 - 10))  // half inner gap - outer right gap
    }

    // MARK: - Split

    @Test func splitReturnsNewLeafTiles() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.6)

        #expect(left.isLeaf)
        #expect(right.isLeaf)
        #expect(!manager.root.isLeaf)
        #expect(manager.root.children.count == 2)
        #expect(isApprox(left.proportion, 0.6))
        #expect(isApprox(right.proportion, 0.4))
    }

    @Test func splitPreservesWindows() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.root.addWindow(id: 42)

        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        // Windows from the split tile move to the first child
        #expect(left.windowIDs.contains(42))
        #expect(manager.root.windowIDs.isEmpty)
    }

    // MARK: - Remove

    @Test func removeTileSiblingAbsorbsSpace() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.6)
        right.addWindow(id: 10)

        manager.remove(left)

        // right should absorb left's space — parent collapses
        #expect(manager.root.isLeaf || manager.root.children.count == 1)
        let frame = manager.frame(for: manager.leafTiles()[0])
        #expect(isApprox(frame.width, 1920, tolerance: 20))
    }

    @Test func removeLastChildCollapsesParent() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let (_, _) = manager.split(left, direction: .vertical, ratio: 0.5)

        // Remove right — left (non-leaf with 2 children) remains
        manager.remove(right)

        let leaves = manager.leafTiles()
        #expect(leaves.count == 2)
    }

    // MARK: - Resize

    @Test func resizeAdjustsSiblings() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        manager.resize(left, newProportion: 0.7)

        #expect(isApprox(left.proportion, 0.7))
        #expect(isApprox(right.proportion, 0.3))
    }

    @Test func resizeClampsToBounds() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        manager.resize(left, newProportion: 0.99)

        // Should be clamped so sibling has at least minProportion
        #expect(left.proportion <= 1.0 - TileManager.minProportion)
        #expect(right.proportion >= TileManager.minProportion)
    }

    @Test func resizeWithThreeSiblings() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let middle = Tile(proportion: 0.25)
        manager.root.children[1].proportion = 0.25
        manager.root.insertChild(middle, at: 1)

        let right = manager.root.children[2]
        manager.resize(left, newProportion: 0.6)

        let total = left.proportion + middle.proportion + right.proportion
        #expect(isApprox(total, 1.0))
    }

    // MARK: - Tile Lookup

    @Test func tileAtPointFindsCorrectLeaf() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (_, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let leftHit = manager.tileAt(point: CGPoint(x: 100, y: 540))
        let rightHit = manager.tileAt(point: CGPoint(x: 1500, y: 540))

        #expect(leftHit === manager.root.children[0])
        #expect(rightHit === manager.root.children[1])
    }

    @Test func tileAtPointReturnsNilOutsideScreen() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let result = manager.tileAt(point: CGPoint(x: -10, y: -10))
        #expect(result == nil)
    }

    @Test func tileAtPointNestedLayout() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let (topLeft, bottomLeft) = manager.split(left, direction: .vertical, ratio: 0.5)

        let topHit = manager.tileAt(point: CGPoint(x: 100, y: 100))
        let bottomHit = manager.tileAt(point: CGPoint(x: 100, y: 800))

        #expect(topHit === topLeft)
        #expect(bottomHit === bottomLeft)
    }

    // MARK: - Leaf Tiles

    @Test func leafTilesReturnsOnlyLeaves() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let leaves = manager.leafTiles()
        #expect(leaves.count == 2)
        #expect(leaves.contains { $0 === left })
        #expect(leaves.contains { $0 === right })
    }

    // MARK: - Adjacent Tile

    @Test func adjacentTileHorizontal() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        #expect(manager.adjacentTile(to: left, direction: .right) === right)
        #expect(manager.adjacentTile(to: right, direction: .left) === left)
        #expect(manager.adjacentTile(to: left, direction: .left) == nil)
        #expect(manager.adjacentTile(to: right, direction: .right) == nil)
    }

    @Test func adjacentTileVertical() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let (top, bottom) = manager.split(manager.root, direction: .vertical, ratio: 0.5)

        #expect(manager.adjacentTile(to: top, direction: .down) === bottom)
        #expect(manager.adjacentTile(to: bottom, direction: .up) === top)
    }

    // MARK: - Helpers

    private func isApprox(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1.0) -> Bool {
        abs(a - b) < tolerance
    }
}
