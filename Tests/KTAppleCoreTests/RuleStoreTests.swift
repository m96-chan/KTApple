import Foundation
import Testing
@testable import KTAppleCore

@Suite("RuleStore")
struct RuleStoreTests {
    private func makeStore(provider: MockStorageProvider? = nil) -> (RuleStore, MockStorageProvider) {
        let storage = provider ?? MockStorageProvider()
        let store = RuleStore(provider: storage, filePath: "rules.json")
        return (store, storage)
    }

    private func sampleRule(
        bundleID: String = "com.apple.Terminal",
        appName: String = "Terminal",
        displayID: UInt32 = 1,
        tileIndex: Int = 0
    ) -> AppRule {
        AppRule(bundleID: bundleID, appName: appName, displayID: displayID, tileIndex: tileIndex)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() {
        let rule = sampleRule()
        let data = try! JSONEncoder().encode([rule])
        let decoded = try! JSONDecoder().decode([AppRule].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == rule.id)
        #expect(decoded[0].bundleID == "com.apple.Terminal")
        #expect(decoded[0].appName == "Terminal")
        #expect(decoded[0].displayID == 1)
        #expect(decoded[0].tileIndex == 0)
    }

    // MARK: - Load / Save

    @Test func loadFromEmptyDisk() {
        let (store, _) = makeStore()
        let result = store.loadFromDisk()
        #expect(!result)
        #expect(store.allRules.isEmpty)
    }

    @Test func addRulePersistsAndLoads() {
        let (store, storage) = makeStore()
        let rule = sampleRule()
        store.addRule(rule)

        #expect(store.allRules.count == 1)
        #expect(store.allRules[0].id == rule.id)

        // Verify persisted to disk
        let (store2, _) = makeStore(provider: storage)
        let loaded = store2.loadFromDisk()
        #expect(loaded)
        #expect(store2.allRules.count == 1)
        #expect(store2.allRules[0].id == rule.id)
    }

    // MARK: - Delete

    @Test func deleteRuleRemovesAndPersists() {
        let (store, storage) = makeStore()
        let rule1 = sampleRule(bundleID: "com.app.A", appName: "A")
        let rule2 = sampleRule(bundleID: "com.app.B", appName: "B")
        store.addRule(rule1)
        store.addRule(rule2)

        store.deleteRule(id: rule1.id)

        #expect(store.allRules.count == 1)
        #expect(store.allRules[0].id == rule2.id)

        let (store2, _) = makeStore(provider: storage)
        store2.loadFromDisk()
        #expect(store2.allRules.count == 1)
    }

    // MARK: - Update

    @Test func updateRuleModifiesInPlace() {
        let (store, _) = makeStore()
        let rule = sampleRule()
        store.addRule(rule)

        var updated = rule
        updated.tileIndex = 2
        store.updateRule(updated)

        #expect(store.allRules.count == 1)
        #expect(store.allRules[0].tileIndex == 2)
    }

    @Test func updateNonExistentRuleIsNoOp() {
        let (store, _) = makeStore()
        store.addRule(sampleRule())

        let phantom = sampleRule(bundleID: "com.phantom.App")
        store.updateRule(phantom)

        #expect(store.allRules.count == 1)
    }

    // MARK: - Lookup

    @Test func ruleLookupCaseInsensitive() {
        let (store, _) = makeStore()
        store.addRule(sampleRule(bundleID: "com.apple.Terminal"))

        #expect(store.rule(for: "com.apple.Terminal") != nil)
        #expect(store.rule(for: "COM.APPLE.TERMINAL") != nil)
        #expect(store.rule(for: "Com.Apple.Terminal") != nil)
    }

    @Test func ruleLookupNoMatch() {
        let (store, _) = makeStore()
        store.addRule(sampleRule(bundleID: "com.apple.Terminal"))

        #expect(store.rule(for: "com.apple.Safari") == nil)
    }

    // MARK: - Corrupt Data

    @Test func corruptDataReturnsFalse() {
        let storage = MockStorageProvider()
        storage.storage["rules.json"] = Data("not json".utf8)

        let store = RuleStore(provider: storage, filePath: "rules.json")
        let result = store.loadFromDisk()

        #expect(!result)
        #expect(store.allRules.isEmpty)
    }

    // MARK: - Order Preservation

    @Test func orderPreservedAcrossLoadSave() {
        let (store, storage) = makeStore()
        let ruleA = sampleRule(bundleID: "com.app.A", appName: "A")
        let ruleB = sampleRule(bundleID: "com.app.B", appName: "B")
        let ruleC = sampleRule(bundleID: "com.app.C", appName: "C")
        store.addRule(ruleA)
        store.addRule(ruleB)
        store.addRule(ruleC)

        let (store2, _) = makeStore(provider: storage)
        store2.loadFromDisk()

        #expect(store2.allRules.map(\.bundleID) == ["com.app.A", "com.app.B", "com.app.C"])
    }
}
