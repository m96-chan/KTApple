import AppKit
import KTAppleCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menuTarget = MenuActionTarget()
    private let profileMenuTarget = ProfileMenuTarget()
    private var profilesMenuItem: NSMenuItem?

    init(
        onOpenEditor: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onSwitchProfile: @escaping (Int) -> Void,
        onSaveCurrentProfile: @escaping () -> Void,
        onExportLayout: @escaping () -> Void,
        onImportLayout: @escaping () -> Void
    ) {
        menuTarget.onOpenEditor = onOpenEditor
        menuTarget.onOpenPreferences = onOpenPreferences
        menuTarget.onExportLayout = onExportLayout
        menuTarget.onImportLayout = onImportLayout
        profileMenuTarget.onSwitchProfile = onSwitchProfile
        profileMenuTarget.onSaveCurrentProfile = onSaveCurrentProfile

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.2x2",
                accessibilityDescription: "KTApple"
            )
        }

        setupMenu()
    }

    /// Update the status bar button to reflect the active profile name.
    /// Pass nil to revert to icon-only display.
    func setActiveProfile(name: String?) {
        guard let button = statusItem.button else { return }
        if let name {
            statusItem.length = NSStatusItem.variableLength
            button.title = " \(name.prefix(14))"
            button.imagePosition = .imageLeft
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// Rebuild the Profiles submenu with an updated profile list.
    func rebuildProfilesMenu(_ profiles: [LayoutProfile]) {
        guard let submenu = profilesMenuItem?.submenu else { return }
        submenu.removeAllItems()
        populateProfilesSubmenu(submenu, profiles: profiles)
    }

    // MARK: - Private

    private func setupMenu() {
        let menu = NSMenu()

        let editorItem = NSMenuItem(
            title: "Open Tile Editor",
            action: #selector(MenuActionTarget.openEditor(_:)),
            keyEquivalent: "t"
        )
        editorItem.keyEquivalentModifierMask = [.control, .option]
        editorItem.target = menuTarget
        menu.addItem(editorItem)

        menu.addItem(NSMenuItem.separator())

        let exportItem = NSMenuItem(
            title: "Export Layout…",
            action: #selector(MenuActionTarget.exportLayout(_:)),
            keyEquivalent: ""
        )
        exportItem.target = menuTarget
        menu.addItem(exportItem)

        let importItem = NSMenuItem(
            title: "Import Layout…",
            action: #selector(MenuActionTarget.importLayout(_:)),
            keyEquivalent: ""
        )
        importItem.target = menuTarget
        menu.addItem(importItem)

        menu.addItem(NSMenuItem.separator())

        // Profiles submenu
        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let profilesSubmenu = NSMenu(title: "Profiles")
        profilesItem.submenu = profilesSubmenu
        populateProfilesSubmenu(profilesSubmenu, profiles: [])
        self.profilesMenuItem = profilesItem
        menu.addItem(profilesItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(MenuActionTarget.openPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = menuTarget
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit KTApple", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        statusItem.menu = menu
    }

    private func populateProfilesSubmenu(_ submenu: NSMenu, profiles: [LayoutProfile]) {
        for (index, profile) in profiles.prefix(9).enumerated() {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(ProfileMenuTarget.switchProfile(_:)),
                keyEquivalent: "\(index + 1)"
            )
            item.keyEquivalentModifierMask = [.control, .option]
            item.tag = index
            item.target = profileMenuTarget
            submenu.addItem(item)
        }

        if !profiles.isEmpty {
            submenu.addItem(NSMenuItem.separator())
        }

        let saveItem = NSMenuItem(
            title: "Save Current Layout as Profile…",
            action: #selector(ProfileMenuTarget.saveCurrentProfile(_:)),
            keyEquivalent: ""
        )
        saveItem.target = profileMenuTarget
        submenu.addItem(saveItem)
    }
}

// MARK: - Menu action targets

/// Plain NSObject target for static menu actions — avoids @MainActor isolation issues.
final class MenuActionTarget: NSObject {
    var onOpenEditor: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onExportLayout: (() -> Void)?
    var onImportLayout: (() -> Void)?

    @objc func openEditor(_ sender: Any?) { onOpenEditor?() }
    @objc func openPreferences(_ sender: Any?) { onOpenPreferences?() }
    @objc func exportLayout(_ sender: Any?) { onExportLayout?() }
    @objc func importLayout(_ sender: Any?) { onImportLayout?() }
}

/// NSObject target for dynamic profile menu actions.
final class ProfileMenuTarget: NSObject {
    var onSwitchProfile: ((Int) -> Void)?
    var onSaveCurrentProfile: (() -> Void)?

    @objc func switchProfile(_ sender: NSMenuItem) {
        onSwitchProfile?(sender.tag)
    }

    @objc func saveCurrentProfile(_ sender: Any?) {
        onSaveCurrentProfile?()
    }
}
