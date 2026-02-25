import CoreGraphics
import Foundation

/// Central coordinator wiring all components together.
///
/// Owns the DisplayObserver, HotkeyManager, WindowManager, LayoutStore,
/// and per-display TileManagers. Orchestrates startup, hotkey dispatch,
/// display events, and layout persistence.
public final class AppCoordinator: DisplayObserverDelegate {
    private let accessibilityProvider: AccessibilityCheckProvider
    private let displayObserver: DisplayObserver
    private let hotkeyManager: HotkeyManager
    private let windowManager: WindowManager
    public let layoutStore: LayoutStore

    /// Per-display tile managers.
    public private(set) var tileManagers: [UInt32: TileManager] = [:]

    /// Gap size applied to all tile managers.
    public var gapSize: CGFloat = 8 {
        didSet {
            for manager in tileManagers.values {
                manager.gap = gapSize
            }
        }
    }

    /// Currently focused window ID for hotkey actions.
    public var focusedWindowID: UInt32?

    /// Whether the coordinator has started.
    public private(set) var isRunning = false

    /// Whether accessibility permission was granted.
    public private(set) var accessibilityGranted = false

    /// Callback for actions that require the UI layer (e.g. opening the tile editor).
    public var onOpenEditor: (() -> Void)?

    public init(
        accessibilityProvider: AccessibilityCheckProvider,
        displayProvider: DisplayProvider,
        hotkeyProvider: HotkeyProvider,
        accessibilityAPIProvider: AccessibilityProvider,
        storageProvider: StorageProvider,
        layoutFilePath: String = "layouts.json"
    ) {
        self.accessibilityProvider = accessibilityProvider
        self.displayObserver = DisplayObserver(provider: displayProvider)
        self.hotkeyManager = HotkeyManager(provider: hotkeyProvider)
        self.windowManager = WindowManager(provider: accessibilityAPIProvider)
        self.layoutStore = LayoutStore(provider: storageProvider, filePath: layoutFilePath)

        displayObserver.delegate = self
        hotkeyManager.onHotkey = { [weak self] action in
            self?.handleAction(action)
        }
    }

    // MARK: - Lifecycle

    /// Start the coordinator: check accessibility, load layouts, discover windows, register hotkeys.
    public func start() {
        accessibilityGranted = accessibilityProvider.isTrusted(promptIfNeeded: false)

        layoutStore.loadFromDisk()

        // Discover displays and create tile managers (always, even without accessibility)
        let displays = displayObserver.connectedDisplays()
        for display in displays {
            createTileManager(for: display)
            let key = LayoutKey(displayID: display.id)
            layoutStore.apply(to: tileManagers[display.id]!, for: key)
        }

        // Window operations and hotkeys require accessibility permission
        if accessibilityGranted {
            let windows = windowManager.discoverWindows()
            assignWindowsToTiles(windows)
        }

        hotkeyManager.registerDefaults()
        displayObserver.startObserving()

        isRunning = true
    }

    /// Stop the coordinator.
    public func stop() {
        displayObserver.stopObserving()
        hotkeyManager.unregisterAll()
        isRunning = false
    }

    // MARK: - Hotkey Dispatch

    /// Handle a triggered hotkey action.
    public func handleAction(_ action: HotkeyAction) {
        guard let windowID = focusedWindowID else { return }

        switch action {
        case .focusLeft:
            focusAdjacent(windowID: windowID, direction: .left)
        case .focusRight:
            focusAdjacent(windowID: windowID, direction: .right)
        case .focusUp:
            focusAdjacent(windowID: windowID, direction: .up)
        case .focusDown:
            focusAdjacent(windowID: windowID, direction: .down)
        case .moveLeft:
            moveWindow(windowID: windowID, direction: .left)
        case .moveRight:
            moveWindow(windowID: windowID, direction: .right)
        case .moveUp:
            moveWindow(windowID: windowID, direction: .up)
        case .moveDown:
            moveWindow(windowID: windowID, direction: .down)
        case .expandTile:
            resizeFocusedTile(windowID: windowID, delta: 0.05)
        case .shrinkTile:
            resizeFocusedTile(windowID: windowID, delta: -0.05)
        case .toggleFloating:
            toggleFloating(windowID: windowID)
        case .openEditor:
            onOpenEditor?()
        case .toggleMaximize:
            break
        }
    }

    // MARK: - Display Events

    public func displayDidConnect(_ display: DisplayInfo) {
        createTileManager(for: display)
        let key = LayoutKey(displayID: display.id)
        layoutStore.apply(to: tileManagers[display.id]!, for: key)
    }

