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
    private let spaceProvider: SpaceProvider?

    /// Per-display tile managers (active set — one per display, current Space).
    public private(set) var tileManagers: [UInt32: TileManager] = [:]

    /// Per-display, per-space tile manager cache.
    /// Key: displayID → [spaceID: TileManager]
    private var spaceManagers: [UInt32: [Int: TileManager]] = [:]

    /// Tracks the active space ID per display to detect changes.
    private var activeSpaceIDs: [UInt32: Int] = [:]

    /// Called when gap size changes, for persistence.
    public var onGapSizeChanged: ((CGFloat) -> Void)?

    /// Gap size applied to all tile managers.
    public var gapSize: CGFloat = 0 {
        didSet {
            for manager in tileManagers.values {
                manager.gap = gapSize
            }
            onGapSizeChanged?(gapSize)
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

    /// Callback when active space changes (for UI layer to react).
    public var onSpaceChanged: (() -> Void)?

    public init(
        accessibilityProvider: AccessibilityCheckProvider,
        displayProvider: DisplayProvider,
        hotkeyProvider: HotkeyProvider,
        accessibilityAPIProvider: AccessibilityProvider,
        storageProvider: StorageProvider,
        layoutFilePath: String = "layouts.json",
        spaceProvider: SpaceProvider? = nil
    ) {
        self.accessibilityProvider = accessibilityProvider
        self.displayObserver = DisplayObserver(provider: displayProvider)
        self.hotkeyManager = HotkeyManager(provider: hotkeyProvider)
        self.windowManager = WindowManager(provider: accessibilityAPIProvider)
        self.layoutStore = LayoutStore(provider: storageProvider, filePath: layoutFilePath)
        self.spaceProvider = spaceProvider

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
            setupDisplayManager(for: display)
        }

        // Window operations and hotkeys require accessibility permission
        if accessibilityGranted {
            let windows = windowManager.discoverWindows()
            assignWindowsToTiles(windows)
        }

        hotkeyManager.registerDefaults()
        displayObserver.startObserving()
        spaceProvider?.startObserving { [weak self] in
            self?.handleSpaceChanged()
        }

        isRunning = true
    }

    /// Stop the coordinator.
    public func stop() {
        displayObserver.stopObserving()
        spaceProvider?.stopObserving()
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
        setupDisplayManager(for: display)
    }

    public func displayDidDisconnect(displayID: UInt32) {
        if let manager = tileManagers[displayID] {
            let key = layoutKey(for: displayID)
            layoutStore.save(tileManager: manager, for: key)
        }
        tileManagers.removeValue(forKey: displayID)
        spaceManagers.removeValue(forKey: displayID)
        activeSpaceIDs.removeValue(forKey: displayID)
    }

    public func displayDidResize(_ display: DisplayInfo) {
        if let manager = tileManagers[display.id] {
            manager.screenFrame = display.frame
        }
    }

    // MARK: - Space Changes

    /// Handle active space change notification.
    private func handleSpaceChanged() {
        guard let spaceProvider else { return }

        var didChange = false

        for (displayID, manager) in tileManagers {
            let newSpaceID = spaceProvider.activeSpaceID(for: displayID)
            let oldSpaceID = activeSpaceIDs[displayID]

            guard newSpaceID != oldSpaceID, newSpaceID != 0 else { continue }

            // Save current layout for the old space
            if let oldSpace = oldSpaceID {
                let oldKey = LayoutKey(displayID: displayID, workspaceIndex: workspaceIndex(spaceID: oldSpace, displayID: displayID))
                layoutStore.save(tileManager: manager, for: oldKey)
            }

            // Look up or create manager for the new space
            let newManager: TileManager
            if let cached = spaceManagers[displayID]?[newSpaceID] {
                newManager = cached
            } else {
                newManager = TileManager(displayID: displayID, screenFrame: manager.screenFrame, gap: gapSize)
                let newKey = LayoutKey(displayID: displayID, workspaceIndex: workspaceIndex(spaceID: newSpaceID, displayID: displayID))
                layoutStore.apply(to: newManager, for: newKey)
                spaceManagers[displayID, default: [:]][newSpaceID] = newManager
            }

            tileManagers[displayID] = newManager
            activeSpaceIDs[displayID] = newSpaceID
            didChange = true
        }

        if didChange {
            // Re-discover and assign windows for new space
            if accessibilityGranted {
                // Clear window assignments on new managers
                for (_, manager) in tileManagers {
                    for leaf in manager.leafTiles() {
                        for wid in leaf.windowIDs {
                            leaf.removeWindow(id: wid)
                        }
                    }
                }
                let windows = windowManager.discoverWindows()
                assignWindowsToTiles(windows)
            }
            onSpaceChanged?()
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

        let key = layoutKey(for: displayID)
        layoutStore.save(tileManager: manager, for: key)

        return true
    }

    /// Current workspace index for a display (for use by UI layer).
    public func currentWorkspaceIndex(for displayID: UInt32) -> Int {
        guard spaceProvider != nil,
              let spaceID = activeSpaceIDs[displayID] else {
            return 0
        }
        return workspaceIndex(spaceID: spaceID, displayID: displayID)
    }

    // MARK: - Private

    /// Set up a tile manager for a display, using space-aware layout keys.
    private func setupDisplayManager(for display: DisplayInfo) {
        let manager = TileManager(displayID: display.id, screenFrame: display.frame, gap: gapSize)

        if let spaceProvider {
            let spaceID = spaceProvider.activeSpaceID(for: display.id)
            activeSpaceIDs[display.id] = spaceID
            let key = LayoutKey(displayID: display.id, workspaceIndex: workspaceIndex(spaceID: spaceID, displayID: display.id))
            layoutStore.apply(to: manager, for: key)
            spaceManagers[display.id, default: [:]][spaceID] = manager
        } else {
            let key = LayoutKey(displayID: display.id)
            layoutStore.apply(to: manager, for: key)
        }

        tileManagers[display.id] = manager
    }

    /// Build a LayoutKey for the current space on a display.
    private func layoutKey(for displayID: UInt32) -> LayoutKey {
        LayoutKey(displayID: displayID, workspaceIndex: currentWorkspaceIndex(for: displayID))
    }

    /// Convert a runtime space ID to a stable 0-based workspace index for persistence.
    private func workspaceIndex(spaceID: Int, displayID: UInt32) -> Int {
        guard let spaceProvider else { return 0 }
        let ids = spaceProvider.spaceIDs(for: displayID)
        return ids.firstIndex(of: spaceID) ?? 0
    }

    private func assignWindowsToTiles(_ windows: [WindowInfo]) {
        for window in windows {
            guard !WindowManager.shouldFloat(window) else { continue }

            // Find the tile manager for this window's display
            for (_, manager) in tileManagers {
                if manager.screenFrame.contains(window.frame.origin) {
                    if let targetTile = firstAvailableLeaf(in: manager) {
                        // Register only — don't resize on startup
                        targetTile.addWindow(id: window.id)
                        // Save current size so drag-out can restore it
                        windowManager.saveOriginalFrame(id: window.id)
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

        // Save current frame before tiling resize (only if not already saved)
        windowManager.saveOriginalFrame(id: windowID)

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
        windowManager.unassignWindow(id: windowID, from: tile)
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

    public func didDragWindowFromTile(_ windowID: UInt32) {
        guard let (_, tile) = findTileContaining(windowID: windowID) else { return }
        windowManager.unassignWindow(id: windowID, from: tile)
    }
}
