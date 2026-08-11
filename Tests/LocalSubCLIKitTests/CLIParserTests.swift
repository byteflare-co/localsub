import XCTest
@testable import LocalSubCLIKit

final class CLIParserTests: XCTestCase {
    func testHelpAndVersionCommands() throws {
        XCTAssertEqual(try CLIParser.parse([]), .help)
        XCTAssertEqual(try CLIParser.parse(["help"]), .help)
        XCTAssertEqual(try CLIParser.parse(["--help"]), .help)
        XCTAssertEqual(try CLIParser.parse(["-h"]), .help)
        XCTAssertEqual(try CLIParser.parse(["version"]), .version)
        XCTAssertEqual(try CLIParser.parse(["--version"]), .version)
        XCTAssertEqual(LocalSubVersion.current, "0.1.0-alpha.2")
    }

    func testParsesDoctorAndSetupCommands() throws {
        XCTAssertEqual(
            try CLIParser.parse(["doctor", "--language", "english", "--translation", "luna"]),
            .doctor(.init(language: .english, translationMode: .gpt56Luna))
        )
        XCTAssertEqual(
            try CLIParser.parse(["setup", "--language", "japanese", "--accept-model-download"]),
            .setup(.init(language: .japanese, acceptsModelDownload: true))
        )
        XCTAssertEqual(
            try CLIParser.parse(["setup"]),
            .setup(.init(language: .japanese, acceptsModelDownload: false))
        )
    }

    func testParsesLegacyAndExplicitGenerateCommands() throws {
        let legacy = try CLIParser.parse([
            "input.mp4", "--output", "output.mp4", "--language", "english",
            "--translation", "luna", "--glossary", "terms.txt",
            "--acknowledge-luna-data-transfer",
        ])
        let explicit = try CLIParser.parse([
            "generate", "input.mp4", "--output", "output.mp4", "--language", "english",
            "--translation", "luna", "--glossary", "terms.txt",
            "--acknowledge-luna-data-transfer",
        ])

        XCTAssertEqual(legacy, explicit)
        guard case .generate(let options) = legacy else {
            return XCTFail("Expected generate command")
        }
        XCTAssertEqual(options.input.lastPathComponent, "input.mp4")
        XCTAssertEqual(options.output.lastPathComponent, "output.mp4")
        XCTAssertEqual(options.language, .english)
        XCTAssertEqual(options.translationMode, .gpt56Luna)
        XCTAssertEqual(options.glossary?.lastPathComponent, "terms.txt")
        XCTAssertTrue(options.acknowledgesLunaDataTransfer)
    }

    func testRejectsMissingGenerateOutputAndUnknownOptions() {
        XCTAssertThrowsError(try CLIParser.parse(["input.mp4"]))
        XCTAssertThrowsError(try CLIParser.parse(["doctor", "--unknown"]))
        XCTAssertThrowsError(try CLIParser.parse(["setup", "--translation", "luna"]))
        XCTAssertThrowsError(try CLIParser.parse(["generate"]))
    }

    func testDoctorReportFailsOnlyOnBlockingChecks() {
        let ready = DoctorReport(checks: [
            .init(name: "platform", status: .pass, detail: "Apple Silicon / macOS 26"),
            .init(name: "translation", status: .warning, detail: "first-use UI may be required"),
        ])
        let blocked = DoctorReport(checks: [
            .init(name: "speech", status: .fail, detail: "model is not installed"),
        ])

        XCTAssertTrue(ready.isReady)
        XCTAssertFalse(blocked.isReady)
        XCTAssertTrue(ready.rendered().contains("PASS platform"))
        XCTAssertTrue(ready.rendered().contains("WARN translation"))
        XCTAssertTrue(blocked.rendered().contains("FAIL speech"))
    }
}
