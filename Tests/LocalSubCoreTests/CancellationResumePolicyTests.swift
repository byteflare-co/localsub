import XCTest
@testable import LocalSubCore

final class CancellationResumePolicyTests: XCTestCase {
    func testExportCancellationReturnsToReviewWhenCuesExist() {
        XCTAssertEqual(
            CancellationResumePolicy.destination(hasSource: true, hasReviewableCues: true),
            .review
        )
    }

    func testProcessingCancellationReturnsToReadyWithoutCues() {
        XCTAssertEqual(
            CancellationResumePolicy.destination(hasSource: true, hasReviewableCues: false),
            .ready
        )
    }

    func testCancellationWithoutSourceReturnsToEmpty() {
        XCTAssertEqual(
            CancellationResumePolicy.destination(hasSource: false, hasReviewableCues: true),
            .empty
        )
    }
}
