import XCTest
@testable import LocalSubCore

final class ProjectValidationTests: XCTestCase {
    func testRejectsOverlappingDisplayCues() throws {
        let first = DisplayCue(
            id: "cue-1",
            text: "最初の字幕",
            range: try .init(start: .zero, end: .seconds(2))
        )
        let second = DisplayCue(
            id: "cue-2",
            text: "重なる字幕",
            range: try .init(start: .seconds(1), end: .seconds(3))
        )

        XCTAssertThrowsError(try CaptionProject.validateDisplayCues([first, second]))
    }

    func testRejectsControlCharactersAndMoreThanTwoLines() throws {
        let range = try RationalTimeRange(start: .zero, end: .seconds(2))
        XCTAssertThrowsError(try DisplayCue.validated(id: "a", text: "bad\u{0000}", range: range))
        XCTAssertThrowsError(try DisplayCue.validated(id: "b", text: "一\n二\n三", range: range))
    }
}
