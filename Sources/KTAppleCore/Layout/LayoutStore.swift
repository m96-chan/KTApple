import Foundation

/// Manages loading and saving tile layouts to disk via a StorageProvider.
public final class LayoutStore {
    private let provider: StorageProvider
    private let filePath: String
    private var document: LayoutDocument

    public init(provider: StorageProvider, filePath: String = "layouts.json") {
        self.provider = provider
        self.filePath = filePath
        self.document = LayoutDocument()
    }

    /// Load layouts from disk. Returns false if file doesn't exist or is corrupt.
    @discardableResult
    public func loadFromDisk() -> Bool {
        guard provider.fileExists(at: filePath) else { return false }
        do {
            let data = try provider.read(from: filePath)
            let decoder = JSONDecoder()
            document = try decoder.decode(LayoutDocument.self, from: data)
            return true
        } catch {
            return false
        }
    }

    /// Save the current TileManager state for a layout key.
    public func save(tileManager: TileManager, for key: LayoutKey) {
        let snapshot = TileSnapshot(tile: tileManager.root)
        document.setLayout(snapshot, for: key)
        saveToDisk()
    }

    /// Get the stored layout for a key.
    public func layout(for key: LayoutKey) -> TileSnapshot? {
        document.layout(for: key)
    }

    /// Apply a stored layout to a TileManager. Returns true if successful.
    @discardableResult
    public func apply(to tileManager: TileManager, for key: LayoutKey) -> Bool {
        guard let snapshot = document.layout(for: key) else { return false }
        let tile = snapshot.toTile()
        tileManager.replaceRoot(tile)
        return true
    }

    /// Remove the stored layout for a key.
    public func removeLayout(for key: LayoutKey) {
        document.removeLayout(for: key)
        saveToDisk()
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try provider.write(data, to: filePath)
        } catch {
            // Silently fail — caller can check via loadFromDisk
        }
    }
}
