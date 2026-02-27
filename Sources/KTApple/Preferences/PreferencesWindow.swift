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
        profiles: [LayoutProfile],
        onGapSizeChanged: @escaping (Double) -> Void,
        onBindingChanged: @escaping (HotkeyBinding) -> Void,
        onProfileRenamed: @escaping (UUID, String) -> Void,
        onProfileDeleted: @escaping (UUID) -> Void
    ) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newState = PreferencesState(
            gapSize: gapSize,
            bindings: bindings,
            profiles: profiles,
            onGapSizeChanged: onGapSizeChanged,
            onBindingChanged: onBindingChanged,
            onProfileRenamed: onProfileRenamed,
            onProfileDeleted: onProfileDeleted
        )
        self.state = newState

        let view = PreferencesView(
            gapSize: newState.gapBinding,
            bindings: newState.bindingsBinding,
            profiles: newState.profilesBinding,
            onGapSizeChanged: onGapSizeChanged,
            onBindingChanged: { binding in
                newState.bindings[binding.action] = binding
                onBindingChanged(binding)
            },
            onProfileRenamed: { id, name in
                if let i = newState.profiles.firstIndex(where: { $0.id == id }) {
                    newState.profiles[i].name = name
                }
                onProfileRenamed(id, name)
            },
            onProfileDeleted: { id in
                newState.profiles.removeAll { $0.id == id }
                onProfileDeleted(id)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
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

    /// Update the displayed profile list while the window is open.
    func updateProfiles(_ profiles: [LayoutProfile]) {
        state?.profiles = profiles
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
    @Published var profiles: [LayoutProfile]
    let onGapSizeChanged: (Double) -> Void
    let onBindingChanged: (HotkeyBinding) -> Void
    let onProfileRenamed: (UUID, String) -> Void
    let onProfileDeleted: (UUID) -> Void

    var gapBinding: Binding<Double> {
        Binding(get: { self.gapSize }, set: { self.gapSize = $0 })
    }

    var bindingsBinding: Binding<[HotkeyAction: HotkeyBinding]> {
        Binding(get: { self.bindings }, set: { self.bindings = $0 })
    }

    var profilesBinding: Binding<[LayoutProfile]> {
        Binding(get: { self.profiles }, set: { self.profiles = $0 })
    }

    init(
        gapSize: Double,
        bindings: [HotkeyAction: HotkeyBinding],
        profiles: [LayoutProfile],
        onGapSizeChanged: @escaping (Double) -> Void,
        onBindingChanged: @escaping (HotkeyBinding) -> Void,
        onProfileRenamed: @escaping (UUID, String) -> Void,
        onProfileDeleted: @escaping (UUID) -> Void
    ) {
        self.gapSize = gapSize
        self.bindings = bindings
        self.profiles = profiles
        self.onGapSizeChanged = onGapSizeChanged
        self.onBindingChanged = onBindingChanged
        self.onProfileRenamed = onProfileRenamed
        self.onProfileDeleted = onProfileDeleted
    }
}
