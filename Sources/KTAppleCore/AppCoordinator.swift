import CoreGraphics
import Foundation
import os.log

/// Central coordinator wiring all components together.
///
/// Owns the DisplayObserver, HotkeyManager, WindowManager, LayoutStore,
/// and per-display TileManagers. Orchestrates startup, hotkey dispatch,
/// display events, and layout persistence.
public final class AppCoordinator: DisplayObserverDelegate {
    private static let log = AppLog.logger(for: "AppCoordinator")
    private let accessibilityProvider: AccessibilityCheckProvider
    private let displayObserver: DisplayObserver
    private let hotkeyManager: HotkeyManager
    private let windowManager: WindowManager
    public let layoutStore: LayoutStore
    public let hotkeyStore: HotkeyStore
    public let profileStore: ProfileStore
    private let spaceProvider: SpaceProvider?
    private let windowLifecycleProvider: WindowLifecycleProvider?

    /// Per-display tile managers (active set — one per display, current Space).
    public private(set) var tileManagers: [UInt32: TileManager] = [:]

    /// Per-display, per-space tile manager cache.
    /// Key: displayID → [spaceID: TileManager]
    private var spaceManagers: [UInt32: [Int: TileManager]] = [:]

    /// Tracks the active space ID per display to detect changes.
    private var activeSpaceIDs: [UInt32: Int] = [:]

    /// Tracks maximized windows: windowID → (displayID, tileID, originalProportion).
    private var maximizedWindows: [UInt32: MaximizedState] = [:]

    /// Called when gap size changes, for persistence.
    public var onGapSizeChanged: ((CGFloat) -> Void)?

