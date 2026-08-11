import XCTest
@testable import LocalSubCore

final class JobLeaseTests: XCTestCase {
    func testRestartInvalidatesEarlierLease() {
        var gate = JobLeaseGate()
        let old = gate.begin()
        let current = gate.begin()

        XCTAssertFalse(gate.isCurrent(old))
        XCTAssertTrue(gate.isCurrent(current))
    }

    func testCancelInvalidatesCurrentLease() {
        var gate = JobLeaseGate()
        let lease = gate.begin()
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(lease))
    }
}

