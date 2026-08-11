import XCTest
@testable import LocalSubCore

final class JobStateMachineTests: XCTestCase {
    func testEnglishPipelineIncludesTranslation() throws {
        var machine = JobStateMachine()
        try machine.apply(.selectedMedia)
        try machine.apply(.inspectionSucceeded(needsModelInstall: false))
        try machine.apply(.generationStarted(sourceLanguage: .english))
        try machine.apply(.transcriptionSucceeded)
        XCTAssertEqual(machine.state, .translating)
        try machine.apply(.translationSucceeded)
        XCTAssertEqual(machine.state, .buildingCues)
    }

    func testCancellationMustBeAcknowledgedBeforeReady() throws {
        var machine = JobStateMachine()
        try machine.apply(.selectedMedia)
        try machine.apply(.cancelRequested)
        XCTAssertEqual(machine.state, .cancelling)
        XCTAssertThrowsError(try machine.apply(.selectedMedia))
        try machine.apply(.cancellationAcknowledged)
        XCTAssertEqual(machine.state, .cancelled)
        try machine.apply(.reset)
        XCTAssertEqual(machine.state, .idle)
    }

    func testRejectsUnlistedTransition() {
        var machine = JobStateMachine()
        XCTAssertThrowsError(try machine.apply(.exportStarted))
    }
}
