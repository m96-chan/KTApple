import Foundation
import os.log

/// Manages global keyboard shortcuts.
///
/// Registers/unregisters hotkeys through a `HotkeyProvider` and dispatches
/// triggered actions via the `onHotkey` callback.
public final class HotkeyManager {
    private static let log = AppLog.logger(for: "HotkeyManager")
    private let provider: HotkeyProvider
    private var bindings: [HotkeyAction: HotkeyBinding] = [:]

    /// Callback invoked when a registered hotkey is triggered.
    public var onHotkey: ((HotkeyAction) -> Void)?

    /// Currently active bindings.
    public var activeBindings: [HotkeyAction: HotkeyBinding] { bindings }

    public init(provider: HotkeyProvider) {
        self.provider = provider
    }

    // MARK: - Registration

    /// Register a hotkey binding.
    public func register(_ binding: HotkeyBinding) {
        Self.log.debug("register: action=\(String(describing: binding.action)) keyCode=\(binding.keyCode)")
        bindings[binding.action] = binding
        provider.register(binding)
    }

    /// Unregister a hotkey by action.
    public func unregister(_ binding: HotkeyBinding) {
        Self.log.debug("unregister: action=\(String(describing: binding.action))")
        bindings.removeValue(forKey: binding.action)
        provider.unregister(action: binding.action)
    }

    /// Update an existing binding (unregister old, register new).
    public func update(_ binding: HotkeyBinding) {
        if bindings[binding.action] != nil {
            provider.unregister(action: binding.action)
        }
        bindings[binding.action] = binding
        provider.register(binding)
    }

    /// Unregister all bindings.
    public func unregisterAll() {
        for action in bindings.keys {
            provider.unregister(action: action)
        }
        bindings.removeAll()
    }

    // MARK: - Handling

    /// Called by the provider when a hotkey is triggered.
    public func handleHotkey(action: HotkeyAction) {
        guard bindings[action] != nil else { return }
        Self.log.debug("handleHotkey: action=\(String(describing: action))")
        onHotkey?(action)
    }

    // MARK: - Defaults

    // macOS virtual key codes
    private enum KeyCode {
        static let t: UInt32        = 17
        static let f: UInt32        = 3
        static let m: UInt32        = 46
        static let equal: UInt32    = 24
        static let minus: UInt32    = 27
        static let leftArrow: UInt32  = 123
        static let rightArrow: UInt32 = 124
        static let downArrow: UInt32  = 125
        static let upArrow: UInt32    = 126
    }

    /// Register the default set of hotkey bindings.
    public func registerDefaults() {
        let ctrlOpt: KeyModifier = [.control, .option]
        let ctrlOptShift: KeyModifier = [.control, .option, .shift]

        let defaults: [HotkeyBinding] = [
            HotkeyBinding(action: .openEditor, keyCode: KeyCode.t, modifiers: ctrlOpt),
            HotkeyBinding(action: .focusLeft, keyCode: KeyCode.leftArrow, modifiers: ctrlOpt),
            HotkeyBinding(action: .focusRight, keyCode: KeyCode.rightArrow, modifiers: ctrlOpt),
            HotkeyBinding(action: .focusUp, keyCode: KeyCode.upArrow, modifiers: ctrlOpt),
            HotkeyBinding(action: .focusDown, keyCode: KeyCode.downArrow, modifiers: ctrlOpt),
            HotkeyBinding(action: .moveLeft, keyCode: KeyCode.leftArrow, modifiers: ctrlOptShift),
            HotkeyBinding(action: .moveRight, keyCode: KeyCode.rightArrow, modifiers: ctrlOptShift),
            HotkeyBinding(action: .moveUp, keyCode: KeyCode.upArrow, modifiers: ctrlOptShift),
            HotkeyBinding(action: .moveDown, keyCode: KeyCode.downArrow, modifiers: ctrlOptShift),
            HotkeyBinding(action: .toggleFloating, keyCode: KeyCode.f, modifiers: ctrlOpt),
            HotkeyBinding(action: .toggleMaximize, keyCode: KeyCode.m, modifiers: ctrlOpt),
            HotkeyBinding(action: .expandTile, keyCode: KeyCode.equal, modifiers: ctrlOpt),
            HotkeyBinding(action: .shrinkTile, keyCode: KeyCode.minus, modifiers: ctrlOpt),
        ]

        Self.log.info("registerDefaults: registering \(defaults.count) bindings")
        for binding in defaults {
            register(binding)
        }
    }
}
