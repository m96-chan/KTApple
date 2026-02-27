import Foundation
import os.log

/// Persists named layout profiles to disk via a StorageProvider.
///
/// Profiles are stored as an ordered array; index 0 corresponds to ⌃⌥1,
/// index 1 to ⌃⌥2, etc., up to a maximum of 9 profiles.
public final class ProfileStore {
    private static let log = AppLog.logger(for: "ProfileStore")
    private let provider: StorageProvider
    private let filePath: String
    private var document: ProfileDocument

    public init(provider: StorageProvider, filePath: String = "profiles.json") {
        self.provider = provider
        self.filePath = filePath
        self.document = ProfileDocument()
    }

    /// All profiles in user-defined order.
    public var profiles: [LayoutProfile] { document.profiles }

    /// Load profiles from disk. Returns false if the file is missing or corrupt.
    @discardableResult
    public func loadFromDisk() -> Bool {
        guard provider.fileExists(at: filePath) else {
            Self.log.info("No profiles file at \(self.filePath)")
            return false
        }
        do {
            let data = try provider.read(from: filePath)
            document = try JSONDecoder().decode(ProfileDocument.self, from: data)
            Self.log.info("Loaded \(self.document.profiles.count) profile(s) from \(self.filePath)")
            return true
        } catch {
            Self.log.error("Failed to decode profiles: \(error.localizedDescription)")
            return false
        }
    }

    /// Append a new profile and persist.
    public func addProfile(_ profile: LayoutProfile) {
        document.profiles.append(profile)
        saveToDisk()
    }

    /// Overwrite the display snapshots of an existing profile and persist.
    public func updateProfile(id: UUID, snapshots: [String: TileSnapshot]) {
        guard let i = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        document.profiles[i].displaySnapshots = snapshots
        saveToDisk()
    }

    /// Rename an existing profile and persist.
    public func renameProfile(id: UUID, name: String) {
        guard let i = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        document.profiles[i].name = name
        saveToDisk()
    }

    /// Delete a profile by ID and persist.
    public func deleteProfile(id: UUID) {
        document.profiles.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Return the profile at a 0-based index, or nil if out of range.
    public func profile(at index: Int) -> LayoutProfile? {
        guard index >= 0, index < document.profiles.count else { return nil }
        return document.profiles[index]
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try provider.write(data, to: filePath)
            Self.log.debug("Saved \(self.document.profiles.count) profile(s) to \(self.filePath)")
        } catch {
            Self.log.error("Failed to save profiles: \(error.localizedDescription)")
        }
    }
}
