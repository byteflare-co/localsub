import AVFoundation
import Foundation
import Speech
import LocalSubCore

public actor AppleSpeechTranscriber {
    public enum ModelStatus: Sendable, Equatable {
        case unavailable
        case notInstalled
        case installed
    }

    private var analyzer: SpeechAnalyzer?

    public init() {}

    public static func containsEquivalentLocale(_ locale: Locale, in installedLocales: [Locale]) -> Bool {
        let requested = Locale.Language(identifier: locale.identifier)
        return installedLocales.contains {
            Locale.Language(identifier: $0.identifier) == requested
        }
    }

    public static func installed(locale: Locale) async -> Bool {
        await modelStatus(locale: locale) == .installed
    }

    public static func modelStatus(locale: Locale) async -> ModelStatus {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unavailable
        }
        return containsEquivalentLocale(supported, in: await SpeechTranscriber.installedLocales)
            ? .installed : .notInstalled
    }

    public func install(locale: Locale) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ApplePipelineError.localeUnavailable(locale.identifier)
        }
        if Self.containsEquivalentLocale(supported, in: await SpeechTranscriber.installedLocales) { return }
        let transcriber = SpeechTranscriber(locale: supported, preset: .timeIndexedTranscriptionWithAlternatives)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard Self.containsEquivalentLocale(supported, in: await SpeechTranscriber.installedLocales) else {
            throw ApplePipelineError.localeNotInstalled(locale.identifier)
        }
    }

    public func transcribe(
        audioURL: URL,
        locale: Locale,
        contextualStrings: [String] = []
    ) async throws -> [TimedText] {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ApplePipelineError.localeUnavailable(locale.identifier)
        }
        guard Self.containsEquivalentLocale(supported, in: await SpeechTranscriber.installedLocales) else {
            throw ApplePipelineError.localeNotInstalled(locale.identifier)
        }
        let audioFile = try AVAudioFile(forReading: audioURL)
        let transcriber = SpeechTranscriber(locale: supported, preset: .timeIndexedTranscriptionWithAlternatives)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(contextualStrings.prefix(100))
            try await analyzer.setContext(context)
        }
        self.analyzer = analyzer

        let resultTask = Task { () throws -> [TimedText] in
            var output: [TimedText] = []
            for try await result in transcriber.results where result.isFinal {
                try Task.checkCancellation()
                let start = max(CMTimeGetSeconds(result.range.start), 0)
                let end = max(CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)), start + 0.001)
                let range = try RationalTimeRange(
                    start: .milliseconds(Int64((start * 1000).rounded())),
                    end: .milliseconds(Int64((end * 1000).rounded()))
                )
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { output.append(TimedText(text: text, range: range)) }
            }
            return output
        }

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let results = try await resultTask.value
            self.analyzer = nil
            return results
        } catch {
            resultTask.cancel()
            self.analyzer = nil
            throw error
        }
    }

    public func cancel() async {
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
    }
}
