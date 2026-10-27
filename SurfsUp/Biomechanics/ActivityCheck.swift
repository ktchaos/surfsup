import Foundation

nonisolated enum ActivitySheetError: Error, Equatable, Sendable {
    case computedStatePresent
    case scoredOutcomePresent
    case expectedSignPresent
    case oppositeLeanPresent
    case usablePauseCount
    case kneePicture
    case missingImageReason
    case unexpectedImageReason
    case uncoveredClipHasPauses
}

nonisolated struct ActivityPauseSheet: Equatable, Sendable, Decodable {
    var clips: [ActivityClip]
}

nonisolated struct ActivityClip: Equatable, Sendable, Decodable {
    var clipDuration: TimeInterval
    var role: Role
    var pauses: [ActivityPause]

    enum Role: String, Equatable, Sendable, Codable {
        case usable
        case uncovered
    }

    init(clipDuration: TimeInterval, role: Role, pauses: [ActivityPause]) {
        self.clipDuration = clipDuration
        self.role = role
        self.pauses = pauses
    }
}

nonisolated struct ActivityPause: Equatable, Sendable, Decodable {
    var timestamp: TimeInterval
    var picture: Picture
    var imageReason: String?

    enum Picture: String, Equatable, Sendable {
        case paddling
        case standing
        case unclear
    }

    init(timestamp: TimeInterval, picture: Picture, imageReason: String?) {
        self.timestamp = timestamp
        self.picture = picture
        self.imageReason = imageReason
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case picture
        case imageReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        let name = try container.decode(String.self, forKey: .picture)
        switch name {
        case "paddling": picture = .paddling
        case "standing": picture = .standing
        case "unclear": picture = .unclear
        case "moreBent", "lessBent": throw ActivitySheetError.kneePicture
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .picture,
                in: container,
                debugDescription: "The picture label must be paddling, standing, or unclear."
            )
        }
        imageReason = try container.decodeIfPresent(String.self, forKey: .imageReason)
    }
}

nonisolated struct ActivityFact: Equatable, Sendable {
    var timestamp: TimeInterval
    var disposition: Disposition
    var state: PictureActivityState?
    var reason: String

    enum Disposition: String, Equatable, Sendable {
        case match
        case mismatch
        case unassessable
        case uncovered
    }
}

nonisolated struct ActivityReport: Equatable, Sendable {
    var clipDuration: TimeInterval
    var role: ActivityClip.Role
    var pauses: [ActivityFact]
    var statement: String

    static let pictureHypothesisStatement = """
    This is a pose-only picture hypothesis for whether the surfer appears to be paddling, standing, or neither, in the same class as the image-plane torso lean and the image-plane knee. It is not a published surf-event detector, not riding performance, and not an event relative to the surfboard. Smartphone sit, paddle, and ride results that use body-worn motion sensors and satellite location are not a comparison. A count of matches does not make the proxy promising. The reading does not say that the app detected a surf maneuver or a ride.
    """
}

nonisolated enum ActivityCheck {
    static func decodeSheet(_ data: Data) throws -> ActivityPauseSheet {
        let object = try JSONSerialization.jsonObject(with: data)
        try rejectForbiddenKeys(object)
        let sheet = try JSONDecoder().decode(ActivityPauseSheet.self, from: data)
        for clip in sheet.clips {
            try validate(clip)
        }
        return sheet
    }

    static func score(clip: ActivityClip, timeline: PoseTimeline) throws -> ActivityReport {
        try validate(clip)
        if clip.role == .uncovered {
            return ActivityReport(
                clipDuration: clip.clipDuration,
                role: .uncovered,
                pauses: [],
                statement: ActivityReport.pictureHypothesisStatement
            )
        }

        let facts = clip.pauses.map { pause in
            fact(pause, in: timeline)
        }
        return ActivityReport(
            clipDuration: clip.clipDuration,
            role: .usable,
            pauses: facts,
            statement: ActivityReport.pictureHypothesisStatement
        )
    }

    private static func fact(_ pause: ActivityPause, in timeline: PoseTimeline) -> ActivityFact {
        let state = PictureActivity.state(at: pause.timestamp, in: timeline)
        guard let state else {
            return ActivityFact(
                timestamp: pause.timestamp,
                disposition: .uncovered,
                state: nil,
                reason: uncoveredReason(at: pause.timestamp, in: timeline)
            )
        }
        switch pause.picture {
        case .unclear:
            return ActivityFact(
                timestamp: pause.timestamp,
                disposition: .unassessable,
                state: state,
                reason: pause.imageReason ?? ""
            )
        case .paddling where state == .paddling, .standing where state == .standing:
            return ActivityFact(
                timestamp: pause.timestamp,
                disposition: .match,
                state: state,
                reason: "The computed state agrees with the picture label."
            )
        case .paddling, .standing:
            return ActivityFact(
                timestamp: pause.timestamp,
                disposition: .mismatch,
                state: state,
                reason: "The computed state is \(stateWord(state))."
            )
        }
    }

    private static func stateWord(_ state: PictureActivityState) -> String {
        switch state {
        case .paddling: "paddling"
        case .standing: "standing"
        case .neither: "neither"
        }
    }

    private static func uncoveredReason(at time: TimeInterval, in timeline: PoseTimeline) -> String {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline) else {
            return "No observation contains this timestamp."
        }
        guard let body = observation.body else {
            return "The retained body is missing."
        }
        guard let neck = body.landmarks.first(where: { $0.joint == .neck }) else {
            return "The stored neck is missing."
        }
        guard let root = body.landmarks.first(where: { $0.joint == .root }) else {
            return "The stored root is missing."
        }
        let dx = neck.x - root.x
        let dy = neck.y - root.y
        if abs(dy) > abs(dx) {
            if body.landmarks.contains(where: { $0.joint == .leftAnkle }) == false {
                return "The stored left ankle is missing."
            }
            return "The stored right ankle is missing."
        }
        if body.landmarks.contains(where: { $0.joint == .leftWrist }) == false {
            return "The stored left wrist is missing."
        }
        return "The stored right wrist is missing."
    }

    private static func validate(_ clip: ActivityClip) throws {
        if clip.role == .uncovered {
            if !clip.pauses.isEmpty { throw ActivitySheetError.uncoveredClipHasPauses }
            return
        }
        guard clip.pauses.count == 2 else { throw ActivitySheetError.usablePauseCount }
        for pause in clip.pauses {
            let reason = pause.imageReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pause.picture == .unclear {
                if reason.isEmpty { throw ActivitySheetError.missingImageReason }
            } else if pause.imageReason != nil {
                throw ActivitySheetError.unexpectedImageReason
            }
        }
    }

    private static func rejectForbiddenKeys(_ object: Any) throws {
        if let dictionary = object as? [String: Any] {
            if dictionary.keys.contains("state") || dictionary.keys.contains("computedState") {
                throw ActivitySheetError.computedStatePresent
            }
            if dictionary.keys.contains("outcome") || dictionary.keys.contains("passed") || dictionary.keys.contains("comparison") {
                throw ActivitySheetError.scoredOutcomePresent
            }
            if dictionary.keys.contains("expectedSign") {
                throw ActivitySheetError.expectedSignPresent
            }
            if dictionary.keys.contains("oppositeLean") {
                throw ActivitySheetError.oppositeLeanPresent
            }
            for value in dictionary.values {
                try rejectForbiddenKeys(value)
            }
        } else if let array = object as? [Any] {
            for value in array {
                try rejectForbiddenKeys(value)
            }
        } else if let string = object as? String, string == "moreBent" || string == "lessBent" {
            throw ActivitySheetError.kneePicture
        }
    }
}
