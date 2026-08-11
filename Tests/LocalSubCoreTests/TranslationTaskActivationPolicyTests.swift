import XCTest
@testable import LocalSubCore

final class TranslationTaskActivationPolicyTests: XCTestCase {
    func testRepeatedRouteInvalidatesExistingConfiguration() {
        var policy = TranslationTaskActivationPolicy()
        let route = TranslationRoute(source: "en", target: "ja")

        XCTAssertEqual(policy.activate(route), .create(route))
        XCTAssertEqual(policy.activate(route), .invalidate)
        XCTAssertEqual(policy.activate(route), .invalidate)
    }

    func testChangedRouteCreatesNewConfiguration() {
        var policy = TranslationTaskActivationPolicy()
        let englishToJapanese = TranslationRoute(source: "en", target: "ja")
        let japaneseToEnglish = TranslationRoute(source: "ja", target: "en")

        XCTAssertEqual(policy.activate(englishToJapanese), .create(englishToJapanese))
        XCTAssertEqual(policy.activate(japaneseToEnglish), .create(japaneseToEnglish))
    }
}
