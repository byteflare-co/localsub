import Foundation
import Darwin

public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    private enum Identifier: Comparable, Sendable {
        case numeric(Int)
        case text(String)

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case (.numeric(let left), .numeric(let right)):
                left < right
            case (.numeric, .text):
                true
            case (.text, .numeric):
                false
            case (.text(let left), .text(let right)):
                left < right
            }
        }
    }

    private let major: Int
    private let minor: Int
    private let patch: Int
    private let prerelease: [Identifier]
    public let description: String
    public var isPrerelease: Bool { !prerelease.isEmpty }

    public init?(_ rawValue: String) {
        let version = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let withoutBuild = version.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard let precedence = withoutBuild.first, !precedence.isEmpty,
              withoutBuild.count <= 2 else { return nil }
        if withoutBuild.count == 2 {
            let values = withoutBuild[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !values.isEmpty, values.allSatisfy({ value in
                !value.isEmpty && value.allSatisfy {
                    $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
                }
            }) else { return nil }
        }
        let mainAndPrerelease = precedence.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let core = mainAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Self.parseNumericIdentifier(core[0]),
              let minor = Self.parseNumericIdentifier(core[1]),
              let patch = Self.parseNumericIdentifier(core[2]) else { return nil }

        var prerelease: [Identifier] = []
        if mainAndPrerelease.count == 2 {
            let values = mainAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !values.isEmpty else { return nil }
            for value in values {
                guard !value.isEmpty,
                      value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                    return nil
                }
                if value.allSatisfy(\.isNumber) {
                    guard let numeric = Self.parseNumericIdentifier(value) else { return nil }
                    prerelease.append(.numeric(numeric))
                } else {
                    prerelease.append(.text(String(value)))
                }
            }
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.description = version
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let leftCore = [lhs.major, lhs.minor, lhs.patch]
        let rightCore = [rhs.major, rhs.minor, rhs.patch]
        if leftCore != rightCore {
            return leftCore.lexicographicallyPrecedes(rightCore)
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        return lhs.prerelease.lexicographicallyPrecedes(rhs.prerelease)
    }

    private static func parseNumericIdentifier(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber),
              value.count == 1 || value.first != "0" else { return nil }
        return Int(value)
    }
}

public struct PublishedUpdateRelease: Sendable, Equatable {
    public let version: SemanticVersion
    public let url: URL
}

public enum UpdateReleaseSelector {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    public static func newestPublishedRelease(
        in data: Data,
        includingPrereleases: Bool = true
    ) throws -> PublishedUpdateRelease? {
        guard data.count <= 256 * 1_024 else { return nil }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        return releases.compactMap { release in
            guard !release.draft,
                  let version = SemanticVersion(release.tagName),
                  includingPrereleases || (!(release.prerelease ?? false) && !version.isPrerelease),
                  release.htmlURL == "https://github.com/byteflare-co/localsub/releases/tag/\(release.tagName)",
                  let url = URL(string: release.htmlURL) else {
                return nil
            }
            return PublishedUpdateRelease(version: version, url: url)
        }.max { $0.version < $1.version }
    }
}

public struct CLIUpdateNotice: Sendable, Equatable {
    public let currentVersion: String
    public let latestVersion: String
    public let releaseURL: URL

    public var rendered: String {
        """
        LocalSub \(latestVersion) が利用できます（現在 \(currentVersion)）。
        Homebrew更新: brew upgrade byteflare-co/tap/localsub
        詳細: \(releaseURL.absoluteString)
        """
    }

    public var progressJSON: String {
        let value: [String: String] = [
            "stage": "update-available",
            "current_version": currentVersion,
            "latest_version": latestVersion,
            "release_url": releaseURL.absoluteString,
            "upgrade_command": "brew upgrade byteflare-co/tap/localsub",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"stage":"update-available"}"#
        }
        return json
    }
}

public enum BoundedResponseData {
    public static func collect<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        maxBytes: Int
    ) async throws -> Data where Bytes.Element == UInt8 {
        precondition(maxBytes >= 0)
        var data = Data()
        data.reserveCapacity(min(maxBytes, 16 * 1_024))
        for try await byte in bytes {
            guard data.count < maxBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
        return data
    }
}

public struct UpdateCheckPreferenceStore: Sendable {
    private struct Preference: Codable {
        let enabled: Bool
    }

    public static var defaultURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("co.byteflare.localsub", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    private let url: URL

    public init(url: URL = UpdateCheckPreferenceStore.defaultURL) {
        self.url = url
    }

    public func isEnabled() -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= 4 * 1_024,
              let preference = try? JSONDecoder().decode(Preference.self, from: data) else {
            return false
        }
        return preference.enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(Preference(enabled: enabled))
        try data.write(to: url, options: [.atomic])
    }
}

private final class UpdateCheckFileLock {
    private let descriptor: Int32

    init?(url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

public actor CLIUpdateChecker {
    public typealias FetchReleases = @Sendable () async throws -> Data

    private struct Cache: Codable {
        let checkedAt: Date
        let latestVersion: String?
        let releaseURL: URL?
    }

    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static var defaultCacheURL: URL {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cacheRoot
            .appendingPathComponent("co.byteflare.localsub", isDirectory: true)
            .appendingPathComponent("update-check.json")
    }

    private let cacheURL: URL
    private let now: @Sendable () -> Date
    private let fetchReleases: FetchReleases

    public init(
        cacheURL: URL = CLIUpdateChecker.defaultCacheURL,
        now: @escaping @Sendable () -> Date = Date.init,
        fetchReleases: @escaping FetchReleases
    ) {
        self.cacheURL = cacheURL
        self.now = now
        self.fetchReleases = fetchReleases
    }

    public func check(currentVersion: String) async -> CLIUpdateNotice? {
        guard let lock = UpdateCheckFileLock(
            url: cacheURL.appendingPathExtension("lock")
        ) else { return nil }
        defer { _ = lock }
        let checkTime = now()
        let previous = readCache()
        if let previous {
            let age = checkTime.timeIntervalSince(previous.checkedAt)
            if age >= 0, age < Self.checkInterval {
                return nil
            }
        }

        do {
            let data = try await fetchReleases()
            guard let current = SemanticVersion(currentVersion) else { return nil }
            let release = try UpdateReleaseSelector.newestPublishedRelease(
                in: data,
                includingPrereleases: current.isPrerelease
            )
            writeCache(Cache(
                checkedAt: checkTime,
                latestVersion: release?.version.description,
                releaseURL: release?.url
            ))
            guard let release,
                  current < release.version else { return nil }
            return CLIUpdateNotice(
                currentVersion: currentVersion,
                latestVersion: release.version.description,
                releaseURL: release.url
            )
        } catch {
            writeCache(Cache(
                checkedAt: checkTime,
                latestVersion: previous?.latestVersion,
                releaseURL: previous?.releaseURL
            ))
            return nil
        }
    }

    private func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL, options: [.mappedIfSafe]),
              data.count <= 16 * 1_024 else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func writeCache(_ cache: Cache) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            // Update checks are advisory and must never make the CLI fail.
        }
    }
}
