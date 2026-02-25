import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("WindowManager")
struct WindowManagerTests {

    // MARK: - Helpers

    private func makeManager() -> (WindowManager, MockAccessibilityProvider) {
        let provider = MockAccessibilityProvider()
        let manager = WindowManager(provider: provider)
        return (manager, provider)
    }

    private func sampleWindow(
        id: UInt32 = 1,
        pid: Int32 = 100,
        title: String = "Test Window",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        isResizable: Bool = true,
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        subrole: WindowSubrole = .standardWindow
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: pid,
            title: title,
            frame: frame,
            isResizable: isResizable,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen,
            subrole: subrole
        )
    }

    // MARK: - Window Discovery

    @Test func discoverWindowsReturnsAll() {
        let (manager, provider) = makeManager()
        provider.windows = [
            sampleWindow(id: 1, title: "Window 1"),
            sampleWindow(id: 2, title: "Window 2"),
            sampleWindow(id: 3, title: "Window 3"),
        ]

        let windows = manager.discoverWindows()
        #expect(windows.count == 3)
        #expect(windows.map(\.id) == [1, 2, 3])
    }

    @Test func discoverWindowsReturnsEmptyWhenNone() {
        let (manager, _) = makeManager()
        let windows = manager.discoverWindows()
        #expect(windows.isEmpty)
    }

    // MARK: - Move & Resize

    @Test func moveWindowUpdatesPosition() {
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 1)]

        let newOrigin = CGPoint(x: 100, y: 200)
        manager.moveWindow(id: 1, to: newOrigin)

        #expect(provider.lastMoveWindowID == 1)
        #expect(provider.lastMovePosition == newOrigin)
    }

    @Test func resizeWindowUpdatesSize() {
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 1)]

        let newSize = CGSize(width: 1024, height: 768)
        manager.resizeWindow(id: 1, to: newSize)

        #expect(provider.lastResizeWindowID == 1)
        #expect(provider.lastResizeSize == newSize)
    }

    @Test func setWindowFrameUsesThreeStepResize() {
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 1)]

        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)
        manager.setWindowFrame(id: 1, frame: frame)

        // Three-step: size → position → size
        #expect(provider.operationLog == [
            .resize(id: 1, size: frame.size),
            .move(id: 1, position: frame.origin),
            .resize(id: 1, size: frame.size),
        ])
    }

    // MARK: - Window-Tile Assignment

    @Test func assignWindowToTile() {
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 1)]

        let tile = Tile()
        let tileManager = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: 0)

        manager.assignWindow(id: 1, to: tile, tileManager: tileManager)

        #expect(tile.windowIDs.contains(1))
        #expect(provider.operationLog.count == 3)  // three-step resize
    }

    @Test func unassignWindow() {
        let (manager, _) = makeManager()
        let tile = Tile()
        tile.addWindow(id: 1)

        manager.unassignWindow(id: 1, from: tile)
        #expect(!tile.windowIDs.contains(1))
    }

    @Test func assignWindowSavesOriginalSize() {
        let originalFrame = CGRect(x: 50, y: 50, width: 400, height: 300)
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 1, frame: originalFrame)]
        _ = manager.discoverWindows()

        let tile = Tile()
        let tileManager = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: 0)
        manager.assignWindow(id: 1, to: tile, tileManager: tileManager)
        provider.operationLog.removeAll()

        // Unassign should restore the original size only
        manager.unassignWindow(id: 1, from: tile)
        #expect(!tile.windowIDs.contains(1))
        #expect(provider.operationLog == [
            .resize(id: 1, size: originalFrame.size),
        ])
    }

    @Test func assignWindowDoesNotOverwriteSavedSize() {
        let originalFrame = CGRect(x: 50, y: 50, width: 400, height: 300)
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 1, frame: originalFrame)]
        _ = manager.discoverWindows()

        let tile1 = Tile()
        let tile2 = Tile()
        let tileManager = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: 0)
        tileManager.split(tileManager.root, direction: .horizontal, ratio: 0.5)

        // First assign saves original size
        manager.assignWindow(id: 1, to: tile1, tileManager: tileManager)

        // Re-assign to different tile should NOT overwrite the saved original
        manager.assignWindow(id: 1, to: tile2, tileManager: tileManager)
        provider.operationLog.removeAll()

        manager.unassignWindow(id: 1, from: tile2)
        // Should restore to the ORIGINAL size, not the tile1 size
        #expect(provider.operationLog == [
            .resize(id: 1, size: originalFrame.size),
        ])
    }

    @Test func unassignWindowWithoutSavedFrameDoesNotResize() {
        let (manager, provider) = makeManager()
        let tile = Tile()
        tile.addWindow(id: 1)

        // No assignWindow was called, so no original frame saved
        manager.unassignWindow(id: 1, from: tile)
        #expect(!tile.windowIDs.contains(1))
        #expect(provider.operationLog.isEmpty)
    }

    // MARK: - Auto-Float Detection

    @Test func dialogWindowsShouldFloat() {
        let window = sampleWindow(subrole: .dialog)
        #expect(WindowManager.shouldFloat(window))
    }

    @Test func nonResizableWindowsShouldFloat() {
        let window = sampleWindow(isResizable: false)
        #expect(WindowManager.shouldFloat(window))
    }

    @Test func standardResizableWindowsShouldNotFloat() {
        let window = sampleWindow(isResizable: true, subrole: .standardWindow)
        #expect(!WindowManager.shouldFloat(window))
    }

    @Test func minimizedWindowsShouldFloat() {
        let window = sampleWindow(isMinimized: true)
        #expect(WindowManager.shouldFloat(window))
    }

    // MARK: - Window Tracking

    @Test func trackedWindowsUpdatedAfterDiscover() {
        let (manager, provider) = makeManager()
        provider.windows = [
            sampleWindow(id: 1),
            sampleWindow(id: 2),
        ]

        _ = manager.discoverWindows()
        #expect(manager.trackedWindows.count == 2)
        #expect(manager.trackedWindows[1] != nil)
        #expect(manager.trackedWindows[2] != nil)
    }

    @Test func windowInfoForID() {
        let (manager, provider) = makeManager()
        provider.windows = [sampleWindow(id: 42, title: "Hello")]

        _ = manager.discoverWindows()
        let info = manager.windowInfo(for: 42)

        #expect(info?.title == "Hello")
    }

    @Test func windowInfoReturnsNilForUnknown() {
        let (manager, _) = makeManager()
        #expect(manager.windowInfo(for: 999) == nil)
    }
}

// MARK: - Mock

final class MockAccessibilityProvider: AccessibilityProvider {
    var windows: [WindowInfo] = []
    var lastMoveWindowID: UInt32?
    var lastMovePosition: CGPoint?
    var lastResizeWindowID: UInt32?
    var lastResizeSize: CGSize?
    var operationLog: [Operation] = []

    enum Operation: Equatable {
        case move(id: UInt32, position: CGPoint)
        case resize(id: UInt32, size: CGSize)
    }

    func discoverWindows() -> [WindowInfo] {
        windows
    }

    func windowFrame(id: UInt32) -> CGRect? {
        windows.first { $0.id == id }?.frame
    }

    func moveWindow(id: UInt32, to position: CGPoint) {
        lastMoveWindowID = id
        lastMovePosition = position
        operationLog.append(.move(id: id, position: position))
    }

    func resizeWindow(id: UInt32, to size: CGSize) {
        lastResizeWindowID = id
        lastResizeSize = size
        operationLog.append(.resize(id: id, size: size))
    }
}
