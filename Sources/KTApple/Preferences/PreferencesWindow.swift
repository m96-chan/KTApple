import AppKit
import SwiftUI

/// Manages the Preferences window as a standard NSWindow.
@MainActor
final class PreferencesWindow {
    private var window: NSWindow?
    private var state: PreferencesState?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(gapSize: Double, onGapSizeChanged: @escaping (Double) -> Void) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newState = PreferencesState(gapSize: gapSize, onGapSizeChanged: onGapSizeChanged)
        self.state = newState
        let view = PreferencesView(
            gapSize: newState.binding,
            onGapSizeChanged: onGapSizeChanged
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "KTApple Preferences"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    func close() {
        window?.close()
    }
}

/// Bridges the gap size binding between AppDelegate and SwiftUI.
@MainActor
private class PreferencesState: ObservableObject {
    @Published var gapSize: Double
    let onGapSizeChanged: (Double) -> Void

    var binding: Binding<Double> {
        Binding(
            get: { self.gapSize },
            set: { self.gapSize = $0 }
        )
    }

    init(gapSize: Double, onGapSizeChanged: @escaping (Double) -> Void) {
        self.gapSize = gapSize
        self.onGapSizeChanged = onGapSizeChanged
    }
}
