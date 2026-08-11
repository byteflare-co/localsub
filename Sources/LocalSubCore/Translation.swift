import Foundation

public enum EnglishTranslationMode: String, Codable, CaseIterable, Sendable {
    case appleLocal
    case gpt56Luna
}

public struct TranslationRoute: Sendable, Hashable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public enum TranslationTaskActivation: Sendable, Equatable {
    case create(TranslationRoute)
    case invalidate
}

public struct TranslationTaskActivationPolicy: Sendable {
    private var activeRoute: TranslationRoute?

    public init() {}

    public mutating func activate(_ route: TranslationRoute) -> TranslationTaskActivation {
        guard activeRoute == route else {
            activeRoute = route
            return .create(route)
        }
        return .invalidate
    }
}

public struct TranslationRequest: Sendable, Hashable {
    public let id: String
    public let sourceSpanIDs: [String]
    public let text: String

    public init(id: String, sourceSpanIDs: [String], text: String) {
        self.id = id
        self.sourceSpanIDs = sourceSpanIDs
        self.text = text
    }
}

public struct TranslationResponse: Sendable, Hashable {
    public let requestID: String
    public let text: String

    public init(requestID: String, text: String) {
        self.requestID = requestID
        self.text = text
    }
}

public struct TranslationUnit: Codable, Sendable, Hashable {
    public let sourceSpanIDs: [String]
    public let text: String
}

public enum TranslationCorrelator {
    public static func correlate(
        requests: [TranslationRequest],
        responses: [TranslationResponse]
    ) throws -> [TranslationUnit] {
        let requestIDs = requests.map(\.id)
        guard Set(requestIDs).count == requestIDs.count else {
            throw LocalSubError.invalidTranslationBatch("duplicate request ID")
        }
        var byID: [String: TranslationResponse] = [:]
        for response in responses {
            guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalSubError.invalidTranslationBatch("empty response")
            }
            guard byID[response.requestID] == nil else {
                throw LocalSubError.invalidTranslationBatch("duplicate response ID")
            }
            guard requestIDs.contains(response.requestID) else {
                throw LocalSubError.invalidTranslationBatch("unknown response ID")
            }
            byID[response.requestID] = response
        }
        guard byID.count == requests.count else {
            throw LocalSubError.invalidTranslationBatch("missing response")
        }
        return try requests.map { request in
            guard let response = byID[request.id] else {
                throw LocalSubError.invalidTranslationBatch("missing response")
            }
            return TranslationUnit(sourceSpanIDs: request.sourceSpanIDs, text: response.text)
        }
    }
}
