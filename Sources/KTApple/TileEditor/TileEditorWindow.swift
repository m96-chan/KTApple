import AppKit
import KTAppleCore
import SwiftUI

/// Borderless fullscreen overlay panel for the tile layout editor.
@MainActor
final class TileEditorWindow {
    private var panel: NSPanel?
    private var viewModel: TileEditorViewModel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel != nil }

    func show(tileManager: TileManager, layoutStore: LayoutStore, layoutKey: LayoutKey, screen: NSScreen? = nil, onApply: (() -> Void)? = nil) {
        let viewModel = TileEditorViewModel(
            tileManager: tileManager,
            layoutStore: layoutStore,
            layoutKey: layoutKey
        )
        viewModel.onApply = onApply
        self.viewModel = viewModel

        let contentView = TileEditorView(viewModel: viewModel) { [weak self] in
            self?.close()
        }

        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? tileManager.screenFrame

        let panel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: contentView)
        panel.setFrame(screenFrame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        installKeyMonitor(viewModel: viewModel)
    }

    func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        panel?.close()
        panel = nil
        viewModel = nil
    }

    // MARK: - Private

    /// Install a local key monitor to handle ⌘Z / ⌘⇧Z while the panel is open.
    ///
    /// SwiftUI .keyboardShortcut does not fire reliably inside NSPanel + NSHostingView
    /// because the panel uses .nonactivatingPanel and SwiftUI's shortcut routing depends
    /// on the standard macOS menu/responder chain being active.
    private func installKeyMonitor(viewModel: TileEditorViewModel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            guard let viewModel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.charactersIgnoringModifiers?.lowercased() == "z",
                  flags.contains(.command) else { return event }
            if flags.contains(.shift) {
                viewModel.redo()
            } else {
                viewModel.undo()
            }
            return nil  // consume the event
        }
    }
}
