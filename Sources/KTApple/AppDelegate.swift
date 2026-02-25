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
    private var tileEditorWindow: TileEditorWindow?
    private var dragDropHandler: DragDropHandler?
    private var hasShownAccessibilityPrompt = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.warning("applicationDidFinishLaunching AXIsProcessTrusted=\(AXIsProcessTrusted())")
        let accessibilityChecker = LiveAccessibilityChecker()
        let displayProvider = LiveDisplayProvider()
        let hotkeyProvider = LiveHotkeyProvider()
        let accessibilityProvider = LiveAccessibilityProvider()
        let storageProvider = LiveStorageProvider()

        // Ensure Application Support directory exists
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("KTApple")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let layoutPath = supportDir.appendingPathComponent("layouts.json").path

        let coordinator = AppCoordinator(
            accessibilityProvider: accessibilityChecker,
            displayProvider: displayProvider,
            hotkeyProvider: hotkeyProvider,
            accessibilityAPIProvider: accessibilityProvider,
            storageProvider: storageProvider,
            layoutFilePath: layoutPath
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

        // If accessibility not granted, open System Settings once
        if !coordinator.accessibilityGranted {
            hasShownAccessibilityPrompt = true
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }

        // Track focused window
        startFocusTracking()

        statusBarController = StatusBarController(onOpenEditor: { [weak self] in
            self?.openTileEditor()
        })
    }

    // MARK: - Drag & Drop

    private func setupDragDrop() {
        guard let coordinator,
              coordinator.accessibilityGranted,
              let (_, tileManager) = coordinator.tileManagers.first else { return }

        let eventProvider = LiveEventProvider()
        let overlayProvider = LiveOverlayProvider()
        let handler = DragDropHandler(
            eventProvider: eventProvider,
            overlayProvider: overlayProvider,
            tileManager: tileManager
        )
        handler.delegate = coordinator
        handler.startMonitoring()
        self.dragDropHandler = handler
    }

    // MARK: - Tile Editor

    @objc func openTileEditorAction(_ sender: Any?) {
        openTileEditor()
    }

    private func openTileEditor() {
        let trusted = AXIsProcessTrusted()
        log.warning("openTileEditor AXIsProcessTrusted=\(trusted)")
        guard trusted else {
            if !hasShownAccessibilityPrompt {
                hasShownAccessibilityPrompt = true
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            return
        }

        // If permission was granted after launch, re-start coordinator to pick up windows
        if let coordinator, !coordinator.accessibilityGranted {
            coordinator.start()
        }

        // Set up drag-drop if not yet initialized (e.g. accessibility was granted after launch)
        if dragDropHandler == nil {
            setupDragDrop()
        }

        // Toggle: if editor is already visible, close it
        if let existing = tileEditorWindow, existing.isVisible {
            existing.close()
            tileEditorWindow = nil
            return
        }

        guard let coordinator,
              let (displayID, tileManager) = coordinator.tileManagers.first else {
            log.warning("openTileEditor: no coordinator or tileManager. coordinatorNil=\(self.coordinator == nil) tileManagers=\(self.coordinator?.tileManagers.count ?? -1)")
            return
        }

        let layoutKey = LayoutKey(displayID: displayID)

        log.warning("openTileEditor: showing editor for display \(tileManager.displayID)")
        tileEditorWindow?.close()
        let editorWindow = TileEditorWindow()
        editorWindow.show(
            tileManager: tileManager,
            layoutStore: coordinator.layoutStore,
            layoutKey: layoutKey
        )
        self.tileEditorWindow = editorWindow
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

        // Initial focus
        updateFocusedWindow()
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
