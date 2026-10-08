import Foundation

/// Local file contents for a finished run.
///
/// The data model requires `clipDuration`, `elapsedSeconds`, `framesCompleted`, and `observations`.
/// The evidence contract also stores raw frame counts: `decodedFrameCount`, `attemptedFrameCount`,
/// and `gapCount`. Those counts are not a judgment, a score, or a surf metric.
/// In this slice every decoded frame is attempted, so the first two equal `framesCompleted`.
nonisolated struct EvidenceRecord: Equatable, Sendable, Codable {
    var clipDuration: TimeInterval
    var elapsedSeconds: TimeInterval
    var framesCompleted: Int
    var decodedFrameCount: Int
    var attemptedFrameCount: Int
    var gapCount: Int
    var observations: [FrameObservation]

    init?(timeline: PoseTimeline, elapsedSeconds: TimeInterval, decodedFrameCount: Int, attemptedFrameCount: Int) {
        guard elapsedSeconds >= 0 else { return nil }
        guard decodedFrameCount == timeline.observations.count else { return nil }
        guard attemptedFrameCount == timeline.observations.count else { return nil }
        self.clipDuration = timeline.clipDuration
        self.elapsedSeconds = elapsedSeconds
        self.framesCompleted = timeline.observations.count
        self.decodedFrameCount = decodedFrameCount
        self.attemptedFrameCount = attemptedFrameCount
        self.gapCount = timeline.observations.filter { $0.body == nil }.count
        self.observations = timeline.observations
    }

    enum CodingKeys: String, CodingKey {
        case clipDuration
        case elapsedSeconds
        case framesCompleted
        case decodedFrameCount
        case attemptedFrameCount
        case gapCount
        case observations
    }
}
