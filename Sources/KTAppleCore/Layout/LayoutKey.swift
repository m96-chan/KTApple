import Foundation

/// Identifies a layout by display and workspace.
public struct LayoutKey: Codable, Hashable, Sendable {
    public let displayID: UInt32
    public let workspaceIndex: Int

    public init(displayID: UInt32, workspaceIndex: Int = 0) {
        self.displayID = displayID
        self.workspaceIndex = workspaceIndex
    }

    /// String representation used as dictionary key in LayoutDocument.
    public var stringKey: String {
        "\(displayID)-\(workspaceIndex)"
    }
}
