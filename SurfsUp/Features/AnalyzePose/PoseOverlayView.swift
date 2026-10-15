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
                PlaybackTimeLabel(time: playhead)
                    .frame(width: rect.width, height: rect.height, alignment: .topTrailing)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                Canvas { context, _ in
                    let torsoPoints = ImagePlaneTorsoLean.storedPoints(at: playhead, in: timeline)
                    guard let observation = PlayheadLookup.observation(at: playhead, in: timeline),
                          let body = observation.body else {
                        drawTorsoSegment(context: &context, points: torsoPoints, in: rect)
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
                    drawTorsoSegment(context: &context, points: torsoPoints, in: rect)
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
private struct PlaybackTimeLabel: View {
    var time: TimeInterval

    var body: some View {
        Text(PlaybackTimestamp.label(for: time))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppColors.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .padding(6)
    }
}

private let torsoNeckColor = Color(red: 0.25, green: 0.95, blue: 1)
private let torsoRootColor = Color(red: 1, green: 0.45, blue: 0.2)

private func drawTorsoSegment(
    context: inout GraphicsContext,
    points: ImagePlaneTorsoPoints,
    in rect: CGRect
) {
    let neck = points.neck.map { PoseLayout.point($0, in: rect) }
    let root = points.root.map { PoseLayout.point($0, in: rect) }
    if let neck, let root {
        var segment = Path()
        segment.move(to: neck)
        segment.addLine(to: root)
        context.stroke(segment, with: .color(.white), lineWidth: 1.5)
    }
    if let neck {
        strokeMarker(context: &context, at: neck, color: torsoNeckColor, shape: .circle)
        drawMarkerLabel("NECK", at: neck, above: true, color: torsoNeckColor, in: rect, context: &context)
    }
    if let root {
        strokeMarker(context: &context, at: root, color: torsoRootColor, shape: .square)
        drawMarkerLabel("ROOT / HIP CENTER", at: root, above: false, color: torsoRootColor, in: rect, context: &context)
    }
}

private enum TorsoMarkerShape {
    case circle
    case square
}

private func strokeMarker(
    context: inout GraphicsContext,
    at center: CGPoint,
    color: Color,
    shape: TorsoMarkerShape
) {
    let side: CGFloat = 14
    let bounds = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    let path = shape == .circle ? Path(ellipseIn: bounds) : Path(roundedRect: bounds, cornerRadius: 2)
    context.stroke(path, with: .color(color), lineWidth: 2)
}

private func drawMarkerLabel(
    _ title: String,
    at marker: CGPoint,
    above: Bool,
    color: Color,
    in rect: CGRect,
    context: inout GraphicsContext
) {
    let resolved = context.resolve(
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
    )
    let size = resolved.measure(in: CGSize(width: 160, height: 16))
    let gap: CGFloat = 8
    var originY = above ? marker.y - gap - size.height : marker.y + gap
    if originY < rect.minY {
        originY = min(marker.y + gap, rect.maxY - size.height)
    }
    if originY + size.height > rect.maxY {
        originY = max(rect.minY, marker.y - gap - size.height)
    }
    let maxX = max(rect.minX, rect.maxX - size.width)
    let originX = min(max(marker.x - size.width / 2, rect.minX), maxX)
    let origin = CGPoint(x: originX, y: originY)
    let background = CGRect(x: origin.x - 3, y: origin.y - 1, width: size.width + 6, height: size.height + 2)
    context.fill(Path(roundedRect: background, cornerRadius: 3), with: .color(.black.opacity(0.6)))
    context.draw(resolved, at: CGPoint(x: background.midX, y: background.midY), anchor: .center)
}

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
