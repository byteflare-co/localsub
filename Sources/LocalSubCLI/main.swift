import Foundation
import LocalSubApple
import LocalSubCloud
import LocalSubCore

struct CLIOptions {
    let input: URL
    let output: URL
    let language: SourceLanguage
    let translationMode: EnglishTranslationMode
    let glossary: URL?
    let acknowledgesLunaDataTransfer: Bool

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        guard let input = arguments.first, input != "--help" else { throw CLIError.usage }
        var output: String?
        var language = SourceLanguage.japanese
        var translationMode = EnglishTranslationMode.appleLocal
        var glossary: String?
        var acknowledgesLunaDataTransfer = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--output" where index + 1 < arguments.count:
                output = arguments[index + 1]; index += 2
            case "--language" where index + 1 < arguments.count:
                guard let parsed = SourceLanguage(rawValue: arguments[index + 1]) else { throw CLIError.usage }
                language = parsed; index += 2
            case "--translation" where index + 1 < arguments.count:
                switch arguments[index + 1] {
                case "apple": translationMode = .appleLocal
                case "luna": translationMode = .gpt56Luna
                default: throw CLIError.usage
                }
                index += 2
            case "--glossary" where index + 1 < arguments.count:
                glossary = arguments[index + 1]; index += 2
            case "--acknowledge-luna-data-transfer":
                acknowledgesLunaDataTransfer = true; index += 1
            default: throw CLIError.usage
            }
        }
        guard let output else { throw CLIError.usage }
        return CLIOptions(
            input: URL(fileURLWithPath: input).standardizedFileURL,
            output: URL(fileURLWithPath: output).standardizedFileURL,
            language: language,
            translationMode: translationMode,
            glossary: glossary.map { URL(fileURLWithPath: $0).standardizedFileURL },
            acknowledgesLunaDataTransfer: acknowledgesLunaDataTransfer
        )
    }
}

enum CLIError: Error, LocalizedError {
    case usage
    case noSpeech
    case lunaConsentRequired
    var errorDescription: String? {
        switch self {
        case .usage: "Usage: localsub INPUT --output OUTPUT.mp4 --language japanese|english [--translation apple|luna] [--glossary terms.txt] [--acknowledge-luna-data-transfer]"
        case .noSpeech: "No speech was recognized."
        case .lunaConsentRequired:
            "\(CloudPrivacyDisclosure.confirmation)\n内容を確認し、同意する場合だけ --acknowledge-luna-data-transfer を指定してください。"
        }
    }
}

func report(_ stage: String) {
    FileHandle.standardError.write(Data("{\"stage\":\"\(stage)\"}\n".utf8))
}

func run() async throws {
    let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
    guard CloudPrivacyDisclosure.permitsCLI(
        mode: options.translationMode,
        acknowledged: options.acknowledgesLunaDataTransfer
    ) else { throw CLIError.lunaConsentRequired }
    if options.translationMode == .gpt56Luna {
        FileHandle.standardError.write(Data("\(CloudPrivacyDisclosure.confirmation)\n".utf8))
    }
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("localsub-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: temporary) }

    report("inspecting")
    _ = try await MediaInspector().inspect(options.input)
    let locale = options.language == .japanese ? Locale(identifier: "ja-JP") : Locale(identifier: "en-US")
    let glossaryText: String
    if let glossaryURL = options.glossary {
        let data = try Data(contentsOf: glossaryURL, options: [.mappedIfSafe])
        guard data.count <= 32 * 1_024, let text = String(data: data, encoding: .utf8) else {
            throw LocalSubError.resourceLimit("glossary file")
        }
        glossaryText = text
    } else {
        glossaryText = ""
    }
    let glossary = try GlossaryParser.parse(glossaryText)
    switch await AppleSpeechTranscriber.modelStatus(locale: locale) {
    case .installed: break
    case .notInstalled: throw ApplePipelineError.localeNotInstalled(locale.identifier)
    case .unavailable: throw ApplePipelineError.localeUnavailable(locale.identifier)
    }
    report("extracting-audio")
    try await AudioExtractor().extract(from: options.input, to: temporary)
    report("transcribing")
    var timed = try await AppleSpeechTranscriber().transcribe(
        audioURL: temporary,
        locale: locale,
        contextualStrings: glossary.map(\.source)
    )
    guard !timed.isEmpty else { throw CLIError.noSpeech }

    if options.language == .english {
        report("translating")
        let plan = try TranslationPlanner().plan(timed)
        let requests = plan.map(\.request)
        let responses: [TranslationResponse]
        switch options.translationMode {
        case .appleLocal:
            responses = try await AppleTranslationProvider().translateInstalled(requests)
        case .gpt56Luna:
            guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
                throw LunaTranslationError.missingAPIKey
            }
            responses = try await LunaTranslationProvider(apiKey: apiKey).translate(requests, glossary: glossary)
        }
        let translations = try TranslationCorrelator.correlate(requests: requests, responses: responses)
        timed = zip(plan, translations).map { TimedText(text: $1.text, range: $0.range) }
    }

    report("building-cues")
    let cues = try CueBuilder(
        policy: .defaultJapanese,
        protectedTerms: glossary.map(\.target)
    ).build(from: timed)
    report("exporting")
    try await SubtitleVideoExporter().export(videoURL: options.input, cues: cues, destinationURL: options.output)
    report("completed")
}

do {
    try await run()
} catch {
    FileHandle.standardError.write(Data("localsub: \(error.localizedDescription)\n".utf8))
    exit(error is CLIError ? 64 : 1)
}
