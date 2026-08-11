import XCTest
@testable import LocalSubCore

final class ProjectCodecTests: XCTestCase {
    func testRoundTripsVersionedProject() throws {
        let cue = try DisplayCue.validated(
            id: "cue-1",
            text: "こんにちは",
            range: .init(start: .milliseconds(0), end: .milliseconds(1200))
        )
        let project = try CaptionProject(displayCues: [cue])

        let data = try ProjectCodec().encode(project)
        XCTAssertEqual(try ProjectCodec().decode(data), project)
    }

    func testRejectsOversizedInputBeforeDecode() throws {
        let data = Data(repeating: 0x20, count: ProjectCodec.maximumProjectBytes + 1)
        XCTAssertThrowsError(try ProjectCodec().decode(data))
    }

    func testRejectsDecodedInvalidSchemaAndTimeInvariants() throws {
        let invalidDocuments = [
            #"{"schemaVersion":2,"displayCues":[]}"#,
            #"{"schemaVersion":1,"displayCues":[{"id":"cue-1","text":"本文","range":{"start":{"value":0,"timescale":0},"end":{"value":1,"timescale":1}},"warnings":[]}] }"#,
            #"{"schemaVersion":1,"displayCues":[{"id":"cue-1","text":"本文","range":{"start":{"value":-1,"timescale":1},"end":{"value":1,"timescale":1}},"warnings":[]}] }"#,
            #"{"schemaVersion":1,"displayCues":[{"id":"cue-1","text":"本文","range":{"start":{"value":2,"timescale":1},"end":{"value":1,"timescale":1}},"warnings":[]}] }"#,
        ]

        for document in invalidDocuments {
            XCTAssertThrowsError(try ProjectCodec().decode(Data(document.utf8)))
        }
    }
}
