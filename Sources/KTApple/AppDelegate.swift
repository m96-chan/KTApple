import AppKit
@preconcurrency import ApplicationServices
import KTAppleCore
import os.log

private let log = Logger(subsystem: "com.m96chan.KTApple", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var coordinator: AppCoordinator?
    private var hotkeyProvider: LiveHotkeyProvider?
    private var tileEditorWindows: [UInt32: TileEditorWindow] = [:]
    private var preferencesWindow: PreferencesWindow?
    private var dragDropHandler: DragDropHandler?
    private var gapResizeHandler: GapResizeHandler?
    private var mouseDownMonitor: Any?
    private var accessibilityTimer: Timer?
    private var hasShownAccessibilityPrompt = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.warning("applicationDidFinishLaunching AXIsProcessTrusted=\(AXIsProcessTrusted())")
        let accessibilityChecker = LiveAccessibilityChecker()
        let displayProvider = LiveDisplayProvider()
        let hotkeyProvider = LiveHotkeyProvider()
        let accessibilityProvider = LiveAccessibilityProvider()
        let storageProvider = LiveStorageProvider()
        let spaceProvider = LiveSpaceProvider()

        // Ensure Application Support directory exists
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("KTApple")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let layoutPath = supportDir.appendingPathComponent("layouts.json").path

        let windowLifecycleProvider = LiveWindowLifecycleProvider(accessibilityProvider: accessibilityProvider)

        let coordinator = AppCoordinator(
            accessibilityProvider: accessibilityChecker,
            displayProvider: displayProvider,
            hotkeyProvider: hotkeyProvider,
            accessibilityAPIProvider: accessibilityProvider,
            storageProvider: storageProvider,
            layoutFilePath: layoutPath,
            spaceProvider: spaceProvider,
            windowLifecycleProvider: windowLifecycleProvider
        )

        coordinator.onOpenEditor = { [weak self] in
            self?.openTileEditor()
        }

        // Wire Carbon hotkey events → coordinator
        hotkeyProvider.onHotkey = { [weak coordinator] action in
            coordinator?.handleAction(action)
        }

        // Restore persisted gap size
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "gapSize") != nil {
            coordinator.gapSize = CGFloat(defaults.double(forKey: "gapSize"))
        }
        coordinator.onGapSizeChanged = { size in
            defaults.set(Double(size), forKey: "gapSize")
        }

        coordinator.start()
        self.coordinator = coordinator
        self.hotkeyProvider = hotkeyProvider

        setupDragDrop()
        setupGapResize()

        // If accessibility not granted, open System Settings and poll until granted
        if !coordinator.accessibilityGranted {
            hasShownAccessibilityPrompt = true
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
            startAccessibilityPolling()
        }

        // Track focused window (on app activation AND mouseDown)
        startFocusTracking()

        statusBarController = StatusBarController(
            onOpenEditor: { [weak self] in
                self?.openTileEditor()
            },
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            }
        )
    }

    // MARK: - Drag & Drop

    private func setupDragDrop() {
        guard let coordinator,
              coordinator.accessibilityGranted,
              !coordinator.tileManagers.isEmpty else { return }

        let eventProvider = LiveEventProvider()
        let overlayProvider = LiveOverlayProvider()
        let handler = DragDropHandler(
            eventProvider: eventProvider,
            overlayProvider: overlayProvider,
            tileManagerResolver: { [weak self] point in
                self?.coordinator?.tileManagers.values.first {
                    $0.screenFrame.contains(point)
                }
            },
            windowPositionProvider: { windowID in
                guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
                      let bounds = info.first?[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat,
                      let y = bounds["Y"] as? CGFloat else { return nil }
                return CGPoint(x: x, y: y)
            }
        )
        handler.delegate = coordinator
        handler.startMonitoring()
        self.dragDropHandler = handler
    }

    // MARK: - Gap Resize

    private func setupGapResize() {
        guard let coordinator,
              coordinator.accessibilityGranted,
              !coordinator.tileManagers.isEmpty else { return }

        let eventProvider = LiveEventProvider()
        let cursorProvider = LiveCursorProvider()
        let handler = GapResizeHandler(
            eventProvider: eventProvider,
            cursorProvider: cursorProvider,
            tileManagerResolver: { [weak self] point in
                self?.coordinator?.tileManagers.values.first {
                    $0.screenFrame.contains(point)
                }
            }
        )
        handler.delegate = coordinator
        handler.startMonitoring()
        self.gapResizeHandler = handler
    }

    // MARK: - Tile Editor

    @objc func openTileEditorAction(_ sender: Any?) {
        openTileEditor()
    }

    private func openTileEditor() {
        let trusted = AXIsProcessTrusted()
        log.warning("openTileEditor AXIsProcessTrusted=\(trusted)")
        guard trusted else {
            // Always open System Preferences when user explicitly requests editor
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
            if accessibilityTimer == nil {
                startAccessibilityPolling()
            }
            return
        }

        // If permission was granted after launch, re-start coordinator to pick up windows
        if let coordinator, !coordinator.accessibilityGranted {
            coordinator.start()
        }

        // Set up handlers if not yet initialized (e.g. accessibility was granted after launch)
        if dragDropHandler == nil {
            setupDragDrop()
        }
        if gapResizeHandler == nil {
            setupGapResize()
        }

        // Toggle: if any editor is visible, close all
        if tileEditorWindows.values.contains(where: { $0.isVisible }) {
            for (_, editor) in tileEditorWindows {
                editor.close()
            }
            tileEditorWindows.removeAll()
            return
        }

        guard let coordinator, !coordinator.tileManagers.isEmpty else {
            log.warning("openTileEditor: no coordinator or tileManager. coordinatorNil=\(self.coordinator == nil) tileManagers=\(self.coordinator?.tileManagers.count ?? -1)")
            return
        }

        // Close any stale editors
        for (_, editor) in tileEditorWindows {
            editor.close()
        }
        tileEditorWindows.removeAll()

        // Open an editor on each display
        for (displayID, tileManager) in coordinator.tileManagers {
            let layoutKey = LayoutKey(displayID: displayID, workspaceIndex: coordinator.currentWorkspaceIndex(for: displayID))
            let screen = NSScreen.screen(for: displayID)

            log.warning("openTileEditor: showing editor for display \(tileManager.displayID)")
            let editorWindow = TileEditorWindow()
            editorWindow.show(
                tileManager: tileManager,
                layoutStore: coordinator.layoutStore,
                layoutKey: layoutKey,
                screen: screen,
                onApply: { [weak coordinator] in
                    coordinator?.reflowWindows(for: displayID)
                }
            )
            tileEditorWindows[displayID] = editorWindow
        }
    }

    // MARK: - Preferences

    private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
        }
        preferencesWindow?.show(
            gapSize: Double(coordinator?.gapSize ?? 8),
            onGapSizeChanged: { [weak self] size in
                self?.coordinator?.setGapSize(CGFloat(size))
            }
        )
    }

    // MARK: - Focus Tracking

    private func startFocusTracking() {
        // Update focused window on app activation
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFocusedWindow()
            }
        }

        // Update focused window on every mouseDown (catches window switches within same app)
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.updateFocusedWindow()
            }
        }

        // Initial focus
        updateFocusedWindow()
    }

    private func startAccessibilityPolling() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            Task { @MainActor [weak self] in
                self?.accessibilityTimer?.invalidate()
                self?.accessibilityTimer = nil
                self?.coordinator?.start()
                self?.setupDragDrop()
                self?.setupGapResize()
                log.warning("Accessibility granted — coordinator restarted, handlers enabled")
            }
        }
    }

    private func updateFocusedWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow
        ) == .success else {
            return
        }

        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(focusedWindow as! AXUIElement, &windowID) == .success else {
            return
        }

        coordinator?.setFocusedWindowID(windowID)
    }
}
