import Foundation

public enum CueWarning: String, Codable, Sendable, Hashable {
    case readingSpeedExceeded
}

public struct TimedText: Codable, Sendable, Hashable {
    public let text: String
    public let range: RationalTimeRange

    public init(text: String, range: RationalTimeRange) {
        self.text = text
        self.range = range
    }
}

public struct DisplayCue: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var text: String
    public var range: RationalTimeRange
    public var warnings: Set<CueWarning>

    public init(id: String, text: String, range: RationalTimeRange, warnings: Set<CueWarning> = []) {
        self.id = id
        self.text = text
        self.range = range
        self.warnings = warnings
    }

    public static func validated(
        id: String,
        text: String,
        range: RationalTimeRange,
        warnings: Set<CueWarning> = []
    ) throws -> DisplayCue {
        guard !id.isEmpty else { throw LocalSubError.invalidCue("missing ID") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalSubError.invalidCue("empty text")
        }
        guard text.unicodeScalars.count <= 512 else { throw LocalSubError.invalidCue("text too long") }
        guard text.split(separator: "\n", omittingEmptySubsequences: false).count <= 2 else {
            throw LocalSubError.invalidCue("more than two lines")
        }
        let forbiddenControl = text.unicodeScalars.contains { scalar in
            scalar == "\n" ? false : scalar.properties.generalCategory == .control
        }
        guard !forbiddenControl else { throw LocalSubError.invalidCue("control character") }
        return DisplayCue(id: id, text: text, range: range, warnings: warnings)
    }

    private enum CodingKeys: String, CodingKey { case id, text, range, warnings }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self.validated(
            id: container.decode(String.self, forKey: .id),
            text: container.decode(String.self, forKey: .text),
            range: container.decode(RationalTimeRange.self, forKey: .range),
            warnings: container.decodeIfPresent(Set<CueWarning>.self, forKey: .warnings) ?? []
        )
    }
}

public struct CaptionProject: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public var displayCues: [DisplayCue]

    public init(schemaVersion: Int = 1, displayCues: [DisplayCue]) throws {
        guard schemaVersion == 1 else { throw LocalSubError.invalidCue("unsupported schema") }
        try Self.validateDisplayCues(displayCues)
        self.schemaVersion = schemaVersion
        self.displayCues = displayCues
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, displayCues }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            displayCues: container.decode([DisplayCue].self, forKey: .displayCues)
        )
    }

    public static func validateDisplayCues(_ cues: [DisplayCue]) throws {
        guard cues.count <= 10_000 else { throw LocalSubError.invalidCue("too many cues") }
        var previousEnd: RationalTime?
        for cue in cues {
            _ = try DisplayCue.validated(id: cue.id, text: cue.text, range: cue.range, warnings: cue.warnings)
            if let previousEnd, cue.range.start < previousEnd {
                throw LocalSubError.overlappingCues
            }
            previousEnd = cue.range.end
        }
    }
}
