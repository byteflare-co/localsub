import AVFoundation
import AVKit
import CoreImage
import XCTest
@testable import LocalSubApple
import LocalSubCore

final class SubtitleVideoExporterTests: XCTestCase {
    func testSecurityScopedAccessStopsExactlyOnceWhenStarted() {
        var stops = 0
        do {
            let access = SecurityScopedResourceAccess(
                start: { true },
                stop: { stops += 1 }
            )
            withExtendedLifetime(access) { XCTAssertEqual(stops, 0) }
        }
        XCTAssertEqual(stops, 1)
    }

    func testSecurityScopedAccessDoesNotStopWhenStartWasNotNeeded() {
        var stops = 0
        do {
            let access = SecurityScopedResourceAccess(
                start: { false },
                stop: { stops += 1 }
            )
            withExtendedLifetime(access) {}
        }
        XCTAssertEqual(stops, 0)
    }

    @MainActor
    func testAppKitPlayerSurfaceOwnsTheProvidedPlayer() {
        let player = AVPlayer()
        let surface = AppKitPlayerSurface(player: player)

        XCTAssertTrue(surface.playerView.player === player)
        XCTAssertEqual(surface.playerView.videoGravity, .resizeAspect)
        surface.update(player: nil)
        XCTAssertNil(surface.playerView.player)
    }

    @MainActor
    func testPeriodicTimeObserverAlwaysDetachesFromItsOwningPlayer() {
        let first = AVPlayer()
        let second = AVPlayer()
        let observer = PlayerTimeObserver()

        observer.install(on: first) { _ in }
        XCTAssertTrue(observer.observedPlayer === first)
        observer.install(on: second) { _ in }
        XCTAssertTrue(observer.observedPlayer === second)
        observer.invalidate()
        XCTAssertNil(observer.observedPlayer)
    }

    func testInstalledLocaleMatchingNormalizesIdentifierSeparators() {
        XCTAssertTrue(AppleSpeechTranscriber.containsEquivalentLocale(
            Locale(identifier: "ja-JP"),
            in: [Locale(identifier: "ja_JP")]
        ))
        XCTAssertTrue(AppleSpeechTranscriber.containsEquivalentLocale(
            Locale(identifier: "en-US"),
            in: [Locale(identifier: "en_US")]
        ))
        XCTAssertFalse(AppleSpeechTranscriber.containsEquivalentLocale(
            Locale(identifier: "en-US"),
            in: [Locale(identifier: "ja_JP")]
        ))
    }

    func testNonReplacingWriterRejectsExistingFileAndSymlink() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("captions.srt")
        try NonReplacingFileWriter.write(Data("safe".utf8), to: output)
        XCTAssertEqual(try Data(contentsOf: output), Data("safe".utf8))
        XCTAssertThrowsError(try NonReplacingFileWriter.write(Data("replace".utf8), to: output))

        let victim = directory.appendingPathComponent("victim.txt")
        try Data("victim".utf8).write(to: victim)
        let link = directory.appendingPathComponent("link.srt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        XCTAssertThrowsError(try NonReplacingFileWriter.write(Data("attack".utf8), to: link))
        XCTAssertEqual(try Data(contentsOf: victim), Data("victim".utf8))
    }

    func testInspectorRejectsMovieWithoutAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-inspect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("silent.mp4")
        try await makeVideo(at: input)
        await XCTAssertThrowsErrorAsync { _ = try await MediaInspector().inspect(input) }
    }

    func testExportsPlayableVideoAndRefusesOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await makeVideo(at: input)
        let cue = try DisplayCue.validated(
            id: "cue-1", text: "動作確認",
            range: .init(start: .milliseconds(0), end: .milliseconds(1_000))
        )

        let exporter = SubtitleVideoExporter()
        try await exporter.export(videoURL: input, cues: [cue], destinationURL: output)
        XCTAssertFalse(exporter.invalidatePublication(), "a committed publication must win over later cancel")

        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertGreaterThan(duration.seconds, 0.9)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertGreaterThan(whitePixelCount(frame), 50, "rendered frame must contain visible caption glyphs")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".localsub-") }.isEmpty)
        await XCTAssertThrowsErrorAsync {
            try await SubtitleVideoExporter().export(videoURL: input, cues: [cue], destinationURL: output)
        }
    }

    func testExportsVisibleCaptionAtHDResolutionForLongCue() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-hd-caption-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await makeVideo(at: input, width: 1_280, height: 720)
        let cue = try DisplayCue.validated(
            id: "cue-hd", text: "これはローカルサブの確認です",
            range: .init(start: .milliseconds(0), end: .milliseconds(2_457))
        )

        try await SubtitleVideoExporter().export(videoURL: input, cues: [cue], destinationURL: output)
        let asset = AVURLAsset(url: output)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertGreaterThan(whitePixelCount(frame), 500, "HD export must burn visible caption glyphs")
    }

    func testRenderedCaptionVerticallyCentersTwoLines() throws {
        let size = CGSize(width: 1_651, height: 136)
        XCTAssertEqual(
            SubtitleVideoExporter.captionFontSize(for: CGSize(width: 1_920, height: 1_080)),
            48.6,
            accuracy: 0.01
        )
        let image = try XCTUnwrap(SubtitleVideoExporter.renderedCaptionImage(
            "そしてそれがさらに発展したのが\nClaudeマネージドエージェントです。",
            size: size,
            fontSize: 48.6
        ))
        let bounds = try XCTUnwrap(nonTransparentBounds(image))
        let firstPadding = bounds.minY
        let secondPadding = CGFloat(image.height - 1) - bounds.maxY

        XCTAssertLessThanOrEqual(
            abs(firstPadding - secondPadding),
            4,
            "expected balanced vertical padding, got \(firstPadding) and \(secondPadding)"
        )
    }

    func testTwoFullJapaneseLinesRemainVisibleOnPortraitAndSquareVideo() throws {
        let value = String(repeating: "字幕", count: 10)
            + "\n"
            + String(repeating: "表示", count: 10)
        for renderSize in [
            CGSize(width: 1_080, height: 1_920),
            CGSize(width: 1_080, height: 1_080),
        ] {
            let frame = SubtitleVideoExporter.captionTextFrame(for: renderSize)
            let rasterization = SubtitleVideoExporter.captionRasterization(
                value,
                size: frame.size,
                fontSize: SubtitleVideoExporter.captionFontSize(for: renderSize)
            )

            XCTAssertNotNil(rasterization.image)
            XCTAssertEqual(
                rasterization.visibleRange.location + rasterization.visibleRange.length,
                (value as NSString).length,
                "all text must fit a two-line caption on \(renderSize)"
            )
            XCTAssertEqual(frame.minX / renderSize.width, 0.07, accuracy: 0.0001)
            XCTAssertEqual(frame.minY / renderSize.height, 0.075, accuracy: 0.0001)
            XCTAssertEqual(frame.width / renderSize.width, 0.86, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(rasterization.lineCount, 2)
        }
    }

    func testRejectsEditedCaptionThatCannotFitInTwoLines() throws {
        let oversizedValues = [
            String(repeating: "語", count: 255) + "\n" + String(repeating: "字", count: 256),
            String(repeating: "LongProductName", count: 31) + "\n" + String(repeating: "A", count: 32),
        ]
        for (index, value) in oversizedValues.enumerated() {
            let cue = try DisplayCue.validated(
                id: "oversized-\(index)",
                text: value,
                range: .init(start: .zero, end: .seconds(10))
            )

            XCTAssertThrowsError(try SubtitleVideoExporter.overlayLayer(
                cues: [cue],
                renderSize: CGSize(width: 1_920, height: 1_080)
            )) { error in
                guard case ApplePipelineError.captionTextDoesNotFit = error else {
                    return XCTFail("expected captionTextDoesNotFit, got \(error)")
                }
            }
        }
    }

    func testPreviewGeometryPreservesExportCoordinatesAcrossLetterboxing() throws {
        let cases = [
            (render: CGSize(width: 1_080, height: 1_920), container: CGSize(width: 1_200, height: 700)),
            (render: CGSize(width: 1_920, height: 1_080), container: CGSize(width: 700, height: 1_200)),
        ]
        for item in cases {
            let geometry = try XCTUnwrap(SubtitleVideoExporter.captionPreviewGeometry(
                renderSize: item.render,
                containerSize: item.container
            ))

            XCTAssertEqual(
                (geometry.textFrame.minX - geometry.videoFrame.minX) / geometry.videoFrame.width,
                0.07,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                (geometry.textFrame.minY - geometry.videoFrame.minY) / geometry.videoFrame.height,
                0.075,
                accuracy: 0.0001
            )
            XCTAssertEqual(geometry.textFrame.width / geometry.videoFrame.width, 0.86, accuracy: 0.0001)
            XCTAssertEqual(geometry.backgroundFrame.midX, geometry.textFrame.midX, accuracy: 0.0001)
            XCTAssertEqual(geometry.backgroundFrame.midY, geometry.textFrame.midY, accuracy: 0.0001)
        }
    }

    func testLongCaptionOverlayKeepsBitmapBudgetBounded() throws {
        var cues: [DisplayCue] = []
        for index in 0..<750 {
            let start = Int64(index) * 3_000
            let range = try RationalTimeRange(
                start: .milliseconds(start),
                end: .milliseconds(start + 2_500)
            )
            cues.append(try DisplayCue.validated(
                id: "cue-\(index)", text: "長尺字幕 \(index)", range: range
            ))
        }

        let overlay = try SubtitleVideoExporter.overlayLayer(
            cues: cues,
            renderSize: CGSize(width: 3_840, height: 2_160)
        )
        let captionImages: [CGImage] = (overlay.sublayers ?? []).compactMap { layer in
            guard layer.contents != nil else { return nil }
            return (layer.contents as! CGImage)
        }
        let estimatedBytes = captionImages.reduce(0) { $0 + $1.bytesPerRow * $1.height }

        XCTAssertEqual(captionImages.count, cues.count)
        XCTAssertLessThanOrEqual(captionImages.map(\.width).max() ?? 0, 1_280)
        XCTAssertLessThan(estimatedBytes, 512 * 1_024 * 1_024,
                          "750 HD captions must stay below a 512 MiB retained bitmap budget")
    }

    func testCaptionBitmapPlannerSupportsTwoHourCadenceAndRejectsTenThousandCues() throws {
        let hd = CGSize(width: 1_920, height: 1_080)
        let twoHourCueCount = 2_400
        let scale = try SubtitleVideoExporter.captionRenderScale(
            cueCount: twoHourCueCount,
            renderSize: hd
        )
        let estimated = SubtitleVideoExporter.estimatedCaptionBitmapBytes(
            cueCount: twoHourCueCount,
            renderSize: hd,
            scale: scale
        )

        XCTAssertGreaterThanOrEqual(hd.width * 0.86 * scale, 640)
        XCTAssertLessThanOrEqual(estimated, SubtitleVideoExporter.captionBitmapBudgetBytes)
        XCTAssertThrowsError(try SubtitleVideoExporter.captionRenderScale(
            cueCount: 10_000,
            renderSize: CGSize(width: 3_840, height: 2_160)
        ))
        XCTAssertEqual(try SubtitleVideoExporter.captionRenderScale(
            cueCount: 1,
            renderSize: CGSize(width: 320, height: 180)
        ), 1)
    }

    func testCancelAfterValidationPreventsFinalPublication() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-cancel-publish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await makeVideo(at: input)
        let cue = try DisplayCue.validated(
            id: "cue-1", text: "取消確認",
            range: .init(start: .milliseconds(0), end: .milliseconds(900))
        )
        let barrier = PublishBarrier()
        let exporter = SubtitleVideoExporter(beforePublish: { await barrier.pause() })
        let exportTask = Task {
            try await exporter.export(videoURL: input, cues: [cue], destinationURL: output)
        }

        await barrier.waitUntilReached()
        XCTAssertTrue(exporter.invalidatePublication(), "cancel must revoke an uncommitted publication")
        await barrier.release()

        await XCTAssertThrowsErrorAsync { try await exportTask.value }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".localsub-") }
        XCTAssertTrue(leftovers.isEmpty, "cancelled export must remove owned staging media")
    }

    func testStagingReplacementFailsClosedWithoutDeletingReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localsub-staging-replacement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        try await makeVideo(at: input)
        let cue = try DisplayCue.validated(
            id: "cue-1", text: "置換確認",
            range: .init(start: .milliseconds(0), end: .milliseconds(900))
        )
        let barrier = PublishBarrier()
        let exporter = SubtitleVideoExporter(beforePublish: { await barrier.pause() })
        let exportTask = Task {
            try await exporter.export(videoURL: input, cues: [cue], destinationURL: output)
        }

        await barrier.waitUntilReached()
        let stagingDirectory = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix(".localsub-") }
        )
        let stagedOutput = stagingDirectory.appendingPathComponent("output.mp4")
        try FileManager.default.removeItem(at: stagedOutput)
        let replacement = Data("foreign replacement".utf8)
        try replacement.write(to: stagedOutput)
        await barrier.release()

        await XCTAssertThrowsErrorAsync { try await exportTask.value }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: stagedOutput), replacement,
                       "cleanup must not delete a file whose identity it never captured")
    }

    private func whitePixelCount(_ image: CGImage) -> Int {
        let rowBytes = image.width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * rowBytes + x * 4
                if pixels[offset] > 220, pixels[offset + 1] > 220, pixels[offset + 2] > 220 { count += 1 }
            }
        }
        return count
    }

    private func nonTransparentBounds(_ image: CGImage) -> CGRect? {
        let rowBytes = image.width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                if pixels[y * rowBytes + x * 4 + 3] > 0 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func makeVideo(at url: URL, width: Int = 320, height: Int = 180) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        let image = CIImage(color: .init(red: 0.08, green: 0.18, blue: 0.35, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            guard let pool = adaptor.pixelBufferPool else { XCTFail("missing pixel pool"); return }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            guard let buffer else { XCTFail("missing pixel buffer"); return }
            context.render(image, to: buffer)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }
}

private actor PublishBarrier {
    private var reached = false
    private var reachedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        reached = true
        reachedWaiters.forEach { $0.resume() }
        reachedWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilReached() async {
        if reached { return }
        await withCheckedContinuation { reachedWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
