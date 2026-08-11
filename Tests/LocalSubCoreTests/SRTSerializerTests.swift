import XCTest
@testable import LocalSubCore

final class SRTSerializerTests: XCTestCase {
    func testSerializesUTF8TextAndRoundedTimes() throws {
        let cue = DisplayCue(
            id: "cue-1",
            text: "こんにちは\n世界",
            range: try .init(
                start: RationalTime(value: 1_234_500, timescale: 1_000_000),
                end: RationalTime(value: 3_000_400, timescale: 1_000_000)
            )
        )

        let output = try SRTSerializer.serialize([cue])

        XCTAssertEqual(output, "1\n00:00:01,235 --> 00:00:03,000\nこんにちは\n世界\n")
    }
}
