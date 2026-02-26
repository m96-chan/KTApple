import Foundation
import os.log

/// Persists custom hotkey bindings to disk via a StorageProvider.
///
/// JSON format: `[HotkeyBinding]` (array). Only customised bindings are stored;
/// defaults are applied at runtime by merging with `HotkeyManager.defaultBindings`.
public final class HotkeyStore {
    private static let log = AppLog.logger(for: "HotkeyStore")
    private let provider: StorageProvider
    private let filePath: String
    private var custom: [HotkeyAction: HotkeyBinding] = [:]

    public init(provider: StorageProvider, filePath: String = "hotkeys.json") {
        self.provider = provider
        self.filePath = filePath
    }

    /// Load custom bindings from disk. Returns false if file is missing or corrupt.
    @discardableResult
    public func loadFromDisk() -> Bool {
        guard provider.fileExists(at: filePath) else {
            Self.log.info("No hotkeys file at \(self.filePath), using defaults")
            return false
        }
        do {
            let data = try provider.read(from: filePath)
            let bindings = try JSONDecoder().decode([HotkeyBinding].self, from: data)
            custom = Dictionary(uniqueKeysWithValues: bindings.map { ($0.action, $0) })
            Self.log.info("Loaded \(bindings.count) custom hotkey(s) from \(self.filePath)")
            return true
        } catch {
            Self.log.error("Failed to decode hotkeys from \(self.filePath): \(error.localizedDescription)")
            return false
        }
    }

    /// Persist a custom binding for its action (overwrites any previous custom binding for that action).
    public func save(_ binding: HotkeyBinding) {
        custom[binding.action] = binding
        saveToDisk()
    }

    /// Return the user-customised binding for an action, or nil if the default should be used.
    public func customBinding(for action: HotkeyAction) -> HotkeyBinding? {
        custom[action]
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Array(custom.values))
            try provider.write(data, to: filePath)
            Self.log.debug("Saved \(self.custom.count) custom hotkey(s) to \(self.filePath)")
        } catch {
            Self.log.error("Failed to save hotkeys to \(self.filePath): \(error.localizedDescription)")
        }
    }
}
