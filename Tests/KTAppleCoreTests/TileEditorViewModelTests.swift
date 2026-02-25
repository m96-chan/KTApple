import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("TileEditorViewModel")
struct TileEditorViewModelTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeVM() -> (TileEditorViewModel, TileManager) {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let vm = TileEditorViewModel(tileManager: manager)
        return (vm, manager)
    }

    private func makeVMWithStore() -> (TileEditorViewModel, TileManager, LayoutStore, MockStorageProvider) {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let key = LayoutKey(displayID: 1)
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let vm = TileEditorViewModel(tileManager: manager, layoutStore: store, layoutKey: key)
        return (vm, manager, store, provider)
    }

    // MARK: - Init / Working Copy

    @Test func initCreatesWorkingCopy() {
        let (vm, manager) = makeVM()

        #expect(vm.workingManager.root.id != manager.root.id)
        #expect(!vm.isDirty)
        #expect(vm.hoveredTileID == nil)
        #expect(vm.selectedTileID == nil)
    }

    @Test func workingCopyIsIndependent() {
        let (vm, manager) = makeVM()
        vm.workingManager.root.layoutDirection = .vertical

        #expect(manager.root.layoutDirection == .horizontal)
    }

    // MARK: - Split

    @Test func splitLeafTile() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id

        let result = vm.splitTile(id: rootID, direction: .horizontal, ratio: 0.6)

        #expect(result)
        #expect(vm.workingManager.root.children.count == 2)
        #expect(vm.isDirty)
    }

    @Test func splitNonLeafReturnsFalse() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal)

        let result = vm.splitTile(id: rootID, direction: .vertical)
        #expect(!result)
    }

    @Test func splitUnknownIDReturnsFalse() {
        let (vm, _) = makeVM()
        let result = vm.splitTile(id: UUID(), direction: .horizontal)
        #expect(!result)
    }

    // MARK: - Delete

    @Test func deleteLeafTile() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal)

        let childID = vm.workingManager.root.children[1].id
        let result = vm.deleteTile(id: childID)

        #expect(result)
        #expect(vm.isDirty)
    }

    @Test func deleteRootReturnsFalse() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id

        let result = vm.deleteTile(id: rootID)
        #expect(!result)
    }

    @Test func deleteUnknownIDReturnsFalse() {
        let (vm, _) = makeVM()
        let result = vm.deleteTile(id: UUID())
        #expect(!result)
    }

    @Test func deleteClearsSelection() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal)

        let childID = vm.workingManager.root.children[0].id
        vm.selectTile(id: childID)
        vm.deleteTile(id: childID)

        #expect(vm.selectedTileID == nil)
    }

    // MARK: - Resize

    @Test func resizeTile() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal, ratio: 0.5)

        let leftID = vm.workingManager.root.children[0].id
        let result = vm.resizeTile(id: leftID, newProportion: 0.7)

        #expect(result)
        #expect(vm.isDirty)
        let left = vm.workingManager.root.children[0]
        #expect(isApprox(left.proportion, 0.7))
    }

    @Test func resizeRootReturnsFalse() {
        let (vm, _) = makeVM()
        let result = vm.resizeTile(id: vm.workingManager.root.id, newProportion: 0.5)
        #expect(!result)
    }

    // MARK: - Boundary Resize

    @Test func resizeBoundary() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal, ratio: 0.5)

        let leftID = vm.workingManager.root.children[0].id
        let rightID = vm.workingManager.root.children[1].id

        let result = vm.resizeBoundary(leftTileID: leftID, rightTileID: rightID, positionFraction: 0.7)

        #expect(result)
        #expect(vm.isDirty)
        let left = vm.workingManager.root.children[0]
        let right = vm.workingManager.root.children[1]
        #expect(isApprox(left.proportion + right.proportion, 1.0))
    }

    @Test func resizeBoundaryWithInvalidIDsReturnsFalse() {
        let (vm, _) = makeVM()
        let result = vm.resizeBoundary(leftTileID: UUID(), rightTileID: UUID(), positionFraction: 0.5)
        #expect(!result)
    }

    // MARK: - Apply / Cancel

    @Test func applyUpdatesLiveManager() {
        let (vm, manager) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal)

        vm.apply()

        #expect(manager.root.children.count == 2)
        #expect(!vm.isDirty)
    }

    @Test func applySavesToLayoutStore() {
        let (vm, _, store, _) = makeVMWithStore()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal)

        vm.apply()

        let key = LayoutKey(displayID: 1)
        let snapshot = store.layout(for: key)
        #expect(snapshot != nil)
        #expect(snapshot?.children.count == 2)
    }

    @Test func cancelResetsWorkingCopy() {
        let (vm, _) = makeVM()
        let originalRootID = vm.workingManager.root.id
        vm.splitTile(id: originalRootID, direction: .horizontal)
        #expect(vm.isDirty)

        vm.cancel()

        #expect(!vm.isDirty)
        #expect(vm.workingManager.root.isLeaf)
        #expect(vm.selectedTileID == nil)
    }

    // MARK: - Presets

    @Test func applyPreset() {
        let (vm, _) = makeVM()
        vm.applyPreset(.thirds)

        #expect(vm.workingManager.root.children.count == 3)
        #expect(vm.isDirty)
        #expect(vm.selectedTileID == nil)
    }

    // MARK: - Hover / Selection

    @Test func hoverAtPointFindsLeaf() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal, ratio: 0.5)

        let leftID = vm.workingManager.root.children[0].id
        vm.hoverAtPoint(CGPoint(x: 100, y: 540))

        #expect(vm.hoveredTileID == leftID)
    }

    @Test func hoverOutsideScreenClearsHover() {
        let (vm, _) = makeVM()
        vm.hoverAtPoint(CGPoint(x: -10, y: -10))
        #expect(vm.hoveredTileID == nil)
    }

    @Test func selectTile() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.selectTile(id: rootID)
        #expect(vm.selectedTileID == rootID)

        vm.selectTile(id: nil)
        #expect(vm.selectedTileID == nil)
    }

    // MARK: - Boundaries

    @Test func boundariesDetected() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal, ratio: 0.5)

        let boundaries = vm.boundaries()

        #expect(boundaries.count == 1)
        #expect(boundaries[0].axis == .horizontal)
    }

    // MARK: - Tile Frames

    @Test func tileFramesReturnsAllLeaves() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        vm.splitTile(id: rootID, direction: .horizontal, ratio: 0.5)

        let frames = vm.tileFrames()

        #expect(frames.count == 2)
        #expect(isApprox(frames[0].frame.width, 960))
        #expect(isApprox(frames[1].frame.width, 960))
    }

    // MARK: - Tile Lookup

    @Test func tileWithIDFound() {
        let (vm, _) = makeVM()
        let rootID = vm.workingManager.root.id
        let tile = vm.tile(withID: rootID)
        #expect(tile != nil)
        #expect(tile?.id == rootID)
    }

    @Test func tileWithUnknownIDReturnsNil() {
        let (vm, _) = makeVM()
        #expect(vm.tile(withID: UUID()) == nil)
    }

    // MARK: - Helpers

    private func isApprox(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1.0) -> Bool {
        abs(a - b) < tolerance
    }
}
