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

    @Test func recordedVideo1PauseSheetIsAccepted() throws {
        let sheet = try TorsoLeanVisualCheck.decodeSheet(Data(video1PauseSheet.utf8))
        let clip = try #require(sheet.clips.first)

        #expect(sheet.clips.count == 1)
        #expect(clip.clipDuration == 5.832)
        #expect(clip.role == .usable)
        #expect(clip.pauses.map(\.timestamp) == [0.381, 1.4, 2.3, 3.067, 5.267])
        #expect(clip.pauses.map(\.expectedSign) == [.right, .right, .left, .left, .right])
        #expect(clip.pauses.map(\.oppositeLean) == [false, true, false, true, false])
        #expect(clip.pauses.allSatisfy { $0.imageReason == nil })
    }

    @Test func recordedVideo2PauseSheetIsAccepted() throws {
        let sheet = try TorsoLeanVisualCheck.decodeSheet(Data(recordedPauseSheet.utf8))
        let video1 = try #require(sheet.clips.first)
        let video2 = try #require(sheet.clips.dropFirst().first)

        #expect(sheet.clips.count == 5)
        #expect(video1.clipDuration == 5.832)
        #expect(video1.role == .usable)
        #expect(video1.pauses.map(\.timestamp) == [0.381, 1.4, 2.3, 3.067, 5.267])
        #expect(video1.pauses.map(\.expectedSign) == [.right, .right, .left, .left, .right])
        #expect(video1.pauses.map(\.oppositeLean) == [false, true, false, true, false])
        #expect(video1.pauses.allSatisfy { $0.imageReason == nil })

        #expect(video2.clipDuration == 9.878)
        #expect(video2.role == .usable)
        #expect(video2.pauses.map(\.timestamp) == [3.267, 4.334, 6.139, 6.4, 9])
        #expect(video2.pauses.map(\.expectedSign) == [.right, .right, .left, .left, .right])
        #expect(video2.pauses.allSatisfy { $0.oppositeLean == false })
        #expect(video2.pauses.allSatisfy { $0.imageReason == nil })
    }

    @Test func recordedVideo3AndVideo5PauseSheetIsAccepted() throws {
        let sheet = try TorsoLeanVisualCheck.decodeSheet(Data(recordedPauseSheet.utf8))
        let video3 = try #require(sheet.clips.first { $0.clipDuration == 13.734 })
        let video5 = try #require(sheet.clips.first { $0.clipDuration == 37.289 })

        #expect(video3.clipDuration == 13.734)
        #expect(video3.role == .usable)
        #expect(video3.pauses.map(\.timestamp) == [5.767, 6.107, 9.054, 9.189, 10.383])
        #expect(video3.pauses.map(\.expectedSign) == [.right, .right, .none, .left, .left])
        #expect(video3.pauses.allSatisfy { $0.oppositeLean == false })
        #expect(video3.pauses[2].imageReason?.isEmpty == false)
        #expect(video3.pauses.enumerated().allSatisfy { index, pause in
            index == 2 ? pause.imageReason != nil : pause.imageReason == nil
        })

        #expect(video5.clipDuration == 37.289)
        #expect(video5.role == .usable)
        #expect(video5.pauses.map(\.timestamp) == [2.072, 11.594, 13.316, 16.341, 21.386])
        #expect(video5.pauses.map(\.expectedSign) == [.left, .right, .right, .left, .left])
        #expect(video5.pauses.allSatisfy { $0.oppositeLean == false })
        #expect(video5.pauses.allSatisfy { $0.imageReason == nil })
    }

    @Test func recordedUncoveredVideo4PauseSheetIsAccepted() throws {
        let sheet = try TorsoLeanVisualCheck.decodeSheet(Data(recordedPauseSheet.utf8))
        let video4 = try #require(sheet.clips.first { $0.clipDuration == 4.517 })

        #expect(video4.role == .uncovered)
        #expect(video4.pauses.isEmpty)
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

    private let recordedPauseSheet = """
    {
      "clips": [
        {
          "clipDuration": 5.832,
          "role": "usable",
          "pauses": [
            {"timestamp": 0.381, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 1.400, "expectedSign": "right", "oppositeLean": true},
            {"timestamp": 2.300, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 3.067, "expectedSign": "left", "oppositeLean": true},
            {"timestamp": 5.267, "expectedSign": "right", "oppositeLean": false}
          ]
        },
        {
          "clipDuration": 9.878,
          "role": "usable",
          "pauses": [
            {"timestamp": 3.267, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 4.334, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 6.139, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 6.400, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 9.000, "expectedSign": "right", "oppositeLean": false}
          ]
        },
        {
          "clipDuration": 13.734,
          "role": "usable",
          "pauses": [
            {"timestamp": 5.767, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 6.107, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 9.054, "expectedSign": "none", "imageReason": "The torso appears visually aligned and centered, with no clear left or right lean.", "oppositeLean": false},
            {"timestamp": 9.189, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 10.383, "expectedSign": "left", "oppositeLean": false}
          ]
        },
        {
          "clipDuration": 4.517,
          "role": "uncovered",
          "pauses": []
        },
        {
          "clipDuration": 37.289,
          "role": "usable",
          "pauses": [
            {"timestamp": 2.072, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 11.594, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 13.316, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 16.341, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 21.386, "expectedSign": "left", "oppositeLean": false}
          ]
        }
      ]
    }
    """

    private let video1PauseSheet = """
    {
      "clips": [
        {
          "clipDuration": 5.832,
          "role": "usable",
          "pauses": [
            {"timestamp": 0.381, "expectedSign": "right", "oppositeLean": false},
            {"timestamp": 1.400, "expectedSign": "right", "oppositeLean": true},
            {"timestamp": 2.300, "expectedSign": "left", "oppositeLean": false},
            {"timestamp": 3.067, "expectedSign": "left", "oppositeLean": true},
            {"timestamp": 5.267, "expectedSign": "right", "oppositeLean": false}
          ]
        }
      ]
    }
    """

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
