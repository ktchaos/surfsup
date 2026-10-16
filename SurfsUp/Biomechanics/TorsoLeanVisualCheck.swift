import Foundation

nonisolated enum TorsoLeanSheetError: Error, Equatable, Sendable {
    case computedAnglePresent
    case scoredOutcomePresent
    case usablePauseCount
    case oppositeLeanCount
    case missingImageReason
    case unexpectedImageReason
    case uncoveredClipHasPauses
}

nonisolated struct PauseSheet: Equatable, Sendable, Decodable {
    var clips: [PauseClip]
}

nonisolated struct PauseClip: Equatable, Sendable, Decodable {
    var clipDuration: TimeInterval
    var role: Role
    var pauses: [PauseEntry]

    enum Role: String, Equatable, Sendable, Codable {
        case usable
        case uncovered
    }

    init(clipDuration: TimeInterval, role: Role, pauses: [PauseEntry]) {
        self.clipDuration = clipDuration
        self.role = role
        self.pauses = pauses
    }
}

nonisolated struct PauseEntry: Equatable, Sendable, Decodable {
    var timestamp: TimeInterval
    var expectedSign: ExpectedSign
    var imageReason: String?
    var oppositeLean: Bool

    enum ExpectedSign: String, Equatable, Sendable, Decodable {
        case left
        case right
        case none
    }

    init(timestamp: TimeInterval, expectedSign: ExpectedSign, imageReason: String?, oppositeLean: Bool) {
        self.timestamp = timestamp
        self.expectedSign = expectedSign
        self.imageReason = imageReason
        self.oppositeLean = oppositeLean
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case expectedSign
        case imageReason
        case oppositeLean
        case angleDegrees
        case computedSign
        case outcome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.angleDegrees) || container.contains(.computedSign) {
            throw TorsoLeanSheetError.computedAnglePresent
        }
        if container.contains(.outcome) {
            throw TorsoLeanSheetError.scoredOutcomePresent
        }
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        expectedSign = try container.decode(ExpectedSign.self, forKey: .expectedSign)
        imageReason = try container.decodeIfPresent(String.self, forKey: .imageReason)
        oppositeLean = try container.decode(Bool.self, forKey: .oppositeLean)
    }
}

nonisolated struct UncoveredRange: Equatable, Sendable, Codable {
    var start: TimeInterval
    var end: TimeInterval
}

nonisolated struct PauseResult: Equatable, Sendable, Codable {
    var timestamp: TimeInterval
    var outcome: Outcome
    var reason: String

    enum Outcome: String, Equatable, Sendable, Codable {
        case match
        case mismatch
        case unassessable
        case uncovered
    }
}

nonisolated struct TorsoLeanClipReport: Equatable, Sendable, Codable {
    var clipDuration: TimeInterval
    var role: PauseClip.Role
    var pauseResults: [PauseResult]
    var matchCount: Int
    var signCheck: SignCheck?
    var oppositeLeanCheck: OppositeLeanCheck?
    var uncoveredRanges: [UncoveredRange]
    var uncoveredFraction: Double
    var statement: String

    enum SignCheck: String, Equatable, Sendable, Codable {
        case passed
        case failed
    }

    enum OppositeLeanCheck: String, Equatable, Sendable, Codable {
        case passed
        case failed
        case notExercised
    }

    static let proxyStatement = """
    The value is the image-plane orientation of the segment from root to neck, a proxy for torso orientation in the picture. It is not a validated anatomical measurement, not a 3D body angle, and not an angle relative to the surfboard.
    """
}

