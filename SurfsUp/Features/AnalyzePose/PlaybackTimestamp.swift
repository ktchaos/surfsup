import Foundation

/// Display text for the review playhead. The value is media time already stored by playback, not a wall clock.
nonisolated enum PlaybackTimestamp {
    static func label(for seconds: TimeInterval) -> String {
        let clamped = seconds.isFinite ? max(0, seconds) : 0
        let totalMilliseconds = Int((clamped * 1000).rounded(.toNearestOrAwayFromZero))
        let minutes = totalMilliseconds / 60_000
        let remainder = totalMilliseconds % 60_000
        let wholeSeconds = remainder / 1000
        let milliseconds = remainder % 1000
        return String(format: "%02d:%02d.%03d", minutes, wholeSeconds, milliseconds)
    }
}
