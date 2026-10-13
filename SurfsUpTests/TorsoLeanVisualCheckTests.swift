import Foundation
import Testing
@testable import SurfsUp

struct TorsoLeanVisualCheckTests {
    @Test func fourMatchesOutOfFivePassAndTheFifthStays() throws {
        let timeline = uniformTimeline(lean: .right, duration: 5)
        let pauses = [
            pause(0.2, .right),
            pause(1.2, .right),
            pause(2.2, .right),
            pause(3.2, .right),
            pause(4.2, .none, imageReason: "foreshortened")
        ]
        let clip = usableClip(duration: 5, pauses: pauses)
        let beforeSheet = clip
        let beforeTimeline = timeline

        let report = try TorsoLeanVisualCheck.score(clip: clip, timeline: timeline)

        #expect(report.pauseResults.count == 5)
        #expect(report.pauseResults.map(\.timestamp) == pauses.map(\.timestamp))
        #expect(report.matchCount == 4)
        #expect(report.signCheck == .passed)
        #expect(report.pauseResults[4].outcome == .unassessable)
        #expect(report.pauseResults[4].reason == "foreshortened")
        #expect(clip == beforeSheet)
        #expect(timeline == beforeTimeline)
        #expect(report.pauseResults.allSatisfy { !$0.reason.isEmpty })
    }

