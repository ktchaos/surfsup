import Foundation

nonisolated enum PlayheadLookup {
    /// The observation containing `time` under the half-open rule `start <= t < end`.
    static func observation(at time: TimeInterval, in timeline: PoseTimeline) -> FrameObservation? {
        timeline.observations.first { $0.start <= time && time < $0.end }
    }
}
