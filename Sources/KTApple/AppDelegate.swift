import AppKit
@preconcurrency import ApplicationServices
import KTAppleCore
import os.log

private let log = AppLog.logger(for: "AppDelegate")

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
    /// Timestamp of last hotkey-driven focus change. Used to prevent
    /// `updateFocusedWindow` from overwriting `focusedWindowID` with
    /// stale data before macOS fully processes the focus switch.
    private var lastHotkeyFocusTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchDiagnostics.logEnvironment()
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
        let hotkeyPath = supportDir.appendingPathComponent("hotkeys.json").path
        let profilePath = supportDir.appendingPathComponent("profiles.json").path
        let rulePath = supportDir.appendingPathComponent("rules.json").path

        let hotkeyStore = HotkeyStore(provider: storageProvider, filePath: hotkeyPath)
        let ruleStore = RuleStore(provider: storageProvider, filePath: rulePath)
        let windowLifecycleProvider = LiveWindowLifecycleProvider(accessibilityProvider: accessibilityProvider)

        let coordinator = AppCoordinator(
            accessibilityProvider: accessibilityChecker,
            displayProvider: displayProvider,
            hotkeyProvider: hotkeyProvider,
            accessibilityAPIProvider: accessibilityProvider,
            storageProvider: storageProvider,
            layoutFilePath: layoutPath,
            hotkeyStore: hotkeyStore,
            profileFilePath: profilePath,
            spaceProvider: spaceProvider,
            windowLifecycleProvider: windowLifecycleProvider,
            ruleStore: ruleStore
        )

        coordinator.onOpenEditor = { [weak self] in
            self?.openTileEditor()
        }

        // Wire Carbon hotkey events → coordinator
        hotkeyProvider.onHotkey = { [weak self, weak coordinator] action in
            coordinator?.handleAction(action)
            // Track focus-related hotkey actions to prevent updateFocusedWindow race
            switch action {
            case .focusLeft, .focusRight, .focusUp, .focusDown:
                self?.lastHotkeyFocusTime = Date()
            default:
                break
            }
        }

        // Restore persisted gap size
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "gapSize") != nil {
            coordinator.gapSize = CGFloat(defaults.double(forKey: "gapSize"))
        }
        coordinator.onGapSizeChanged = { size in
            defaults.set(Double(size), forKey: "gapSize")
        }

        coordinator.onProfilesChanged = { [weak self] in
            Task { @MainActor in
                guard let self, let coordinator = self.coordinator else { return }
                let profiles = coordinator.profiles
                self.statusBarController?.rebuildProfilesMenu(profiles)
                self.preferencesWindow?.updateProfiles(profiles)
            }
        }

        coordinator.onActiveProfileChanged = { [weak self] name in
            Task { @MainActor in
                self?.statusBarController?.setActiveProfile(name: name)
            }
        }

        coordinator.start()
        self.coordinator = coordinator
        self.hotkeyProvider = hotkeyProvider

        setupDragDrop()
        setupGapResize()

        // Track focused window (on app activation AND mouseDown)
        startFocusTracking()

        statusBarController = StatusBarController(
            onOpenEditor: { [weak self] in
                self?.openTileEditor()
            },
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onSwitchProfile: { [weak self] index in
                self?.coordinator?.switchProfile(index: index)
            },
            onSaveCurrentProfile: { [weak self] in
                self?.promptSaveProfile()
            },
            onExportLayout: { [weak self] in
                self?.exportLayouts()
            },
            onImportLayout: { [weak self] in
                self?.importLayouts()
            },
            onFixAccessibility: { [weak self] in
                self?.requestAccessibilityPermission(explain: true)
            }
        )
        // Populate initial profile list in the status bar menu
        statusBarController?.rebuildProfilesMenu(coordinator.profiles)

        // Surface the permission state and keep watching it. Trust is not
        // constant for the process lifetime: a macOS upgrade can reset TCC and
        // reinstalling changes the signature, both of which revoke it.
        coordinator.onAccessibilityStatusChanged = { [weak self] granted in
            self?.handleAccessibilityStatusChanged(granted: granted)
        }
        statusBarController?.setAccessibilityWarning(!coordinator.accessibilityGranted)
        if !coordinator.accessibilityGranted {
            // Let macOS render its own prompt at launch. The persistent menu
            // bar warning carries the message from here on, and clicking it
            // brings up the fuller explanation.
            requestAccessibilityPermission(explain: false)
        }
        startAccessibilityPolling()
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
        log.info("openTileEditor AXIsProcessTrusted=\(trusted)")
        guard trusted else {
            // The user explicitly asked for the editor, so explain why it did
            // not open rather than silently doing nothing.
            requestAccessibilityPermission(explain: true)
            return
        }

        // Permission may have been granted moments ago, before the next poll
        // tick. Go through refresh rather than restarting the coordinator
        // directly, so the menu bar warning clears with it.
        coordinator?.refreshAccessibilityStatus()

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
            log.warning("openTileEditor: no coordinator or tileManagers coordinatorNil=\(self.coordinator == nil) tileManagers=\(self.coordinator?.tileManagers.count ?? -1)")
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

            log.debug("openTileEditor: showing editor for display \(tileManager.displayID)")
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
        let displayIDs = Array(coordinator?.tileManagers.keys.sorted() ?? [])
        var leafCounts: [UInt32: Int] = [:]
        for (id, manager) in coordinator?.tileManagers ?? [:] {
            leafCounts[id] = manager.leafTiles().count
        }
        preferencesWindow?.show(
            gapSize: Double(coordinator?.gapSize ?? 8),
            bindings: coordinator?.activeHotkeyBindings ?? [:],
            profiles: coordinator?.profiles ?? [],
            rules: coordinator?.rules ?? [],
            displayIDs: displayIDs,
            leafCounts: leafCounts,
            onGapSizeChanged: { [weak self] size in
                self?.coordinator?.setGapSize(CGFloat(size))
            },
            onBindingChanged: { [weak self] binding in
                self?.coordinator?.updateHotkeyBinding(binding)
            },
            onProfileRenamed: { [weak self] id, name in
                self?.coordinator?.renameProfile(id: id, name: name)
            },
            onProfileDeleted: { [weak self] id in
                self?.coordinator?.deleteProfile(id: id)
            },
            onRuleAdded: { [weak self] rule in
                self?.coordinator?.addRule(rule)
            },
            onRuleDeleted: { [weak self] id in
                self?.coordinator?.deleteRule(id: id)
            }
        )
    }

    private func exportLayouts() {
        guard let data = coordinator?.exportLayout() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Layout"
        panel.nameFieldStringValue = "layout.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            log.info("exportLayouts: saved to \(url.path)")
        } catch {
            log.error("exportLayouts: write failed: \(error.localizedDescription)")
        }
    }

    private func importLayouts() {
        let panel = NSOpenPanel()
        panel.title = "Import Layout"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let coordinator else { return }
            if coordinator.importLayout(data) {
                log.info("importLayouts: imported from \(url.path)")
            } else {
                showAlert(message: "Invalid Layout File", info: "The selected file is not a valid KTApple layout.")
            }
        } catch {
            log.error("importLayouts: read failed: \(error.localizedDescription)")
            showAlert(message: "Could Not Read File", info: error.localizedDescription)
        }
    }

    private func showAlert(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func promptSaveProfile() {
        let alert = NSAlert()
        alert.messageText = "Save Layout as Profile"
        alert.informativeText = "Enter a name for this layout profile."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        let nextIndex = (coordinator?.profiles.count ?? 0) + 1
        textField.stringValue = "Profile \(nextIndex)"
        textField.selectText(nil)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        coordinator?.saveCurrentAsProfile(name: name)
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

    // MARK: - Accessibility

    /// Poll interval while waiting for the user to grant permission.
    private static let accessibilityPollWaiting: TimeInterval = 2.0
    /// Poll interval once permission is held — revocation is rare, but it does
    /// happen (TCC reset by an OS upgrade, reinstall changing the signature).
    private static let accessibilityPollGranted: TimeInterval = 10.0

    /// Watch the accessibility trust state in both directions, for as long as
    /// the app runs.
    ///
    /// The previous implementation polled only until permission was granted
    /// and then stopped, so a later revocation left the app running but inert
    /// with no indication anywhere. See issue #37.
    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        let granted = coordinator?.accessibilityGranted ?? false
        let interval = granted
            ? Self.accessibilityPollGranted
            : Self.accessibilityPollWaiting

        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.coordinator?.refreshAccessibilityStatus()
            }
        }
    }

    /// React to a trust change reported by the coordinator.
    private func handleAccessibilityStatusChanged(granted: Bool) {
        log.info("accessibility status changed: granted=\(granted)")
        statusBarController?.setAccessibilityWarning(!granted)

        if granted {
            // stop() resets isRunning so start() re-checks accessibilityGranted
            // and backfills the windows that could not be discovered before.
            coordinator?.stop()
            coordinator?.start()
            setupDragDrop()
            setupGapResize()
            log.info("Accessibility granted — coordinator restarted, handlers enabled")
        } else {
            log.notice("Accessibility revoked — window management is disabled until it is restored")
        }

        // Re-arm the timer at the interval matching the new state.
        startAccessibilityPolling()
    }

    /// Ask for accessibility permission.
    ///
    /// Pass `explain: true` for user-initiated requests: macOS's own prompt
    /// says nothing about the reinstall-and-re-add dance that this app's
    /// ad-hoc signature requires, so an alert covers that before sending the
    /// user to Settings. At launch pass `false` — the system prompt is enough,
    /// and the menu bar warning stays visible afterwards.
    private func requestAccessibilityPermission(explain: Bool) {
        // Registers KTApple in the Accessibility list and lets macOS render
        // its own prompt — the one route into Settings that cannot go stale
        // when the URL scheme changes in a later release.
        if AccessibilitySettings.requestViaSystemPrompt() {
            coordinator?.refreshAccessibilityStatus()
            return
        }

        // At launch the system prompt is the whole interaction; stacking our
        // own alert on top of it would just be two dialogs saying the same
        // thing. The explanation is reserved for when the user asks, by
        // clicking the menu bar warning or trying to open the editor.
        if explain {
            let alert = NSAlert()
            alert.messageText = "KTApple Needs Accessibility Permission"
            alert.informativeText = """
                KTApple cannot move or resize windows without Accessibility access.

                macOS revokes this permission whenever the app is updated or reinstalled, \
                because the code signature changes. A macOS upgrade can reset it as well.

                In System Settings, remove any existing KTApple entry under Privacy & \
                Security > Accessibility, then add it back. Toggling the existing entry \
                off and on may keep using the stale signature.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        if !AccessibilitySettings.openPane() {
            showAlert(
                message: "Could Not Open System Settings",
                info: "Open System Settings > Privacy & Security > Accessibility "
                    + "and enable KTApple manually."
            )
        }
    }

    private func updateFocusedWindow() {
        // Skip if a hotkey just changed focus — macOS may not have fully processed the switch yet
        if let lastTime = lastHotkeyFocusTime, Date().timeIntervalSince(lastTime) < 0.5 {
            return
        }

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
        guard PrivateSymbols.axWindowID(focusedWindow as! AXUIElement, &windowID) == .success else {
            return
        }

        coordinator?.setFocusedWindowID(windowID)
    }
}
