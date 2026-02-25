import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

// MARK: - Mocks

final class MockAccessibilityChecker: AccessibilityCheckProvider {
    var isTrustedResult = true
    var promptCount = 0

    func isTrusted(promptIfNeeded: Bool) -> Bool {
        promptCount += 1
        return isTrustedResult
    }
}

final class CoordinatorMockDisplayProvider: DisplayProvider {
    var displays: [DisplayInfo] = []
    var isObserving = false
    var onReconfiguration: (() -> Void)?

    func connectedDisplays() -> [DisplayInfo] { displays }

    func startObserving(callback: @escaping () -> Void) {
        isObserving = true
        onReconfiguration = callback
    }

    func stopObserving() {
        isObserving = false
        onReconfiguration = nil
    }
}

final class CoordinatorMockHotkeyProvider: HotkeyProvider {
    var registeredBindings: [HotkeyBinding] = []
    var unregisteredActions: Set<HotkeyAction> = []

    func register(_ binding: HotkeyBinding) {
        registeredBindings.append(binding)
    }

    func unregister(action: HotkeyAction) {
        unregisteredActions.insert(action)
    }
}

final class CoordinatorMockAccessibilityProvider: AccessibilityProvider {
    var windows: [WindowInfo] = []
    var operations: [CoordinatorAccessibilityOp] = []

    func discoverWindows() -> [WindowInfo] { windows }

    func moveWindow(id: UInt32, to position: CGPoint) {
        operations.append(.move(id, position))
    }

    func resizeWindow(id: UInt32, to size: CGSize) {
        operations.append(.resize(id, size))
    }

    func windowFrame(id: UInt32) -> CGRect? {
        windows.first { $0.id == id }?.frame
    }

    func focusWindow(id: UInt32) {
        operations.append(.focus(id))
    }
}

enum CoordinatorAccessibilityOp: Equatable {
    case move(UInt32, CGPoint)
    case resize(UInt32, CGSize)
    case focus(UInt32)
}

final class MockSpaceProvider: SpaceProvider {
    var spaceIDsByDisplay: [UInt32: [Int]] = [:]
    var activeSpaceByDisplay: [UInt32: Int] = [:]
    var isObserving = false
    var onSpaceChange: (() -> Void)?

    func activeSpaceID(for displayID: UInt32) -> Int {
        activeSpaceByDisplay[displayID] ?? 0
    }

    func spaceIDs(for displayID: UInt32) -> [Int] {
        spaceIDsByDisplay[displayID] ?? []
    }

    func startObserving(callback: @escaping () -> Void) {
        isObserving = true
        onSpaceChange = callback
    }

    func stopObserving() {
        isObserving = false
        onSpaceChange = nil
    }

    func simulateSpaceChange() {
        onSpaceChange?()
    }
}

final class MockWindowLifecycleProvider: WindowLifecycleProvider {
    var isMonitoring = false
    var onCreated: ((WindowInfo) -> Void)?
    var onDestroyed: ((UInt32) -> Void)?

    func startMonitoring(
        onWindowCreated: @escaping (WindowInfo) -> Void,
        onWindowDestroyed: @escaping (UInt32) -> Void
    ) {
        isMonitoring = true
        onCreated = onWindowCreated
        onDestroyed = onWindowDestroyed
    }

    func stopMonitoring() {
        isMonitoring = false
        onCreated = nil
        onDestroyed = nil
    }

    func simulateWindowCreated(_ window: WindowInfo) {
        onCreated?(window)
    }

    func simulateWindowDestroyed(_ windowID: UInt32) {
        onDestroyed?(windowID)
    }
}

