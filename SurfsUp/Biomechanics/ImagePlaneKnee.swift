import Foundation

/// One included-angle reading of a stored knee. Absent means that side has no sample.
///
/// This is a picture proxy. It is not a pose observation and it is not stored on one.
nonisolated struct ImagePlaneKneeSample: Equatable, Sendable {
    var time: TimeInterval
    var side: ImagePlaneKneeSide
    var angleDegrees: Double
}

/// The stored side already named on the retained body.
nonisolated enum ImagePlaneKneeSide: Equatable, Sendable {
    case left
    case right

    var hip: JointName {
        switch self {
        case .left: .leftHip
        case .right: .rightHip
        }
    }

    var knee: JointName {
        switch self {
        case .left: .leftKnee
        case .right: .rightKnee
        }
    }

    var ankle: JointName {
        switch self {
        case .left: .leftAnkle
        case .right: .rightAnkle
        }
    }
}

/// Reads a finished pose timeline and does not modify it.
nonisolated enum ImagePlaneKnee {
    /// Included angle at the stored knee, or no sample for this side.
    ///
    /// Vectors run from the knee to the hip and from the knee to the ankle.
    /// The cosine is their unit-vector dot product clamped to `-1...1`.
    /// `angleDegrees = acos(cosine) * 180 / .pi`. Straight is 180°.
    static func sample(
        _ side: ImagePlaneKneeSide,
        at time: TimeInterval,
        in timeline: PoseTimeline
    ) -> ImagePlaneKneeSample? {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline),
              let body = observation.body,
              let hip = body.landmarks.first(where: { $0.joint == side.hip }),
              let knee = body.landmarks.first(where: { $0.joint == side.knee }),
              let ankle = body.landmarks.first(where: { $0.joint == side.ankle })
        else { return nil }

        if hip.x == knee.x, hip.y == knee.y { return nil }
        if knee.x == ankle.x, knee.y == ankle.y { return nil }
        if hip.x == ankle.x, hip.y == ankle.y { return nil }

        let towardHipX = hip.x - knee.x
        let towardHipY = hip.y - knee.y
        let towardAnkleX = ankle.x - knee.x
        let towardAnkleY = ankle.y - knee.y
        let hipLength = (towardHipX * towardHipX + towardHipY * towardHipY).squareRoot()
        let ankleLength = (towardAnkleX * towardAnkleX + towardAnkleY * towardAnkleY).squareRoot()
        if hipLength == 0 || ankleLength == 0 { return nil }

        let dot = (towardHipX * towardAnkleX + towardHipY * towardAnkleY) / (hipLength * ankleLength)
        let cosine = min(1, max(-1, dot))
        let angleDegrees = acos(cosine) * 180 / .pi
        return ImagePlaneKneeSample(time: time, side: side, angleDegrees: angleDegrees)
    }
}
