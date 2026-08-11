@preconcurrency import AVFoundation
import AppKit
import CoreText
import Foundation
import QuartzCore
import Darwin
import LocalSubCore

public actor SubtitleVideoExporter {
    private var session: AVAssetExportSession?
    private nonisolated let publicationPermit = PublicationPermit()
    private let beforePublish: (@Sendable () async -> Void)?

    public init() { beforePublish = nil }

    init(beforePublish: @escaping @Sendable () async -> Void) {
        self.beforePublish = beforePublish
    }

    public func export(videoURL: URL, cues: [DisplayCue], destinationURL: URL) async throws {
        try Task.checkCancellation()
        let publicationLease = publicationPermit.begin()
        defer { publicationPermit.finish(publicationLease) }
        try CaptionProject.validateDisplayCues(cues)
        let publisher = try OutputPublisher(destinationURL: destinationURL)
        defer { publisher.cleanup() }

        let asset = AVURLAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else { throw ApplePipelineError.exportUnavailable }
        let duration = try await asset.load(.duration)
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let renderSize = Self.orientedSize(naturalSize, transform: transform)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ApplePipelineError.exportUnavailable }
        try videoTrack.insertTimeRange(.init(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try audioTrack.insertTimeRange(.init(start: .zero, duration: duration), of: sourceAudio, at: .zero)
        }

        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        layerConfiguration.setTransform(transform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [layerInstruction],
            timeRange: .init(start: .zero, duration: duration)
        ))

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let overlayLayer = try Self.overlayLayer(cues: cues, renderSize: renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        let animationTool = AVVideoCompositionCoreAnimationTool(configuration: .init(
            postProcessingAsVideoLayer: videoLayer,
            containingLayer: parentLayer
        ))
        let videoComposition = AVVideoComposition(configuration: .init(
            animationTool: animationTool,
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [instruction],
            renderSize: renderSize
        ))

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ApplePipelineError.exportUnavailable
        }
        session.videoComposition = videoComposition
        self.session = session
        defer { self.session = nil }
        do {
            try await session.export(to: publisher.stagingURL, as: .mp4)
        } catch {
            try? publisher.captureStagingIdentity()
            throw error
        }
        try publisher.captureStagingIdentity()
        try Task.checkCancellation()
        try publicationPermit.check(publicationLease)
        try await Self.validate(stagedOutput: publisher.stagingURL, expectedDuration: duration)
        try publisher.verifyStagingIdentity()
        try Task.checkCancellation()
        if let beforePublish { await beforePublish() }
        try Task.checkCancellation()
        try publicationPermit.publish(publicationLease) { try publisher.publish() }
    }

    @discardableResult
    public nonisolated func invalidatePublication() -> Bool {
        publicationPermit.invalidate()
    }

    public func cancel() {
        invalidatePublication()
        session?.cancelExport()
        session = nil
    }

    private static func orientedSize(_ size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private static func validate(stagedOutput url: URL, expectedDuration: CMTime) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable),
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw ApplePipelineError.exportUnavailable
        }
        let actualDuration = try await asset.load(.duration)
        let delta = abs(CMTimeGetSeconds(actualDuration) - CMTimeGetSeconds(expectedDuration))
        guard delta.isFinite, delta <= 1.0 / 15.0 else { throw ApplePipelineError.exportUnavailable }
    }

    static let captionBitmapBudgetBytes = 512 * 1_024 * 1_024
    static let minimumCaptionBitmapWidth: CGFloat = 640

    public nonisolated static func captionFontSize(for renderSize: CGSize) -> CGFloat {
        max(24, min(renderSize.width, renderSize.height) * 0.045)
    }

    public nonisolated static func captionFrameSize(for renderSize: CGSize) -> CGSize {
        CGSize(width: renderSize.width * 0.86, height: captionFontSize(for: renderSize) * 2.8)
    }

    public nonisolated static func captionTextFrame(for renderSize: CGSize) -> CGRect {
        let size = captionFrameSize(for: renderSize)
        return CGRect(
            x: renderSize.width * 0.07,
            y: captionBottomInset(for: renderSize),
            width: size.width,
            height: size.height
        )
    }

    public nonisolated static func captionBackgroundPadding(fontSize: CGFloat) -> CGSize {
        CGSize(width: fontSize * 0.35, height: fontSize * 0.12)
    }

    public nonisolated static func captionBottomInset(for renderSize: CGSize) -> CGFloat {
        renderSize.height * 0.075
    }

    public nonisolated static func captionPreviewGeometry(
        renderSize: CGSize,
        containerSize: CGSize
    ) -> (videoFrame: CGRect, textFrame: CGRect, backgroundFrame: CGRect, fontSize: CGFloat)? {
        guard renderSize.width > 0, renderSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return nil }
        let scale = min(containerSize.width / renderSize.width, containerSize.height / renderSize.height)
        let videoSize = CGSize(width: renderSize.width * scale, height: renderSize.height * scale)
        let videoFrame = CGRect(
            x: (containerSize.width - videoSize.width) / 2,
            y: (containerSize.height - videoSize.height) / 2,
            width: videoSize.width,
            height: videoSize.height
        )
        let sourceTextFrame = captionTextFrame(for: renderSize)
        let textFrame = CGRect(
            x: videoFrame.minX + sourceTextFrame.minX * scale,
            y: videoFrame.minY + sourceTextFrame.minY * scale,
            width: sourceTextFrame.width * scale,
            height: sourceTextFrame.height * scale
        )
        let fontSize = captionFontSize(for: renderSize) * scale
        let padding = captionBackgroundPadding(fontSize: fontSize)
        return (
            videoFrame,
            textFrame,
            textFrame.insetBy(dx: -padding.width, dy: -padding.height),
            fontSize
        )
    }

    static func captionRenderScale(cueCount: Int, renderSize: CGSize) throws -> CGFloat {
        let frameSize = captionFrameSize(for: renderSize)
        let frameWidth = frameSize.width
        let frameHeight = frameSize.height
        guard cueCount > 0, frameWidth > 0, frameHeight > 0 else { return 1 }

        let desiredScale = min(1, 1_280 / frameWidth)
        let bytesAtScaleOne = Double(cueCount) * frameWidth * frameHeight * 4
        let budgetWithAlignmentMargin = Double(captionBitmapBudgetBytes) * 0.95
        let budgetScale = sqrt(budgetWithAlignmentMargin / bytesAtScaleOne)
        let scale = min(desiredScale, budgetScale)
        let requiredWidth = min(minimumCaptionBitmapWidth, frameWidth)
        guard scale.isFinite, scale > 0,
              frameWidth * scale >= requiredWidth else {
            throw ApplePipelineError.captionBitmapBudgetExceeded
        }
        return scale
    }

    static func estimatedCaptionBitmapBytes(
        cueCount: Int,
        renderSize: CGSize,
        scale: CGFloat
    ) -> Int {
        let frameSize = captionFrameSize(for: renderSize)
        let frameWidth = frameSize.width
        let frameHeight = frameSize.height
        let pixelWidth = max(Int(ceil(frameWidth * scale)), 1)
        let pixelHeight = max(Int(ceil(frameHeight * scale)), 1)
        let alignedRowBytes = ((pixelWidth * 4 + 63) / 64) * 64
        let (perCue, perCueOverflow) = alignedRowBytes.multipliedReportingOverflow(by: pixelHeight)
        let (total, totalOverflow) = perCue.multipliedReportingOverflow(by: cueCount)
        return perCueOverflow || totalOverflow ? .max : total
    }

    static func overlayLayer(cues: [DisplayCue], renderSize: CGSize) throws -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: renderSize)
        let fontSize = captionFontSize(for: renderSize)
        let renderScale = try captionRenderScale(cueCount: cues.count, renderSize: renderSize)
        guard estimatedCaptionBitmapBytes(
            cueCount: cues.count,
            renderSize: renderSize,
            scale: renderScale
        ) <= captionBitmapBudgetBytes else {
            throw ApplePipelineError.captionBitmapBudgetExceeded
        }

        for cue in cues {
            let start = (try? cue.range.start.srtMilliseconds()).map(Double.init) ?? 0
            let end = (try? cue.range.end.srtMilliseconds()).map(Double.init) ?? start + 1
            let frame = captionTextFrame(for: renderSize)
            let backgroundPadding = captionBackgroundPadding(fontSize: fontSize)
            let background = CALayer()
            background.frame = frame.insetBy(dx: -backgroundPadding.width, dy: -backgroundPadding.height)
            background.backgroundColor = CGColor(gray: 0.04, alpha: 0.72)
            background.cornerRadius = fontSize * 0.2
            background.opacity = 0

            let text = CALayer()
            text.frame = frame
            let rasterization = captionRasterization(
                cue.text,
                size: frame.size,
                fontSize: fontSize,
                scale: renderScale
            )
            let expectedLength = (cue.text as NSString).length
            guard rasterization.image != nil,
                  rasterization.visibleRange.location + rasterization.visibleRange.length >= expectedLength,
                  rasterization.lineCount <= 2 else {
                throw ApplePipelineError.captionTextDoesNotFit
            }
            text.contents = rasterization.image
            text.contentsGravity = .resizeAspect
            text.contentsScale = 1
            text.opacity = 0

            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1
            animation.toValue = 1
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start / 1000
            animation.duration = max((end - start) / 1000, 0.001)
            animation.isRemovedOnCompletion = false
            background.add(animation, forKey: "visibility")
            text.add(animation, forKey: "visibility")
            overlay.addSublayer(background)
            overlay.addSublayer(text)
        }
        return overlay
    }

    public nonisolated static func renderedCaptionImage(
        _ value: String,
        size: CGSize,
        fontSize: CGFloat,
        scale: CGFloat = 1
    ) -> CGImage? {
        let rasterization = captionRasterization(value, size: size, fontSize: fontSize, scale: scale)
        let expectedLength = (value as NSString).length
        guard rasterization.visibleRange.location + rasterization.visibleRange.length >= expectedLength,
              rasterization.lineCount <= 2 else { return nil }
        return rasterization.image
    }

    nonisolated static func captionRasterization(
        _ value: String,
        size: CGSize,
        fontSize: CGFloat,
        scale: CGFloat = 1
    ) -> (image: CGImage?, visibleRange: CFRange, lineCount: Int) {
        let scale = max(min(scale, 1), 0.1)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (nil, CFRange(location: 0, length: 0), 0) }
        context.scaleBy(x: scale, y: scale)
        var effectiveFontSize = fontSize
        var finalFrame: CTFrame?
        var finalRange = CFRange(location: 0, length: 0)
        var finalLineCount = 0
        for _ in 0..<16 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let font = NSFont(name: "Hiragino Sans W6", size: effectiveFontSize)
                ?? NSFont.systemFont(ofSize: effectiveFontSize, weight: .semibold)
            let attributed = NSAttributedString(string: value, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                nil,
                CGSize(width: size.width, height: .greatestFiniteMagnitude),
                nil
            )
            let textHeight = min(ceil(measured.height), size.height)
            let path = CGPath(rect: CGRect(
                x: 0,
                y: floor((size.height - textHeight) / 2),
                width: size.width,
                height: textHeight
            ), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                path,
                nil
            )
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let lineCount = CFArrayGetCount(CTFrameGetLines(frame))
            finalFrame = frame
            finalRange = visibleRange
            finalLineCount = lineCount
            if visibleRange.location + visibleRange.length >= attributed.length, lineCount <= 2 { break }
            effectiveFontSize *= 0.92
        }
        if let finalFrame { CTFrameDraw(finalFrame, context) }
        return (context.makeImage(), finalRange, finalLineCount)
    }
}