nonisolated enum TorsoLeanVisualCheck {
    static func decodeSheet(_ data: Data) throws -> PauseSheet {
        let sheet = try JSONDecoder().decode(PauseSheet.self, from: data)
        for clip in sheet.clips {
            try validate(clip)
        }
        return sheet
    }

    static func score(clip: PauseClip, timeline: PoseTimeline) throws -> TorsoLeanClipReport {
        try validate(clip)
        let ranges = uncoveredRanges(in: timeline)
        let uncoveredDuration = ranges.reduce(0.0) { $0 + ($1.end - $1.start) }
        if clip.role == .uncovered {
            return TorsoLeanClipReport(
                clipDuration: clip.clipDuration,
                role: clip.role,
                pauseResults: [],
                matchCount: 0,
                signCheck: nil,
                oppositeLeanCheck: nil,
                uncoveredRanges: ranges,
                uncoveredFraction: uncoveredDuration / timeline.clipDuration,
                statement: TorsoLeanClipReport.proxyStatement
            )
        }

        let results = clip.pauses.map { pause in
            scoredPause(pause, in: timeline)
        }
        let matchCount = results.filter { $0.outcome == .match }.count
        return TorsoLeanClipReport(
            clipDuration: clip.clipDuration,
            role: clip.role,
            pauseResults: results,
            matchCount: matchCount,
            signCheck: matchCount >= 4 ? .passed : .failed,
            oppositeLeanCheck: oppositeLeanCheck(pauses: clip.pauses, results: results),
            uncoveredRanges: ranges,
            uncoveredFraction: uncoveredDuration / timeline.clipDuration,
            statement: TorsoLeanClipReport.proxyStatement
        )
    }

    private static func validate(_ clip: PauseClip) throws {
        if clip.role == .uncovered {
            if !clip.pauses.isEmpty {
                throw TorsoLeanSheetError.uncoveredClipHasPauses
            }
            return
        }
        guard clip.pauses.count == 5 else {
            throw TorsoLeanSheetError.usablePauseCount
        }
        let marked = clip.pauses.filter(\.oppositeLean).count
        guard marked == 0 || marked == 2 else {
            throw TorsoLeanSheetError.oppositeLeanCount
        }
        for pause in clip.pauses {
            if pause.expectedSign == .none {
                if pause.imageReason?.isEmpty != false {
                    throw TorsoLeanSheetError.missingImageReason
                }
            } else if pause.imageReason != nil {
                throw TorsoLeanSheetError.unexpectedImageReason
            }
        }
    }

    private static func scoredPause(_ pause: PauseEntry, in timeline: PoseTimeline) -> PauseResult {
        if let missing = missingPoseData(at: pause.timestamp, in: timeline) {
            return PauseResult(timestamp: pause.timestamp, outcome: .uncovered, reason: missing)
        }
        guard let sample = ImagePlaneTorsoLean.sample(at: pause.timestamp, in: timeline) else {
            return PauseResult(timestamp: pause.timestamp, outcome: .uncovered, reason: "No sample: required pose data is missing.")
        }
        if pause.expectedSign == .none {
            return PauseResult(
                timestamp: pause.timestamp,
                outcome: .unassessable,
                reason: pause.imageReason ?? ""
            )
        }
        let agrees = (sample.ordinarySign == .right && pause.expectedSign == .right)
            || (sample.ordinarySign == .left && pause.expectedSign == .left)
        if agrees {
            return PauseResult(
                timestamp: pause.timestamp,
                outcome: .match,
                reason: "Calculated sign agrees with the expected visual sign."
            )
        }
        return PauseResult(
            timestamp: pause.timestamp,
            outcome: .mismatch,
            reason: "Calculated sign disagrees with the expected visual sign."
        )
    }

    private static func missingPoseData(at time: TimeInterval, in timeline: PoseTimeline) -> String? {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline) else {
            return "No sample: no observation."
        }
        guard let body = observation.body else {
            return "No sample: no body."
        }
        let neck = body.landmarks.first { $0.joint == .neck }
        let root = body.landmarks.first { $0.joint == .root }
        switch (neck, root) {
        case (nil, nil):
            return "No sample: missing neck and root."
        case (nil, _):
            return "No sample: missing neck."
        case (_, nil):
            return "No sample: missing root."
        case let (neck?, root?) where neck.x == root.x && neck.y == root.y:
            return "No sample: coincident points."
        default:
            return nil
        }
    }

    private static func oppositeLeanCheck(
        pauses: [PauseEntry],
        results: [PauseResult]
    ) -> TorsoLeanClipReport.OppositeLeanCheck {
        let marked = zip(pauses, results).filter { $0.0.oppositeLean }
        guard marked.count == 2 else {
            return .notExercised
        }
        let signs = marked.map(\.0.expectedSign)
        let bothSides = signs.contains(.left) && signs.contains(.right)
        let bothMatch = marked.allSatisfy { $0.1.outcome == .match }
        if bothSides && bothMatch {
            return .passed
        }
        return .failed
    }

    private static func uncoveredRanges(in timeline: PoseTimeline) -> [UncoveredRange] {
        var ranges: [UncoveredRange] = []
        for observation in timeline.observations where observation.body == nil {
            if let last = ranges.last, last.end == observation.start {
                ranges[ranges.count - 1].end = observation.end
            } else {
                ranges.append(UncoveredRange(start: observation.start, end: observation.end))
            }
        }
        return ranges
    }
}
