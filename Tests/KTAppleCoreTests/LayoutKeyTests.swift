import Foundation
import Testing
@testable import KTAppleCore

@Suite("LayoutKey")
struct LayoutKeyTests {

    @Test func stringKey() {
        let key = LayoutKey(displayID: 42, workspaceIndex: 3)
        #expect(key.stringKey == "42-3")
    }

    @Test func equality() {
        let a = LayoutKey(displayID: 1, workspaceIndex: 0)
        let b = LayoutKey(displayID: 1, workspaceIndex: 0)
        let c = LayoutKey(displayID: 1, workspaceIndex: 1)

        #expect(a == b)
        #expect(a != c)
    }

    @Test func jsonRoundTrip() throws {
        let key = LayoutKey(displayID: 99, workspaceIndex: 2)
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(LayoutKey.self, from: data)

        #expect(decoded.displayID == 99)
        #expect(decoded.workspaceIndex == 2)
    }
}
