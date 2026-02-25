import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("LayoutPreset")
struct LayoutPresetTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func halvesPreset() {
        let tree = LayoutPreset.halves.buildTree()
        let leaves = tree.leafTiles()

        #expect(leaves.count == 2)
        #expect(tree.layoutDirection == .horizontal)
        #expect(isApprox(leaves[0].proportion, 0.5))
        #expect(isApprox(leaves[1].proportion, 0.5))
    }

    @Test func thirdsPreset() {
        let tree = LayoutPreset.thirds.buildTree()
        let leaves = tree.leafTiles()

        #expect(leaves.count == 3)
        #expect(tree.layoutDirection == .horizontal)
        let third: CGFloat = 1.0 / 3.0
        for leaf in leaves {
            #expect(isApprox(leaf.proportion, third))
        }
    }

    @Test func masterStackPreset() {
        let tree = LayoutPreset.masterStack.buildTree()
        let leaves = tree.leafTiles()

        #expect(leaves.count == 3)
        #expect(tree.layoutDirection == .horizontal)
        #expect(isApprox(tree.children[0].proportion, 0.6))
        #expect(isApprox(tree.children[1].proportion, 0.4))
        #expect(tree.children[1].layoutDirection == .vertical)
    }

    @Test func gridPreset() {
        let tree = LayoutPreset.grid.buildTree()
        let leaves = tree.leafTiles()

        #expect(leaves.count == 4)
        #expect(tree.children.count == 2)
        #expect(tree.children[0].children.count == 2)
        #expect(tree.children[1].children.count == 2)
    }

    @Test func centerFocusPreset() {
        let tree = LayoutPreset.centerFocus.buildTree()
        let leaves = tree.leafTiles()

        #expect(leaves.count == 3)
        #expect(tree.layoutDirection == .horizontal)
        #expect(isApprox(tree.children[0].proportion, 0.2))
        #expect(isApprox(tree.children[1].proportion, 0.6))
        #expect(isApprox(tree.children[2].proportion, 0.2))
    }

    @Test func applyPresetReplacesTree() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.7)

        LayoutPreset.thirds.apply(to: manager)

        #expect(manager.root.children.count == 3)
        #expect(manager.leafTiles().count == 3)
    }

    @Test func allPresetsHaveDisplayNames() {
        for preset in LayoutPreset.allCases {
            #expect(!preset.displayName.isEmpty)
        }
    }

    @Test func presetJsonRoundTrip() throws {
        for preset in LayoutPreset.allCases {
            let tree = preset.buildTree()
            let snapshot = TileSnapshot(tile: tree)
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(TileSnapshot.self, from: data)
            let restored = decoded.toTile()
            #expect(restored.leafTiles().count == tree.leafTiles().count)
        }
    }

    private func isApprox(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.01) -> Bool {
        abs(a - b) < tolerance
    }
}