    /// Gap size applied to all tile managers.
    public var gapSize: CGFloat = 0 {
        didSet {
            for (displayID, manager) in tileManagers {
                manager.gap = gapSize
                reflowWindows(for: displayID)
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

    /// Currently active hotkey bindings (default or user-customised).
    public var activeHotkeyBindings: [HotkeyAction: HotkeyBinding] { hotkeyManager.activeBindings }

    /// All saved layout profiles in order.
    public var profiles: [LayoutProfile] { profileStore.profiles }

    /// The name of the currently active profile, or nil if none has been switched to.
    public private(set) var activeProfileName: String?

    /// ID of the currently active profile (for stable rename tracking).
    private var activeProfileID: UUID?

    /// Called when profiles change (add/rename/delete), so the UI layer can rebuild menus.
    public var onProfilesChanged: (() -> Void)?

    /// Called when the active profile changes (switch, rename of active profile).
    public var onActiveProfileChanged: ((String?) -> Void)?

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
        hotkeyStore: HotkeyStore? = nil,
        profileFilePath: String = "profiles.json",
        spaceProvider: SpaceProvider? = nil,
        windowLifecycleProvider: WindowLifecycleProvider? = nil
    ) {
        self.accessibilityProvider = accessibilityProvider
        self.displayObserver = DisplayObserver(provider: displayProvider)
        self.hotkeyManager = HotkeyManager(provider: hotkeyProvider)
        self.windowManager = WindowManager(provider: accessibilityAPIProvider)
        self.layoutStore = LayoutStore(provider: storageProvider, filePath: layoutFilePath)
        self.hotkeyStore = hotkeyStore ?? HotkeyStore(provider: storageProvider, filePath: "hotkeys.json")
        self.profileStore = ProfileStore(provider: storageProvider, filePath: profileFilePath)
        self.spaceProvider = spaceProvider
        self.windowLifecycleProvider = windowLifecycleProvider

        displayObserver.delegate = self
        hotkeyManager.onHotkey = { [weak self] action in
            self?.handleAction(action)
        }
    }

    // MARK: - Lifecycle

    /// Start the coordinator: check accessibility, load layouts, discover windows, register hotkeys.
    public func start() {
        guard !isRunning else { return }

        accessibilityGranted = accessibilityProvider.isTrusted(promptIfNeeded: false)
        Self.log.info("start: accessibilityGranted=\(self.accessibilityGranted)")

        layoutStore.loadFromDisk()

        // Discover displays and create tile managers (always, even without accessibility)
        let displays = displayObserver.connectedDisplays()
        Self.log.info("start: discovered \(displays.count) display(s)")
        for display in displays {
            setupDisplayManager(for: display)
        }

        // Window operations and hotkeys require accessibility permission
        if accessibilityGranted {
            let windows = windowManager.discoverWindows()
            Self.log.info("start: discovered \(windows.count) window(s)")
            assignWindowsToTiles(windows)
        }

        hotkeyStore.loadFromDisk()
        let mergedBindings = HotkeyManager.defaultBindings.map {
            hotkeyStore.customBinding(for: $0.action) ?? $0
        }
        hotkeyManager.registerAll(mergedBindings)
        profileStore.loadFromDisk()
        displayObserver.startObserving()
        spaceProvider?.startObserving { [weak self] in
            self?.handleSpaceChanged()
        }

        if accessibilityGranted {
            windowLifecycleProvider?.startMonitoring(
                onWindowCreated: { [weak self] window in
                    self?.handleWindowCreated(window)
                },
                onWindowDestroyed: { [weak self] windowID in
                    self?.handleWindowDestroyed(windowID)
                }
            )
        }

        isRunning = true
        Self.log.info("start: coordinator running")
    }

    /// Stop the coordinator.
    public func stop() {
        Self.log.info("stop")
        displayObserver.stopObserving()
        spaceProvider?.stopObserving()
        windowLifecycleProvider?.stopMonitoring()
        hotkeyManager.unregisterAll()
        isRunning = false
    }

    // MARK: - Hotkey Dispatch

    /// Handle a triggered hotkey action.
    public func handleAction(_ action: HotkeyAction) {
        // Actions that don't require a focused window
        if action == .openEditor {
            Self.log.debug("handleAction: openEditor")
            onOpenEditor?()
            return
        }

        // Profile switch actions don't require a focused window
        if let index = action.profileIndex {
            Self.log.debug("handleAction: switchProfile index=\(index)")
            switchProfile(index: index)
            return
        }

        guard let windowID = focusedWindowID else { return }
        Self.log.debug("handleAction: \(String(describing: action)) windowID=\(windowID)")

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
        case .toggleMaximize:
            toggleMaximize(windowID: windowID)
        case .cycleWindowNext:
            cycleWindow(windowID: windowID, forward: true)
        case .cycleWindowPrev:
            cycleWindow(windowID: windowID, forward: false)
        case .openEditor,
             .switchProfile1, .switchProfile2, .switchProfile3,
             .switchProfile4, .switchProfile5, .switchProfile6,
             .switchProfile7, .switchProfile8, .switchProfile9:
            break // handled above
        }
    }

    // MARK: - Display Events

    public func displayDidConnect(_ display: DisplayInfo) {
        Self.log.info("displayDidConnect: id=\(display.id) frame=\(String(describing: display.frame))")
        setupDisplayManager(for: display)
    }

    public func displayDidDisconnect(displayID: UInt32) {
        Self.log.info("displayDidDisconnect: id=\(displayID)")
        if let manager = tileManagers[displayID] {
            let key = layoutKey(for: displayID)
            layoutStore.save(tileManager: manager, for: key)
        }
        tileManagers.removeValue(forKey: displayID)
        spaceManagers.removeValue(forKey: displayID)
        activeSpaceIDs.removeValue(forKey: displayID)
    }

    public func displayDidResize(_ display: DisplayInfo) {
        Self.log.info("displayDidResize: id=\(display.id) frame=\(String(describing: display.frame))")
        if let manager = tileManagers[display.id] {
            manager.screenFrame = display.frame
            reflowWindows(for: display.id)
        }
    }

    // MARK: - Space Changes

    /// Handle active space change notification.
    private func handleSpaceChanged() {
        guard let spaceProvider else { return }
        Self.log.info("handleSpaceChanged")

        var changedDisplayIDs: Set<UInt32> = []

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
            changedDisplayIDs.insert(displayID)
        }

        if !changedDisplayIDs.isEmpty {
            // Re-discover and assign windows only for changed displays
            if accessibilityGranted {
                for displayID in changedDisplayIDs {
                    guard let manager = tileManagers[displayID] else { continue }
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

    // MARK: - Layout Import / Export

    /// Encode all current layouts as JSON for export to a file.
    public func exportLayout() -> Data? {
        try? layoutStore.exportJSON()
    }

    /// Import layouts from JSON data, apply to active tile managers, and reflow windows.
    /// Returns false if the data cannot be decoded.
    @discardableResult
    public func importLayout(_ data: Data) -> Bool {
        do {
            try layoutStore.importJSON(data)
        } catch {
            Self.log.error("importLayout: decode failed: \(error.localizedDescription)")
            return false
        }
        for (displayID, manager) in tileManagers {
            let key = layoutKey(for: displayID)
            layoutStore.apply(to: manager, for: key)
            reflowWindows(for: displayID)
        }
        Self.log.info("importLayout: applied to \(self.tileManagers.count) display(s)")
        return true
    }

    // MARK: - Profile Operations

    /// Capture the current tile layout for all displays and save it as a named profile.
    @discardableResult
    public func saveCurrentAsProfile(name: String) -> LayoutProfile {
        var snapshots: [String: TileSnapshot] = [:]
        for (displayID, manager) in tileManagers {
            // Strip window IDs — profiles store layout structure, not window assignments
            snapshots["\(displayID)"] = TileSnapshot(tile: manager.root).clearingWindowIDs()
        }
        let profile = LayoutProfile(name: name, displaySnapshots: snapshots)
        profileStore.addProfile(profile)
        Self.log.info("saveCurrentAsProfile: saved '\(name)'")
        onProfilesChanged?()
        return profile
    }

    /// Overwrite an existing profile's snapshots with the current tile layout.
    public func updateProfile(id: UUID) {
        var snapshots: [String: TileSnapshot] = [:]
        for (displayID, manager) in tileManagers {
            snapshots["\(displayID)"] = TileSnapshot(tile: manager.root).clearingWindowIDs()
        }
        profileStore.updateProfile(id: id, snapshots: snapshots)
        onProfilesChanged?()
    }

    /// Switch to a profile by 0-based index. Returns false if no profile exists at that index.
    @discardableResult
    public func switchProfile(index: Int) -> Bool {
        guard let profile = profileStore.profile(at: index) else {
            Self.log.info("switchProfile: no profile at index \(index)")
            return false
        }
        Self.log.info("switchProfile: '\(profile.name)' (index=\(index))")
        applyProfile(profile)
        activeProfileID = profile.id
        activeProfileName = profile.name
        onActiveProfileChanged?(profile.name)
        return true
    }

    /// Switch to a profile by ID.
    public func switchProfile(id: UUID) {
        guard let profile = profileStore.profiles.first(where: { $0.id == id }) else { return }
        Self.log.info("switchProfile: '\(profile.name)' (id=\(id))")
        applyProfile(profile)
        activeProfileID = profile.id
        activeProfileName = profile.name
        onActiveProfileChanged?(profile.name)
    }

    /// Rename a saved profile.
    public func renameProfile(id: UUID, name: String) {
        profileStore.renameProfile(id: id, name: name)
        // Keep activeProfileName in sync if the active profile was renamed
        if activeProfileID == id {
            activeProfileName = name
            onActiveProfileChanged?(name)
        }
        onProfilesChanged?()
    }

    /// Delete a saved profile.
    public func deleteProfile(id: UUID) {
        profileStore.deleteProfile(id: id)
        onProfilesChanged?()
    }

    /// Update a hotkey binding at runtime and persist it.
    public func updateHotkeyBinding(_ binding: HotkeyBinding) {
        hotkeyManager.update(binding)
        hotkeyStore.save(binding)
    }

    /// Set the gap size for all tile managers.
    public func setGapSize(_ size: CGFloat) {
        gapSize = size
    }

    /// Set the focused window ID.
    public func setFocusedWindowID(_ id: UInt32?) {
        focusedWindowID = id
    }

    /// Reflow all windows in a tile manager to match current tile frames.
    public func reflowWindows(for displayID: UInt32) {
        guard let manager = tileManagers[displayID] else { return }
        for leaf in manager.leafTiles() {
            for windowID in leaf.windowIDs {
                let frame = manager.frame(for: leaf)
                windowManager.setWindowFrame(id: windowID, frame: frame)
            }
        }
    }

    /// Split a tile in a specific tile manager, with auto-save.
    @discardableResult
    public func splitTile(displayID: UInt32, tileID: UUID, direction: LayoutDirection, ratio: CGFloat = 0.5) -> Bool {
        guard let manager = tileManagers[displayID] else { return false }
        guard let tile = manager.root.find(id: tileID), tile.isLeaf else { return false }

        Self.log.info("splitTile: displayID=\(displayID) direction=\(String(describing: direction)) ratio=\(ratio)")
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

    private func applyProfile(_ profile: LayoutProfile) {
        for (displayID, manager) in tileManagers {
            guard let snapshot = profile.displaySnapshots["\(displayID)"] else {
                Self.log.debug("applyProfile: no snapshot for displayID=\(displayID) in '\(profile.name)'")
                continue
            }
            // Collect existing window IDs before replacing the tile tree
            let existingWindowIDs = manager.leafTiles().flatMap { Array($0.windowIDs) }

            let newRoot = snapshot.toTile() // snapshot has no windowIDs (cleared on save)
            manager.replaceRoot(newRoot)

            // Re-seat existing windows into new leaf tiles in order
            let newLeaves = manager.leafTiles()
            for (i, windowID) in existingWindowIDs.enumerated() where i < newLeaves.count {
                newLeaves[i].addWindow(id: windowID)
            }

            let key = layoutKey(for: displayID)
            layoutStore.save(tileManager: manager, for: key)
            reflowWindows(for: displayID)
        }
    }

    private func handleWindowCreated(_ window: WindowInfo) {
        // New windows appear at their default position/size — no auto-assignment to tiles.
        // Users can Shift+drag to assign windows to tiles manually.
    }

    private func handleWindowDestroyed(_ windowID: UInt32) {
        Self.log.debug("handleWindowDestroyed: windowID=\(windowID)")
        // Remove from any tile it's assigned to
        if let (_, tile) = findTileContaining(windowID: windowID) {
            tile.removeWindow(id: windowID)
        }
        // Clean up maximized state if applicable
        maximizedWindows.removeValue(forKey: windowID)
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
            if let tile = manager.root.findTile(containingWindow: windowID) {
                return (manager, tile)
            }
        }
        return nil
    }

    private func focusAdjacent(windowID: UInt32, direction: NavigationDirection) {
        guard let (manager, tile) = findTileContaining(windowID: windowID) else { return }
        guard let adjacent = manager.adjacentTile(to: tile, direction: direction) else { return }
        if let targetWindowID = adjacent.windowIDs.first {
            Self.log.debug("focusAdjacent: windowID=\(windowID) direction=\(String(describing: direction)) → targetID=\(targetWindowID)")
            focusedWindowID = targetWindowID
            windowManager.focusWindow(id: targetWindowID)
        }
    }

    private func moveWindow(windowID: UInt32, direction: NavigationDirection) {
        guard let (manager, currentTile) = findTileContaining(windowID: windowID) else { return }
        guard let adjacentTile = manager.adjacentTile(to: currentTile, direction: direction) else { return }

        Self.log.debug("moveWindow: windowID=\(windowID) direction=\(String(describing: direction))")
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

        // Reflow windows in affected tiles (the resized tile and its siblings)
        guard let parent = tile.parent else { return }
        for sibling in parent.children {
            for leaf in sibling.leafTiles() {
                for wid in leaf.windowIDs {
                    let frame = manager.frame(for: leaf)
                    windowManager.setWindowFrame(id: wid, frame: frame)
                }
            }
        }
    }

    private func cycleWindow(windowID: UInt32, forward: Bool) {
        guard let (manager, currentTile) = findTileContaining(windowID: windowID) else { return }
        let leaves = manager.leafTiles()
        guard leaves.count > 1,
              let currentIndex = leaves.firstIndex(where: { $0.id == currentTile.id }) else { return }

        let nextIndex = forward
            ? (currentIndex + 1) % leaves.count
            : (currentIndex - 1 + leaves.count) % leaves.count
        let targetTile = leaves[nextIndex]

        Self.log.debug("cycleWindow: windowID=\(windowID) \(currentIndex) → \(nextIndex)")
        windowManager.saveOriginalFrame(id: windowID)
        currentTile.removeWindow(id: windowID)
        targetTile.addWindow(id: windowID)

        let frame = manager.frame(for: targetTile)
        windowManager.setWindowFrame(id: windowID, frame: frame)
    }

    private func toggleFloating(windowID: UInt32) {
        guard let (_, tile) = findTileContaining(windowID: windowID) else { return }
        Self.log.debug("toggleFloating: windowID=\(windowID)")
        windowManager.unassignWindow(id: windowID, from: tile)
    }

    private func toggleMaximize(windowID: UInt32) {
        if let state = maximizedWindows.removeValue(forKey: windowID) {
            // Un-maximize: restore to original tile
            guard let manager = tileManagers[state.displayID],
                  let tile = manager.root.find(id: state.tileID) else { return }
            Self.log.debug("toggleMaximize: restore windowID=\(windowID)")
            tile.addWindow(id: windowID)
            let frame = manager.frame(for: tile)
            windowManager.setWindowFrame(id: windowID, frame: frame)
        } else {
            // Maximize: expand window to full screen frame
            guard let (manager, tile) = findTileContaining(windowID: windowID) else { return }
            Self.log.debug("toggleMaximize: maximize windowID=\(windowID)")
            maximizedWindows[windowID] = MaximizedState(
                displayID: manager.displayID,
                tileID: tile.id
            )
            tile.removeWindow(id: windowID)
            windowManager.setWindowFrame(id: windowID, frame: manager.screenFrame)
        }
    }
}

/// State saved when a window is maximized, for restoration on un-maximize.
struct MaximizedState {
    let displayID: UInt32
    let tileID: UUID
}

// MARK: - GapResizeDelegate

extension AppCoordinator: GapResizeDelegate {
    public func didResize(_ boundary: TileBoundary, affectedTiles: [UUID]) {
        Self.log.debug("didResize: boundary axis=\(String(describing: boundary.axis)) affectedTiles=\(affectedTiles.count)")
        // Find which display owns these tiles and auto-save + reflow windows
        for (displayID, manager) in tileManagers {
            if manager.root.find(id: boundary.leadingTileID) != nil {
                // Reflow windows in affected tiles
                for tileID in affectedTiles {
                    if let tile = manager.root.find(id: tileID) {
                        for windowID in tile.windowIDs {
                            let frame = manager.frame(for: tile)
                            windowManager.setWindowFrame(id: windowID, frame: frame)
                        }
                    }
                }
                let key = layoutKey(for: displayID)
                layoutStore.save(tileManager: manager, for: key)
                break
            }
        }
    }
}

// MARK: - DragDropDelegate

extension AppCoordinator: DragDropDelegate {
    public func didDropWindow(_ windowID: UInt32, onTile tileID: UUID) {
        Self.log.info("didDropWindow: windowID=\(windowID) onTile=\(tileID)")
        for (_, manager) in tileManagers {
            if let tile = manager.root.find(id: tileID) {
                windowManager.assignWindow(id: windowID, to: tile, tileManager: manager)
                break
            }
        }
    }

    public func didCancelDrop() {
        Self.log.debug("didCancelDrop")
    }

    public func didDragWindowFromTile(_ windowID: UInt32) {
        Self.log.debug("didDragWindowFromTile: windowID=\(windowID)")
        guard let (_, tile) = findTileContaining(windowID: windowID) else { return }
        windowManager.unassignWindow(id: windowID, from: tile)
    }
}
