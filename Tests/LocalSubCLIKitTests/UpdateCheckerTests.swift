import Foundation
import XCTest
@testable import LocalSubCLIKit

final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionOrdersPrereleasesAndStableVersions() throws {
        let alpha1 = try XCTUnwrap(SemanticVersion("0.1.0-alpha.1"))
        let alpha2 = try XCTUnwrap(SemanticVersion("v0.1.0-alpha.2"))
        let beta = try XCTUnwrap(SemanticVersion("0.1.0-beta.1"))
        let stable = try XCTUnwrap(SemanticVersion("0.1.0"))
        let next = try XCTUnwrap(SemanticVersion("0.2.0"))

        XCTAssertLessThan(alpha1, alpha2)
        XCTAssertLessThan(alpha2, beta)
        XCTAssertLessThan(beta, stable)
        XCTAssertLessThan(stable, next)
        XCTAssertNil(SemanticVersion("release-latest"))
    }

    func testStableChannelDoesNotOfferPrereleases() throws {
        let data = Data(#"""
        [
          {"tag_name":"v0.2.0-alpha.1","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.2.0-alpha.1","draft":false,"prerelease":true},
          {"tag_name":"v0.1.1","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.1.1","draft":false,"prerelease":false}
        ]
        """#.utf8)

        let release = try XCTUnwrap(UpdateReleaseSelector.newestPublishedRelease(
            in: data,
            includingPrereleases: false
        ))
        XCTAssertEqual(release.version.description, "0.1.1")
    }

    func testSelectsNewestValidPublishedRelease() throws {
        let data = Data(#"""
        [
          {"tag_name":"v0.1.0-alpha.2","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.1.0-alpha.2","draft":false},
          {"tag_name":"v0.2.0","html_url":"https://example.com/not-localsub","draft":false},
          {"tag_name":"v9.0.0","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v9.0.0","draft":true},
          {"tag_name":"invalid","html_url":"https://github.com/byteflare-co/localsub/releases/tag/invalid","draft":false}
        ]
        """#.utf8)

        let release = try XCTUnwrap(UpdateReleaseSelector.newestPublishedRelease(in: data))
        XCTAssertEqual(release.version.description, "0.1.0-alpha.2")
        XCTAssertEqual(
            release.url.absoluteString,
            "https://github.com/byteflare-co/localsub/releases/tag/v0.1.0-alpha.2"
        )
    }

    func testChecksAtMostOncePerDayAndReturnsNewerReleaseNotice() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-update-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("update.json")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let response = Data(#"""
        [{"tag_name":"v0.1.0-alpha.2","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.1.0-alpha.2","draft":false}]
        """#.utf8)
        let calls = CallCounter()
        let checker = CLIUpdateChecker(cacheURL: cacheURL, now: { now }) {
            await calls.increment()
            return response
        }

        let first = await checker.check(currentVersion: "0.1.0-alpha.1")
        let second = await checker.check(currentVersion: "0.1.0-alpha.1")

        XCTAssertEqual(first?.latestVersion, "0.1.0-alpha.2")
        XCTAssertTrue(first?.rendered.contains("brew upgrade byteflare-co/tap/localsub") == true)
        XCTAssertNil(second)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
    }

    func testNetworkFailureIsSilentAndThrottled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-update-failure-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("update.json")
        let now = Date(timeIntervalSince1970: 3_000_000)
        let calls = CallCounter()
        let checker = CLIUpdateChecker(cacheURL: cacheURL, now: { now }) {
            await calls.increment()
            throw URLError(.notConnectedToInternet)
        }

        let first = await checker.check(currentVersion: "0.1.0-alpha.1")
        let second = await checker.check(currentVersion: "0.1.0-alpha.1")
        XCTAssertNil(first)
        XCTAssertNil(second)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
