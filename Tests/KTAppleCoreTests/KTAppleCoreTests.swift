import Testing
@testable import KTAppleCore

@Suite("KTAppleCore")
struct KTAppleCoreTests {
    @Test func version() {
        #expect(KTAppleCore.version == "0.1.0")
    }
}
