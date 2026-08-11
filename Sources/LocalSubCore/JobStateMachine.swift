import Foundation

public enum SourceLanguage: String, Codable, Sendable, Hashable {
    case japanese
    case english
}

public enum JobState: String, Codable, Sendable, Hashable {
    case idle
    case inspecting
    case awaitingModelInstall
    case ready
    case transcribing
    case translating
    case buildingCues
    case review
    case exporting
    case completed
    case cancelling
    case cancelled
    case failed
}

public enum JobEvent: Sendable, Equatable {
    case selectedMedia
    case inspectionSucceeded(needsModelInstall: Bool)
    case inspectionFailed
    case modelInstallSucceeded
    case modelInstallFailed
    case generationStarted(sourceLanguage: SourceLanguage)
    case transcriptionSucceeded
    case translationSucceeded
    case cuesBuilt
    case exportStarted
    case exportSucceeded
    case operationFailed
    case cancelRequested
    case cancellationAcknowledged
    case reset
}

public struct JobStateMachine: Sendable {
    public private(set) var state: JobState = .idle
    private var sourceLanguage: SourceLanguage?

    public init() {}

    public mutating func apply(_ event: JobEvent) throws {
        switch (state, event) {
        case (.idle, .selectedMedia), (.ready, .selectedMedia), (.completed, .selectedMedia):
            state = .inspecting
        case (.inspecting, .inspectionSucceeded(let needsInstall)):
            state = needsInstall ? .awaitingModelInstall : .ready
        case (.inspecting, .inspectionFailed), (.awaitingModelInstall, .modelInstallFailed):
            state = .failed
        case (.awaitingModelInstall, .modelInstallSucceeded):
            state = .ready
        case (.ready, .generationStarted(let language)):
            sourceLanguage = language
            state = .transcribing
        case (.transcribing, .transcriptionSucceeded):
            state = sourceLanguage == .english ? .translating : .buildingCues
        case (.translating, .translationSucceeded):
            state = .buildingCues
        case (.buildingCues, .cuesBuilt):
            state = .review
        case (.review, .exportStarted):
            state = .exporting
        case (.exporting, .exportSucceeded):
            state = .completed
        case (.inspecting, .cancelRequested),
             (.awaitingModelInstall, .cancelRequested),
             (.transcribing, .cancelRequested),
             (.translating, .cancelRequested),
             (.buildingCues, .cancelRequested),
             (.exporting, .cancelRequested):
            state = .cancelling
        case (.cancelling, .cancellationAcknowledged):
            state = .cancelled
        case (.cancelled, .reset), (.failed, .reset), (.completed, .reset):
            sourceLanguage = nil
            state = .idle
        case (.inspecting, .operationFailed),
             (.awaitingModelInstall, .operationFailed),
             (.transcribing, .operationFailed),
             (.translating, .operationFailed),
             (.buildingCues, .operationFailed),
             (.exporting, .operationFailed):
            state = .failed
        default:
            throw LocalSubError.invalidTransition(from: state, event: String(describing: event))
        }
    }
}
