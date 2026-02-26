import Foundation
import Testing
@testable import KTAppleCore

@Suite("HotkeyStore")
struct HotkeyStoreTests {

    // MARK: - Codable round-trip

    @Test func hotkeyBindingCodableRoundTrip() throws {
        let original = HotkeyBinding(action: .openEditor, keyCode: 17, modifiers: [.control, .option])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        #expect(decoded.action == original.action)
        #expect(decoded.keyCode == original.keyCode)
        #expect(decoded.modifiers == original.modifiers)
    }

    @Test func keyModifierCodableRoundTrip() throws {
        let mods: KeyModifier = [.control, .option, .shift]
        let data = try JSONEncoder().encode(mods)
        let decoded = try JSONDecoder().decode(KeyModifier.self, from: data)
        #expect(decoded == mods)
    }

    @Test func hotkeyActionCodableRoundTrip() throws {
        for action in HotkeyAction.allCases {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(HotkeyAction.self, from: data)
            #expect(decoded == action)
        }
    }

    // MARK: - Load / Save

    @Test func loadFromDiskReturnsFalseWhenFileAbsent() {
        let provider = MockStorageProvider()
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        #expect(!store.loadFromDisk())
    }

    @Test func loadFromDiskParsesSavedBindings() throws {
        let provider = MockStorageProvider()
        let bindings = [
            HotkeyBinding(action: .openEditor, keyCode: 17, modifiers: [.control, .option]),
            HotkeyBinding(action: .focusLeft,  keyCode: 123, modifiers: [.control, .option]),
        ]
        provider.storage["hotkeys.json"] = try JSONEncoder().encode(bindings)

        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        #expect(store.loadFromDisk())
        #expect(store.customBinding(for: .openEditor)?.keyCode == 17)
        #expect(store.customBinding(for: .focusLeft)?.keyCode == 123)
        #expect(store.customBinding(for: .focusRight) == nil)
    }

    @Test func saveWritesToDisk() {
        let provider = MockStorageProvider()
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        let binding = HotkeyBinding(action: .toggleFloating, keyCode: 3, modifiers: [.control, .option])

        store.save(binding)

        #expect(provider.storage["hotkeys.json"] != nil)
    }

    @Test func saveAndReloadPreservesBinding() {
        let provider = MockStorageProvider()
        let store1 = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        let binding = HotkeyBinding(action: .expandTile, keyCode: 24, modifiers: [.control, .option, .shift])
        store1.save(binding)

        let store2 = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        store2.loadFromDisk()

        let loaded = store2.customBinding(for: .expandTile)
        #expect(loaded?.keyCode == 24)
        #expect(loaded?.modifiers == [.control, .option, .shift])
    }

    @Test func customBindingReturnsNilBeforeSave() {
        let provider = MockStorageProvider()
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        #expect(store.customBinding(for: .openEditor) == nil)
    }

    @Test func saveOverwritesPreviousCustomBinding() {
        let provider = MockStorageProvider()
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")

        store.save(HotkeyBinding(action: .openEditor, keyCode: 17, modifiers: [.control, .option]))
        store.save(HotkeyBinding(action: .openEditor, keyCode: 14, modifiers: [.control, .option]))

        #expect(store.customBinding(for: .openEditor)?.keyCode == 14)
    }

    @Test func corruptDataReturnsFalse() {
        let provider = MockStorageProvider()
        provider.storage["hotkeys.json"] = Data("not json".utf8)
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        #expect(!store.loadFromDisk())
    }

    @Test func writeErrorDoesNotCrash() {
        let provider = MockStorageProvider()
        provider.shouldThrowOnWrite = true
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        let binding = HotkeyBinding(action: .openEditor, keyCode: 17, modifiers: [.control, .option])

        // Must not crash; error is logged, not thrown
        store.save(binding)

        // In-memory state is updated even if disk write failed
        #expect(store.customBinding(for: .openEditor) != nil)
    }

    // MARK: - Default bindings merge

    @Test func defaultBindingsCoverAllActions() {
        let defaults = HotkeyManager.defaultBindings
        let covered = Set(defaults.map(\.action))
        let all = Set(HotkeyAction.allCases)
        #expect(covered == all)
    }

    @Test func mergeAppliesCustomOverDefault() {
        let provider = MockStorageProvider()
        let store = HotkeyStore(provider: provider, filePath: "hotkeys.json")
        let custom = HotkeyBinding(action: .openEditor, keyCode: 14, modifiers: [.control, .option])
        store.save(custom)

        let merged = HotkeyManager.defaultBindings.map {
            store.customBinding(for: $0.action) ?? $0
        }

        let openEditor = merged.first { $0.action == .openEditor }
        #expect(openEditor?.keyCode == 14)

        // Other defaults are untouched
        let focusLeft = merged.first { $0.action == .focusLeft }
        let defaultFocusLeft = HotkeyManager.defaultBindings.first { $0.action == .focusLeft }
        #expect(focusLeft?.keyCode == defaultFocusLeft?.keyCode)
    }
}
