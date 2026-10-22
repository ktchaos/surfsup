import Foundation

nonisolated enum KneeOrdinalSheetError: Error, Equatable, Sendable {
    case computedAnglePresent
    case scoredOutcomePresent
    case expectedSignPresent
    case oppositeLeanPresent
    case usablePauseCount
    case picturePair
    case missingImageReason
    case unexpectedImageReason
    case missingKnee
    case uncoveredClipHasPauses
    case uncoveredClipHasKnee
}

nonisolated struct KneeOrdinalSheet: Equatable, Sendable, Decodable {
    var clips: [KneeOrdinalClip]
}

nonisolated struct KneeOrdinalClip: Equatable, Sendable, Decodable {
    var clipDuration: TimeInterval
    var role: Role
    var knee: ImagePlaneKneeSide?
    var pauses: [KneeOrdinalPause]

    enum Role: String, Equatable, Sendable, Codable {
        case usable
        case uncovered
    }

    init(clipDuration: TimeInterval, role: Role, knee: ImagePlaneKneeSide?, pauses: [KneeOrdinalPause]) {
        self.clipDuration = clipDuration
        self.role = role
        self.knee = knee
        self.pauses = pauses
    }

    enum CodingKeys: String, CodingKey {
        case clipDuration
        case role
        case knee
        case pauses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipDuration = try container.decode(TimeInterval.self, forKey: .clipDuration)
        role = try container.decode(Role.self, forKey: .role)
        if container.contains(.knee) {
            let name = try container.decode(String.self, forKey: .knee)
            switch name {
            case "left": knee = .left
            case "right": knee = .right
            default: throw DecodingError.dataCorruptedError(
                forKey: .knee,
                in: container,
                debugDescription: "The stored knee must be left or right."
            )
            }
        } else {
            knee = nil
        }
        pauses = try container.decode([KneeOrdinalPause].self, forKey: .pauses)
    }
}

nonisolated struct KneeOrdinalPause: Equatable, Sendable, Decodable {
    var timestamp: TimeInterval
    var picture: Picture
    var imageReason: String?

    enum Picture: String, Equatable, Sendable, Codable {
        case moreBent
        case lessBent
        case unclear
        case visible
    }

    init(timestamp: TimeInterval, picture: Picture, imageReason: String?) {
        self.timestamp = timestamp
        self.picture = picture
        self.imageReason = imageReason
    }
}

nonisolated struct KneeOrdinalFact: Equatable, Sendable {
    var timestamp: TimeInterval
    var disposition: Disposition
    var reason: String

    enum Disposition: String, Equatable, Sendable {
        case uncovered
        case unassessable
        case compared
        case listed
    }
}

nonisolated enum KneeOrdinalComparison: String, Equatable, Sendable {
    case match
    case mismatch
    case notScored
}

nonisolated struct KneeOrdinalReport: Equatable, Sendable {
    var clipDuration: TimeInterval
    var role: KneeOrdinalClip.Role
    var knee: ImagePlaneKneeSide?
    var pauses: [KneeOrdinalFact]
    var comparison: KneeOrdinalComparison?
    var statement: String

    static let pictureProxyStatement = """
    This is an image-plane picture proxy for how bent one stored knee looks, in the same class as the image-plane torso lean. It is not anatomical knee flexion, not a 3D joint angle, not an angle relative to the surfboard, and not a surf score. Published surfing knee values are not a comparison. A count of matches does not make the proxy promising.
    """
}

