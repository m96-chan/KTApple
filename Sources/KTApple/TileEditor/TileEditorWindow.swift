import AppKit
import KTAppleCore
import SwiftUI

/// Borderless fullscreen overlay panel for the tile layout editor.
@MainActor
final class TileEditorWindow {
    private var panel: NSPanel?

    var isVisible: Bool { panel != nil }

    func show(tileManager: TileManager, layoutStore: LayoutStore, layoutKey: LayoutKey) {
        let viewModel = TileEditorViewModel(
            tileManager: tileManager,
            layoutStore: layoutStore,
            layoutKey: layoutKey
        )

        let contentView = TileEditorView(viewModel: viewModel) { [weak self] in
            self?.close()
        }

        let screenFrame = NSScreen.main?.frame ?? tileManager.screenFrame

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
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
