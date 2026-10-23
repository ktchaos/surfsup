import Foundation

/// A coarse picture state for one moment. Absent means no state, which is not `neither`.
///
/// This is a picture hypothesis. It is not a pose observation and it is not stored on one.
nonisolated enum PictureActivityState: Equatable, Sendable {
    case paddling
    case standing
    case neither
}

/// Reads a finished pose timeline and does not modify it.
nonisolated enum PictureActivity {
    /// Paddling, standing, or neither. `nil` is no state.
    ///
    /// The rule is frozen. No observation, a missing neck or root, a missing
    /// ankle on the vertical path, or a missing wrist on the horizontal path
    /// is no state. A missing retained body is `neither`.
    static func state(
        at time: TimeInterval,
        in timeline: PoseTimeline
    ) -> PictureActivityState? {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline) else {
            return nil
        }
        guard let body = observation.body else {
            return .neither
        }
        guard let neck = landmark(.neck, in: body),
              let root = landmark(.root, in: body)
        else { return nil }

        let dx = neck.x - root.x
        let dy = neck.y - root.y
        if abs(dy) > abs(dx) {
            guard let leftAnkle = landmark(.leftAnkle, in: body),
                  let rightAnkle = landmark(.rightAnkle, in: body)
            else { return nil }
            if leftAnkle.y < root.y, rightAnkle.y < root.y {
                return .standing
            }
            return .neither
        }

        guard landmark(.leftWrist, in: body) != nil,
              landmark(.rightWrist, in: body) != nil
        else { return nil }
        return .paddling
    }

    private static func landmark(_ joint: JointName, in body: BodyObservation) -> Landmark? {
        body.landmarks.first { $0.joint == joint }
    }
}