@Suite("AppCoordinator")
struct AppCoordinatorTests {
    let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeCoordinator(
        trusted: Bool = true,
        displays: [DisplayInfo] = [],
        windows: [WindowInfo] = [],
        spaceProvider: MockSpaceProvider? = nil,
        windowLifecycleProvider: MockWindowLifecycleProvider? = nil
    ) -> (AppCoordinator, MockAccessibilityChecker, CoordinatorMockDisplayProvider, CoordinatorMockHotkeyProvider, CoordinatorMockAccessibilityProvider, MockStorageProvider) {
        let checker = MockAccessibilityChecker()
        checker.isTrustedResult = trusted

        let displayProvider = CoordinatorMockDisplayProvider()
        displayProvider.displays = displays

        let hotkeyProvider = CoordinatorMockHotkeyProvider()
        let accessibilityProvider = CoordinatorMockAccessibilityProvider()
        accessibilityProvider.windows = windows
        let storageProvider = MockStorageProvider()

        let coordinator = AppCoordinator(
            accessibilityProvider: checker,
            displayProvider: displayProvider,
            hotkeyProvider: hotkeyProvider,
            accessibilityAPIProvider: accessibilityProvider,
            storageProvider: storageProvider,
            spaceProvider: spaceProvider,
            windowLifecycleProvider: windowLifecycleProvider
        )

        return (coordinator, checker, displayProvider, hotkeyProvider, accessibilityProvider, storageProvider)
    }

    // MARK: - Startup Flow

