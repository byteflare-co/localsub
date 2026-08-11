public enum MediaContainer: String, Codable, Sendable { case mp4, mov }
public enum VideoCodec: String, Codable, Sendable { case h264, hevc }
public enum AudioCodec: String, Codable, Sendable { case aac, pcm }

public struct MediaDescriptor: Codable, Sendable, Hashable {
    public let container: MediaContainer
    public let videoCodec: VideoCodec
    public let audioCodec: AudioCodec
    public let width: Int
    public let height: Int
    public let durationSeconds: Double
    public let fileBytes: Int64
    public let isHDR: Bool
    public let videoTrackCount: Int
    public let audioTrackCount: Int
    public let nominalFrameRate: Double
    public let audioChannelCount: Int
    public let audioSampleRate: Double

    public init(container: MediaContainer, videoCodec: VideoCodec, audioCodec: AudioCodec,
                width: Int, height: Int, durationSeconds: Double, fileBytes: Int64, isHDR: Bool,
                videoTrackCount: Int = 1, audioTrackCount: Int = 1, nominalFrameRate: Double = 30,
                audioChannelCount: Int = 2, audioSampleRate: Double = 48_000) {
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.fileBytes = fileBytes
        self.isHDR = isHDR
        self.videoTrackCount = videoTrackCount
        self.audioTrackCount = audioTrackCount
        self.nominalFrameRate = nominalFrameRate
        self.audioChannelCount = audioChannelCount
        self.audioSampleRate = audioSampleRate
    }
}

public struct MediaPolicy: Sendable {
    public let maximumDurationSeconds: Double
    public let maximumFileBytes: Int64
    public let maximumPixelCount: Int

    public static let desktopV1 = MediaPolicy(
        maximumDurationSeconds: 2 * 3600,
        maximumFileBytes: 20 * 1024 * 1024 * 1024,
        maximumPixelCount: 3840 * 2160
    )

    public func validate(_ media: MediaDescriptor) throws {
        guard !media.isHDR else { throw LocalSubError.unsupportedMedia("HDR") }
        guard media.durationSeconds.isFinite, media.durationSeconds > 0,
              media.durationSeconds <= maximumDurationSeconds else {
            throw LocalSubError.resourceLimit("duration")
        }
        guard media.fileBytes > 0, media.fileBytes <= maximumFileBytes else {
            throw LocalSubError.resourceLimit("file size")
        }
        let (pixels, overflow) = media.width.multipliedReportingOverflow(by: media.height)
        guard media.width > 0, media.height > 0, !overflow, pixels <= maximumPixelCount else {
            throw LocalSubError.resourceLimit("dimensions")
        }
        guard media.videoTrackCount == 1, media.audioTrackCount == 1 else {
            throw LocalSubError.resourceLimit("track count")
        }
        guard media.nominalFrameRate.isFinite, media.nominalFrameRate > 0,
              media.nominalFrameRate <= 60,
              media.durationSeconds * media.nominalFrameRate <= maximumDurationSeconds * 60 else {
            throw LocalSubError.resourceLimit("frame rate/count")
        }
        guard (1...8).contains(media.audioChannelCount), media.audioSampleRate.isFinite,
              media.audioSampleRate > 0, media.audioSampleRate <= 192_000 else {
            throw LocalSubError.resourceLimit("audio format")
        }
    }
}
