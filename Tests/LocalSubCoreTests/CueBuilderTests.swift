import XCTest
@testable import LocalSubCore

final class CueBuilderTests: XCTestCase {
    func testBuildsNonOverlappingJapaneseCuesWithAtMostTwoLines() throws {
        let spans = [
            TimedText(text: "今日は字幕生成について説明します。", range: try .init(start: .zero, end: .seconds(3))),
            TimedText(text: "英語の動画も日本語に翻訳できます。", range: try .init(start: .seconds(3), end: .seconds(7))),
        ]

        let cues = try CueBuilder(policy: .defaultJapanese).build(from: spans)

        XCTAssertFalse(cues.isEmpty)
        XCTAssertTrue(cues.allSatisfy { $0.text.split(separator: "\n", omittingEmptySubsequences: false).count <= 2 })
        XCTAssertNoOverlap(cues)
    }

    func testDefaultJapaneseKeepsFortyEightFullWidthCharactersInOneTwoLineCue() throws {
        let input = TimedText(
            text: String(repeating: "あ", count: 48),
            range: try .init(start: .zero, end: .seconds(8))
        )

        let cues = try CueBuilder(
            policy: .defaultJapanese,
            protectedTerms: []
        ).build(from: [input])

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text.replacingOccurrences(of: "\n", with: ""), input.text)
        XCTAssertLessThanOrEqual(cues[0].text.split(separator: "\n").count, 2)
    }

    func testWarnsInsteadOfDeletingTextWhenReadingSpeedIsTooHigh() throws {
        let input = TimedText(
            text: "非常に短い時間に大量の日本語が含まれていても内容を勝手に削除しません",
            range: try .init(start: .zero, end: .milliseconds(500))
        )

        let cues = try CueBuilder(policy: .defaultJapanese).build(from: [input])

        XCTAssertEqual(cues.map(\.text).joined().replacingOccurrences(of: "\n", with: ""), input.text)
        XCTAssertTrue(cues.contains { $0.warnings.contains(.readingSpeedExceeded) })
    }

    func testDoesNotLeaveJapaneseAuxiliaryVerbAtStartOfLineOrCue() throws {
        let input = TimedText(
            text: "これはプログラム的に構築できる最初の方法になります。",
            range: try .init(start: .zero, end: .seconds(8))
        )
        let policy = CuePolicy(maxLineHalfUnits: 20, maxLines: 2, maxReadingUnitsPerSecond: 20)

        let cues = try CueBuilder(policy: policy).build(from: [input])
        let lines = cues.flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(lines.joined(), input.text)
        XCTAssertFalse(lines.contains { $0.hasPrefix("ます") })
        XCTAssertFalse(lines.contains { $0.hasSuffix("なり") })
    }

    func testDoesNotSplitLatinProductNamesInTheMiddle() throws {
        let input = TimedText(
            text: "AnthropicのClaude Codeを紹介します。",
            range: try .init(start: .zero, end: .seconds(6))
        )
        let policy = CuePolicy(maxLineHalfUnits: 12, maxLines: 2, maxReadingUnitsPerSecond: 20)

        let cues = try CueBuilder(policy: policy).build(from: [input])
        let lines = cues.flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(lines.joined(), input.text)
        XCTAssertTrue(lines.contains { $0.contains("Anthropic") })
        XCTAssertTrue(lines.contains { $0.contains("Claude") })
    }

    func testDoesNotSplitProtectedGlossaryTermInTheMiddle() throws {
        let input = TimedText(
            text: "今日は初めてのマネージドエージェントを提供するセッションです。",
            range: try .init(start: .zero, end: .seconds(8))
        )
        let policy = CuePolicy(maxLineHalfUnits: 26, maxLines: 2, maxReadingUnitsPerSecond: 20)

        let cues = try CueBuilder(
            policy: policy,
            protectedTerms: ["マネージドエージェント"]
        ).build(from: [input])
        let lines = cues.flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(lines.joined(), input.text)
        XCTAssertTrue(lines.contains { $0.contains("マネージドエージェント") })
    }

    func testPrefersCompletedSentenceOverFillingTheCue() throws {
        let input = TimedText(
            text: "今日はここで終わりにします。来てくださって、本当にありがとうございます。次のセッションもぜひお楽しみください。",
            range: try .init(start: .zero, end: .seconds(10))
        )

        let cues = try CueBuilder(policy: .defaultJapanese).build(from: [input])
        let normalized = cues.map { $0.text.replacingOccurrences(of: "\n", with: "") }

        XCTAssertEqual(normalized.joined(), input.text)
        XCTAssertEqual(normalized.first, "今日はここで終わりにします。来てくださって、本当にありがとうございます。")
    }

    func testDoesNotEndLineOrCueAtDependentNoParticle() throws {
        let input = TimedText(
            text: "では、さっそく進めましょう。ただ先ほど言ったように、手順の前に環境を確認します。",
            range: try .init(start: .zero, end: .seconds(12))
        )

        let cues = try CueBuilder(policy: .defaultJapanese).build(from: [input])
        let normalized = cues.map { $0.text.replacingOccurrences(of: "\n", with: "") }
        let lines = cues.flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(normalized.joined(), input.text)
        XCTAssertFalse(lines.dropLast().contains { $0.hasSuffix("手順の") })
    }

    func testKeepsVeryShortAcknowledgementWithFollowingSentence() throws {
        let input = TimedText(
            text: "はい。では、始めましょう。",
            range: try .init(start: .zero, end: .seconds(4))
        )

        let cues = try CueBuilder(policy: .defaultJapanese).build(from: [input])

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text.replacingOccurrences(of: "\n", with: ""), input.text)
    }

    func testDoesNotSeparateJapaneseHonorificPrefixFromFollowingWord() throws {
        let input = TimedText(
            text: "今日は、初めてのマネージドエージェントを提供するセッションにお越しいただき、ありがとうございます。",
            range: try .init(start: .zero, end: .seconds(12))
        )

        let cues = try CueBuilder(
            policy: .defaultJapanese,
            protectedTerms: ["マネージドエージェント"]
        ).build(from: [input])
        let lines = cues.flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(lines.joined(), input.text)
        XCTAssertFalse(lines.dropLast().contains { $0.hasSuffix("にお") })
        XCTAssertFalse(lines.dropFirst().contains { $0.hasPrefix("越し") })
    }

    func testDoesNotSplitJapaneseCompoundAtBalancedLineFallback() throws {
        let input = TimedText(
            text: "ただ、先ほどお伝えしたように、手順がどこにあるかを皆さんにお見せします。",
            range: try .init(start: .zero, end: .seconds(10))
        )

        let cues = try CueBuilder(policy: .defaultJapanese).build(from: [input])
        let lines = cues.flatMap { $0.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(lines.joined(), input.text)
        XCTAssertFalse(lines.dropLast().contains { $0.hasSuffix("手") })
        XCTAssertFalse(lines.dropFirst().contains { $0.hasPrefix("順") })
        XCTAssertTrue(lines.allSatisfy { testHalfUnits(in: $0) <= 48 })
    }

    func testBuildsFiveThousandJapaneseSentencesWithinBoundedTime() throws {
        let sentence = "これは専門用語0を含む日本語字幕の境界処理性能を確認する文章です。"
        let protectedTerms = (0..<100).map { "専門用語\($0)" }
        let input = TimedText(
            text: String(repeating: sentence, count: 5_000),
            range: try .init(start: .zero, end: .seconds(10_000))
        )
        let clock = ContinuousClock()

        let started = clock.now
        let cues = try CueBuilder(policy: .defaultJapanese, protectedTerms: protectedTerms).build(from: [input])
        let elapsed = started.duration(to: clock.now)

        XCTAssertEqual(cues.map(\.text).joined().replacingOccurrences(of: "\n", with: ""), input.text)
        XCTAssertGreaterThanOrEqual(cues.count, 5_000)
        XCTAssertLessThanOrEqual(cues.count, 10_000)
        // Keep this as a coarse regression guard rather than a machine benchmark. GitHub's
        // shared macOS runners are materially slower than a local Apple Silicon workstation.
        XCTAssertLessThan(elapsed, .seconds(20))
    }
}

private func XCTAssertNoOverlap(_ cues: [DisplayCue], file: StaticString = #filePath, line: UInt = #line) {
    for pair in zip(cues, cues.dropFirst()) {
        XCTAssertLessThanOrEqual(pair.0.range.end, pair.1.range.start, file: file, line: line)
    }
}

private func testHalfUnits(in text: String) -> Int {
    text.unicodeScalars.reduce(0) { result, scalar in
        result + (scalar.value <= 0x7F ? 1 : 2)
    }
}
