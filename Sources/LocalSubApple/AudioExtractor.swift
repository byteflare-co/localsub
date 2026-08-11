import AVFoundation
import Foundation

public actor AudioExtractor {
    private var session: AVAssetExportSession?
    public init() {}

    public func extract(from videoURL: URL, to audioURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw ApplePipelineError.missingAudio
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ApplePipelineError.exportUnavailable
        }
        self.session = session
        defer { self.session = nil }
        try await session.export(to: audioURL, as: .m4a)
    }

    public func cancel() {
        session?.cancelExport()
        session = nil
    }
}

