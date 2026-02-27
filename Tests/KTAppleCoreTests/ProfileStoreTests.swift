import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("ProfileStore")
struct ProfileStoreTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeSnapshot() -> TileSnapshot {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        return TileSnapshot(tile: manager.root).clearingWindowIDs()
    }

    // MARK: - Codable round-trip

    @Test func layoutProfileCodableRoundTrip() throws {
        let snapshot = makeSnapshot()
        let profile = LayoutProfile(name: "Coding", displaySnapshots: ["1": snapshot])
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LayoutProfile.self, from: data)
        #expect(decoded.id == profile.id)
        #expect(decoded.name == profile.name)
        #expect(decoded.displaySnapshots["1"]?.children.count == 2)
    }

    @Test func clearingWindowIDsRemovesAllWindowIDs() {
        let manager = TileManager(displayID: 1, screenFrame: screenFrame)
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let leaves = manager.leafTiles()
        leaves.forEach { $0.addWindow(id: 42) }
        let snapshot = TileSnapshot(tile: manager.root)
        let cleared = snapshot.clearingWindowIDs()
        #expect(cleared.windowIDs.isEmpty)
        #expect(cleared.children.allSatisfy { $0.windowIDs.isEmpty })
    }

    // MARK: - Load / Save

    @Test func loadFromDiskReturnsFalseWhenFileAbsent() {
        let store = ProfileStore(provider: MockStorageProvider(), filePath: "profiles.json")
        #expect(!store.loadFromDisk())
    }

    @Test func addAndLoadProfile() {
        let provider = MockStorageProvider()
        let store1 = ProfileStore(provider: provider, filePath: "profiles.json")
        let profile = LayoutProfile(name: "Coding", displaySnapshots: ["1": makeSnapshot()])
        store1.addProfile(profile)

        let store2 = ProfileStore(provider: provider, filePath: "profiles.json")
        store2.loadFromDisk()
        #expect(store2.profiles.count == 1)
        #expect(store2.profiles[0].name == "Coding")
    }

    @Test func profileAtIndexReturnsCorrectProfile() {
        let provider = MockStorageProvider()
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        store.addProfile(LayoutProfile(name: "A"))
        store.addProfile(LayoutProfile(name: "B"))
        store.addProfile(LayoutProfile(name: "C"))

        #expect(store.profile(at: 0)?.name == "A")
        #expect(store.profile(at: 2)?.name == "C")
        #expect(store.profile(at: 3) == nil)
        #expect(store.profile(at: -1) == nil)
    }

    @Test func deleteProfileRemovesIt() {
        let provider = MockStorageProvider()
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        let profile = LayoutProfile(name: "Zoom")
        store.addProfile(profile)
        #expect(store.profiles.count == 1)

        store.deleteProfile(id: profile.id)
        #expect(store.profiles.isEmpty)
        #expect(provider.storage["profiles.json"] != nil)
    }

    @Test func renameProfilePersists() {
        let provider = MockStorageProvider()
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        let profile = LayoutProfile(name: "Old Name")
        store.addProfile(profile)

        store.renameProfile(id: profile.id, name: "New Name")
        #expect(store.profiles[0].name == "New Name")

        let store2 = ProfileStore(provider: provider, filePath: "profiles.json")
        store2.loadFromDisk()
        #expect(store2.profiles[0].name == "New Name")
    }

    @Test func updateProfileSnapshotsPersists() {
        let provider = MockStorageProvider()
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        let profile = LayoutProfile(name: "Test")
        store.addProfile(profile)
        #expect(store.profiles[0].displaySnapshots.isEmpty)

        let snapshot = makeSnapshot()
        store.updateProfile(id: profile.id, snapshots: ["1": snapshot])
        #expect(store.profiles[0].displaySnapshots["1"]?.children.count == 2)
    }

    @Test func multipleProfilesStoredInOrder() {
        let provider = MockStorageProvider()
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        ["A", "B", "C", "D"].forEach { store.addProfile(LayoutProfile(name: $0)) }

        let store2 = ProfileStore(provider: provider, filePath: "profiles.json")
        store2.loadFromDisk()
        #expect(store2.profiles.map(\.name) == ["A", "B", "C", "D"])
    }

    @Test func corruptDataReturnsFalse() {
        let provider = MockStorageProvider()
        provider.storage["profiles.json"] = Data("not json".utf8)
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        #expect(!store.loadFromDisk())
    }

    @Test func writeErrorDoesNotCrash() {
        let provider = MockStorageProvider()
        provider.shouldThrowOnWrite = true
        let store = ProfileStore(provider: provider, filePath: "profiles.json")
        // Must not crash — error is logged, not thrown
        store.addProfile(LayoutProfile(name: "Test"))
        // In-memory state updated even if disk write failed
        #expect(store.profiles.count == 1)
    }
}
