import XCTest
@testable import LocalSubCore

final class GlossaryTests: XCTestCase {
    func testParsesOneEntryPerLineAndRejectsMalformedOrDuplicateSources() throws {
        let entries = try GlossaryParser.parse("""
        Managed Agent = マネージドエージェント
        ship=提供する
        """)

        XCTAssertEqual(entries, [
            GlossaryEntry(source: "Managed Agent", target: "マネージドエージェント"),
            GlossaryEntry(source: "ship", target: "提供する"),
        ])
        XCTAssertThrowsError(try GlossaryParser.parse("missing separator"))
        XCTAssertThrowsError(try GlossaryParser.parse("ship=提供する\nship=出荷する"))
    }

    func testLimitsGlossarySizeAndControlCharacters() throws {
        XCTAssertThrowsError(try GlossaryParser.parse("bad\u{0007}=値"))
        let oversized = (0..<101).map { "term\($0)=訳\($0)" }.joined(separator: "\n")
        XCTAssertThrowsError(try GlossaryParser.parse(oversized))
    }

    func testRejectsOversizedTextBeforeParsingLines() {
        let oversized = String(repeating: "x", count: 32 * 1_024 + 1)

        XCTAssertThrowsError(try GlossaryParser.parse(oversized))
    }

    func testRejectsTargetThatCannotFitOnOneCaptionLine() throws {
        XCTAssertNoThrow(try GlossaryParser.parse("term=\(String(repeating: "語", count: 24))"))
        XCTAssertNoThrow(try GlossaryParser.parse("term=\(String(repeating: "x", count: 48))"))
        XCTAssertThrowsError(try GlossaryParser.parse("term=\(String(repeating: "語", count: 25))"))
        XCTAssertThrowsError(try GlossaryParser.parse("term=\(String(repeating: "x", count: 49))"))
    }

    func testCloudDisclosureStatesDefaultMaximumRetention() {
        XCTAssertTrue(CloudPrivacyDisclosure.confirmation.contains("store:false"))
        XCTAssertTrue(CloudPrivacyDisclosure.confirmation.contains("最大30日"))
        XCTAssertTrue(CloudPrivacyDisclosure.confirmation.contains("最大24時間"))
        XCTAssertTrue(CloudPrivacyDisclosure.confirmation.contains("組織・プロジェクト"))
    }

    func testCLIRequiresExplicitAcknowledgementOnlyForLuna() {
        XCTAssertTrue(CloudPrivacyDisclosure.permitsCLI(mode: .appleLocal, acknowledged: false))
        XCTAssertFalse(CloudPrivacyDisclosure.permitsCLI(mode: .gpt56Luna, acknowledged: false))
        XCTAssertTrue(CloudPrivacyDisclosure.permitsCLI(mode: .gpt56Luna, acknowledged: true))
    }
}