nonisolated enum KneeOrdinalCheck {
    static func decodeSheet(_ data: Data) throws -> KneeOrdinalSheet {
        let object = try JSONSerialization.jsonObject(with: data)
        try rejectForbiddenKeys(object)
        let sheet = try JSONDecoder().decode(KneeOrdinalSheet.self, from: data)
        for clip in sheet.clips {
            try validate(clip)
        }
        return sheet
    }

    static func score(clip: KneeOrdinalClip, timeline: PoseTimeline) throws -> KneeOrdinalReport {
        try validate(clip)
        if clip.role == .uncovered {
            return KneeOrdinalReport(
                clipDuration: clip.clipDuration,
                role: .uncovered,
                knee: nil,
                pauses: [],
                comparison: nil,
                statement: KneeOrdinalReport.pictureProxyStatement
            )
        }

        let knee = clip.knee!
        let samples = clip.pauses.map { pause in
            ImagePlaneKnee.sample(knee, at: pause.timestamp, in: timeline)
        }
        let bothCompared = samples.allSatisfy { $0 != nil } && pictures(clip.pauses) == .ordered
        let facts = zip(clip.pauses, samples).map { pause, sample in
            fact(pause, sample: sample, bothCompared: bothCompared, side: knee, timeline: timeline)
        }
        return KneeOrdinalReport(
            clipDuration: clip.clipDuration,
            role: .usable,
            knee: knee,
            pauses: facts,
            comparison: comparison(facts: facts, pauses: clip.pauses, samples: samples, bothCompared: bothCompared),
            statement: KneeOrdinalReport.pictureProxyStatement
        )
    }

    private static func fact(
        _ pause: KneeOrdinalPause,
        sample: ImagePlaneKneeSample?,
        bothCompared: Bool,
        side: ImagePlaneKneeSide,
        timeline: PoseTimeline
    ) -> KneeOrdinalFact {
        guard sample != nil else {
            return KneeOrdinalFact(
                timestamp: pause.timestamp,
                disposition: .uncovered,
                reason: uncoveredReason(side: side, at: pause.timestamp, in: timeline)
            )
        }
        switch pause.picture {
        case .unclear:
            return KneeOrdinalFact(
                timestamp: pause.timestamp,
                disposition: .unassessable,
                reason: pause.imageReason ?? ""
            )
        case .visible:
            return KneeOrdinalFact(
                timestamp: pause.timestamp,
                disposition: .listed,
                reason: "The pause is kept. It is not a bend rank, not compared, and not unassessable."
            )
        case .moreBent, .lessBent:
            if bothCompared {
                return KneeOrdinalFact(
                    timestamp: pause.timestamp,
                    disposition: .compared,
                    reason: "The pause entered the comparison."
                )
            }
            return KneeOrdinalFact(
                timestamp: pause.timestamp,
                disposition: .listed,
                reason: "The other pause blocked the comparison, so this pause is not compared."
            )
        }
    }

    private static func comparison(
        facts: [KneeOrdinalFact],
        pauses: [KneeOrdinalPause],
        samples: [ImagePlaneKneeSample?],
        bothCompared: Bool
    ) -> KneeOrdinalComparison {
        let blocked = facts.contains {
            $0.disposition == .unassessable || $0.disposition == .uncovered || $0.disposition == .listed
        }
        guard bothCompared, !blocked,
              let moreIndex = pauses.firstIndex(where: { $0.picture == .moreBent }),
              let lessIndex = pauses.firstIndex(where: { $0.picture == .lessBent }),
              let more = samples[moreIndex]?.angleDegrees,
              let less = samples[lessIndex]?.angleDegrees
        else { return .notScored }
        return more < less ? .match : .mismatch
    }

    private static func uncoveredReason(
        side: ImagePlaneKneeSide,
        at time: TimeInterval,
        in timeline: PoseTimeline
    ) -> String {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline) else {
            return "No observation contains this timestamp."
        }
        guard let body = observation.body else {
            return "The retained body is missing."
        }
        let hip = body.landmarks.first { $0.joint == side.hip }
        let knee = body.landmarks.first { $0.joint == side.knee }
        let ankle = body.landmarks.first { $0.joint == side.ankle }
        if hip == nil { return "The stored hip is missing." }
        if knee == nil { return "The stored knee is missing." }
        if ankle == nil { return "The stored ankle is missing." }
        if let hip, let knee, hip.x == knee.x, hip.y == knee.y {
            return "Two of the stored points are exactly coincident."
        }
        if let hip, let ankle, hip.x == ankle.x, hip.y == ankle.y {
            return "Two of the stored points are exactly coincident."
        }
        return "A segment has zero length."
    }

    private static func validate(_ clip: KneeOrdinalClip) throws {
        if clip.role == .uncovered {
            if clip.knee != nil { throw KneeOrdinalSheetError.uncoveredClipHasKnee }
            if !clip.pauses.isEmpty { throw KneeOrdinalSheetError.uncoveredClipHasPauses }
            return
        }
        guard clip.knee != nil else { throw KneeOrdinalSheetError.missingKnee }
        guard clip.pauses.count == 2 else { throw KneeOrdinalSheetError.usablePauseCount }
        guard pictures(clip.pauses) != .invalid else { throw KneeOrdinalSheetError.picturePair }
        for pause in clip.pauses {
            let reason = pause.imageReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pause.picture == .unclear {
                if reason.isEmpty { throw KneeOrdinalSheetError.missingImageReason }
            } else if pause.imageReason != nil {
                throw KneeOrdinalSheetError.unexpectedImageReason
            }
        }
    }

    private enum PicturePair {
        case ordered
        case unclear
        case unclearAndVisible
        case invalid
    }

    private static func pictures(_ pauses: [KneeOrdinalPause]) -> PicturePair {
        let set = Set(pauses.map(\.picture))
        if pauses.count == 2, set == [.moreBent, .lessBent] { return .ordered }
        if pauses.count == 2, set == [.unclear] { return .unclear }
        if pauses.count == 2, set == [.unclear, .visible] { return .unclearAndVisible }
        return .invalid
    }

    private static func rejectForbiddenKeys(_ object: Any) throws {
        if let dictionary = object as? [String: Any] {
            if dictionary.keys.contains("angleDegrees") || dictionary.keys.contains("computedSign") {
                throw KneeOrdinalSheetError.computedAnglePresent
            }
            if dictionary.keys.contains("outcome") {
                throw KneeOrdinalSheetError.scoredOutcomePresent
            }
            if dictionary.keys.contains("expectedSign") {
                throw KneeOrdinalSheetError.expectedSignPresent
            }
            if dictionary.keys.contains("oppositeLean") {
                throw KneeOrdinalSheetError.oppositeLeanPresent
            }
            for value in dictionary.values {
                try rejectForbiddenKeys(value)
            }
        } else if let array = object as? [Any] {
            for value in array {
                try rejectForbiddenKeys(value)
            }
        }
    }
}