private final class PublicationPermit: @unchecked Sendable {
    struct Lease: Sendable {
        let generation: UInt64
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var inProgress = false
    private var published = false

    func begin() -> Lease {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        inProgress = true
        published = false
        return Lease(generation: generation)
    }

    func invalidate() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !published else { return false }
        generation &+= 1
        inProgress = false
        return true
    }

    func check(_ lease: Lease) throws {
        lock.lock()
        defer { lock.unlock() }
        guard generation == lease.generation else { throw CancellationError() }
    }

    func publish(_ lease: Lease, operation: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard generation == lease.generation, inProgress else { throw CancellationError() }
        try operation()
        inProgress = false
        published = true
    }

    func finish(_ lease: Lease) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == lease.generation, !published else { return }
        inProgress = false
    }
}

private final class OutputPublisher: @unchecked Sendable {
    let destinationURL: URL
    let stagingURL: URL
    private let stagingDirectoryURL: URL
    private let stagingDirectoryFD: Int32
    private let stagingDevice: dev_t
    private let stagingInode: ino_t
    private var stagingFileIdentity: (device: dev_t, inode: ino_t)?

    init(destinationURL: URL) throws {
        let directory = try NonReplacingFileWriter.canonicalDirectory(destinationURL.deletingLastPathComponent())
        self.destinationURL = directory.appendingPathComponent(destinationURL.lastPathComponent)
        let nonce = UUID().uuidString
        let stagingDirectoryURL = directory.appendingPathComponent(".localsub-\(nonce).staging", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        guard Darwin.mkdir(stagingDirectoryURL.path, mode_t(0o700)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var identity = stat()
        guard Darwin.lstat(stagingDirectoryURL.path, &identity) == 0,
              identity.st_mode & S_IFMT == S_IFDIR else {
            _ = Darwin.rmdir(stagingDirectoryURL.path)
            throw POSIXError(.EIO)
        }
        let fd = Darwin.open(stagingDirectoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else {
            _ = Darwin.rmdir(stagingDirectoryURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var openedIdentity = stat()
        guard Darwin.fstat(fd, &openedIdentity) == 0,
              openedIdentity.st_dev == identity.st_dev,
              openedIdentity.st_ino == identity.st_ino,
              openedIdentity.st_mode & S_IFMT == S_IFDIR else {
            Darwin.close(fd)
            _ = Darwin.rmdir(stagingDirectoryURL.path)
            throw POSIXError(.EIO)
        }
        self.stagingDirectoryURL = stagingDirectoryURL
        self.stagingDirectoryFD = fd
        self.stagingDevice = identity.st_dev
        self.stagingInode = identity.st_ino
        self.stagingURL = stagingDirectoryURL.appendingPathComponent("output.mp4")
    }

    deinit { Darwin.close(stagingDirectoryFD) }

    func publish() throws {
        try verifyStagingIdentity()
        let result = Darwin.renameatx_np(
            stagingDirectoryFD, "output.mp4",
            AT_FDCWD, destinationURL.path,
            UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)
        )
        guard result == 0 else {
            if errno == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func captureStagingIdentity() throws {
        let fd = Darwin.openat(stagingDirectoryFD, "output.mp4", O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        var identity = stat()
        guard Darwin.fstat(fd, &identity) == 0,
              identity.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.EIO) }
        var pathIdentity = stat()
        guard Darwin.fstatat(stagingDirectoryFD, "output.mp4", &pathIdentity, AT_SYMLINK_NOFOLLOW) == 0,
              pathIdentity.st_dev == identity.st_dev,
              pathIdentity.st_ino == identity.st_ino else { throw POSIXError(.EIO) }
        stagingFileIdentity = (identity.st_dev, identity.st_ino)
    }

    func verifyStagingIdentity() throws {
        guard let expected = stagingFileIdentity else { throw POSIXError(.EIO) }
        var identity = stat()
        guard Darwin.fstatat(stagingDirectoryFD, "output.mp4", &identity, AT_SYMLINK_NOFOLLOW) == 0,
              identity.st_mode & S_IFMT == S_IFREG,
              identity.st_dev == expected.device,
              identity.st_ino == expected.inode else { throw POSIXError(.EIO) }
    }

    func cleanup() {
        if (try? verifyStagingIdentity()) != nil {
            _ = Darwin.unlinkat(stagingDirectoryFD, "output.mp4", 0)
        }
        var identity = stat()
        guard Darwin.lstat(stagingDirectoryURL.path, &identity) == 0,
              identity.st_dev == stagingDevice,
              identity.st_ino == stagingInode,
              identity.st_mode & S_IFMT == S_IFDIR else { return }
        _ = Darwin.rmdir(stagingDirectoryURL.path)
    }

}
