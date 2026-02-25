import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

// MARK: - Mock Storage Provider

final class MockStorageProvider: StorageProvider {
    var storage: [String: Data] = [:]
    var shouldThrowOnWrite = false
    var shouldThrowOnRead = false

    func write(_ data: Data, to path: String) throws {
        if shouldThrowOnWrite { throw MockError.writeFailed }
        storage[path] = data
    }

    func read(from path: String) throws -> Data {
        if shouldThrowOnRead { throw MockError.readFailed }
        guard let data = storage[path] else { throw MockError.notFound }
        return data
    }

    func fileExists(at path: String) -> Bool {
        storage[path] != nil
    }

    func createDirectoryIfNeeded(at path: String) throws {}

    enum MockError: Error {
        case writeFailed
        case readFailed
        case notFound
    }
}

@Suite("LayoutStore")
struct LayoutStoreTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func saveAndLoad() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.6)
        let key = LayoutKey(displayID: 1)

        store.save(tileManager: manager, for: key)

        let store2 = LayoutStore(provider: provider)
        let loaded = store2.loadFromDisk()
        #expect(loaded)

        let snapshot = store2.layout(for: key)
        #expect(snapshot != nil)
        #expect(snapshot?.children.count == 2)
    }

    @Test func loadMissingFile() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)

        let loaded = store.loadFromDisk()
        #expect(!loaded)
    }

    @Test func layoutForMissingKey() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let key = LayoutKey(displayID: 999)

        #expect(store.layout(for: key) == nil)
    }

    @Test func corruptData() {
        let provider = MockStorageProvider()
        provider.storage["layouts.json"] = Data("not json".utf8)
        let store = LayoutStore(provider: provider)

        let loaded = store.loadFromDisk()
        #expect(!loaded)
    }

    @Test func removeLayout() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let key = LayoutKey(displayID: 1)

        store.save(tileManager: manager, for: key)
        #expect(store.layout(for: key) != nil)

        store.removeLayout(for: key)
        #expect(store.layout(for: key) == nil)
    }

    @Test func applyToTileManager() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.6)
        let key = LayoutKey(displayID: 1)
        store.save(tileManager: manager, for: key)

        let target = TileManager(displayID: 1, screenFrame: screenFrame)
        let result = store.apply(to: target, for: key)

        #expect(result)
        #expect(target.root.children.count == 2)
    }

    @Test func applyWithMissingKeyReturnsFalse() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let target = TileManager(displayID: 1, screenFrame: screenFrame)
        let key = LayoutKey(displayID: 999)

        let result = store.apply(to: target, for: key)
        #expect(!result)
    }

    @Test func multipleDisplaysSavedSeparately() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)

        let manager1 = TileManager(displayID: 1, screenFrame: screenFrame)
        manager1.split(manager1.root, direction: .horizontal, ratio: 0.5)
        let key1 = LayoutKey(displayID: 1)

        let manager2 = TileManager(displayID: 2, screenFrame: screenFrame)
        manager2.split(manager2.root, direction: .vertical, ratio: 0.3)
        let key2 = LayoutKey(displayID: 2)

        store.save(tileManager: manager1, for: key1)
        store.save(tileManager: manager2, for: key2)

        let s1 = store.layout(for: key1)
        let s2 = store.layout(for: key2)
        #expect(s1?.layoutDirection == .horizontal)
        #expect(s2?.layoutDirection == .vertical)
    }

    @Test func saveOverwritesPreviousLayout() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let key = LayoutKey(displayID: 1)

        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        store.save(tileManager: manager, for: key)
        #expect(store.layout(for: key)?.children.isEmpty == true)

        manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        store.save(tileManager: manager, for: key)
        #expect(store.layout(for: key)?.children.count == 2)
    }

    @Test func loadPersistsAcrossInstances() {
        let provider = MockStorageProvider()
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let key = LayoutKey(displayID: 1)

        let store1 = LayoutStore(provider: provider)
        store1.save(tileManager: manager, for: key)

        let store2 = LayoutStore(provider: provider)
        store2.loadFromDisk()

        let snapshot = store2.layout(for: key)
        #expect(snapshot?.children.count == 2)
    }

    // MARK: - Bug #34: saveToDisk logs errors instead of silently swallowing

    @Test func saveWithWriteErrorDoesNotCrash() {
        let provider = MockStorageProvider()
        let store = LayoutStore(provider: provider)
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        let key = LayoutKey(displayID: 1)

        provider.shouldThrowOnWrite = true

        // Should not crash — error is logged, not thrown
        store.save(tileManager: manager, for: key)

        // In-memory state should still be updated even if disk write failed
        #expect(store.layout(for: key) != nil)
    }
}
