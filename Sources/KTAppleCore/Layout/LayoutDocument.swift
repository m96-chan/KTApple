import Foundation

/// Top-level container for persisted layouts.
public struct LayoutDocument: Codable, Sendable {
    public var version: Int
    public var layouts: [String: TileSnapshot]

    public init(version: Int = 1, layouts: [String: TileSnapshot] = [:]) {
        self.version = version
        self.layouts = layouts
    }

    /// Get the snapshot for a given layout key.
    public func layout(for key: LayoutKey) -> TileSnapshot? {
        layouts[key.stringKey]
    }

    /// Set or update the snapshot for a given layout key.
    public mutating func setLayout(_ snapshot: TileSnapshot, for key: LayoutKey) {
        layouts[key.stringKey] = snapshot
    }

    /// Remove the layout for a given key.
    public mutating func removeLayout(for key: LayoutKey) {
        layouts.removeValue(forKey: key.stringKey)
    }
}
