import Foundation

public enum LocalSubError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidTime
    case invalidRange
    case invalidCue(String)
    case overlappingCues
    case invalidTranslationBatch(String)
    case invalidTransition(from: JobState, event: String)
    case resourceLimit(String)
    case unsupportedMedia(String)

    public var description: String {
        switch self {
        case .invalidTime: "Invalid rational time"
        case .invalidRange: "Invalid time range"
        case .invalidCue(let reason): "Invalid display cue: \(reason)"
        case .overlappingCues: "Display cues overlap"
        case .invalidTranslationBatch(let reason): "Invalid translation batch: \(reason)"
        case .invalidTransition(let state, let event): "Invalid transition from \(state): \(event)"
        case .resourceLimit(let resource): "Resource limit exceeded: \(resource)"
        case .unsupportedMedia(let reason): "Unsupported media: \(reason)"
        }
    }
}
