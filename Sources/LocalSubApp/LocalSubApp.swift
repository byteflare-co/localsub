import AVFoundation
import AVKit
import SwiftUI
import Translation
import UniformTypeIdentifiers
import LocalSubApple
import LocalSubCloud
import LocalSubCore

@main
struct LocalSubApp: App {
    @StateObject private var model = WorkspaceModel()

    var body: some Scene {
        WindowGroup("LocalSub") {
            WorkspaceView(model: model)
                .frame(minWidth: 980, minHeight: 680)
                .translationTask(model.translationConfiguration) { session in
                    await model.finishEnglishTranslation(with: session)
                }
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    enum Phase: Equatable {
        case empty, ready, working(String), speechModelRequired(String), installingSpeechModel(String), awaitingTranslation, review, exporting, completed(URL), failed(String)
    }

    @Published var sourceURL: URL?
    @Published var sourceLanguage: SourceLanguage = .japanese
    @Published var cues: [DisplayCue] = []
    @Published var phase: Phase = .empty
    @Published var outputError: String?
    @Published var player: AVPlayer?
    @Published var currentSeconds: Double = 0
    @Published var sourceRenderSize: CGSize?
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var englishTranslationMode: EnglishTranslationMode = .appleLocal
    @Published private(set) var glossaryText = ""
    @Published private(set) var hasLunaAPIKey = false
    @Published private(set) var hasStoredLunaAPIKey = false

    private let extractor = AudioExtractor()
    private let inspector = MediaInspector()
    private let transcriber = AppleSpeechTranscriber()
    private let exporter = SubtitleVideoExporter()
    private let apiKeyStore = OpenAIAPIKeyStore()
    private var pendingEnglish: [TimedText] = []
    private var pendingTranslationLease: JobLease?
    private var pendingProtectedTerms: [String] = []
    private struct ActiveTranslation {
        let lease: JobLease
        let session: TranslationSession
    }
    private var activeTranslation: ActiveTranslation?
    private var translationActivationPolicy = TranslationTaskActivationPolicy()
    private var task: Task<Void, Never>?
    private var leaseGate = JobLeaseGate()
    private let playerTimeObserver = PlayerTimeObserver()
    private var sourceScopeStarted = false

    init() {
        hasStoredLunaAPIKey = ((try? apiKeyStore.read()) ?? nil) != nil
        hasLunaAPIKey = hasStoredLunaAPIKey
            || !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
        guard let data = UserDefaults.standard.data(forKey: "lastSourceBookmark") else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: "lastSourceBookmark")
            return
        }
        sourceURL = url
        sourceScopeStarted = true
        phase = .working("動画を検査中")
        if stale { persistBookmark(for: url) }
        let lease = leaseGate.begin()
        task = Task {
            do {
                let media = try await inspector.inspect(url)
                guard leaseGate.isCurrent(lease) else { return }
                sourceRenderSize = CGSize(width: media.width, height: media.height)
                player = AVPlayer(url: url)
                installTimeObserver()
                phase = .ready
            } catch {
                guard leaseGate.isCurrent(lease) else { return }
                playerTimeObserver.invalidate()
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                player = nil
                if sourceScopeStarted { url.stopAccessingSecurityScopedResource() }
                sourceScopeStarted = false
                sourceURL = nil
                UserDefaults.standard.removeObject(forKey: "lastSourceBookmark")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    var canGenerate: Bool { sourceURL != nil && phase == .ready }
    var canExport: Bool {
        sourceURL != nil && !cues.isEmpty && (phase == .review || isCompleted)
    }
    var canSaveSRT: Bool { !cues.isEmpty && phase != .exporting }
    var sendsTranscriptToOpenAI: Bool {
        sourceLanguage == .english && englishTranslationMode == .gpt56Luna
    }
    var settingsLocked: Bool {
        switch phase {
        case .working, .installingSpeechModel, .awaitingTranslation, .exporting:
            true
        default:
            false
        }
    }

    private var isCompleted: Bool {
        if case .completed = phase { return true }
        return false
    }

    var currentCaption: String? {
        cues.first { cue in
            let start = (try? cue.range.start.srtMilliseconds()).map { Double($0) / 1000 } ?? 0
            let end = (try? cue.range.end.srtMilliseconds()).map { Double($0) / 1000 } ?? 0
            return currentSeconds >= start && currentSeconds < end
        }?.text
    }

    func select(_ url: URL) {
        outputError = nil
        let previousTask = task
        exporter.invalidatePublication()
        previousTask?.cancel()
        leaseGate.invalidate()
        activeTranslation?.session.cancel()
        activeTranslation = nil
        let previousURL = sourceURL
        let previousPlayer = player
        let previousScopeStarted = sourceScopeStarted
        phase = .working("前の処理を終了中")
        task = Task {
            await extractor.cancel()
            await transcriber.cancel()
            await exporter.cancel()
            await previousTask?.value
            guard !Task.isCancelled else { return }
            playerTimeObserver.invalidate()
            previousPlayer?.pause()
            previousPlayer?.replaceCurrentItem(with: nil)
            player = nil
            if previousScopeStarted { previousURL?.stopAccessingSecurityScopedResource() }
            let accessible = url.startAccessingSecurityScopedResource()
            sourceScopeStarted = accessible
            sourceURL = url
            sourceRenderSize = nil
            cues = []
            pendingEnglish = []
            pendingTranslationLease = nil
            pendingProtectedTerms = []
            phase = .working("動画を検査中")
            let lease = leaseGate.begin()
            do {
                let media = try await inspector.inspect(url)
                guard leaseGate.isCurrent(lease) else { return }
                sourceRenderSize = CGSize(width: media.width, height: media.height)
                player = AVPlayer(url: url)
                installTimeObserver()
                if accessible { persistBookmark(for: url) }
                phase = .ready
            } catch {
                guard leaseGate.isCurrent(lease) else { return }
                if accessible { url.stopAccessingSecurityScopedResource() }
                sourceScopeStarted = false
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func generate() {
        guard let sourceURL else { return }
        task?.cancel()
        let lease = leaseGate.begin()
        let selectedLanguage = sourceLanguage
        let selectedTranslationMode = englishTranslationMode
        let selectedGlossaryText = glossaryText
        let selectedAPIKey: String?
        if selectedLanguage == .english, selectedTranslationMode == .gpt56Luna {
            do {
                selectedAPIKey = try lunaAPIKey()
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        } else {
            selectedAPIKey = nil
        }
        phase = .working("音声を準備中")
        task = Task {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("localsub-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                let glossary = try GlossaryParser.parse(selectedGlossaryText)
                let locale = selectedLanguage == .japanese
                    ? Locale(identifier: "ja-JP") : Locale(identifier: "en-US")
                switch await AppleSpeechTranscriber.modelStatus(locale: locale) {
                case .installed: break
                case .notInstalled:
                    guard leaseGate.isCurrent(lease) else { return }
                    phase = .speechModelRequired(locale.identifier)
                    return
                case .unavailable:
                    throw ApplePipelineError.localeUnavailable(locale.identifier)
                }
                try await extractor.extract(from: sourceURL, to: temporary)
                try Task.checkCancellation()
                guard leaseGate.isCurrent(lease) else { return }
                phase = .working("音声を文字起こし中")
                let transcript = try await transcriber.transcribe(
                    audioURL: temporary,
                    locale: locale,
                    contextualStrings: glossary.map(\.source)
                )
                try Task.checkCancellation()
                guard leaseGate.isCurrent(lease) else { return }
                if selectedLanguage == .english {
                    switch selectedTranslationMode {
                    case .appleLocal:
                        pendingEnglish = transcript
                        pendingTranslationLease = lease
                        pendingProtectedTerms = glossary.map(\.target)
                        phase = .awaitingTranslation
                        activateTranslationTask(source: "en", target: "ja")
                    case .gpt56Luna:
                        phase = .working("GPT-5.6 Lunaで日本語へ翻訳中")
                        let plan = try TranslationPlanner().plan(transcript)
                        guard let apiKey = selectedAPIKey else { throw LunaTranslationError.missingAPIKey }
                        let responses = try await LunaTranslationProvider(apiKey: apiKey).translate(
                            plan.map(\.request), glossary: glossary
                        )
                        try Task.checkCancellation()
                        guard leaseGate.isCurrent(lease) else { return }
                        let correlated = try TranslationCorrelator.correlate(
                            requests: plan.map(\.request), responses: responses
                        )
                        let translated = zip(plan, correlated).map {
                            TimedText(text: $1.text, range: $0.range)
                        }
                        cues = try CueBuilder(
                            policy: .defaultJapanese,
                            protectedTerms: glossary.map(\.target)
                        ).build(from: translated)
                        phase = .review
                    }
                } else {
                    cues = try CueBuilder(policy: .defaultJapanese).build(from: transcript)
                    phase = .review
                }
            } catch is CancellationError {
                guard leaseGate.isCurrent(lease) else { return }
                phase = .ready
            } catch {
                guard leaseGate.isCurrent(lease) else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func prepareSpeechModel() {
        guard case .speechModelRequired(let identifier) = phase else { return }
        task?.cancel()
        let lease = leaseGate.begin()
        phase = .installingSpeechModel(identifier)
        task = Task {
            do {
                try await transcriber.install(locale: Locale(identifier: identifier))
                guard leaseGate.isCurrent(lease) else { return }
                phase = .ready
            } catch is CancellationError {
                guard leaseGate.isCurrent(lease) else { return }
                phase = .speechModelRequired(identifier)
            } catch {
                guard leaseGate.isCurrent(lease) else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func updateGlossaryText(_ value: String) {
        var bounded = ""
        bounded.reserveCapacity(min(value.count, GlossaryParser.maximumUTF8Bytes))
        var byteCount = 0
        for character in value {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= GlossaryParser.maximumUTF8Bytes else { break }
            bounded.append(character)
            byteCount += characterBytes
        }
        glossaryText = bounded
    }

    @discardableResult
    func saveLunaAPIKey(_ value: String) -> Bool {
        do {
            try apiKeyStore.save(value)
            hasStoredLunaAPIKey = true
            hasLunaAPIKey = true
            outputError = nil
            return true
        } catch {
            outputError = error.localizedDescription
            return false
        }
    }

    func deleteLunaAPIKey() {
        do {
            try apiKeyStore.delete()
            hasStoredLunaAPIKey = false
            hasLunaAPIKey = !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
            outputError = nil
        } catch {
            outputError = error.localizedDescription
        }
    }

    private func lunaAPIKey() throws -> String {
        if let stored = try apiKeyStore.read(), !stored.isEmpty { return stored }
        if let environment = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !environment.isEmpty {
            return environment
        }
        throw LunaTranslationError.missingAPIKey
    }

    func finishEnglishTranslation(with session: TranslationSession) async {
        guard phase == .awaitingTranslation, !pendingEnglish.isEmpty,
              let lease = pendingTranslationLease, leaseGate.isCurrent(lease) else { return }
        activeTranslation = .init(lease: lease, session: session)
        defer {
            if activeTranslation?.lease == lease { activeTranslation = nil }
        }
        do {
            phase = .working("日本語へ翻訳中")
            let plan = try TranslationPlanner().plan(pendingEnglish)
            let coreRequests = plan.map(\.request)
            let requests = coreRequests.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
            }
            var responses: [TranslationResponse] = []
            for try await response in session.translate(batch: requests) {
                try Task.checkCancellation()
                guard leaseGate.isCurrent(lease) else { throw ApplePipelineError.staleJob }
                responses.append(.init(
                    requestID: response.clientIdentifier ?? "",
                    text: response.targetText
                ))
            }
            let correlated = try TranslationCorrelator.correlate(requests: coreRequests, responses: responses)
            try Task.checkCancellation()
            guard leaseGate.isCurrent(lease) else { throw ApplePipelineError.staleJob }
            let translated = plan.enumerated().map {
                TimedText(text: correlated[$0.offset].text, range: $0.element.range)
            }
            cues = try CueBuilder(
                policy: .defaultJapanese,
                protectedTerms: pendingProtectedTerms
            ).build(from: translated)
            pendingEnglish = []
            pendingTranslationLease = nil
            pendingProtectedTerms = []
            phase = .review
        } catch is CancellationError {
            guard leaseGate.isCurrent(lease) else { return }
            phase = .ready
        } catch {
            guard leaseGate.isCurrent(lease) else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func export(to destination: URL, securityScopedRoot: URL) {
        guard let sourceURL else { return }
        outputError = nil
        let snapshot = cues
        let lease = leaseGate.begin()
        let destinationAccess = SecurityScopedResourceAccess(url: securityScopedRoot)
        phase = .exporting
        task = Task {
            defer { withExtendedLifetime(destinationAccess) {} }
            do {
                try await exporter.export(videoURL: sourceURL, cues: snapshot, destinationURL: destination)
                guard leaseGate.isCurrent(lease) else { return }
                phase = .completed(destination)
            } catch is CancellationError {
                guard leaseGate.isCurrent(lease) else { return }
                phase = .review
            } catch {
                guard leaseGate.isCurrent(lease) else { return }
                outputError = error.localizedDescription
                phase = .review
            }
        }
    }

    func cancel() {
        let publicationRevoked = exporter.invalidatePublication()
        if phase == .exporting, !publicationRevoked {
            return
        }
        let resumeDestination = CancellationResumePolicy.destination(
            hasSource: sourceURL != nil,
            hasReviewableCues: !cues.isEmpty
        )
        let previousTask = task
        previousTask?.cancel()
        leaseGate.invalidate()
        activeTranslation?.session.cancel()
        activeTranslation = nil
        pendingTranslationLease = nil
        pendingEnglish = []
        pendingProtectedTerms = []
        phase = sourceURL == nil ? .empty : .working("キャンセル中")
        task = Task {
            await extractor.cancel()
            await transcriber.cancel()
            await exporter.cancel()
            await previousTask?.value
            guard !Task.isCancelled else { return }
            switch resumeDestination {
            case .empty: phase = .empty
            case .ready: phase = .ready
            case .review: phase = .review
            }
        }
    }

    func updateCue(id: String, text: String) {
        guard let index = cues.firstIndex(where: { $0.id == id }),
              let validated = try? DisplayCue.validated(
                id: id, text: text, range: cues[index].range, warnings: cues[index].warnings
              ) else { return }
        cues[index] = validated
        outputError = nil
        if isCompleted { phase = .review }
    }

    func saveSRT(to url: URL) {
        let destinationAccess = SecurityScopedResourceAccess(url: url)
        defer { withExtendedLifetime(destinationAccess) {} }
        do {
            let value = try SRTSerializer.serialize(cues)
            try NonReplacingFileWriter.write(Data(value.utf8), to: url)
            outputError = nil
        } catch {
            outputError = error.localizedDescription
        }
    }

    private func installTimeObserver() {
        guard let player else {
            playerTimeObserver.invalidate()
            return
        }
        playerTimeObserver.install(on: player) { [weak self] time in
            Task { @MainActor in self?.currentSeconds = max(CMTimeGetSeconds(time), 0) }
        }
    }

    private func activateTranslationTask(source: String, target: String) {
        let route = TranslationRoute(source: source, target: target)
        switch translationActivationPolicy.activate(route) {
        case .create:
            if #available(macOS 26.4, *) {
                translationConfiguration = .init(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target),
                    preferredStrategy: .highFidelity
                )
            } else {
                translationConfiguration = .init(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )
            }
        case .invalidate:
            translationConfiguration?.invalidate()
        }
    }

    private func persistBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(data, forKey: "lastSourceBookmark")
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var importing = false
    @State private var showExporter = false
    @State private var confirmCloudTranslation = false
    @State private var showingAPIKeySettings = false
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.sourceURL == nil { emptyState } else { workspace }
            Divider()
            statusBar
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            if case .success(let url) = result { model.select(url) }
        }
        .alert("英文をOpenAIへ送信します", isPresented: $confirmCloudTranslation) {
            Button("キャンセル", role: .cancel) {}
            Button("同意して生成") { model.generate() }
        } message: {
            Text(CloudPrivacyDisclosure.confirmation)
        }
        .sheet(isPresented: $showingAPIKeySettings) {
            VStack(alignment: .leading, spacing: 14) {
                Text("OpenAI APIキー").font(.headline)
                Text("APIキーはこのMacのKeychainにだけ保存します。既存のキーは表示しません。")
                    .font(.callout).foregroundStyle(.secondary)
                SecureField("APIキー", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if model.hasStoredLunaAPIKey {
                        Button("保存済みキーを削除", role: .destructive) {
                            model.deleteLunaAPIKey()
                            apiKeyDraft = ""
                        }
                    }
                    Spacer()
                    Button("閉じる", role: .cancel) { showingAPIKeySettings = false }
                    Button("Keychainに保存") {
                        if model.saveLunaAPIKey(apiKeyDraft) {
                            apiKeyDraft = ""
                            showingAPIKeySettings = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 480)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "captions.bubble.fill")
                .font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("LocalSub").font(.headline)
                Text("動画を端末内で日本語字幕付きに").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("動画を選ぶ", systemImage: "film") { importing = true }
                .keyboardShortcut("o")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("動画を選択", systemImage: "film.stack")
        } description: {
            Text("MP4 / MOV（SDR、最大 4K・2時間）に対応します。\n音声と映像は送信しません。Luna選択時のみ文字起こしした英文を送信します。")
        } actions: {
            Button("動画を選ぶ") { importing = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspace: some View {
        HSplitView {
            VStack(spacing: 12) {
                ZStack(alignment: .bottom) {
                    if let player = model.player { NativeVideoPlayer(player: player) }
                    if let caption = model.currentCaption {
                        CaptionRasterPreview(
                            text: caption,
                            renderSize: model.sourceRenderSize ?? CGSize(width: 1_920, height: 1_080)
                        )
                    }
                }
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("字幕プレビュー")
                controls
            }
            .padding(18).frame(minWidth: 540)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("字幕").font(.headline)
                    Spacer()
                    Text("\(model.cues.count) 件").foregroundStyle(.secondary)
                }
                if model.cues.isEmpty {
                    ContentUnavailableView("字幕はまだありません", systemImage: "text.bubble")
                } else {
                    List(model.cues) { cue in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(timeLabel(cue)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            TextField("字幕", text: Binding(
                                get: { cue.text },
                                set: { model.updateCue(id: cue.id, text: $0) }
                            ), axis: .vertical)
                            .lineLimit(2)
                            if cue.warnings.contains(.readingSpeedExceeded) {
                                Label("読む速度が速すぎます", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
            .padding(18).frame(minWidth: 320, idealWidth: 380)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("話している言語", selection: $model.sourceLanguage) {
                    Text("日本語").tag(SourceLanguage.japanese)
                    Text("英語").tag(SourceLanguage.english)
                }.frame(width: 230)
                if model.sourceLanguage == .english {
                    Picker("翻訳", selection: $model.englishTranslationMode) {
                        Text("Apple（ローカル）").tag(EnglishTranslationMode.appleLocal)
                        Text("GPT-5.6 Luna").tag(EnglishTranslationMode.gpt56Luna)
                    }.frame(width: 230)
                }
            }
            .disabled(model.settingsLocked)
            if model.sourceLanguage == .english {
                TextField(
                    "用語集（1行に source=訳。例: Managed Agent=マネージドエージェント）",
                    text: Binding(get: { model.glossaryText }, set: { model.updateGlossaryText($0) }),
                    axis: .vertical
                )
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .disabled(model.settingsLocked)
                if model.sendsTranscriptToOpenAI {
                    HStack {
                        Label("文字起こしした英文と用語集だけをOpenAIへ送信します", systemImage: "cloud")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(apiKeyButtonTitle) {
                            apiKeyDraft = ""
                            showingAPIKeySettings = true
                        }
                        .controlSize(.small)
                    }
                }
            }
            HStack {
                if case .working = model.phase {
                    Button("キャンセル", role: .cancel) { model.cancel() }
                } else if model.phase == .awaitingTranslation {
                    Button("キャンセル", role: .cancel) { model.cancel() }
                } else if model.phase == .exporting {
                    Button("キャンセル", role: .cancel) { model.cancel() }
                }
                Button("字幕を生成", systemImage: "waveform.and.badge.magnifyingglass") {
                    if model.sendsTranscriptToOpenAI {
                        if model.hasLunaAPIKey {
                            confirmCloudTranslation = true
                        } else {
                            apiKeyDraft = ""
                            showingAPIKeySettings = true
                        }
                    } else {
                        model.generate()
                    }
                }
                .disabled(!model.canGenerate)
                Button("SRT", systemImage: "doc.text") { chooseSRTDestination() }
                    .disabled(!model.canSaveSRT)
                Button("動画を書き出す", systemImage: "square.and.arrow.up") { chooseDestination() }
                    .buttonStyle(.borderedProminent).disabled(!model.canExport)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(statusText).font(.callout)
            Spacer()
            if case .completed(let url) = model.phase {
                Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if case .speechModelRequired = model.phase {
                Button("音声認識モデルを準備") { model.prepareSpeechModel() }
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var apiKeyButtonTitle: String {
        if model.hasStoredLunaAPIKey { return "APIキー設定済み" }
        if model.hasLunaAPIKey { return "開発用キー" }
        return "APIキーを設定"
    }

    @ViewBuilder private var statusIcon: some View {
        if model.outputError != nil {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else {
            switch model.phase {
            case .working, .installingSpeechModel, .awaitingTranslation, .exporting:
                ProgressView().controlSize(.small)
            case .speechModelRequired: Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            default: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if let outputError = model.outputError { return outputError }
        return switch model.phase {
        case .empty: "動画を選んでください"
        case .ready: "字幕を生成できます"
        case .working(let text): text
        case .speechModelRequired(let locale): "音声認識モデル（\(locale)）の準備が必要です"
        case .installingSpeechModel:
            "Appleの音声認識モデルを準備中です。OSが取得を継続する場合があります"
        case .awaitingTranslation: "翻訳モデルを準備中"
        case .review: "字幕を確認・修正してから書き出してください"
        case .exporting: "字幕付き動画を書き出し中"
        case .completed: "書き出しが完了しました"
        case .failed(let message): message
        }
    }

    private func chooseDestination() {
        let filename = "字幕付き-\(model.sourceURL?.deletingPathExtension().lastPathComponent ?? "動画").mp4"
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "このフォルダに書き出す"
        panel.message = "保存先フォルダを選択してください。ファイル名: \(filename)"
        if panel.runModal() == .OK, let directory = panel.url {
            model.export(
                to: directory.appendingPathComponent(filename, isDirectory: false),
                securityScopedRoot: directory
            )
        }
    }

    private func chooseSRTDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(model.sourceURL?.deletingPathExtension().lastPathComponent ?? "字幕").srt"
        if panel.runModal() == .OK, let url = panel.url { model.saveSRT(to: url) }
    }

    private func timeLabel(_ cue: DisplayCue) -> String {
        let start = (try? cue.range.start.srtMilliseconds()) ?? 0
        let end = (try? cue.range.end.srtMilliseconds()) ?? 0
        return String(format: "%02d:%02d.%03d – %02d:%02d.%03d",
                      start / 60_000, (start / 1000) % 60, start % 1000,
                      end / 60_000, (end / 1000) % 60, end % 1000)
    }
}

private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AppKitPlayerSurface {
        AppKitPlayerSurface(player: player)
    }

    func updateNSView(_ nsView: AppKitPlayerSurface, context: Context) {
        nsView.update(player: player)
    }

    static func dismantleNSView(_ nsView: AppKitPlayerSurface, coordinator: ()) {
        nsView.update(player: nil)
    }
}

private struct CaptionRasterPreview: View {
    let text: String
    let renderSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            if let geometry = SubtitleVideoExporter.captionPreviewGeometry(
                renderSize: renderSize,
                containerSize: proxy.size
            ) {
                let backgroundPadding = SubtitleVideoExporter.captionBackgroundPadding(fontSize: geometry.fontSize)
                if let image = SubtitleVideoExporter.renderedCaptionImage(
                    text,
                    size: geometry.textFrame.size,
                    fontSize: geometry.fontSize
                ) {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .frame(width: geometry.textFrame.width, height: geometry.textFrame.height)
                        .padding(.horizontal, backgroundPadding.width)
                        .padding(.vertical, backgroundPadding.height)
                        .background(
                            .black.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: geometry.fontSize * 0.2)
                        )
                        .position(
                            x: geometry.backgroundFrame.midX,
                            y: proxy.size.height - geometry.backgroundFrame.midY
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
