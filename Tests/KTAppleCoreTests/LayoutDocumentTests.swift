import Foundation
import Testing
@testable import KTAppleCore

@Suite("LayoutDocument")
struct LayoutDocumentTests {

    @Test func emptyDocument() {
        let doc = LayoutDocument()
        #expect(doc.version == 1)
        #expect(doc.layouts.isEmpty)
    }

    @Test func setAndGetLayout() {
        var doc = LayoutDocument()
        let key = LayoutKey(displayID: 1, workspaceIndex: 0)
        let snapshot = TileSnapshot(proportion: 1.0)

        doc.setLayout(snapshot, for: key)

        let retrieved = doc.layout(for: key)
        #expect(retrieved != nil)
        #expect(retrieved?.proportion == 1.0)
    }

    @Test func removeLayout() {
        var doc = LayoutDocument()
        let key = LayoutKey(displayID: 1, workspaceIndex: 0)
        let snapshot = TileSnapshot(proportion: 1.0)

        doc.setLayout(snapshot, for: key)
        doc.removeLayout(for: key)

        #expect(doc.layout(for: key) == nil)
    }

    @Test func jsonRoundTrip() throws {
        var doc = LayoutDocument()
        let key = LayoutKey(displayID: 1, workspaceIndex: 0)
        doc.setLayout(TileSnapshot(proportion: 0.5), for: key)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(LayoutDocument.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.layout(for: key)?.proportion == 0.5)
    }
}
