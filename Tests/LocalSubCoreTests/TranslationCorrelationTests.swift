import XCTest
@testable import LocalSubCore

final class TranslationCorrelationTests: XCTestCase {
    func testCorrelatesReorderedResponsesByRequestID() throws {
        let requests = [
            TranslationRequest(id: "a", sourceSpanIDs: ["s1"], text: "Hello"),
            TranslationRequest(id: "b", sourceSpanIDs: ["s2"], text: "World"),
        ]
        let responses = [
            TranslationResponse(requestID: "b", text: "世界"),
            TranslationResponse(requestID: "a", text: "こんにちは"),
        ]

        let units = try TranslationCorrelator.correlate(requests: requests, responses: responses)

        XCTAssertEqual(units.map(\.sourceSpanIDs), [["s1"], ["s2"]])
        XCTAssertEqual(units.map(\.text), ["こんにちは", "世界"])
    }

    func testRejectsDuplicateMissingUnknownAndEmptyResponses() {
        let request = TranslationRequest(id: "a", sourceSpanIDs: ["s1"], text: "Hello")
        XCTAssertThrowsError(try TranslationCorrelator.correlate(requests: [request], responses: []))
        XCTAssertThrowsError(try TranslationCorrelator.correlate(
            requests: [request],
            responses: [.init(requestID: "a", text: "訳"), .init(requestID: "a", text: "重複")]
        ))
        XCTAssertThrowsError(try TranslationCorrelator.correlate(
            requests: [request], responses: [.init(requestID: "unknown", text: "訳")]
        ))
        XCTAssertThrowsError(try TranslationCorrelator.correlate(
            requests: [request], responses: [.init(requestID: "a", text: "  ")]
        ))
    }
}
