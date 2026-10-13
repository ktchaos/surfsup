import AVFoundation
import SwiftUI
import UIKit

struct PoseOverlayView: View {
    let clip: SelectedClip
    let timeline: PoseTimeline
    let playhead: TimeInterval
    let isPlaying: Bool
    let onPlayhead: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            let rect = PoseLayout.aspectFit(content: clip.displaySize, in: proxy.size)
            ZStack {
                VideoPlaybackView(
                    url: clip.url,
                    isPlaying: isPlaying,
                    playhead: playhead,
                    onPlayhead: onPlayhead
                )
                Canvas { context, _ in
                    guard let observation = PlayheadLookup.observation(at: playhead, in: timeline),
                          let body = observation.body else {
                        return
                    }
                    let points = Dictionary(uniqueKeysWithValues: body.landmarks.map { ($0.joint, $0) })
                    var bones = Path()
                    for edge in SkeletonEdges.visible(in: body.landmarks) {
                        guard let start = points[edge.start], let end = points[edge.end] else { continue }
                        bones.move(to: PoseLayout.point(start, in: rect))
                        bones.addLine(to: PoseLayout.point(end, in: rect))
                    }
                    context.stroke(
                        bones,
                        with: .color(AppColors.pose),
                        lineWidth: AppConstants.UI.poseLineWidth
                    )
                    let side = AppConstants.UI.posePointSize
                    for landmark in body.landmarks {
                        let center = PoseLayout.point(landmark, in: rect)
                        let dot = CGRect(
                            x: center.x - side / 2,
                            y: center.y - side / 2,
                            width: side,
                            height: side
                        )
                        context.fill(Path(ellipseIn: dot), with: .color(AppColors.pose))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .background(AppColors.background)
    }
}

/// Maps upright, bottom-left normalized landmarks into the same aspect-fit rect as playback.
/// Detection already applied `SelectedClip.displayTransform` as the Vision orientation,
/// so the stored points match the upright picture the player shows.
enum PoseLayout {
    static func aspectFit(content: CGSize, in bounds: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        return CGRect(origin: origin, size: size)
    }

    static func point(_ landmark: Landmark, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + landmark.x * rect.width,
            y: rect.minY + (1 - landmark.y) * rect.height
        )
    }
}

struct VideoPlaybackView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let playhead: TimeInterval
    let onPlayhead: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlayhead: onPlayhead)
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        let coordinator = context.coordinator
        coordinator.player = player
        coordinator.url = url
        coordinator.desiredPlaying = isPlaying
        coordinator.desiredPlayhead = playhead
        coordinator.observeStatus(of: item)
        let interval = CMTime(seconds: UIConstants.AnalyzePose.playheadInterval, preferredTimescale: 600)
        coordinator.token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard player.rate > 0 else { return }
            coordinator.onPlayhead(time.seconds)
        }
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPlayhead = onPlayhead
        coordinator.desiredPlaying = isPlaying
        coordinator.desiredPlayhead = playhead
        guard let player = view.playerLayer.player else { return }
        if player.currentItem == nil || coordinator.url != url {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            coordinator.url = url
            coordinator.resetAlignment()
            coordinator.observeStatus(of: item)
        }
        coordinator.apply(player: player)
    }

    static func dismantleUIView(_ view: PlayerHostView, coordinator: Coordinator) {
        coordinator.statusObservation?.invalidate()
        coordinator.statusObservation = nil
        if let token = coordinator.token {
            coordinator.player?.removeTimeObserver(token)
        }
        coordinator.player?.pause()
    }

    final class Coordinator {
        var player: AVPlayer?
        var token: Any?
        var url: URL?
        var onPlayhead: (TimeInterval) -> Void
        var desiredPlaying = false
        var desiredPlayhead: TimeInterval = 0
        var hasAlignedStart = false
        var seekInFlight = false
        var pendingSeek: PlaybackSync.Seek?
        var seekGeneration = 0
        var statusObservation: NSKeyValueObservation?

        init(onPlayhead: @escaping (TimeInterval) -> Void) {
            self.onPlayhead = onPlayhead
        }

        func resetAlignment() {
            hasAlignedStart = false
            seekInFlight = false
            pendingSeek = nil
            seekGeneration += 1
        }

        func observeStatus(of item: AVPlayerItem) {
            statusObservation?.invalidate()
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, let player = self.player else { return }
                    self.apply(player: player)
                }
            }
        }

        func apply(player: AVPlayer) {
            let command = PlaybackSync.command(
                itemReady: player.currentItem?.status == .readyToPlay,
                isPlaying: desiredPlaying,
                playhead: desiredPlayhead,
                currentTime: player.currentTime().seconds,
                hasAlignedStart: hasAlignedStart,
                seekTolerance: UIConstants.AnalyzePose.seekTolerance
            )
            if command.markStartAligned {
                hasAlignedStart = true
            }
            guard player.currentItem?.status == .readyToPlay else {
                if player.rate != 0 { player.pause() }
                return
            }
            if let seek = command.seek {
                guard !seekInFlight || pendingSeek != seek else { return }
                seekGeneration += 1
                let generation = seekGeneration
                seekInFlight = true
                pendingSeek = seek
                if player.rate != 0 { player.pause() }
                let tolerances = PlaybackSync.tolerances(for: seek.precision)
                player.seek(
                    to: CMTime(seconds: seek.time, preferredTimescale: 600),
                    toleranceBefore: tolerances.before,
                    toleranceAfter: tolerances.after
                ) { [weak self] finished in
                    Task { @MainActor in
                        guard let self, let player = self.player, generation == self.seekGeneration else { return }
                        self.seekInFlight = false
                        self.pendingSeek = nil
                        if finished, seek.precision == .startOfClip {
                            self.hasAlignedStart = true
                        }
                        self.apply(player: player)
                    }
                }
                return
            }
            switch command.transport {
            case .play:
                guard !seekInFlight, player.rate == 0 else { return }
                player.play()
            case .pause:
                if player.rate != 0 { player.pause() }
            case nil:
                break
            }
        }
    }
}

final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
