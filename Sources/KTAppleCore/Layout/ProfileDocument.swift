import Foundation

/// Top-level container for persisted layout profiles.
public struct ProfileDocument: Codable, Sendable {
    public var version: Int
    public var profiles: [LayoutProfile]

    public init(version: Int = 1, profiles: [LayoutProfile] = []) {
        self.version = version
        self.profiles = profiles
    }
}
