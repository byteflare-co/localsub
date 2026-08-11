import XCTest
@testable import LocalSubCore

final class TranslationPlannerTests: XCTestCase {
    func testGroupsAdjacentShortSentencesUntilEightSecondPreferredDisplayDuration() throws {
        let spans = [
            TimedText(text: "This is the first", range: try .init(start: .zero, end: .seconds(2))),
            TimedText(text: "way to build it.", range: try .init(start: .seconds(2), end: .seconds(4))),
            TimedText(text: "Next topic.", range: try .init(start: .seconds(4), end: .seconds(6))),
            TimedText(text: "More context.", range: try .init(start: .seconds(6), end: .seconds(8))),
        ]

        let units = try TranslationPlanner().plan(spans)

        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].request.text, "This is the first way to build it. Next topic. More context.")
        XCTAssertEqual(units[0].request.sourceSpanIDs, ["segment-0", "segment-1", "segment-2", "segment-3"])
        XCTAssertEqual(units[0].range, try .init(start: .zero, end: .seconds(8)))
    }

    func testStartsNewUnitAfterLongSilenceEvenWithoutPunctuation() throws {
        let spans = [
            TimedText(text: "First thought", range: try .init(start: .zero, end: .seconds(2))),
            TimedText(text: "Second thought", range: try .init(start: .seconds(4), end: .seconds(6))),
        ]

        let units = try TranslationPlanner(maxGapSeconds: 1, maxDurationSeconds: 12, maxCharacters: 300).plan(spans)

        XCTAssertEqual(units.map(\.request.text), ["First thought", "Second thought"])
    }

    func testNormalizesInvalidPreferredDuration() {
        XCTAssertEqual(TranslationPlanner(preferredDurationSeconds: .nan).preferredDurationSeconds, 0)
        XCTAssertEqual(TranslationPlanner(preferredDurationSeconds: -1).preferredDurationSeconds, 0)
        XCTAssertEqual(
            TranslationPlanner(maxDurationSeconds: 12, preferredDurationSeconds: 20).preferredDurationSeconds,
            12
        )
    }

    func testCapsTranslationContextWithoutDroppingSourceText() throws {
        let spans = [
            TimedText(text: "A long fragment without punctuation", range: try .init(start: .zero, end: .seconds(7))),
            TimedText(text: "continues here", range: try .init(start: .seconds(7), end: .seconds(14))),
        ]

        let units = try TranslationPlanner(maxGapSeconds: 1, maxDurationSeconds: 10, maxCharacters: 300).plan(spans)

        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units.map(\.request.text).joined(separator: " "), spans.map(\.text).joined(separator: " "))
    }

    func testSplitsSingleOversizedSpanAtWordBoundariesAndPartitionsTime() throws {
        let words = (0..<76).map { "word\($0)" }
        let source = words.joined(separator: " ")
        let span = TimedText(text: source, range: try .init(start: .seconds(2), end: .seconds(12)))

        let units = try TranslationPlanner(maxCharacters: 80).plan([span])

        XCTAssertGreaterThan(units.count, 1)
        XCTAssertTrue(units.allSatisfy { $0.request.text.count <= 80 })
        XCTAssertEqual(units.map(\.request.text).joined(separator: " "), source)
        XCTAssertEqual(units.first?.range.start, span.range.start)
        XCTAssertEqual(units.last?.range.end, span.range.end)
        for pair in zip(units, units.dropFirst()) {
            XCTAssertEqual(pair.0.range.end, pair.1.range.start)
        }
    }

    func testHardSplitsSingleTokenOverProviderLimitWithoutDroppingCharacters() throws {
        let source = String(repeating: "x", count: 2_001)
        let span = TimedText(text: source, range: try .init(start: .zero, end: .seconds(10)))

        let units = try TranslationPlanner(maxCharacters: 300).plan([span])

        XCTAssertTrue(units.allSatisfy { $0.request.text.count <= 300 })
        XCTAssertEqual(units.map(\.request.text).joined(), source)
        XCTAssertEqual(units.first?.range.start, span.range.start)
        XCTAssertEqual(units.last?.range.end, span.range.end)
    }
}
