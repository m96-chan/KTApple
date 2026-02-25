import AppKit
import CoreGraphics
import Foundation
import KTAppleCore

// MARK: - CGS Private API declarations

/// Connection ID for the current window server session.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

/// Returns a CFArray of dictionaries describing per-display spaces.
/// Each dictionary has "Display Identifier" (String) and "Spaces" (Array of dicts with "id64").
/// The current space has "Current Space" with an "id64" key.
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray?

final class LiveSpaceProvider: SpaceProvider {
    private var observer: NSObjectProtocol?

    func activeSpaceID(for displayID: UInt32) -> Int {
        let spaces = displaySpaceInfo()
        let uuid = displayUUID(for: displayID)
        guard let entry = spaces.first(where: { $0.uuid == uuid }),
              let current = entry.currentSpaceID else {
            return 0
        }
        return current
    }

    func spaceIDs(for displayID: UInt32) -> [Int] {
        let spaces = displaySpaceInfo()
        let uuid = displayUUID(for: displayID)
        guard let entry = spaces.first(where: { $0.uuid == uuid }) else {
            return []
        }
        return entry.spaceIDs
    }

    func startObserving(callback: @escaping () -> Void) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            callback()
        }
    }

    func stopObserving() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    // MARK: - Private

    private struct DisplaySpaceEntry {
        let uuid: String
        let spaceIDs: [Int]
        let currentSpaceID: Int?
    }

    private func displaySpaceInfo() -> [DisplaySpaceEntry] {
        let cid = CGSMainConnectionID()
        guard let cfArray = CGSCopyManagedDisplaySpaces(cid) else { return [] }

        let displays = cfArray as [AnyObject]
        var entries: [DisplaySpaceEntry] = []

        for display in displays {
            guard let dict = display as? [String: AnyObject] else { continue }
            guard let uuid = dict["Display Identifier"] as? String else { continue }

            var spaceIDs: [Int] = []
            if let spacesArray = dict["Spaces"] as? [[String: AnyObject]] {
                for space in spacesArray {
                    if let id = space["id64"] as? Int {
                        spaceIDs.append(id)
                    }
                }
            }

            var currentID: Int?
            if let current = dict["Current Space"] as? [String: AnyObject],
               let id = current["id64"] as? Int {
                currentID = id
            }

            entries.append(DisplaySpaceEntry(uuid: uuid, spaceIDs: spaceIDs, currentSpaceID: currentID))
        }

        return entries
    }

    /// Convert a CGDirectDisplayID to its UUID string, matching the format from CGSCopyManagedDisplaySpaces.
    private func displayUUID(for displayID: UInt32) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return ""
    }
}
