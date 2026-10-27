import Foundation

/// The review-screen presentation of one frozen image-plane torso sample.
///
/// This is a display mapping only. The angle, the coordinates, and the side
/// classifier come from `ImagePlaneTorsoLean.sample(at:in:)` as it stands.
/// Nothing here reads a landmark, computes an angle, or chooses a side from the number.
nonisolated struct TorsoLeanReadout: Equatable, Sendable {
    /// Digits after the decimal separator in `degreesText`. Display-only rounding.
    static let fractionDigits = 1

    /// The signed sample angle, for example `12.3°`, `-7.0°`, `180.0°`.
    /// Period as the decimal separator and ASCII hyphen-minus, like the playhead label.
    var degreesText: String

    /// Mapped one-to-one from `ImagePlaneTorsoSample.OrdinarySign`.
    var side: Side

    enum Side: Equatable, Sendable {
        case left
        case right
        case upright
        case straightDown
    }

    /// Returns `nil` when the frozen sample is `nil`. No stand-in value is produced.
    static func make(at playhead: TimeInterval, in timeline: PoseTimeline) -> TorsoLeanReadout? {
        guard let sample = ImagePlaneTorsoLean.sample(at: playhead, in: timeline) else { return nil }
        return TorsoLeanReadout(
            degreesText: degreesText(for: sample.angleDegrees),
            side: side(for: sample.ordinarySign)
        )
    }

    private static let negativeZeroText = String(format: "%.\(fractionDigits)f°", -0.0)
    private static let zeroText = String(format: "%.\(fractionDigits)f°", 0.0)

    private static func degreesText(for angleDegrees: Double) -> String {
        let text = String(format: "%.\(fractionDigits)f°", angleDegrees)
        return text == negativeZeroText ? zeroText : text
    }

    private static func side(for sign: ImagePlaneTorsoSample.OrdinarySign) -> Side {
        switch sign {
        case .left: .left
        case .right: .right
        case .upright: .upright
        case .branchCut: .straightDown
        }
    }
}