    @Test func startChecksAccessibility() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, checker, _, _, _, _) = makeCoordinator(displays: [display])

        coordinator.start()

        #expect(checker.promptCount == 1)
        #expect(coordinator.accessibilityGranted)
    }

    @Test func startDeniedAccessibilityStillStartsButSkipsWindows() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, hotkeyProvider, accessibilityProvider, _) = makeCoordinator(trusted: false, displays: [display])

        coordinator.start()

        #expect(!coordinator.accessibilityGranted)
        // Coordinator starts, registers hotkeys, and creates tile managers even without accessibility
        #expect(coordinator.isRunning)
        #expect(!hotkeyProvider.registeredBindings.isEmpty)
        #expect(coordinator.tileManagers[1] != nil)
        // But window discovery is skipped
        #expect(accessibilityProvider.operations.isEmpty)
    }

    @Test func startLoadsLayouts() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, storage) = makeCoordinator(displays: [display])

        // Pre-populate storage with a saved layout
        let manager = TileManager(displayID: 1, screenFrame: displayFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.6)
        let store = LayoutStore(provider: storage)
        store.save(tileManager: manager, for: LayoutKey(displayID: 1))

        coordinator.start()

        #expect(coordinator.tileManagers[1] != nil)
    }

    @Test func startCreatesTileManagers() {
        let display1 = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let display2 = DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), name: "Secondary")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display1, display2])

        coordinator.start()

        #expect(coordinator.tileManagers.count == 2)
        #expect(coordinator.tileManagers[1] != nil)
        #expect(coordinator.tileManagers[2] != nil)
    }

    @Test func startRegistersHotkeys() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, hotkeyProvider, _, _) = makeCoordinator(displays: [display])

        coordinator.start()

        #expect(hotkeyProvider.registeredBindings.count == 13)
    }

    @Test func startAssignsWindows() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let window = WindowInfo(
            id: 42, pid: 1, title: "Test",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isResizable: true, isMinimized: false, isFullscreen: false,
            subrole: .standardWindow
        )
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], windows: [window])

        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let hasWindow = manager.root.leafTiles().contains { $0.windowIDs.contains(42) }
        #expect(hasWindow)
    }

    // MARK: - Display Events

    @Test func displayConnectCreatesTileManager() {
        let (coordinator, _, _, _, _, _) = makeCoordinator()
        coordinator.start()

        let display = DisplayInfo(id: 5, frame: displayFrame, name: "New")
        coordinator.displayDidConnect(display)

        #expect(coordinator.tileManagers[5] != nil)
    }

    @Test func displayDisconnectRemovesTileManager() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()
        #expect(coordinator.tileManagers[1] != nil)

        coordinator.displayDidDisconnect(displayID: 1)

        #expect(coordinator.tileManagers[1] == nil)
    }

    @Test func displayDisconnectSavesLayout() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, storage) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        manager.split(manager.root, direction: .horizontal, ratio: 0.6)

        coordinator.displayDidDisconnect(displayID: 1)

        let store = LayoutStore(provider: storage)
        store.loadFromDisk()
        let snapshot = store.layout(for: LayoutKey(displayID: 1))
        #expect(snapshot?.children.count == 2)
    }

    @Test func displayResizeUpdatesFrame() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let newFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        coordinator.displayDidResize(DisplayInfo(id: 1, frame: newFrame, name: "Main"))

        #expect(coordinator.tileManagers[1]?.screenFrame == newFrame)
    }

    @Test func displayConnectLoadsSavedLayout() {
        let (coordinator, _, _, _, _, storage) = makeCoordinator()
        coordinator.start()

        // Pre-save a layout for display 5
        let tempManager = TileManager(displayID: 5, screenFrame: displayFrame)
        tempManager.split(tempManager.root, direction: .vertical, ratio: 0.3)
        let store = LayoutStore(provider: storage)
        store.save(tileManager: tempManager, for: LayoutKey(displayID: 5))

        coordinator.displayDidConnect(DisplayInfo(id: 5, frame: displayFrame, name: "External"))

        #expect(coordinator.tileManagers[5] != nil)
    }

    // MARK: - Hotkey Actions

    @Test func focusActionChangesFocusedWindow() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)
        right.addWindow(id: 20)

        coordinator.setFocusedWindowID(10)
        coordinator.handleAction(.focusRight)

        #expect(coordinator.focusedWindowID == 20)
    }

    @Test func focusActionRaisesTargetWindow() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, accessibilityProvider, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)
        right.addWindow(id: 20)

        coordinator.setFocusedWindowID(10)
        accessibilityProvider.operations.removeAll()
        coordinator.handleAction(.focusRight)

        // Should call focusWindow to actually raise the window
        #expect(accessibilityProvider.operations.contains { op in
            if case .focus(20) = op { return true }
            return false
        })
    }

    @Test func moveActionMovesWindow() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, accessibilityProvider, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)

        coordinator.setFocusedWindowID(10)
        coordinator.handleAction(.moveRight)

        #expect(!left.windowIDs.contains(10))
        #expect(right.windowIDs.contains(10))
        #expect(!accessibilityProvider.operations.isEmpty)
    }

    @Test func expandTileAction() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, accessibilityProvider, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)
        right.addWindow(id: 20)

        let originalProportion = left.proportion
        coordinator.setFocusedWindowID(10)
        accessibilityProvider.operations.removeAll()
        coordinator.handleAction(.expandTile)

        #expect(left.proportion > originalProportion)
        // Windows should be resized on screen
        #expect(!accessibilityProvider.operations.isEmpty)
    }

    @Test func shrinkTileAction() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, accessibilityProvider, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)
        right.addWindow(id: 20)

        let originalProportion = left.proportion
        coordinator.setFocusedWindowID(10)
        accessibilityProvider.operations.removeAll()
        coordinator.handleAction(.shrinkTile)

        #expect(left.proportion < originalProportion)
        // Windows should be resized on screen
        #expect(!accessibilityProvider.operations.isEmpty)
    }

    @Test func toggleFloatingRemovesWindowFromTile() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)

        coordinator.setFocusedWindowID(10)
        coordinator.handleAction(.toggleFloating)

        #expect(!left.windowIDs.contains(10))
    }

    @Test func toggleMaximizeExpandsToFullScreen() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, accessibilityProvider, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)

        coordinator.setFocusedWindowID(10)
        coordinator.handleAction(.toggleMaximize)

        // Window should be removed from tile
        #expect(!left.windowIDs.contains(10))
        // Window should be resized to screen frame
        #expect(!accessibilityProvider.operations.isEmpty)
    }

    @Test func toggleMaximizeRestoresOriginalTile() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)

        coordinator.setFocusedWindowID(10)
        // Maximize
        coordinator.handleAction(.toggleMaximize)
        #expect(!left.windowIDs.contains(10))

        // Un-maximize
        coordinator.handleAction(.toggleMaximize)
        #expect(left.windowIDs.contains(10))
    }

    @Test func openEditorWorksWithoutFocusedWindow() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        // No focused window set — focusedWindowID is nil
        #expect(coordinator.focusedWindowID == nil)

        var editorOpened = false
        coordinator.onOpenEditor = { editorOpened = true }
        coordinator.handleAction(.openEditor)

        #expect(editorOpened)
    }

    // MARK: - Auto-Save

    @Test func splitTileAutoSaves() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, storage) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let rootID = manager.root.id
        coordinator.splitTile(displayID: 1, tileID: rootID, direction: .horizontal, ratio: 0.5)

        let store = LayoutStore(provider: storage)
        store.loadFromDisk()
        let snapshot = store.layout(for: LayoutKey(displayID: 1))
        #expect(snapshot?.children.count == 2)
    }

    // MARK: - Gap Size

    @Test func setGapSizeAffectsAllManagers() {
        let display1 = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let display2 = DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), name: "Secondary")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display1, display2])
        coordinator.start()

        coordinator.setGapSize(16)

        #expect(coordinator.tileManagers[1]?.gap == 16)
        #expect(coordinator.tileManagers[2]?.gap == 16)
    }

    // MARK: - Stop

    @Test func stopCleansUp() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, displayProvider, hotkeyProvider, _, _) = makeCoordinator(displays: [display])
        coordinator.start()
        #expect(coordinator.isRunning)

        coordinator.stop()

        #expect(!coordinator.isRunning)
        #expect(!displayProvider.isObserving)
        #expect(hotkeyProvider.unregisteredActions.count == 13)
    }

    // MARK: - Spaces Support

    @Test func startWithSpaceProviderUsesSpaceAwareKeys() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200, 300]
        spaceProvider.activeSpaceByDisplay[1] = 200

        let (coordinator, _, _, _, _, storage) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)

        // Pre-save a layout for display 1, workspace index 1 (space 200 is index 1)
        let tempManager = TileManager(displayID: 1, screenFrame: displayFrame)
        tempManager.split(tempManager.root, direction: .horizontal, ratio: 0.6)
        let store = LayoutStore(provider: storage)
        store.save(tileManager: tempManager, for: LayoutKey(displayID: 1, workspaceIndex: 1))

        coordinator.start()

        // The active manager should have loaded the layout for workspace index 1
        let manager = coordinator.tileManagers[1]!
        #expect(manager.root.children.count == 2)
    }

    @Test func spaceChangeSwapsActiveTileManager() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200]
        spaceProvider.activeSpaceByDisplay[1] = 100

        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)
        coordinator.start()

        let managerBeforeSwitch = coordinator.tileManagers[1]!
        // Split on space 100
        managerBeforeSwitch.split(managerBeforeSwitch.root, direction: .horizontal, ratio: 0.5)

        // Switch to space 200
        spaceProvider.activeSpaceByDisplay[1] = 200
        spaceProvider.simulateSpaceChange()

        let managerAfterSwitch = coordinator.tileManagers[1]!
        // New space should have a fresh manager (no split)
        #expect(managerAfterSwitch !== managerBeforeSwitch)
        #expect(managerAfterSwitch.root.isLeaf)
    }

    @Test func spaceChangeSavesCurrentLayout() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200]
        spaceProvider.activeSpaceByDisplay[1] = 100

        let (coordinator, _, _, _, _, storage) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        manager.split(manager.root, direction: .horizontal, ratio: 0.6)

        // Switch space
        spaceProvider.activeSpaceByDisplay[1] = 200
        spaceProvider.simulateSpaceChange()

        // Verify layout was saved for workspace index 0 (space 100)
        let store = LayoutStore(provider: storage)
        store.loadFromDisk()
        let snapshot = store.layout(for: LayoutKey(displayID: 1, workspaceIndex: 0))
        #expect(snapshot?.children.count == 2)
    }

    @Test func spaceSwitchBackRestoresCachedManager() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200]
        spaceProvider.activeSpaceByDisplay[1] = 100

        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)
        coordinator.start()

        let originalManager = coordinator.tileManagers[1]!
        originalManager.split(originalManager.root, direction: .horizontal, ratio: 0.5)

        // Switch to space 200
        spaceProvider.activeSpaceByDisplay[1] = 200
        spaceProvider.simulateSpaceChange()
        #expect(coordinator.tileManagers[1] !== originalManager)

        // Switch back to space 100
        spaceProvider.activeSpaceByDisplay[1] = 100
        spaceProvider.simulateSpaceChange()

        // Should get back the same cached manager instance
        #expect(coordinator.tileManagers[1] === originalManager)
    }

    @Test func spaceChangeNotifiesCallback() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200]
        spaceProvider.activeSpaceByDisplay[1] = 100

        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)
        var spaceChangedCount = 0
        coordinator.onSpaceChanged = { spaceChangedCount += 1 }
        coordinator.start()

        spaceProvider.activeSpaceByDisplay[1] = 200
        spaceProvider.simulateSpaceChange()

        #expect(spaceChangedCount == 1)
    }

    @Test func spaceChangeOnlyAffectsChangedDisplay() {
        let display1 = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let display2 = DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), name: "Secondary")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200]
        spaceProvider.spaceIDsByDisplay[2] = [300, 400]
        spaceProvider.activeSpaceByDisplay[1] = 100
        spaceProvider.activeSpaceByDisplay[2] = 300

        let window1 = WindowInfo(
            id: 10, pid: 1, title: "Win1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isResizable: true, isMinimized: false, isFullscreen: false,
            subrole: .standardWindow
        )
        let window2 = WindowInfo(
            id: 20, pid: 2, title: "Win2",
            frame: CGRect(x: 2020, y: 100, width: 800, height: 600),
            isResizable: true, isMinimized: false, isFullscreen: false,
            subrole: .standardWindow
        )

        let (coordinator, _, _, _, _, _) = makeCoordinator(
            displays: [display1, display2],
            windows: [window1, window2],
            spaceProvider: spaceProvider
        )
        coordinator.start()

        // Verify both displays have windows assigned
        let manager2 = coordinator.tileManagers[2]!
        let display2HasWindow = manager2.root.leafTiles().contains { $0.windowIDs.contains(20) }
        #expect(display2HasWindow)

        // Change space on display 1 only
        spaceProvider.activeSpaceByDisplay[1] = 200
        spaceProvider.simulateSpaceChange()

        // Display 2 windows should NOT be cleared — they weren't affected
        let manager2After = coordinator.tileManagers[2]!
        let display2StillHasWindow = manager2After.root.leafTiles().contains { $0.windowIDs.contains(20) }
        #expect(display2StillHasWindow)
    }

    @Test func currentWorkspaceIndexReturnsCorrectIndex() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100, 200, 300]
        spaceProvider.activeSpaceByDisplay[1] = 200

        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)
        coordinator.start()

        #expect(coordinator.currentWorkspaceIndex(for: 1) == 1)
    }

    // MARK: - Window Lifecycle

    @Test func windowCreatedDoesNotAutoAssignToTile() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let lifecycleProvider = MockWindowLifecycleProvider()
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], windowLifecycleProvider: lifecycleProvider)
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let newWindow = WindowInfo(
            id: 99, pid: 1, title: "New",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isResizable: true, isMinimized: false, isFullscreen: false,
            subrole: .standardWindow
        )
        lifecycleProvider.simulateWindowCreated(newWindow)

        // New windows should NOT be auto-assigned to tiles
        let hasWindow = left.windowIDs.contains(99) || right.windowIDs.contains(99)
        #expect(!hasWindow)
    }

    @Test func windowDestroyedRemovesFromTile() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let lifecycleProvider = MockWindowLifecycleProvider()
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], windowLifecycleProvider: lifecycleProvider)
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 42)

        lifecycleProvider.simulateWindowDestroyed(42)

        #expect(!left.windowIDs.contains(42))
    }

    @Test func stopStopsWindowLifecycleMonitoring() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let lifecycleProvider = MockWindowLifecycleProvider()
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], windowLifecycleProvider: lifecycleProvider)
        coordinator.start()
        #expect(lifecycleProvider.isMonitoring)

        coordinator.stop()
        #expect(!lifecycleProvider.isMonitoring)
    }

    @Test func stopStopsSpaceObserving() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let spaceProvider = MockSpaceProvider()
        spaceProvider.spaceIDsByDisplay[1] = [100]
        spaceProvider.activeSpaceByDisplay[1] = 100

        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display], spaceProvider: spaceProvider)
        coordinator.start()
        #expect(spaceProvider.isObserving)

        coordinator.stop()
        #expect(!spaceProvider.isObserving)
    }
}
