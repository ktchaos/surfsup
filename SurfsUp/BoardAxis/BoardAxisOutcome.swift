import Foundation

/// Reviewer judgment of whether the stored quadrilateral lies along the surfboard.
///
/// This is not inferred from the human nose and tail, and it is not inferred from
/// the angle delta. `notReviewed` cannot produce `match` or `mismatch`.
nonisolated enum BoardAxisBoardIdentity: Equatable, Sendable {
    case notReviewed
    case liesAlongBoard
    case doesNotLieAlongBoard
}

/// Reviewer comparison of the two directed arrows.
///
/// Consulted only after the quadrilateral has been judged to lie along the board.
nonisolated enum BoardAxisDirectionAgreement: Equatable, Sendable {
    case notReviewed
    case agrees
    case disagrees
}

nonisolated struct BoardAxisOutcomeRow: Equatable, Sendable {
    var frameId: String
    var label: BoardAxisLabel
    var candidate: BoardAxisCandidate
    var identity: BoardAxisBoardIdentity
    var directionAgreement: BoardAxisDirectionAgreement
}

nonisolated struct BoardAxisFrameOutcome: Equatable, Sendable {
    enum Outcome: String, Equatable, Sendable {
        case match
        case mismatch
        case unassessable
        case noCandidate
    }

    var frameId: String
    var outcome: Outcome
    var reason: String
    var angleDeltaDegrees: Double?
}

nonisolated enum BoardAxisOutcomeError: Error, Equatable, Sendable {
    case identityNotReviewed
    case directionNotReviewed
    case frameMismatch
    case droppedFrame
    case missingDirection
}

/// Outcome precedence for one scheduled frame.
///
/// The angle delta is stored only for `match` and `mismatch`. It does not choose the outcome.
nonisolated enum BoardAxisOutcome {
    static let unassessableReason = "The human label is unassessable."
    static let offBoardReason = "The stored quadrilateral does not lie along the surfboard."
    static let matchReason = "The quadrilateral lies along the surfboard and the tail-to-nose directions agree."
    static let mismatchReason = "The quadrilateral lies along the surfboard and the tail-to-nose directions disagree."

    static func assign(_ row: BoardAxisOutcomeRow) throws -> BoardAxisFrameOutcome {
        guard row.label.frameId == row.frameId, row.candidate.frameId == row.frameId else {
            throw BoardAxisOutcomeError.frameMismatch
        }

        if row.label.judgment == .unassessable {
            return BoardAxisFrameOutcome(
                frameId: row.frameId,
                outcome: .unassessable,
                reason: unassessableReason,
                angleDeltaDegrees: nil
            )
        }

        if case .noCandidate(let reason) = row.candidate.status {
            guard !reason.isEmpty else { throw BoardAxisOutcomeError.missingDirection }
            return BoardAxisFrameOutcome(
                frameId: row.frameId,
                outcome: .noCandidate,
                reason: reason,
                angleDeltaDegrees: nil
            )
        }

        switch row.identity {
        case .notReviewed:
            throw BoardAxisOutcomeError.identityNotReviewed
        case .doesNotLieAlongBoard:
            return BoardAxisFrameOutcome(
                frameId: row.frameId,
                outcome: .noCandidate,
                reason: offBoardReason,
                angleDeltaDegrees: nil
            )
        case .liesAlongBoard:
            break
        }

        let outcome: BoardAxisFrameOutcome.Outcome
        let reason: String
        switch row.directionAgreement {
        case .notReviewed:
            throw BoardAxisOutcomeError.directionNotReviewed
        case .agrees:
            outcome = .match
            reason = matchReason
        case .disagrees:
            outcome = .mismatch
            reason = mismatchReason
        }

        return BoardAxisFrameOutcome(
            frameId: row.frameId,
            outcome: outcome,
            reason: reason,
            angleDeltaDegrees: try angleDelta(label: row.label, candidate: row.candidate)
        )
    }

    static func assignAll(_ rows: [BoardAxisOutcomeRow]) throws -> [BoardAxisFrameOutcome] {
        let outcomes = try rows.map(assign)
        guard outcomes.count == rows.count, zip(outcomes, rows).allSatisfy({ $0.frameId == $1.frameId }) else {
            throw BoardAxisOutcomeError.droppedFrame
        }
        return outcomes
    }

    /// Signed difference folded into (-180, 180]. `-180` folds to `180`.
    static func foldedSignedDelta(_ delta: Double) -> Double {
        let remainder = delta.truncatingRemainder(dividingBy: 360)
        if remainder <= -180 {
            return remainder + 360
        }
        if remainder > 180 {
            return remainder - 360
        }
        return remainder
    }

    private static func angleDelta(label: BoardAxisLabel, candidate: BoardAxisCandidate) throws -> Double {
        guard let tailX = label.tailX,
              let tailY = label.tailY,
              let noseX = label.noseX,
              let noseY = label.noseY,
              let human = BoardAxisDirection.make(tailX: tailX, tailY: tailY, noseX: noseX, noseY: noseY),
              case .directed(let tail, let nose, _) = candidate.status,
              let detected = BoardAxisDirection.make(tailX: tail.x, tailY: tail.y, noseX: nose.x, noseY: nose.y)
        else {
            throw BoardAxisOutcomeError.missingDirection
        }
        return foldedSignedDelta(detected.angleDegrees - human.angleDegrees)
    }
}
