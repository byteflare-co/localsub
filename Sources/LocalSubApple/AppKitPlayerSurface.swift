import AppKit
import AVFoundation
import AVKit

@MainActor
public final class AppKitPlayerSurface: NSView {
    public let playerView: AVPlayerView

    public init(player: AVPlayer?) {
        playerView = AVPlayerView(frame: .zero)
        super.init(frame: .zero)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func update(player: AVPlayer?) {
        if playerView.player !== player {
            playerView.player = player
        }
    }
}

@MainActor
public final class PlayerTimeObserver {
    private final class ObserverToken: @unchecked Sendable {
        let value: Any
        init(_ value: Any) { self.value = value }
    }

    public private(set) var observedPlayer: AVPlayer?
    private var token: ObserverToken?

    public init() {}

    public func install(
        on player: AVPlayer,
        interval: CMTime = CMTime(value: 1, timescale: 10),
        handler: @escaping @Sendable (CMTime) -> Void
    ) {
        invalidate()
        observedPlayer = player
        token = ObserverToken(
            player.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: handler)
        )
    }

    public func invalidate() {
        if let token, let observedPlayer {
            observedPlayer.removeTimeObserver(token.value)
        }
        token = nil
        observedPlayer = nil
    }

    deinit {
        if let token, let observedPlayer {
            observedPlayer.removeTimeObserver(token.value)
        }
    }
}
