import Foundation

/// A persistent rule that auto-assigns windows from a specific app to a tile.
public struct AppRule: Codable, Sendable, Identifiable {
    public let id: UUID
    public var bundleID: String      // e.g. "com.apple.Terminal"
    public var appName: String       // display-only
    public var displayID: UInt32     // target display
    public var tileIndex: Int        // 0-based leaf index

    public init(
        id: UUID = UUID(),
        bundleID: String,
        appName: String,
        displayID: UInt32,
        tileIndex: Int
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.displayID = displayID
        self.tileIndex = tileIndex
    }
}
