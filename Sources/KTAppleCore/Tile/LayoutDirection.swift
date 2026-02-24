import Foundation

/// Direction in which child tiles are arranged within a parent tile.
public enum LayoutDirection: String, Codable, Sendable {
    /// Children are arranged left to right.
    case horizontal
    /// Children are arranged top to bottom.
    case vertical
}
