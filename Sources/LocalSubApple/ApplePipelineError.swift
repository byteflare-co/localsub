import Foundation

public enum ApplePipelineError: Error, LocalizedError, Sendable {
    case localeUnavailable(String)
    case localeNotInstalled(String)
    case missingAudio
    case exportUnavailable
    case captionBitmapBudgetExceeded
    case captionTextDoesNotFit
    case staleJob

    public var errorDescription: String? {
        switch self {
        case .localeUnavailable(let locale): "音声認識モデル（\(locale)）を利用できません。"
        case .localeNotInstalled(let locale): "音声認識モデル（\(locale)）が未導入です。Desktopアプリで準備してください。"
        case .missingAudio: "動画に音声トラックがありません。"
        case .exportUnavailable: "この動画を変換できません。"
        case .captionBitmapBudgetExceeded: "字幕が多すぎるため、安全なメモリ上限内で動画を書き出せません。"
        case .captionTextDoesNotFit: "2行に収まらない字幕があります。字幕を短くしてから再度書き出してください。"
        case .staleJob: "古い処理結果を破棄しました。"
        }
    }
}
