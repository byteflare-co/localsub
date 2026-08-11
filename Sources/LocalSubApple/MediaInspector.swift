@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import LocalSubCore

public struct MediaInspector: Sendable {
    public init() {}

    public func inspect(_ url: URL) async throws -> MediaDescriptor {
        let container: MediaContainer
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": container = .mp4
        case "mov": container = .mov
        default: throw LocalSubError.unsupportedMedia("container")
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable), try await asset.load(.isPlayable) else {
            throw LocalSubError.unsupportedMedia("unreadable asset")
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let video = videoTracks.first else {
            throw LocalSubError.unsupportedMedia("missing video")
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audio = audioTracks.first else {
            throw LocalSubError.unsupportedMedia("missing audio")
        }
        let videoFormats = try await video.load(.formatDescriptions)
        let audioFormats = try await audio.load(.formatDescriptions)
        guard let videoFormat = videoFormats.first, let audioFormat = audioFormats.first else {
            throw LocalSubError.unsupportedMedia("missing format description")
        }
        let videoCodec: VideoCodec
        switch CMFormatDescriptionGetMediaSubType(videoFormat) {
        case kCMVideoCodecType_H264: videoCodec = .h264
        case kCMVideoCodecType_HEVC: videoCodec = .hevc
        default: throw LocalSubError.unsupportedMedia("video codec")
        }
        let audioCodec: LocalSubCore.AudioCodec
        switch CMFormatDescriptionGetMediaSubType(audioFormat) {
        case kAudioFormatMPEG4AAC: audioCodec = .aac
        case kAudioFormatLinearPCM: audioCodec = .pcm
        default: throw LocalSubError.unsupportedMedia("audio codec")
        }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: size).applying(transform)
        let duration = try await asset.load(.duration).seconds
        let frameRate = Double(try await video.load(.nominalFrameRate))
        guard let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat) else {
            throw LocalSubError.unsupportedMedia("audio description")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let descriptor = MediaDescriptor(
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            width: Int(abs(oriented.width)),
            height: Int(abs(oriented.height)),
            durationSeconds: duration,
            fileBytes: Int64(values.fileSize ?? 0),
            isHDR: Self.isHDR(videoFormat),
            videoTrackCount: videoTracks.count,
            audioTrackCount: audioTracks.count,
            nominalFrameRate: frameRate,
            audioChannelCount: Int(audioDescription.pointee.mChannelsPerFrame),
            audioSampleRate: audioDescription.pointee.mSampleRate
        )
        try MediaPolicy.desktopV1.validate(descriptor)
        return descriptor
    }

    private static func isHDR(_ description: CMFormatDescription) -> Bool {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any],
              let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String else {
            return false
        }
        return transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
            || transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
    }
}
