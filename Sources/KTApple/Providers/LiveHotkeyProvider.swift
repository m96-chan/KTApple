import Carbon
import Foundation
import KTAppleCore
import os.log

final class LiveHotkeyProvider: HotkeyProvider {
    fileprivate static let log = AppLog.logger(for: "LiveHotkeyProvider")
    // "KTAp" as FourCharCode
    private static let hotKeySignature: UInt32 = 0x4B54_4170

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    fileprivate var actionMap: [UInt32: HotkeyAction] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Called when a registered hotkey fires.
    var onHotkey: ((HotkeyAction) -> Void)?

    init() {
        installHandler()
    }

    deinit {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }

    func register(_ binding: HotkeyBinding) {
        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)

        var carbonModifiers: UInt32 = 0
        if binding.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if binding.modifiers.contains(.option)  { carbonModifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.shift)   { carbonModifiers |= UInt32(shiftKey) }
        if binding.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            hotKeyRefs[id] = ref
            actionMap[id] = binding.action
            Self.log.debug("register: action=\(String(describing: binding.action)) id=\(id)")
        } else {
            Self.log.error("register failed: action=\(String(describing: binding.action)) status=\(status)")
        }
    }

    func unregister(action: HotkeyAction) {
        let idsToRemove = actionMap.filter { $0.value == action }.map(\.key)
        for id in idsToRemove {
            if let ref = hotKeyRefs[id] {
                UnregisterEventHotKey(ref)
            }
            hotKeyRefs.removeValue(forKey: id)
            actionMap.removeValue(forKey: id)
        }
    }

    // MARK: - Private

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &handler
        )
    }
}

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let provider = Unmanaged<LiveHotkeyProvider>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }

    if let action = provider.actionMap[hotKeyID.id] {
        LiveHotkeyProvider.log.debug("hotkey fired: action=\(String(describing: action))")
        // Carbon hotkey callback fires on an arbitrary thread.
        // Capture the callback and dispatch to main to avoid data races.
        nonisolated(unsafe) let callback = provider.onHotkey
        DispatchQueue.main.async {
            callback?(action)
        }
    }

    return noErr
}
