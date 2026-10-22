import Foundation
import Testing
@testable import SurfsUp

struct KneeOrdinalCheckTests {
    @Test func matchWhenMoreBentHasTheStrictlySmallerAngle() throws {
        let clip = orderedClip(moreBentAt: 0.25, lessBentAt: 0.75)
        let timeline = twoFrames(first: bentLeft(), second: straightLeft())
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: timeline)

        #expect(report.comparison == .match)
        #expect(report.pauses.map(\.timestamp) == [0.25, 0.75])
        #expect(report.pauses.allSatisfy { $0.disposition == .compared })
        #expect(report.knee == .left)
        #expect(report.statement == KneeOrdinalReport.pictureProxyStatement)
    }

    @Test func mismatchWhenMoreBentAngleIsLarger() throws {
        let clip = orderedClip(moreBentAt: 0.25, lessBentAt: 0.75)
        let timeline = twoFrames(first: straightLeft(), second: bentLeft())
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: timeline)

        #expect(report.comparison == .mismatch)
        #expect(report.pauses.map(\.timestamp) == [0.25, 0.75])
        #expect(report.pauses.allSatisfy { $0.disposition == .compared })
    }

    @Test func mismatchWhenAnglesAreEqual() throws {
        let clip = orderedClip(moreBentAt: 0.25, lessBentAt: 0.75)
        let timeline = twoFrames(first: straightLeft(), second: straightLeft())
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: timeline)

        #expect(report.comparison == .mismatch)
        #expect(report.pauses.allSatisfy { $0.disposition == .compared })
    }

    @Test func unclearPictureWithASampleIsUnassessableAndKeepsImageReason() throws {
        let reason = "The named knee is not clear enough to order."
        let clip = KneeOrdinalClip(
            clipDuration: 1,
            role: .usable,
            knee: .left,
            pauses: [
                KneeOrdinalPause(timestamp: 0.25, picture: .unclear, imageReason: reason),
                KneeOrdinalPause(timestamp: 0.75, picture: .unclear, imageReason: reason)
            ]
        )
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: oneFrame(straightLeft()))

        #expect(report.comparison == .notScored)
        #expect(report.pauses.allSatisfy { $0.disposition == .unassessable })
        #expect(report.pauses.allSatisfy { $0.reason == reason })
        #expect(report.pauses.map(\.timestamp) == [0.25, 0.75])
    }

    @Test func noSampleIsUncoveredEvenWhenPictureIsUnclear() throws {
        let clip = KneeOrdinalClip(
            clipDuration: 1,
            role: .usable,
            knee: .left,
            pauses: [
                KneeOrdinalPause(timestamp: 0.25, picture: .unclear, imageReason: "The knee is hidden."),
                KneeOrdinalPause(timestamp: 0.75, picture: .visible, imageReason: nil)
            ]
        )
        let timeline = twoFrames(first: leftMissingKnee(), second: straightLeft())
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: timeline)

        #expect(report.pauses[0].disposition == .uncovered)
        #expect(report.pauses[0].disposition != .unassessable)
        #expect(report.pauses[0].reason.contains("knee"))
        #expect(report.pauses[0].timestamp == 0.25)
        #expect(report.comparison == .notScored)
    }

    @Test func visiblePauseWithASampleIsListed() throws {
        let clip = KneeOrdinalClip(
            clipDuration: 1,
            role: .usable,
            knee: .left,
            pauses: [
                KneeOrdinalPause(timestamp: 0.25, picture: .unclear, imageReason: "The knee is hidden."),
                KneeOrdinalPause(timestamp: 0.75, picture: .visible, imageReason: nil)
            ]
        )
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: oneFrame(straightLeft()))
        let visible = report.pauses[1]

        #expect(visible.disposition == .listed)
        #expect(visible.disposition != .compared)
        #expect(visible.disposition != .unassessable)
        #expect(visible.timestamp == 0.75)
        #expect(report.comparison == .notScored)
    }

    @Test func notScoredWhenEitherPauseIsUnassessableUncoveredOrListed() throws {
        let unclear = try KneeOrdinalCheck.score(
            clip: KneeOrdinalClip(
                clipDuration: 1,
                role: .usable,
                knee: .left,
                pauses: [
                    KneeOrdinalPause(timestamp: 0.25, picture: .unclear, imageReason: "Hidden."),
                    KneeOrdinalPause(timestamp: 0.75, picture: .unclear, imageReason: "Hidden.")
                ]
            ),
            timeline: oneFrame(straightLeft())
        )
        let uncovered = try KneeOrdinalCheck.score(
            clip: orderedClip(moreBentAt: 0.25, lessBentAt: 0.75),
            timeline: oneFrame(leftMissingKnee())
        )
        let listed = try KneeOrdinalCheck.score(
            clip: KneeOrdinalClip(
                clipDuration: 1,
                role: .usable,
                knee: .left,
                pauses: [
                    KneeOrdinalPause(timestamp: 0.25, picture: .visible, imageReason: nil),
                    KneeOrdinalPause(timestamp: 0.75, picture: .unclear, imageReason: "Hidden.")
                ]
            ),
            timeline: oneFrame(straightLeft())
        )

        #expect(unclear.comparison == .notScored)
        #expect(uncovered.comparison == .notScored)
        #expect(uncovered.pauses.allSatisfy { $0.disposition == .uncovered })
        #expect(listed.comparison == .notScored)
        #expect(listed.pauses.contains { $0.disposition == .listed })
    }

    @Test func uncoveredClipDurationHasNoKneePausesOrComparison() throws {
        let clip = KneeOrdinalClip(clipDuration: 4.517, role: .uncovered, knee: nil, pauses: [])
        let report = try KneeOrdinalCheck.score(clip: clip, timeline: oneFrame(straightLeft()))

        #expect(report.clipDuration == 4.517)
        #expect(report.role == .uncovered)
        #expect(report.knee == nil)
        #expect(report.pauses.isEmpty)
        #expect(report.comparison == nil)
        #expect(report.statement == KneeOrdinalReport.pictureProxyStatement)
    }

    @Test func sheetWithAnAngleOrOutcomeIsRejected() {
        #expect(throws: KneeOrdinalSheetError.computedAnglePresent) {
            try KneeOrdinalCheck.decodeSheet(Data(orderedJSON(extra: "\"angleDegrees\": 12").utf8))
        }
        #expect(throws: KneeOrdinalSheetError.scoredOutcomePresent) {
            try KneeOrdinalCheck.decodeSheet(Data(orderedJSON(extra: "\"outcome\": \"match\"").utf8))
        }
    }

    @Test func fivePausesExpectedSignAndOppositeLeanAreRejected() {
        let five = (0..<5).map { index in
            KneeOrdinalPause(
                timestamp: 0.125 * Double(index),
                picture: index == 0 ? .moreBent : .lessBent,
                imageReason: nil
            )
        }
        #expect(throws: KneeOrdinalSheetError.usablePauseCount) {
            try KneeOrdinalCheck.score(
                clip: KneeOrdinalClip(clipDuration: 1, role: .usable, knee: .left, pauses: five),
                timeline: oneFrame(straightLeft())
            )
        }
        #expect(throws: KneeOrdinalSheetError.expectedSignPresent) {
            try KneeOrdinalCheck.decodeSheet(Data(orderedJSON(extra: "\"expectedSign\": \"left\"").utf8))
        }
        #expect(throws: KneeOrdinalSheetError.expectedSignPresent) {
            try KneeOrdinalCheck.decodeSheet(Data(orderedJSON(extra: "\"expectedSign\": \"right\"").utf8))
        }
        #expect(throws: KneeOrdinalSheetError.oppositeLeanPresent) {
            try KneeOrdinalCheck.decodeSheet(Data(orderedJSON(extra: "\"oppositeLean\": true").utf8))
        }
    }

    @Test func imageReasonIsRequiredOnlyOnUnclear() {
        #expect(throws: KneeOrdinalSheetError.missingImageReason) {
            try KneeOrdinalCheck.score(
                clip: KneeOrdinalClip(
                    clipDuration: 1,
                    role: .usable,
                    knee: .left,
                    pauses: [
                        KneeOrdinalPause(timestamp: 0.25, picture: .unclear, imageReason: nil),
                        KneeOrdinalPause(timestamp: 0.75, picture: .unclear, imageReason: "Hidden.")
                    ]
                ),
                timeline: oneFrame(straightLeft())
            )
        }
        #expect(throws: KneeOrdinalSheetError.unexpectedImageReason) {
            try KneeOrdinalCheck.score(
                clip: KneeOrdinalClip(
                    clipDuration: 1,
                    role: .usable,
                    knee: .left,
                    pauses: [
                        KneeOrdinalPause(timestamp: 0.25, picture: .moreBent, imageReason: "Not allowed."),
                        KneeOrdinalPause(timestamp: 0.75, picture: .lessBent, imageReason: nil)
                    ]
                ),
                timeline: oneFrame(straightLeft())
            )
        }
        #expect(throws: KneeOrdinalSheetError.picturePair) {
            try KneeOrdinalCheck.score(
                clip: KneeOrdinalClip(
                    clipDuration: 1,
                    role: .usable,
                    knee: .left,
                    pauses: [
                        KneeOrdinalPause(timestamp: 0.25, picture: .moreBent, imageReason: nil),
                        KneeOrdinalPause(timestamp: 0.75, picture: .visible, imageReason: nil)
                    ]
                ),
                timeline: oneFrame(straightLeft())
            )
        }
    }

    private func orderedClip(moreBentAt: TimeInterval, lessBentAt: TimeInterval) -> KneeOrdinalClip {
        KneeOrdinalClip(
            clipDuration: 1,
            role: .usable,
            knee: .left,
            pauses: [
                KneeOrdinalPause(timestamp: moreBentAt, picture: .moreBent, imageReason: nil),
                KneeOrdinalPause(timestamp: lessBentAt, picture: .lessBent, imageReason: nil)
            ]
        )
    }

    private func orderedJSON(extra: String) -> String {
        """
        {"clips":[{"clipDuration":1,"role":"usable","knee":"left","pauses":[{"timestamp":0.25,"picture":"moreBent",\(extra)},{"timestamp":0.75,"picture":"lessBent"}]}]}
        """
    }

    private func oneFrame(_ landmarks: [Landmark]) -> PoseTimeline {
        let frame = FrameObservation(start: 0, end: 1, clipDuration: 1, body: body(landmarks))!
        return PoseTimeline(clipDuration: 1, observations: [frame])!
    }

    private func twoFrames(first: [Landmark], second: [Landmark]) -> PoseTimeline {
        let earlier = FrameObservation(start: 0, end: 0.5, clipDuration: 1, body: body(first))!
        let later = FrameObservation(start: 0.5, end: 1, clipDuration: 1, body: body(second))!
        return PoseTimeline(clipDuration: 1, observations: [earlier, later])!
    }

    private func straightLeft() -> [Landmark] {
        [
            point(.leftHip, x: 0.5, y: 0.25),
            point(.leftKnee, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.5, y: 0.75)
        ]
    }

    private func bentLeft() -> [Landmark] {
        [
            point(.leftHip, x: 0.5, y: 0.75),
            point(.leftKnee, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.75, y: 0.25)
        ]
    }

    private func leftMissingKnee() -> [Landmark] {
        [
            point(.leftHip, x: 0.5, y: 0.25),
            point(.leftAnkle, x: 0.5, y: 0.75)
        ]
    }

    private func body(_ landmarks: [Landmark]) -> BodyObservation? {
        BodyObservation(landmarks: landmarks, selectionArea: 0.1)
    }

    private func point(_ joint: JointName, x: Double, y: Double) -> Landmark {
        Landmark(joint: joint, x: x, y: y, confidence: 1)!
    }
}
