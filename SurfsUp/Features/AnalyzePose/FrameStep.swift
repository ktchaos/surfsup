import Foundation

/// One video frame of the clip under review, and where a step lands.
///
/// The duration is the clip's own nominal frame rate. A step moves from the
/// current playhead by that duration and stays inside the clip. It does not
/// snap to a frame grid and it does not read a timeline.
nonisolated enum FrameStep {
    enum Direction: Equatable, Sendable {
        case backward
        case forward
    }

    /// `nil` unless the rate is finite and greater than zero.
    static func duration(nominalFrameRate: Float) -> TimeInterval? {
        guard nominalFrameRate.isFinite, nominalFrameRate > 0 else { return nil }
        return 1 / TimeInterval(nominalFrameRate)
    }

    /// `playhead` minus one frame for `.backward`, plus one frame for `.forward`,
    /// clamped to `0...max(clipDuration, 0)`.
    static func target(
        from playhead: TimeInterval,
        direction: Direction,
        frameDuration: TimeInterval,
        clipDuration: TimeInterval
    ) -> TimeInterval {
        let moved = direction == .backward ? playhead - frameDuration : playhead + frameDuration
        let upper = max(clipDuration, 0)
        return min(max(0, moved), upper)
    }
}
