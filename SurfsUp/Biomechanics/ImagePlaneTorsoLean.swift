import Foundation

/// One image-plane reading of the segment from `root` to `neck`.
///
/// This is a proxy for torso orientation in the upright picture. It is not a
/// pose observation, not a 3D body angle, and not an angle relative to a surfboard.
nonisolated struct ImagePlaneTorsoSample: Equatable, Sendable {
    var time: TimeInterval
    var angleDegrees: Double
    var ordinarySign: OrdinarySign

    enum OrdinarySign: Equatable, Sendable {
        case left
        case right
        case upright
        case branchCut
    }
}

/// Reads a finished pose timeline and does not modify it.
nonisolated enum ImagePlaneTorsoLean {
    /// Returns no sample when the observation, body, neck, or root is missing,
    /// or when the two stored points are exactly equal.
    static func sample(at time: TimeInterval, in timeline: PoseTimeline) -> ImagePlaneTorsoSample? {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline),
              let body = observation.body,
              let neck = body.landmarks.first(where: { $0.joint == .neck }),
              let root = body.landmarks.first(where: { $0.joint == .root })
        else {
            return nil
        }

        let rightward = neck.x - root.x
        let upward = neck.y - root.y
        guard rightward != 0 || upward != 0 else { return nil }

        let angleDegrees = atan2(rightward, upward) * 180 / .pi
        return ImagePlaneTorsoSample(
            time: time,
            angleDegrees: angleDegrees,
            ordinarySign: ordinarySign(rightward: rightward, upward: upward)
        )
    }

    private static func ordinarySign(rightward: Double, upward: Double) -> ImagePlaneTorsoSample.OrdinarySign {
        if rightward == 0, upward > 0 {
            return .upright
        }
        if rightward == 0, upward < 0 {
            return .branchCut
        }
        if rightward > 0 {
            return .right
        }
        return .left
    }
}
