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
}

enum CoordinatorAccessibilityOp {
    case move(UInt32, CGPoint)
    case resize(UInt32, CGSize)
}

@Suite("AppCoordinator")
struct AppCoordinatorTests {
    let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeCoordinator(
        trusted: Bool = true,
        displays: [DisplayInfo] = [],
        windows: [WindowInfo] = []
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
            storageProvider: storageProvider
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
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)

        let originalProportion = left.proportion
        coordinator.setFocusedWindowID(10)
        coordinator.handleAction(.expandTile)

        #expect(left.proportion > originalProportion)
    }

    @Test func shrinkTileAction() {
        let display = DisplayInfo(id: 1, frame: displayFrame, name: "Main")
        let (coordinator, _, _, _, _, _) = makeCoordinator(displays: [display])
        coordinator.start()

        let manager = coordinator.tileManagers[1]!
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        left.addWindow(id: 10)

        let originalProportion = left.proportion
        coordinator.setFocusedWindowID(10)
        coordinator.handleAction(.shrinkTile)

        #expect(left.proportion < originalProportion)
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
}
