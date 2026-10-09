import Foundation

/// One pass over one clip. A session holds at most one run.
nonisolated struct AnalysisRun: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case running
        case finished
        case failed
        case cancelled
    }

    var clip: SelectedClip
    var phase: Phase
    var framesCompleted: Int
    var framesTotal: Int?
    var startedAt: Date
    var finishedAt: Date?
    var timeline: PoseTimeline?
    var failure: String?

    init?(
        clip: SelectedClip,
        phase: Phase,
        framesCompleted: Int,
        framesTotal: Int?,
        startedAt: Date,
        finishedAt: Date?,
        timeline: PoseTimeline?,
        failure: String?
    ) {
        switch phase {
        case .finished:
            guard timeline != nil, failure == nil else { return nil }
        case .failed:
            guard timeline == nil, let failure, !failure.isEmpty else { return nil }
        case .running, .cancelled:
            guard timeline == nil, failure == nil else { return nil }
        }
        guard framesCompleted >= 0 else { return nil }
        self.clip = clip
        self.phase = phase
        self.framesCompleted = framesCompleted
        self.framesTotal = framesTotal
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.timeline = timeline
        self.failure = failure
    }
}

nonisolated struct AnalysisSession: Equatable, Sendable {
    var clip: SelectedClip?
    var run: AnalysisRun?
    var evidenceMissing = false

    enum Kind: Equatable {
        case empty
        case ready
        case running
        case review
        case failed
    }

    var kind: Kind {
        guard let run else { return clip == nil ? .empty : .ready }
        switch run.phase {
        case .running:
            return .running
        case .finished:
            return .review
        case .failed:
            return .failed
        case .cancelled:
            return .ready
        }
    }
}
