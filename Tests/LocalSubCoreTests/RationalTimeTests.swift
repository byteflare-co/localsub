import XCTest
@testable import LocalSubCore

final class RationalTimeTests: XCTestCase {
    func testRejectsInvalidTimescaleAndNegativeValue() {
        XCTAssertThrowsError(try RationalTime(value: 1, timescale: 0))
        XCTAssertThrowsError(try RationalTime(value: -1, timescale: 1))
    }

    func testComparesDifferentTimescalesExactly() throws {
        let half = try RationalTime(value: 1, timescale: 2)
        let fiveHundredMilliseconds = try RationalTime(value: 500, timescale: 1_000)
        let later = try RationalTime(value: 501, timescale: 1_000)

        XCTAssertEqual(half, fiveHundredMilliseconds)
        XCTAssertLessThan(half, later)
    }

    func testRoundsToSRTMilliseconds() throws {
        XCTAssertEqual(try RationalTime(value: 1_234_499, timescale: 1_000_000).srtMilliseconds(), 1_234)
        XCTAssertEqual(try RationalTime(value: 1_234_500, timescale: 1_000_000).srtMilliseconds(), 1_235)
    }
}
