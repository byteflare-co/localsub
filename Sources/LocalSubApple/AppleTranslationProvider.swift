import Foundation
@preconcurrency import Translation
import LocalSubCore

@MainActor
public final class AppleTranslationProvider {
    private var session: TranslationSession?

    public init() {}

    public func translateInstalled(_ requests: [TranslationRequest]) async throws -> [TranslationResponse] {
        let session: TranslationSession
        if #available(macOS 26.4, *) {
            session = TranslationSession(
                installedSource: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ja"),
                preferredStrategy: .highFidelity
            )
        } else {
            session = TranslationSession(
                installedSource: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ja")
            )
        }
        self.session = session
        defer { self.session = nil }
        let native = requests.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
        }
        var output: [TranslationResponse] = []
        for try await response in session.translate(batch: native) {
            output.append(TranslationResponse(
                requestID: response.clientIdentifier ?? "",
                text: response.targetText
            ))
        }
        return output
    }

    public func cancel() {
        session?.cancel()
        session = nil
    }
}
