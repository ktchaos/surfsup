import AVFoundation
import Foundation

/// Decides when playback may start and which seek tolerance to use.
/// The initial seek to the start of a clip is the only inexact seek.
/// Later scrubs stay exact. This type does not talk to AVPlayer.
nonisolated struct PlaybackSync: Equatable, Sendable {
    enum Precision: Equatable, Sendable {
        /// Allow samples at or before the start so a trimmed edit list can land on the first frame.
        case startOfClip
        case exactFrame
    }

    struct Seek: Equatable, Sendable {
        var time: TimeInterval
        var precision: Precision
    }

    enum Transport: Equatable, Sendable {
        case play
        case pause
    }

    struct Command: Equatable, Sendable {
        var transport: Transport?
        var seek: Seek?
        var markStartAligned: Bool

        static let wait = Command(transport: nil, seek: nil, markStartAligned: false)
    }

    /// Half a frame when the clip has a frame duration, otherwise the start-alignment tolerance.
    static func pausedSeekThreshold(frameDuration: TimeInterval?, seekTolerance: TimeInterval) -> TimeInterval {
        guard let frameDuration else { return seekTolerance }
        return frameDuration / 2
    }

    static func command(
        itemReady: Bool,
        isPlaying: Bool,
        playhead: TimeInterval,
        currentTime: TimeInterval,
        hasAlignedStart: Bool,
        seekTolerance: TimeInterval,
        frameDuration: TimeInterval?
    ) -> Command {
        guard itemReady else { return .wait }

        let targetIsStart = playhead <= seekTolerance
        if !hasAlignedStart, targetIsStart {
            let alreadyAtStart = currentTime.isFinite && currentTime <= seekTolerance
            if alreadyAtStart {
                return Command(
                    transport: isPlaying ? .play : .pause,
                    seek: nil,
                    markStartAligned: true
                )
            }
            return Command(
                transport: .pause,
                seek: Seek(time: 0, precision: .startOfClip),
                markStartAligned: false
            )
        }

        if !isPlaying,
           currentTime.isFinite,
           abs(currentTime - playhead) > pausedSeekThreshold(frameDuration: frameDuration, seekTolerance: seekTolerance) {
            return Command(
                transport: .pause,
                seek: Seek(
                    time: playhead,
                    precision: targetIsStart ? .startOfClip : .exactFrame
                ),
                markStartAligned: true
            )
        }

        return Command(
            transport: isPlaying ? .play : .pause,
            seek: nil,
            markStartAligned: hasAlignedStart || !targetIsStart
        )
    }

    static func tolerances(for precision: Precision) -> (before: CMTime, after: CMTime) {
        switch precision {
        case .startOfClip:
            (before: .positiveInfinity, after: .zero)
        case .exactFrame:
            (before: .zero, after: .zero)
        }
    }
}