    @Test func threeMatchesFailWhileUncoveredRemainsInTheFive() throws {
        let timeline = timelineWithGap()
        let pauses = [
            pause(0.5, .right),
            pause(1.5, .right),
            pause(2.5, .right),
            pause(3.5, .left),
            pause(4.5, .right)
        ]
        let report = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 5, pauses: pauses),
            timeline: timeline
        )

        #expect(report.pauseResults.count == 5)
        #expect(report.matchCount == 3)
        #expect(report.signCheck == .failed)
        #expect(report.pauseResults[3].outcome == .mismatch)
        #expect(report.pauseResults[4].outcome == .uncovered)
        #expect(report.pauseResults[4].timestamp == 4.5)
        #expect(report.pauseResults[4].reason.contains("no body"))
    }

    @Test func disagreementIncludesUprightAndTheBranchCut() throws {
        let upright = try scoreOne(lean: .upright, expected: .left)
        let branchCut = try scoreOne(lean: .branchCut, expected: .right)

        #expect(upright.outcome == .mismatch)
        #expect(branchCut.outcome == .mismatch)
        #expect(branchCut.outcome != .uncovered)
    }

    @Test func missingSampleOnAnUnjudgeablePauseIsUncovered() throws {
        let timeline = timelineWithGap()
        let pauses = [
            pause(0.5, .right),
            pause(1.5, .right),
            pause(2.5, .right),
            pause(3.5, .right),
            pause(4.5, .none, imageReason: "cannot see the torso")
        ]
        let report = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 5, pauses: pauses),
            timeline: timeline
        )

        #expect(report.pauseResults[4].outcome == .uncovered)
        #expect(report.pauseResults[4].reason.contains("no body"))
        #expect(report.pauseResults[4].reason != "cannot see the torso")
        #expect(report.matchCount == 4)
        #expect(report.signCheck == .passed)
    }

    @Test func declaredOppositePairPassesOnlyWhenBothExpectationsMatch() throws {
        let timeline = leftAndRightTimeline()
        let passing = [
            pause(0.5, .right, opposite: true),
            pause(1.5, .left, opposite: true),
            pause(0.6, .right),
            pause(0.7, .right),
            pause(0.8, .right)
        ]
        let passed = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 2, pauses: passing),
            timeline: timeline
        )
        #expect(passed.oppositeLeanCheck == .passed)

        let sameSide = [
            pause(0.5, .right, opposite: true),
            pause(0.6, .right, opposite: true),
            pause(0.7, .right),
            pause(0.8, .right),
            pause(1.5, .left)
        ]
        let notOpposite = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 2, pauses: sameSide),
            timeline: timeline
        )
        #expect(notOpposite.oppositeLeanCheck == .failed)
    }

    @Test func oppositeCheckUsesTheDeclaredPairRatherThanComputedSigns() throws {
        let timeline = leftAndRightTimeline()
        let pauses = [
            pause(0.5, .right),
            pause(1.5, .left),
            pause(0.6, .right, opposite: true),
            pause(1.6, .right, opposite: true),
            pause(0.7, .right)
        ]
        let report = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 2, pauses: pauses),
            timeline: timeline
        )

        #expect(report.oppositeLeanCheck == .failed)
        #expect(report.oppositeLeanCheck != .notExercised)
        #expect(report.pauseResults[3].outcome == .mismatch)
    }

    @Test func unmarkedSheetIsNotExercisedEvenWhenComputedSignsAreOpposite() throws {
        let timeline = leftAndRightTimeline()
        let pauses = [
            pause(0.5, .right),
            pause(1.5, .left),
            pause(0.6, .right),
            pause(0.7, .right),
            pause(0.8, .right)
        ]
        let report = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 2, pauses: pauses),
            timeline: timeline
        )

        #expect(report.oppositeLeanCheck == .notExercised)
        #expect(report.oppositeLeanCheck != .passed)
    }

    @Test func oppositePairFailsWhenOnePauseIsUnassessableOrUncovered() throws {
        let unassessable = [
            pause(0.2, .right, opposite: true),
            pause(0.4, .none, imageReason: "edge-on", opposite: true),
            pause(0.5, .right),
            pause(0.6, .right),
            pause(0.7, .right)
        ]
        let unclear = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 1, pauses: unassessable),
            timeline: uniformTimeline(lean: .right, duration: 1)
        )
        #expect(unclear.oppositeLeanCheck == .failed)
        #expect(unclear.pauseResults[1].outcome == .unassessable)

        let uncovered = [
            pause(0.5, .right, opposite: true),
            pause(4.5, .left, opposite: true),
            pause(1.5, .right),
            pause(2.5, .right),
            pause(3.5, .right)
        ]
        let gap = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 5, pauses: uncovered),
            timeline: timelineWithGap()
        )
        #expect(gap.oppositeLeanCheck == .failed)
        #expect(gap.pauseResults[1].outcome == .uncovered)
    }

    @Test func sheetsWithAnAngleOrAnOutcomeAreRejected() throws {
        let angle = """
        {"clips":[{"clipDuration":1,"role":"usable","pauses":[
        {"timestamp":0.1,"expectedSign":"right","oppositeLean":false,"angleDegrees":12},
        {"timestamp":0.2,"expectedSign":"right","oppositeLean":false},
        {"timestamp":0.3,"expectedSign":"right","oppositeLean":false},
        {"timestamp":0.4,"expectedSign":"right","oppositeLean":false},
        {"timestamp":0.5,"expectedSign":"right","oppositeLean":false}
        ]}]}
        """
        let outcome = """
        {"clips":[{"clipDuration":1,"role":"usable","pauses":[
        {"timestamp":0.1,"expectedSign":"right","oppositeLean":false,"outcome":"match"},
        {"timestamp":0.2,"expectedSign":"right","oppositeLean":false},
        {"timestamp":0.3,"expectedSign":"right","oppositeLean":false},
        {"timestamp":0.4,"expectedSign":"right","oppositeLean":false},
        {"timestamp":0.5,"expectedSign":"right","oppositeLean":false}
        ]}]}
        """

        #expect(throws: TorsoLeanSheetError.computedAnglePresent) {
            try TorsoLeanVisualCheck.decodeSheet(Data(angle.utf8))
        }
        #expect(throws: TorsoLeanSheetError.scoredOutcomePresent) {
            try TorsoLeanVisualCheck.decodeSheet(Data(outcome.utf8))
        }
    }

    @Test func invalidPauseCountsAndImageReasonsAreRejected() {
        #expect(throws: TorsoLeanSheetError.usablePauseCount) {
            try TorsoLeanVisualCheck.score(
                clip: usableClip(duration: 1, pauses: [pause(0.2, .right), pause(0.4, .right)]),
                timeline: uniformTimeline(lean: .right, duration: 1)
            )
        }
        #expect(throws: TorsoLeanSheetError.oppositeLeanCount) {
            try TorsoLeanVisualCheck.score(
                clip: usableClip(duration: 1, pauses: [
                    pause(0.1, .right, opposite: true),
                    pause(0.2, .right),
                    pause(0.3, .right),
                    pause(0.4, .right),
                    pause(0.5, .right)
                ]),
                timeline: uniformTimeline(lean: .right, duration: 1)
            )
        }
        #expect(throws: TorsoLeanSheetError.missingImageReason) {
            try TorsoLeanVisualCheck.score(
                clip: usableClip(duration: 1, pauses: five(pause(0.2, .none))),
                timeline: uniformTimeline(lean: .right, duration: 1)
            )
        }
        #expect(throws: TorsoLeanSheetError.unexpectedImageReason) {
            try TorsoLeanVisualCheck.score(
                clip: usableClip(duration: 1, pauses: five(pause(0.2, .right, imageReason: "not allowed"))),
                timeline: uniformTimeline(lean: .right, duration: 1)
            )
        }
    }

    @Test func uncoveredClipHasNoSignCheckAndListsTimeWithoutABody() throws {
        let duration = 4.517
        let frame = FrameObservation(start: 0, end: duration, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!
        let clip = PauseClip(clipDuration: duration, role: .uncovered, pauses: [])

        let report = try TorsoLeanVisualCheck.score(clip: clip, timeline: timeline)

        #expect(report.signCheck == nil)
        #expect(report.oppositeLeanCheck == nil)
        #expect(report.pauseResults.isEmpty)
        #expect(report.uncoveredFraction == 1)
        #expect(report.uncoveredRanges == [UncoveredRange(start: 0, end: duration)])
        #expect(report.statement.contains("proxy"))
        #expect(report.statement.contains("not a 3D body angle"))
        #expect(report.statement.contains("not an angle relative to the surfboard"))
    }

    private enum Lean {
        case right, left, upright, branchCut
    }

    private func scoreOne(lean: Lean, expected: PauseEntry.ExpectedSign) throws -> PauseResult {
        let pauses = [
            pause(0.2, expected),
            pause(0.3, .right),
            pause(0.4, .right),
            pause(0.5, .right),
            pause(0.6, .right)
        ]
        let report = try TorsoLeanVisualCheck.score(
            clip: usableClip(duration: 1, pauses: pauses),
            timeline: uniformTimeline(lean: lean, duration: 1)
        )
        return report.pauseResults[0]
    }

    private func five(_ entry: PauseEntry) -> [PauseEntry] {
        (0..<5).map { index in
            PauseEntry(
                timestamp: 0.1 + Double(index) * 0.1,
                expectedSign: entry.expectedSign,
                imageReason: entry.imageReason,
                oppositeLean: false
            )
        }
    }

    private func pause(
        _ timestamp: TimeInterval,
        _ expected: PauseEntry.ExpectedSign,
        imageReason: String? = nil,
        opposite: Bool = false
    ) -> PauseEntry {
        PauseEntry(
            timestamp: timestamp,
            expectedSign: expected,
            imageReason: imageReason,
            oppositeLean: opposite
        )
    }

    private func usableClip(duration: TimeInterval, pauses: [PauseEntry]) -> PauseClip {
        PauseClip(clipDuration: duration, role: .usable, pauses: pauses)
    }

    private func uniformTimeline(lean: Lean, duration: TimeInterval) -> PoseTimeline {
        let frame = FrameObservation(
            start: 0,
            end: duration,
            clipDuration: duration,
            body: body(lean)
        )!
        return PoseTimeline(clipDuration: duration, observations: [frame])!
    }

    private func timelineWithGap() -> PoseTimeline {
        let duration = 5.0
        let bodyFrame = FrameObservation(start: 0, end: 4, clipDuration: duration, body: body(.right))!
        let gap = FrameObservation(start: 4, end: 5, clipDuration: duration, body: nil)!
        return PoseTimeline(clipDuration: duration, observations: [bodyFrame, gap])!
    }

    private func leftAndRightTimeline() -> PoseTimeline {
        let duration = 2.0
        let right = FrameObservation(start: 0, end: 1, clipDuration: duration, body: body(.right))!
        let left = FrameObservation(start: 1, end: 2, clipDuration: duration, body: body(.left))!
        return PoseTimeline(clipDuration: duration, observations: [right, left])!
    }

    private func body(_ lean: Lean) -> BodyObservation? {
        let neck: (Double, Double)
        let root = (0.5, 0.5)
        switch lean {
        case .right:
            neck = (0.8, 0.5)
        case .left:
            neck = (0.2, 0.5)
        case .upright:
            neck = (0.5, 0.8)
        case .branchCut:
            neck = (0.5, 0.2)
        }
        return BodyObservation(
            landmarks: [
                Landmark(joint: .neck, x: neck.0, y: neck.1, confidence: 1)!,
                Landmark(joint: .root, x: root.0, y: root.1, confidence: 1)!
            ],
            selectionArea: 0.1
        )
    }
}
