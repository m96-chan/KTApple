import CoreGraphics
import Foundation
import os.log

/// Monitors display configuration changes and notifies its delegate.
///
/// Tracks connected displays and detects additions, removals, and resizes
/// by comparing snapshots on each refresh cycle.
public final class DisplayObserver {
    private static let log = AppLog.logger(for: "DisplayObserver")
    private let provider: DisplayProvider

    /// Delegate receiving display change events.
    public weak var delegate: DisplayObserverDelegate?

    /// Last known display state, keyed by display ID.
    private var knownDisplays: [UInt32: DisplayInfo] = [:]

    public init(provider: DisplayProvider) {
        self.provider = provider
    }

    // MARK: - Query

    /// Get currently connected displays from the provider.
    public func connectedDisplays() -> [DisplayInfo] {
        provider.connectedDisplays()
    }

    // MARK: - Observation

    /// Start observing display reconfiguration events.
    public func startObserving() {
        Self.log.debug("startObserving")
        provider.startObserving { [weak self] in
            self?.refresh()
        }
    }

    /// Stop observing display reconfiguration events.
    public func stopObserving() {
        Self.log.debug("stopObserving")
        provider.stopObserving()
    }

    // MARK: - Refresh

    /// Compare current display state with known state and fire delegate events.
    public func refresh() {
        let current = provider.connectedDisplays()
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        let currentIDs = Set(currentByID.keys)
        let knownIDs = Set(knownDisplays.keys)

        // Detect new displays
        for id in currentIDs.subtracting(knownIDs) {
            if let display = currentByID[id] {
                Self.log.info("refresh: display connected id=\(id)")
                delegate?.displayDidConnect(display)
            }
        }

        // Detect removed displays
        for id in knownIDs.subtracting(currentIDs) {
            Self.log.info("refresh: display disconnected id=\(id)")
            delegate?.displayDidDisconnect(displayID: id)
        }

        // Detect resized displays
        for id in currentIDs.intersection(knownIDs) {
            if let current = currentByID[id], let known = knownDisplays[id] {
                if current.frame != known.frame {
                    Self.log.info("refresh: display resized id=\(id) frame=\(String(describing: current.frame))")
                    delegate?.displayDidResize(current)
                }
            }
        }

        knownDisplays = currentByID
    }

    // MARK: - Direct Event Handlers (for external use)

    /// Manually signal that a display was connected.
    public func handleDisplayConnected(_ display: DisplayInfo) {
        knownDisplays[display.id] = display
        delegate?.displayDidConnect(display)
    }

    /// Manually signal that a display was disconnected.
    public func handleDisplayDisconnected(displayID: UInt32) {
        knownDisplays.removeValue(forKey: displayID)
        delegate?.displayDidDisconnect(displayID: displayID)
    }

    /// Manually signal that a display was resized.
    public func handleDisplayResized(_ display: DisplayInfo) {
        knownDisplays[display.id] = display
        delegate?.displayDidResize(display)
    }
}
