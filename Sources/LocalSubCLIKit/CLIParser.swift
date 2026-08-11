import Foundation
import LocalSubCore

public enum LocalSubVersion {
    public static let current = "0.1.0-alpha.1"
}

public struct GenerateOptions: Sendable, Equatable {
    public let input: URL
    public let output: URL
    public let language: SourceLanguage
    public let translationMode: EnglishTranslationMode
    public let glossary: URL?
    public let acknowledgesLunaDataTransfer: Bool

    public init(
        input: URL,
        output: URL,
        language: SourceLanguage,
        translationMode: EnglishTranslationMode,
        glossary: URL?,
        acknowledgesLunaDataTransfer: Bool
    ) {
        self.input = input
        self.output = output
        self.language = language
        self.translationMode = translationMode
        self.glossary = glossary
        self.acknowledgesLunaDataTransfer = acknowledgesLunaDataTransfer
    }
}

public struct DoctorOptions: Sendable, Equatable {
    public let language: SourceLanguage
    public let translationMode: EnglishTranslationMode

    public init(language: SourceLanguage, translationMode: EnglishTranslationMode) {
        self.language = language
        self.translationMode = translationMode
    }
}

public struct SetupOptions: Sendable, Equatable {
    public let language: SourceLanguage
    public let acceptsModelDownload: Bool

    public init(language: SourceLanguage, acceptsModelDownload: Bool) {
        self.language = language
        self.acceptsModelDownload = acceptsModelDownload
    }
}

public enum CLICommand: Sendable, Equatable {
    case help
    case version
    case doctor(DoctorOptions)
    case setup(SetupOptions)
    case generate(GenerateOptions)
}

public enum CLIParseError: Error, LocalizedError, Equatable {
    case invalidArguments

    public var errorDescription: String? {
        "Invalid arguments. Run 'localsub --help' for usage."
    }
}

public enum CLIParser {
    public static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else { return .help }
        switch first {
        case "help", "--help", "-h":
            guard arguments.count == 1 else { throw CLIParseError.invalidArguments }
            return .help
        case "version", "--version":
            guard arguments.count == 1 else { throw CLIParseError.invalidArguments }
            return .version
        case "doctor":
            return .doctor(try parseDoctor(Array(arguments.dropFirst())))
        case "setup":
            return .setup(try parseSetup(Array(arguments.dropFirst())))
        case "generate":
            return .generate(try parseGenerate(Array(arguments.dropFirst())))
        default:
            return .generate(try parseGenerate(arguments))
        }
    }

    private static func parseDoctor(_ arguments: [String]) throws -> DoctorOptions {
        var language = SourceLanguage.japanese
        var translationMode = EnglishTranslationMode.appleLocal
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--language" where index + 1 < arguments.count:
                language = try parseLanguage(arguments[index + 1])
                index += 2
            case "--translation" where index + 1 < arguments.count:
                translationMode = try parseTranslationMode(arguments[index + 1])
                index += 2
            default:
                throw CLIParseError.invalidArguments
            }
        }
        return DoctorOptions(language: language, translationMode: translationMode)
    }

    private static func parseSetup(_ arguments: [String]) throws -> SetupOptions {
        var language = SourceLanguage.japanese
        var acceptsModelDownload = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--language" where index + 1 < arguments.count:
                language = try parseLanguage(arguments[index + 1])
                index += 2
            case "--accept-model-download":
                acceptsModelDownload = true
                index += 1
            default:
                throw CLIParseError.invalidArguments
            }
        }
        return SetupOptions(language: language, acceptsModelDownload: acceptsModelDownload)
    }

    private static func parseGenerate(_ arguments: [String]) throws -> GenerateOptions {
        guard let input = arguments.first, !input.hasPrefix("-") else {
            throw CLIParseError.invalidArguments
        }
        var output: String?
        var language = SourceLanguage.japanese
        var translationMode = EnglishTranslationMode.appleLocal
        var glossary: String?
        var acknowledgesLunaDataTransfer = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--output" where index + 1 < arguments.count:
                output = arguments[index + 1]
                index += 2
            case "--language" where index + 1 < arguments.count:
                language = try parseLanguage(arguments[index + 1])
                index += 2
            case "--translation" where index + 1 < arguments.count:
                translationMode = try parseTranslationMode(arguments[index + 1])
                index += 2
            case "--glossary" where index + 1 < arguments.count:
                glossary = arguments[index + 1]
                index += 2
            case "--acknowledge-luna-data-transfer":
                acknowledgesLunaDataTransfer = true
                index += 1
            default:
                throw CLIParseError.invalidArguments
            }
        }
        guard let output else { throw CLIParseError.invalidArguments }
        return GenerateOptions(
            input: fileURL(input),
            output: fileURL(output),
            language: language,
            translationMode: translationMode,
            glossary: glossary.map(fileURL),
            acknowledgesLunaDataTransfer: acknowledgesLunaDataTransfer
        )
    }

    private static func parseLanguage(_ value: String) throws -> SourceLanguage {
        guard let language = SourceLanguage(rawValue: value) else {
            throw CLIParseError.invalidArguments
        }
        return language
    }

    private static func parseTranslationMode(_ value: String) throws -> EnglishTranslationMode {
        switch value {
        case "apple": return .appleLocal
        case "luna": return .gpt56Luna
        default: throw CLIParseError.invalidArguments
        }
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

public enum CLIHelp {
    public static let text = """
    LocalSub \(LocalSubVersion.current)
    Generate editable Japanese captions and a captioned video on Apple Silicon.

    USAGE
      localsub INPUT --output OUTPUT.mp4 [OPTIONS]
      localsub generate INPUT --output OUTPUT.mp4 [OPTIONS]
      localsub doctor [--language japanese|english] [--translation apple|luna]
      localsub setup [--language japanese|english] --accept-model-download
      localsub --version
      localsub --help

    GENERATE OPTIONS
      --language japanese|english       Source speech language (default: japanese)
      --translation apple|luna          English-to-Japanese provider (default: apple)
      --glossary FILE                    UTF-8 source=日本語 glossary, up to 32 KiB
      --acknowledge-luna-data-transfer  Required when using Luna

    REQUIREMENTS
      Apple Silicon, macOS 26 or later, and an installed Apple Speech model.
      Run 'localsub doctor' before the first video.

    UPDATE CHECK
      LocalSub checks GitHub Releases at most once every 24 hours and only prints a notice.
      Set LOCALSUB_NO_UPDATE_CHECK=1 to disable the metadata request.
    """
}

public enum DiagnosticStatus: String, Sendable, Equatable {
    case pass = "PASS"
    case warning = "WARN"
    case fail = "FAIL"
}

public struct DiagnosticCheck: Sendable, Equatable {
    public let name: String
    public let status: DiagnosticStatus
    public let detail: String

    public init(name: String, status: DiagnosticStatus, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct DoctorReport: Sendable, Equatable {
    public let checks: [DiagnosticCheck]

    public init(checks: [DiagnosticCheck]) {
        self.checks = checks
    }

    public var isReady: Bool {
        !checks.contains { $0.status == .fail }
    }

    public func rendered() -> String {
        checks.map { "\($0.status.rawValue) \($0.name): \($0.detail)" }.joined(separator: "\n")
    }
}