    public func displayDidDisconnect(displayID: UInt32) {
        if let manager = tileManagers[displayID] {
            let key = LayoutKey(displayID: displayID)
            layoutStore.save(tileManager: manager, for: key)
        }
        tileManagers.removeValue(forKey: displayID)
    }

    public func displayDidResize(_ display: DisplayInfo) {
        if let manager = tileManagers[display.id] {
            manager.screenFrame = display.frame
        }
    }

    // MARK: - Public Operations

    /// Set the gap size for all tile managers.
    public func setGapSize(_ size: CGFloat) {
        gapSize = size
    }

    /// Set the focused window ID.
    public func setFocusedWindowID(_ id: UInt32?) {
        focusedWindowID = id
    }

    /// Split a tile in a specific tile manager, with auto-save.
    @discardableResult
    public func splitTile(displayID: UInt32, tileID: UUID, direction: LayoutDirection, ratio: CGFloat = 0.5) -> Bool {
        guard let manager = tileManagers[displayID] else { return false }
        guard let tile = findTile(id: tileID, in: manager.root), tile.isLeaf else { return false }

        manager.split(tile, direction: direction, ratio: ratio)

        let key = LayoutKey(displayID: displayID)
        layoutStore.save(tileManager: manager, for: key)

        return true
    }

    // MARK: - Private

    private func createTileManager(for display: DisplayInfo) {
        let manager = TileManager(displayID: display.id, screenFrame: display.frame, gap: gapSize)
        tileManagers[display.id] = manager
    }

    private func assignWindowsToTiles(_ windows: [WindowInfo]) {
        for window in windows {
            guard !WindowManager.shouldFloat(window) else { continue }

            // Find the tile manager for this window's display
            for (_, manager) in tileManagers {
                if manager.screenFrame.contains(window.frame.origin) {
                    if let targetTile = firstAvailableLeaf(in: manager) {
                        windowManager.assignWindow(id: window.id, to: targetTile, tileManager: manager)
                    }
                    break
                }
            }
        }
    }

    private func firstAvailableLeaf(in manager: TileManager) -> Tile? {
        manager.leafTiles().first { $0.windowIDs.isEmpty } ?? manager.leafTiles().first
    }

    private func findTileContaining(windowID: UInt32) -> (TileManager, Tile)? {
        for (_, manager) in tileManagers {
            if let tile = findTileWithWindow(windowID: windowID, in: manager.root) {
                return (manager, tile)
            }
        }
        return nil
    }

    private func findTileWithWindow(windowID: UInt32, in tile: Tile) -> Tile? {
        if tile.windowIDs.contains(windowID) { return tile }
        for child in tile.children {
            if let found = findTileWithWindow(windowID: windowID, in: child) { return found }
        }
        return nil
    }

    private func findTile(id: UUID, in tile: Tile) -> Tile? {
        if tile.id == id { return tile }
        for child in tile.children {
            if let found = findTile(id: id, in: child) { return found }
        }
        return nil
    }

    private func focusAdjacent(windowID: UInt32, direction: NavigationDirection) {
        guard let (manager, tile) = findTileContaining(windowID: windowID) else { return }
        guard let adjacent = manager.adjacentTile(to: tile, direction: direction) else { return }
        if let targetWindowID = adjacent.windowIDs.first {
            focusedWindowID = targetWindowID
        }
    }

    private func moveWindow(windowID: UInt32, direction: NavigationDirection) {
        guard let (manager, currentTile) = findTileContaining(windowID: windowID) else { return }
        guard let adjacentTile = manager.adjacentTile(to: currentTile, direction: direction) else { return }

        currentTile.removeWindow(id: windowID)
        adjacentTile.addWindow(id: windowID)

        let frame = manager.frame(for: adjacentTile)
        windowManager.setWindowFrame(id: windowID, frame: frame)
    }

    private func resizeFocusedTile(windowID: UInt32, delta: CGFloat) {
        guard let (manager, tile) = findTileContaining(windowID: windowID) else { return }
        let newProportion = tile.proportion + delta
        manager.resize(tile, newProportion: newProportion)
    }

    private func toggleFloating(windowID: UInt32) {
        guard let (_, tile) = findTileContaining(windowID: windowID) else { return }
        tile.removeWindow(id: windowID)
    }
}

// MARK: - DragDropDelegate

extension AppCoordinator: DragDropDelegate {
    public func didDropWindow(_ windowID: UInt32, onTile tileID: UUID) {
        for (_, manager) in tileManagers {
            if let tile = findTile(id: tileID, in: manager.root) {
                windowManager.assignWindow(id: windowID, to: tile, tileManager: manager)
                break
            }
        }
    }

    public func didCancelDrop() {}
}
