import Foundation
import os.log

/// Persists app auto-assignment rules to disk via a StorageProvider.
///
/// JSON format: `[AppRule]` (array). Write-through cache.
public final class RuleStore {
    private static let log = AppLog.logger(for: "RuleStore")
    private let provider: StorageProvider
    private let filePath: String
    private var rules: [AppRule] = []

    public init(provider: StorageProvider, filePath: String = "rules.json") {
        self.provider = provider
        self.filePath = filePath
    }

    /// Load rules from disk. Returns false if file is missing or corrupt.
    @discardableResult
    public func loadFromDisk() -> Bool {
        guard provider.fileExists(at: filePath) else {
            Self.log.info("No rules file at \(self.filePath)")
            return false
        }
        do {
            let data = try provider.read(from: filePath)
            rules = try JSONDecoder().decode([AppRule].self, from: data)
            Self.log.info("Loaded \(self.rules.count) rule(s) from \(self.filePath)")
            return true
        } catch {
            Self.log.error("Failed to decode rules from \(self.filePath): \(error.localizedDescription)")
            return false
        }
    }

    /// All current rules in order.
    public var allRules: [AppRule] { rules }

    /// Add a new rule and persist.
    public func addRule(_ rule: AppRule) {
        rules.append(rule)
        saveToDisk()
    }

    /// Delete a rule by ID and persist.
    public func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Update an existing rule in-place and persist.
    public func updateRule(_ rule: AppRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        saveToDisk()
    }

    /// Find the first rule matching a bundle ID (case-insensitive).
    public func rule(for bundleID: String) -> AppRule? {
        let lowered = bundleID.lowercased()
        return rules.first { $0.bundleID.lowercased() == lowered }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try provider.write(data, to: filePath)
            Self.log.debug("Saved \(self.rules.count) rule(s) to \(self.filePath)")
        } catch {
            Self.log.error("Failed to save rules to \(self.filePath): \(error.localizedDescription)")
        }
    }
}
