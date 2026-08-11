import Foundation

public struct GlossaryEntry: Codable, Sendable, Hashable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public enum GlossaryParser {
    public static let maximumUTF8Bytes = 32 * 1_024

    public static func parse(_ text: String) throws -> [GlossaryEntry] {
        guard text.utf8.count <= maximumUTF8Bytes else {
            throw LocalSubError.resourceLimit("glossary text")
        }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count <= 100 else {
            throw LocalSubError.resourceLimit("glossary entries")
        }
        var entries: [GlossaryEntry] = []
        var sources: Set<String> = []
        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let separator = line.firstIndex(of: "=") else {
                throw LocalSubError.invalidTranslationBatch("glossary line requires source=target")
            }
            let source = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let target = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty, !target.isEmpty, source.count <= 120, target.count <= 120 else {
                throw LocalSubError.invalidTranslationBatch("invalid glossary entry")
            }
            guard displayHalfUnits(target) <= CuePolicy.defaultJapanese.maxLineHalfUnits else {
                throw LocalSubError.invalidTranslationBatch("glossary target exceeds one-line caption width")
            }
            guard !containsControlCharacters(source), !containsControlCharacters(target) else {
                throw LocalSubError.invalidTranslationBatch("control character in glossary")
            }
            let normalized = source.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en"))
            guard sources.insert(normalized).inserted else {
                throw LocalSubError.invalidTranslationBatch("duplicate glossary source")
            }
            entries.append(.init(source: source, target: target))
        }
        return entries
    }

    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private static func displayHalfUnits(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { $0 + ($1.value <= 0x7F ? 1 : 2) }
    }
}

public enum CloudPrivacyDisclosure {
    public static let confirmation = """
    動画・音声は送信しません。Macで文字起こしした英文と入力した用語集だけをGPT-5.6 Lunaへ送信します。\
    store:falseでResponse自体の保存は無効にしますが、OpenAIの既定設定では不正利用監視ログに最大30日、\
    暗号化されたプロンプトキャッシュに最大24時間保持される場合があります。組織・プロジェクトのデータ保持設定に依存します。
    """

    public static func permitsCLI(mode: EnglishTranslationMode, acknowledged: Bool) -> Bool {
        mode != .gpt56Luna || acknowledged
    }
}
