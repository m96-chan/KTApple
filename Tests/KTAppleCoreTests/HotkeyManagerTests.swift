import Testing
import Foundation
@testable import KTAppleCore

@Suite("HotkeyManager")
struct HotkeyManagerTests {

    // MARK: - Helpers

    private func makeManager() -> (HotkeyManager, MockHotkeyProvider) {
        let provider = MockHotkeyProvider()
        let manager = HotkeyManager(provider: provider)
        return (manager, provider)
    }

    // MARK: - Registration

    @Test func registerBindingCallsProvider() {
        let (manager, provider) = makeManager()
        let binding = HotkeyBinding(
            action: .openEditor,
            keyCode: 17,  // T
            modifiers: [.control, .option]
        )

        manager.register(binding)

        #expect(provider.registeredBindings.count == 1)
        #expect(provider.registeredBindings[0].action == .openEditor)
    }

    @Test func unregisterBindingCallsProvider() {
        let (manager, provider) = makeManager()
        let binding = HotkeyBinding(
            action: .openEditor,
            keyCode: 17,
            modifiers: [.control, .option]
        )

        manager.register(binding)
        manager.unregister(binding)

        #expect(provider.unregisteredActions.contains(.openEditor))
    }

    @Test func registerMultipleBindings() {
        let (manager, provider) = makeManager()

        manager.register(HotkeyBinding(action: .openEditor, keyCode: 17, modifiers: [.control, .option]))
        manager.register(HotkeyBinding(action: .toggleFloating, keyCode: 3, modifiers: [.control, .option]))

        #expect(provider.registeredBindings.count == 2)
    }

    // MARK: - Handling

    @Test func handleHotkeyTriggersCallback() {
        let (manager, _) = makeManager()
        var triggered: HotkeyAction?

        manager.onHotkey = { action in
            triggered = action
        }

        let binding = HotkeyBinding(action: .focusLeft, keyCode: 123, modifiers: [.control, .option])
        manager.register(binding)
        manager.handleHotkey(action: .focusLeft)

        #expect(triggered == .focusLeft)
    }

    @Test func handleUnregisteredHotkeyDoesNothing() {
        let (manager, _) = makeManager()
        var triggered = false

        manager.onHotkey = { _ in
            triggered = true
        }

        manager.handleHotkey(action: .openEditor)
        #expect(!triggered)
    }

    // MARK: - Default Bindings

    @Test func registerDefaultBindings() {
        let (manager, provider) = makeManager()
        manager.registerDefaults()

        let actions = Set(provider.registeredBindings.map(\.action))
        #expect(actions.contains(.openEditor))
        #expect(actions.contains(.focusLeft))
        #expect(actions.contains(.focusRight))
        #expect(actions.contains(.focusUp))
        #expect(actions.contains(.focusDown))
        #expect(actions.contains(.moveLeft))
        #expect(actions.contains(.moveRight))
        #expect(actions.contains(.moveUp))
        #expect(actions.contains(.moveDown))
        #expect(actions.contains(.toggleFloating))
        #expect(actions.contains(.toggleMaximize))
        #expect(actions.contains(.expandTile))
        #expect(actions.contains(.shrinkTile))
    }

    // MARK: - Update Binding

    @Test func updateBindingReregisters() {
        let (manager, provider) = makeManager()
        let original = HotkeyBinding(action: .openEditor, keyCode: 17, modifiers: [.control, .option])
        manager.register(original)

        let updated = HotkeyBinding(action: .openEditor, keyCode: 14, modifiers: [.control, .option])
        manager.update(updated)

        #expect(provider.unregisteredActions.contains(.openEditor))
        #expect(provider.registeredBindings.last?.keyCode == 14)
    }

    // MARK: - Active Bindings

    @Test func activeBindingsReturnsCurrentState() {
        let (manager, _) = makeManager()
        let binding = HotkeyBinding(action: .toggleFloating, keyCode: 3, modifiers: [.control, .option])
        manager.register(binding)

        let active = manager.activeBindings
        #expect(active.count == 1)
        #expect(active[.toggleFloating]?.keyCode == 3)
    }

    @Test func unregisterAllClearsBindings() {
        let (manager, provider) = makeManager()
        manager.registerDefaults()

        let countBefore = provider.registeredBindings.count
        manager.unregisterAll()

        #expect(countBefore > 0)
        #expect(manager.activeBindings.isEmpty)
    }
}

// MARK: - Mock

final class MockHotkeyProvider: HotkeyProvider {
    var registeredBindings: [HotkeyBinding] = []
    var unregisteredActions: Set<HotkeyAction> = []

    func register(_ binding: HotkeyBinding) {
        registeredBindings.append(binding)
    }

    func unregister(action: HotkeyAction) {
        unregisteredActions.insert(action)
    }
}
