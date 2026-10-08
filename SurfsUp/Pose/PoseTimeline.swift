import CoreGraphics
import Foundation

nonisolated enum PoseModelError: Error, Equatable {
    case invalidClip
    case invalidTimeline
}

/// The video chosen for the current session. The URL is a local file, not a remote address.
nonisolated struct SelectedClip: Equatable, Identifiable, Sendable {
    var id: UUID
    var url: URL
    var duration: TimeInterval
    var nominalFrameRate: Float
    var displaySize: CGSize
    var displayTransform: CGAffineTransform

    init?(
        id: UUID,
        url: URL,
        duration: TimeInterval,
        nominalFrameRate: Float,
        displaySize: CGSize,
        displayTransform: CGAffineTransform
    ) {
        guard duration > 0, duration.isFinite else { return nil }
        self.id = id
        self.url = url
        self.duration = duration
        self.nominalFrameRate = nominalFrameRate
        self.displaySize = displaySize
        self.displayTransform = displayTransform
    }
}

/// A detected joint. Confidence 0 is not a landmark. Confidence is stored and never displayed.
nonisolated struct Landmark: Equatable, Sendable, Codable {
    var joint: JointName
    var x: Double
    var y: Double
    var confidence: Double

    init?(joint: JointName, x: Double, y: Double, confidence: Double) {
        guard (0...1).contains(x), (0...1).contains(y), confidence > 0 else { return nil }
        self.joint = joint
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case joint
        case x
        case y
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let joint = try container.decode(JointName.self, forKey: .joint)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let confidence = try container.decode(Double.self, forKey: .confidence)
        guard let landmark = Landmark(joint: joint, x: x, y: y, confidence: confidence) else {
            throw DecodingError.dataCorruptedError(
                forKey: .confidence,
                in: container,
                debugDescription: "Landmark is outside the image or has no confidence."
            )
        }
        self = landmark
    }
}

/// The one body kept for a frame. Not a surfer, a stance, or an event.
nonisolated struct BodyObservation: Equatable, Sendable {
    var landmarks: [Landmark]
    /// Area of the axis-aligned box, in normalized image space. Not displayed.
    var selectionArea: Double

    init?(landmarks: [Landmark], selectionArea: Double) {
        guard !landmarks.isEmpty else { return nil }
        let names = landmarks.map(\.joint)
        guard Set(names).count == names.count else { return nil }
        self.landmarks = landmarks
        self.selectionArea = selectionArea
    }
}

/// One detection attempt. The range is half-open: `start <= t < end`.
nonisolated struct FrameObservation: Equatable, Sendable, Codable {
    var start: TimeInterval
    var end: TimeInterval
    var body: BodyObservation?

    init?(start: TimeInterval, end: TimeInterval, clipDuration: TimeInterval, body: BodyObservation?) {
        guard start >= 0, start < clipDuration, end > start, end <= clipDuration else { return nil }
        self.start = start
        self.end = end
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case landmarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(TimeInterval.self, forKey: .start)
        let end = try container.decode(TimeInterval.self, forKey: .end)
        let landmarks = try container.decode([Landmark].self, forKey: .landmarks)
        guard end > start else {
            throw DecodingError.dataCorruptedError(forKey: .end, in: container, debugDescription: "Frame range is empty.")
        }
        self.start = start
        self.end = end
        if landmarks.isEmpty {
            self.body = nil
        } else {
            self.body = BodyObservation(landmarks: landmarks, selectionArea: ProminentBody.area(of: landmarks))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(body?.landmarks ?? [], forKey: .landmarks)
    }
}

/// Raw pose observations for a finished run. One entry per frame the schedule visited.
nonisolated struct PoseTimeline: Equatable, Sendable, Codable {
    var clipDuration: TimeInterval
    var observations: [FrameObservation]

    init?(clipDuration: TimeInterval, observations: [FrameObservation]) {
        guard clipDuration > 0, !observations.isEmpty else { return nil }
        var previousStart = -TimeInterval.greatestFiniteMagnitude
        var previousEnd: TimeInterval?
        for observation in observations {
            guard observation.start >= 0, observation.start < clipDuration else { return nil }
            guard observation.end > observation.start, observation.end <= clipDuration else { return nil }
            guard observation.start > previousStart else { return nil }
            if let previousEnd, observation.start != previousEnd { return nil }
            previousStart = observation.start
            previousEnd = observation.end
        }
        self.clipDuration = clipDuration
        self.observations = observations
    }
}
