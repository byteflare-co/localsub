import XCTest
@testable import LocalSubApple

final class OpenAIAPIKeyStoreTests: XCTestCase {
    func testStoresUpdatesAndDeletesKeyInKeychain() throws {
        let store = OpenAIAPIKeyStore(service: "com.byteflare.localsub.tests.\(UUID().uuidString)")
        defer { try? store.delete() }

        XCTAssertNil(try store.read())
        try store.save("  sk-test-first  ")
        XCTAssertEqual(try store.read(), "sk-test-first")

        try store.save("sk-test-second")
        XCTAssertEqual(try store.read(), "sk-test-second")

        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testRejectsEmptyKey() {
        let store = OpenAIAPIKeyStore(service: "com.byteflare.localsub.tests.\(UUID().uuidString)")

        XCTAssertThrowsError(try store.save(" \n ")) { error in
            XCTAssertEqual(error as? OpenAIAPIKeyStoreError, .emptyKey)
        }
    }
}
