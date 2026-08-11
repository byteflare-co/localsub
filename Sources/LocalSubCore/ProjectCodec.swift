import Foundation

public struct ProjectCodec: Sendable {
    public static let maximumProjectBytes = 16 * 1024 * 1024
    public init() {}

    public func encode(_ project: CaptionProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(project)
        guard data.count <= Self.maximumProjectBytes else { throw LocalSubError.resourceLimit("project JSON") }
        return data
    }

    public func decode(_ data: Data) throws -> CaptionProject {
        guard data.count <= Self.maximumProjectBytes else { throw LocalSubError.resourceLimit("project JSON") }
        let project = try JSONDecoder().decode(CaptionProject.self, from: data)
        try CaptionProject.validateDisplayCues(project.displayCues)
        return project
    }
}

