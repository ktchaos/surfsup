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
        let player = AVPlayer(url: url)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        let interval = CMTime(seconds: UIConstants.AnalyzePose.playheadInterval, preferredTimescale: 600)
        context.coordinator.player = player
        context.coordinator.token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard player.rate > 0 else { return }
            context.coordinator.onPlayhead(time.seconds)
        }
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        context.coordinator.onPlayhead = onPlayhead
        guard let player = view.playerLayer.player else { return }
        if player.currentItem == nil || context.coordinator.url != url {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            context.coordinator.url = url
        }
        if isPlaying {
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 {
            player.pause()
        }
        guard !isPlaying else { return }
        let current = player.currentTime().seconds
        guard current.isFinite, abs(current - playhead) > UIConstants.AnalyzePose.seekTolerance else { return }
        player.seek(
            to: CMTime(seconds: playhead, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    static func dismantleUIView(_ view: PlayerHostView, coordinator: Coordinator) {
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

        init(onPlayhead: @escaping (TimeInterval) -> Void) {
            self.onPlayhead = onPlayhead
        }
    }
}

final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
