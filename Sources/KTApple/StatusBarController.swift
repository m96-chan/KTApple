import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menuTarget = MenuActionTarget()

    init(onOpenEditor: @escaping () -> Void) {
        menuTarget.onOpenEditor = onOpenEditor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.2x2",
                accessibilityDescription: "KTApple"
            )
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let editorItem = NSMenuItem(
            title: "Open Tile Editor",
            action: #selector(MenuActionTarget.openEditor(_:)),
            keyEquivalent: ""
        )
        editorItem.target = menuTarget
        menu.addItem(editorItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Preferences...", action: nil, keyEquivalent: ",")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit KTApple", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        statusItem.menu = menu
    }
}

/// Plain NSObject target for menu actions — no @MainActor, no Swift 6 isolation issues.
final class MenuActionTarget: NSObject {
    var onOpenEditor: (() -> Void)?

    @objc func openEditor(_ sender: Any?) {
        onOpenEditor?()
    }
}
