import CoreGraphics
import Foundation

/// Manages window operations using an AccessibilityProvider.
///
/// Handles window discovery, move/resize, tile assignment, and auto-float detection.
public final class WindowManager {
    private let provider: AccessibilityProvider

    /// Currently tracked windows, keyed by window ID.
    public private(set) var trackedWindows: [UInt32: WindowInfo] = [:]

    /// Original frames before tiling, keyed by window ID.
    private var originalFrames: [UInt32: CGRect] = [:]

    public init(provider: AccessibilityProvider) {
        self.provider = provider
    }

    // MARK: - Discovery

    /// Discover all visible windows and update tracked state.
    @discardableResult
    public func discoverWindows() -> [WindowInfo] {
        let windows = provider.discoverWindows()
        trackedWindows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        return windows
    }

    /// Get cached info for a window ID.
    public func windowInfo(for id: UInt32) -> WindowInfo? {
        trackedWindows[id]
    }

    // MARK: - Move & Resize

    /// Move a window to a new position.
    public func moveWindow(id: UInt32, to position: CGPoint) {
        provider.moveWindow(id: id, to: position)
    }

    /// Resize a window to a new size.
    public func resizeWindow(id: UInt32, to size: CGSize) {
        provider.resizeWindow(id: id, to: size)
    }

    /// Set a window's frame using the three-step resize workaround.
    ///
    /// macOS enforces size constraints when moving between displays.
    /// The correct sequence is: size → position → size.
    public func setWindowFrame(id: UInt32, frame: CGRect) {
        provider.resizeWindow(id: id, to: frame.size)
        provider.moveWindow(id: id, to: frame.origin)
        provider.resizeWindow(id: id, to: frame.size)
    }

    // MARK: - Tile Assignment

    /// Save the window's current live frame as its pre-tiling original (only if not already saved).
    public func saveOriginalFrame(id: UInt32) {
        if originalFrames[id] == nil {
            originalFrames[id] = provider.windowFrame(id: id)
        }
    }

    /// Assign a window to a tile and move/resize it to fit.
    public func assignWindow(id: UInt32, to tile: Tile, tileManager: TileManager) {
        // Save current frame before tiling (only if not already saved)
        if originalFrames[id] == nil {
            originalFrames[id] = provider.windowFrame(id: id)
        }
        tile.addWindow(id: id)
        let frame = tileManager.frame(for: tile)
        setWindowFrame(id: id, frame: frame)
    }

    /// Remove a window from a tile and restore its original size (if saved).
    public func unassignWindow(id: UInt32, from tile: Tile) {
        tile.removeWindow(id: id)
        if let original = originalFrames.removeValue(forKey: id) {
            resizeWindow(id: id, to: original.size)
        }
    }

    // MARK: - Auto-Float Detection

    /// Determine if a window should be treated as floating.
    public static func shouldFloat(_ window: WindowInfo) -> Bool {
        if !window.isResizable { return true }
        if window.isMinimized { return true }

        switch window.subrole {
        case .dialog, .systemDialog, .floatingWindow:
            return true
        case .standardWindow, .unknown:
            return false
        }
    }
}
