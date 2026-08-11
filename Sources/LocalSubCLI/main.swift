import Foundation
import LocalSubApple
import LocalSubCLIKit
import LocalSubCloud
import LocalSubCore

enum CLIRuntimeError: Error, LocalizedError {
    case noSpeech
    case lunaConsentRequired
    case modelDownloadConsentRequired
    case doctorNotReady

    var errorDescription: String? {
        switch self {
        case .noSpeech:
            "No speech was recognized."
        case .lunaConsentRequired:
            "\(CloudPrivacyDisclosure.confirmation)\n内容を確認し、同意する場合だけ --acknowledge-luna-data-transfer を指定してください。"
        case .modelDownloadConsentRequired:
            "Apple Speechモデルをダウンロードします。同意する場合だけ --accept-model-download を指定してください。"
        case .doctorNotReady:
            "Environment is not ready. Resolve the FAIL checks above and run 'localsub doctor' again."
        }
    }
}

func writeStandardOutput(_ value: String) {
    FileHandle.standardOutput.write(Data("\(value)\n".utf8))
}

func writeStandardError(_ value: String) {
    FileHandle.standardError.write(Data("\(value)\n".utf8))
}

func report(_ stage: String) {
    writeStandardError("{\"stage\":\"\(stage)\"}")
}

func locale(for language: SourceLanguage) -> Locale {
    language == .japanese ? Locale(identifier: "ja-JP") : Locale(identifier: "en-US")
}

func doctor(_ options: DoctorOptions) async throws {
    var checks: [DiagnosticCheck] = []

    #if arch(arm64)
    checks.append(.init(name: "architecture", status: .pass, detail: "Apple Silicon (arm64)"))
    #else
    checks.append(.init(name: "architecture", status: .fail, detail: "Apple Silicon (arm64) is required"))
    #endif

    let version = ProcessInfo.processInfo.operatingSystemVersion
    if version.majorVersion >= 26 {
        checks.append(.init(
            name: "macOS",
            status: .pass,
            detail: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        ))
    } else {
        checks.append(.init(name: "macOS", status: .fail, detail: "macOS 26 or later is required"))
    }

    let speechLocale = locale(for: options.language)
    switch await AppleSpeechTranscriber.modelStatus(locale: speechLocale) {
    case .installed:
        checks.append(.init(name: "speech", status: .pass, detail: "\(speechLocale.identifier) model is installed"))
    case .notInstalled:
        checks.append(.init(
            name: "speech",
            status: .fail,
            detail: "\(speechLocale.identifier) model is missing; run 'localsub setup --language \(options.language.rawValue) --accept-model-download'"
        ))
    case .unavailable:
        checks.append(.init(name: "speech", status: .fail, detail: "\(speechLocale.identifier) is unavailable"))
    }

    if options.language == .japanese {
        checks.append(.init(name: "translation", status: .pass, detail: "not required for Japanese speech"))
    } else {
        switch options.translationMode {
        case .appleLocal:
            checks.append(.init(
                name: "translation",
                status: .warning,
                detail: "Apple en→ja assets must already be installed; first-use consent is available in the LocalSub app"
            ))
        case .gpt56Luna:
            let hasKey = !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
            checks.append(.init(
                name: "OPENAI_API_KEY",
                status: hasKey ? .pass : .fail,
                detail: hasKey ? "available to this process" : "required for --translation luna"
            ))
        }
    }

    let report = DoctorReport(checks: checks)
    writeStandardOutput(report.rendered())
    writeStandardOutput(report.isReady ? "READY" : "NOT READY")
    guard report.isReady else { throw CLIRuntimeError.doctorNotReady }
}

func setup(_ options: SetupOptions) async throws {
    guard options.acceptsModelDownload else {
        throw CLIRuntimeError.modelDownloadConsentRequired
    }
    let speechLocale = locale(for: options.language)
    report("installing-speech-model")
    try await AppleSpeechTranscriber().install(locale: speechLocale)
    report("completed")
    writeStandardOutput("Installed Apple Speech model for \(speechLocale.identifier).")
}

func generate(_ options: GenerateOptions) async throws {
    guard CloudPrivacyDisclosure.permitsCLI(
        mode: options.translationMode,
        acknowledged: options.acknowledgesLunaDataTransfer
    ) else { throw CLIRuntimeError.lunaConsentRequired }
    if options.translationMode == .gpt56Luna {
        writeStandardError(CloudPrivacyDisclosure.confirmation)
    }
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("localsub-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: temporary) }

    report("inspecting")
    _ = try await MediaInspector().inspect(options.input)
    let speechLocale = locale(for: options.language)
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
    switch await AppleSpeechTranscriber.modelStatus(locale: speechLocale) {
    case .installed: break
    case .notInstalled: throw ApplePipelineError.localeNotInstalled(speechLocale.identifier)
    case .unavailable: throw ApplePipelineError.localeUnavailable(speechLocale.identifier)
    }
    report("extracting-audio")
    try await AudioExtractor().extract(from: options.input, to: temporary)
    report("transcribing")
    var timed = try await AppleSpeechTranscriber().transcribe(
        audioURL: temporary,
        locale: speechLocale,
        contextualStrings: glossary.map(\.source)
    )
    guard !timed.isEmpty else { throw CLIRuntimeError.noSpeech }

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

func run() async throws {
    switch try CLIParser.parse(Array(CommandLine.arguments.dropFirst())) {
    case .help:
        writeStandardOutput(CLIHelp.text)
    case .version:
        writeStandardOutput("localsub \(LocalSubVersion.current)")
    case .doctor(let options):
        try await doctor(options)
    case .setup(let options):
        try await setup(options)
    case .generate(let options):
        try await generate(options)
    }
}

do {
    try await run()
} catch {
    writeStandardError("localsub: \(error.localizedDescription)")
    switch error {
    case is CLIParseError, CLIRuntimeError.modelDownloadConsentRequired, CLIRuntimeError.lunaConsentRequired:
        exit(64)
    default:
        exit(1)
    }
}
