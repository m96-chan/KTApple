import AppKit
import KTAppleCore
import SwiftUI

/// Manages the Preferences window as a standard NSWindow.
@MainActor
final class PreferencesWindow {
    private var window: NSWindow?
    private var state: PreferencesState?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(
        gapSize: Double,
        bindings: [HotkeyAction: HotkeyBinding],
        onGapSizeChanged: @escaping (Double) -> Void,
        onBindingChanged: @escaping (HotkeyBinding) -> Void
    ) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newState = PreferencesState(
            gapSize: gapSize,
            bindings: bindings,
            onGapSizeChanged: onGapSizeChanged,
            onBindingChanged: onBindingChanged
        )
        self.state = newState

        let view = PreferencesView(
            gapSize: newState.gapBinding,
            bindings: newState.bindingsBinding,
            onGapSizeChanged: onGapSizeChanged,
            onBindingChanged: { binding in
                newState.bindings[binding.action] = binding
                onBindingChanged(binding)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
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

/// Observable state bridging AppDelegate values into SwiftUI.
@MainActor
private class PreferencesState: ObservableObject {
    @Published var gapSize: Double
    @Published var bindings: [HotkeyAction: HotkeyBinding]
    let onGapSizeChanged: (Double) -> Void
    let onBindingChanged: (HotkeyBinding) -> Void

    var gapBinding: Binding<Double> {
        Binding(get: { self.gapSize }, set: { self.gapSize = $0 })
    }

    var bindingsBinding: Binding<[HotkeyAction: HotkeyBinding]> {
        Binding(get: { self.bindings }, set: { self.bindings = $0 })
    }

    init(
        gapSize: Double,
        bindings: [HotkeyAction: HotkeyBinding],
        onGapSizeChanged: @escaping (Double) -> Void,
        onBindingChanged: @escaping (HotkeyBinding) -> Void
    ) {
        self.gapSize = gapSize
        self.bindings = bindings
        self.onGapSizeChanged = onGapSizeChanged
        self.onBindingChanged = onBindingChanged
    }
}
