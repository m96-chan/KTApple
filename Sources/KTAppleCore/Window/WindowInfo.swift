import Foundation

/// Subrole of a window, used for auto-float detection.
public enum WindowSubrole: String, Sendable {
    case standardWindow = "AXStandardWindow"
    case dialog = "AXDialog"
    case systemDialog = "AXSystemDialog"
    case floatingWindow = "AXFloatingWindow"
    case unknown = ""
}

/// Snapshot of a window's properties.
public struct WindowInfo: Sendable {
    public let id: UInt32
    public let pid: Int32
    public let title: String
    public let frame: CGRect
    public let isResizable: Bool
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let subrole: WindowSubrole

    public init(
        id: UInt32,
        pid: Int32,
        title: String,
        frame: CGRect,
        isResizable: Bool,
        isMinimized: Bool,
        isFullscreen: Bool,
        subrole: WindowSubrole
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
        self.isResizable = isResizable
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.subrole = subrole
    }
}
