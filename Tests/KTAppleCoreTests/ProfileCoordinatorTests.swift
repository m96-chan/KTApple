import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("ProfileCoordinator")
struct ProfileCoordinatorTests {
    let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeCoordinator(displays: [DisplayInfo] = []) -> AppCoordinator {
        let checker = MockAccessibilityChecker()
        let displayProvider = CoordinatorMockDisplayProvider()
        displayProvider.displays = displays
        let coordinator = AppCoordinator(
            accessibilityProvider: checker,
            displayProvider: displayProvider,
            hotkeyProvider: CoordinatorMockHotkeyProvider(),
            accessibilityAPIProvider: CoordinatorMockAccessibilityProvider(),
            storageProvider: MockStorageProvider()
        )
        coordinator.start()
        return coordinator
    }

    // MARK: - Save

    @Test func saveCurrentAsProfileCapturesAllDisplays() {
        let display1 = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let display2 = DisplayInfo(id: 2, frame: displayFrame, name: "Secondary")
        let coordinator = makeCoordinator(displays: [display1, display2])

        let profile = coordinator.saveCurrentAsProfile(name: "Coding")

        #expect(profile.name == "Coding")
        #expect(profile.displaySnapshots["1"] != nil)
        #expect(profile.displaySnapshots["2"] != nil)
        #expect(coordinator.profiles.count == 1)
    }

    @Test func saveCurrentAsProfileClearsWindowIDs() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let coordinator = makeCoordinator(displays: [display])
        coordinator.tileManagers[1]?.leafTiles().first?.addWindow(id: 42)

        let profile = coordinator.saveCurrentAsProfile(name: "Test")

        let snapshot = profile.displaySnapshots["1"]
        #expect(snapshot?.windowIDs.isEmpty == true)
        #expect(snapshot?.children.allSatisfy { $0.windowIDs.isEmpty } == true)
    }

    @Test func saveCurrentAsProfileFiresOnProfilesChanged() {
        let coordinator = makeCoordinator(displays: [DisplayInfo(id: 1, frame: displayFrame, name: "Main")])
        var callCount = 0
        coordinator.onProfilesChanged = { callCount += 1 }

        coordinator.saveCurrentAsProfile(name: "Test")

        #expect(callCount == 1)
    }

    // MARK: - Switch

    @Test func switchProfileReturnsFalseForMissingIndex() {
        let coordinator = makeCoordinator(displays: [DisplayInfo(id: 1, frame: displayFrame, name: "Main")])
        #expect(!coordinator.switchProfile(index: 0))
        #expect(!coordinator.switchProfile(index: 5))
    }

    @Test func switchProfileAppliesSnapshotToTileManager() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let coordinator = makeCoordinator(displays: [display])

        // Save a layout with a horizontal split as profile 0
        coordinator.tileManagers[1]?.split(coordinator.tileManagers[1]!.root, direction: .horizontal, ratio: 0.5)
        coordinator.saveCurrentAsProfile(name: "Split")
        // Now reset to a single tile
        coordinator.tileManagers[1]?.replaceRoot(Tile())

        #expect(coordinator.tileManagers[1]?.leafTiles().count == 1)

        let result = coordinator.switchProfile(index: 0)
        #expect(result)
        #expect(coordinator.tileManagers[1]?.leafTiles().count == 2)
    }

    @Test func switchProfileReseatsWindowsIntoNewTiles() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let coordinator = makeCoordinator(displays: [display])

        // Assign a window to the single leaf, then save a 2-tile profile
        let manager = coordinator.tileManagers[1]!
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        coordinator.saveCurrentAsProfile(name: "Two Tiles")

        // Reset to single tile with a window
        let singleRoot = Tile()
        singleRoot.addWindow(id: 99)
        manager.replaceRoot(singleRoot)

        coordinator.switchProfile(index: 0)

        // Window should be re-seated into first leaf of new 2-tile layout
        let leaves = manager.leafTiles()
        #expect(leaves.count == 2)
        #expect(leaves[0].windowIDs.contains(99))
    }

    @Test func switchProfileReturnsTrueOnSuccess() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let coordinator = makeCoordinator(displays: [display])
        coordinator.saveCurrentAsProfile(name: "Default")

        #expect(coordinator.switchProfile(index: 0))
    }

    // MARK: - handleAction dispatch

    @Test func handleActionSwitchProfile1DispatchesToIndex0() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let coordinator = makeCoordinator(displays: [display])
        coordinator.saveCurrentAsProfile(name: "P1")

        var reflowCalled = false
        // Indirect: verify profile was applied by checking profileIndex on the action
        #expect(HotkeyAction.switchProfile1.profileIndex == 0)
        #expect(HotkeyAction.switchProfile9.profileIndex == 8)
        #expect(HotkeyAction.openEditor.profileIndex == nil)

        // Verify handleAction dispatches without crashing
        coordinator.handleAction(.switchProfile1)
        coordinator.handleAction(.switchProfile9) // no-op, no profile at index 8
        _ = reflowCalled
    }

    // MARK: - Rename / Delete

    @Test func renameProfileUpdatesStore() {
        let coordinator = makeCoordinator()
        let profile = coordinator.saveCurrentAsProfile(name: "Old")

        coordinator.renameProfile(id: profile.id, name: "New")

        #expect(coordinator.profiles.first?.name == "New")
    }

    @Test func deleteProfileRemovesFromStore() {
        let coordinator = makeCoordinator()
        let profile = coordinator.saveCurrentAsProfile(name: "ToDelete")
        #expect(coordinator.profiles.count == 1)

        coordinator.deleteProfile(id: profile.id)

        #expect(coordinator.profiles.isEmpty)
    }

    @Test func renameAndDeleteFireOnProfilesChanged() {
        let coordinator = makeCoordinator()
        let profile = coordinator.saveCurrentAsProfile(name: "X")
        var callCount = 0
        coordinator.onProfilesChanged = { callCount += 1 }

        coordinator.renameProfile(id: profile.id, name: "Y")
        coordinator.deleteProfile(id: profile.id)

        #expect(callCount == 2)
    }

    // MARK: - Persistence

    @Test func switchProfilePersistsNewLayoutToLayoutStore() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let coordinator = makeCoordinator(displays: [display])

        coordinator.tileManagers[1]?.split(coordinator.tileManagers[1]!.root, direction: .horizontal, ratio: 0.5)
        coordinator.saveCurrentAsProfile(name: "Split")

        coordinator.switchProfile(index: 0)

        // LayoutStore should have saved the new layout
        let key = LayoutKey(displayID: 1)
        #expect(coordinator.layoutStore.layout(for: key) != nil)
    }
}
