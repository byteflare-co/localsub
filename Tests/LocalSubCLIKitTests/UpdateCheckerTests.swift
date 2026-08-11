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
        XCTAssertNotNil(SemanticVersion("1.2.3+build.7"))
        XCTAssertNil(SemanticVersion("1.2.3+"))
        XCTAssertNil(SemanticVersion("1.2.3+bad_metadata"))
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

    func testRejectsReleaseURLsThatAreNotExact() throws {
        let data = Data(#"""
        [
          {"tag_name":"v0.1.4","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.1.4?from=cli","draft":false},
          {"tag_name":"v0.1.3","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.1.3#notes","draft":false},
          {"tag_name":"v0.1.2","html_url":"https://user@github.com/byteflare-co/localsub/releases/tag/v0.1.2","draft":false},
          {"tag_name":"v0.1.1","html_url":"https://github.com:443/byteflare-co/localsub/releases/tag/v0.1.1","draft":false}
        ]
        """#.utf8)

        XCTAssertNil(try UpdateReleaseSelector.newestPublishedRelease(in: data))
    }

    func testBoundedResponseStopsAtLimit() async throws {
        let exact = try await BoundedResponseData.collect(byteStream([1, 2, 3]), maxBytes: 3)
        XCTAssertEqual(exact, Data([1, 2, 3]))
        await XCTAssertThrowsErrorAsync {
            _ = try await BoundedResponseData.collect(byteStream([1, 2, 3, 4]), maxBytes: 3)
        }
    }

    func testUpdateCheckPreferenceDefaultsOffAndPersistsConsent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-update-preference-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UpdateCheckPreferenceStore(url: root.appendingPathComponent("preferences.json"))

        XCTAssertFalse(store.isEnabled())
        try store.setEnabled(true)
        XCTAssertTrue(store.isEnabled())
        try store.setEnabled(false)
        XCTAssertFalse(store.isEnabled())
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

    func testConcurrentCheckersShareANonblockingFileLock() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-update-concurrency-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("update.json")
        let now = Date(timeIntervalSince1970: 4_000_000)
        let response = Data(#"""
        [{"tag_name":"v0.1.0-alpha.2","html_url":"https://github.com/byteflare-co/localsub/releases/tag/v0.1.0-alpha.2","draft":false}]
        """#.utf8)
        let calls = CallCounter()
        let first = CLIUpdateChecker(cacheURL: cacheURL, now: { now }) {
            await calls.increment()
            try await Task.sleep(for: .milliseconds(100))
            return response
        }
        let second = CLIUpdateChecker(cacheURL: cacheURL, now: { now }) {
            await calls.increment()
            return response
        }

        async let firstResult = first.check(currentVersion: "0.1.0-alpha.1")
        try await Task.sleep(for: .milliseconds(20))
        async let secondResult = second.check(currentVersion: "0.1.0-alpha.1")
        _ = await (firstResult, secondResult)

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

private func byteStream(_ bytes: [UInt8]) -> AsyncStream<UInt8> {
    AsyncStream { continuation in
        for byte in bytes {
            continuation.yield(byte)
        }
        continuation.finish()
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}
