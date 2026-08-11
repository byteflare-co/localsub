import XCTest
@testable import LocalSubCore

final class MediaPolicyTests: XCTestCase {
    func testAcceptsSupportedSDRMovie() throws {
        XCTAssertNoThrow(try MediaPolicy.desktopV1.validate(.init(
            container: .mp4,
            videoCodec: .h264,
            audioCodec: .aac,
            width: 1920,
            height: 1080,
            durationSeconds: 600,
            fileBytes: 500_000_000,
            isHDR: false
        )))
    }

    func testRejectsHDRAndOversizedMedia() throws {
        var media = MediaDescriptor(
            container: .mov,
            videoCodec: .hevc,
            audioCodec: .pcm,
            width: 3840,
            height: 2160,
            durationSeconds: 60,
            fileBytes: 100,
            isHDR: true
        )
        XCTAssertThrowsError(try MediaPolicy.desktopV1.validate(media))

        media = .init(container: .mp4, videoCodec: .h264, audioCodec: .aac,
                      width: 1920, height: 1080, durationSeconds: 8 * 3600,
                      fileBytes: 100, isHDR: false)
        XCTAssertThrowsError(try MediaPolicy.desktopV1.validate(media))
    }

    func testRejectsExcessiveFrameRateAndAudioChannels() {
        let media = MediaDescriptor(
            container: .mp4, videoCodec: .h264, audioCodec: .aac,
            width: 1920, height: 1080, durationSeconds: 60, fileBytes: 100,
            isHDR: false, nominalFrameRate: 120, audioChannelCount: 16
        )
        XCTAssertThrowsError(try MediaPolicy.desktopV1.validate(media))
    }
}
