import Foundation

/// Which decoded frames a run attempts.
///
/// `everyFrame` is the baseline experiment, not the final performance strategy.
/// The first study analyzes every decoded frame so pose quality and temporal
/// consistency can be judged. Stride and adaptive skipping are a later experiment.
/// Detection and overlay consume this value and do not hard-code a skip.
nonisolated enum FrameSchedule: Equatable, Sendable {
    case everyFrame

    func includes(frameIndex: Int) -> Bool {
        switch self {
        case .everyFrame:
            return frameIndex >= 0
        }
    }
}
