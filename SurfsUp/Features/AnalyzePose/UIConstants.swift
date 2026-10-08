import Foundation

nonisolated enum UIConstants {
    nonisolated enum AnalyzePose {
        static let progressInterval: TimeInterval = 2
        static let cancelBound: TimeInterval = 1
        static let playheadInterval: TimeInterval = 1.0 / 30.0
        static let seekTolerance: TimeInterval = 0.05
    }
}

/// Publishes at least as often as `interval`. More frequent publication is allowed by the caller.
nonisolated struct ProgressCadence: Equatable, Sendable {
    var interval: TimeInterval
    private var lastPublication: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func shouldPublish(at now: Date) -> Bool {
        guard let lastPublication else {
            self.lastPublication = now
            return true
        }
        guard now.timeIntervalSince(lastPublication) >= interval else { return false }
        self.lastPublication = now
        return true
    }
}
