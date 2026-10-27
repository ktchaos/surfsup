import Foundation
import Testing
@testable import SurfsUp

struct ActivityCheckTests {
    @Test func matchWhenPictureLabelEqualsComputedState() throws {
        let clip = usableClip(first: .standing, second: .paddling)
        let report = try ActivityCheck.score(clip: clip, timeline: standingThenPaddling())

        #expect(report.pauses.map(\.timestamp) == [0.25, 0.75])
        #expect(report.pauses[0].disposition == .match)
        #expect(report.pauses[0].state == .standing)
        #expect(report.pauses[1].disposition == .match)
        #expect(report.pauses[1].state == .paddling)
        #expect(report.statement == ActivityReport.pictureHypothesisStatement)
    }

    @Test func mismatchWhenComputedStateDiffersIncludingNeither() throws {
        let labeledAgainstTheState = usableClip(first: .paddling, second: .standing)
        let crossed = try ActivityCheck.score(clip: labeledAgainstTheState, timeline: standingThenPaddling())

        #expect(crossed.pauses[0].disposition == .mismatch)
        #expect(crossed.pauses[0].state == .standing)
        #expect(crossed.pauses[1].disposition == .mismatch)
        #expect(crossed.pauses[1].state == .paddling)
        #expect(crossed.pauses.map(\.timestamp) == [0.25, 0.75])

        let neitherThenStanding = usableClip(first: .standing, second: .standing)
        let report = try ActivityCheck.score(clip: neitherThenStanding, timeline: emptyBodyThenStanding())

        #expect(report.pauses[0].disposition == .mismatch)
        #expect(report.pauses[0].state == .neither)
        #expect(report.pauses[1].disposition == .match)
        #expect(report.pauses[1].state == .standing)
        #expect(report.pauses[1].timestamp == 0.75)
    }

    @Test func unclearWithAStateIsUnassessableAndKeepsImageReason() throws {
        let reason = "The activity is not clear enough to name."
        let clip = ActivityClip(
            clipDuration: 1,
            role: .usable,
            pauses: [
                ActivityPause(timestamp: 0.25, picture: .unclear, imageReason: reason),
                ActivityPause(timestamp: 0.75, picture: .standing, imageReason: nil)
            ]
        )
        let report = try ActivityCheck.score(clip: clip, timeline: emptyBodyThenStanding())

        #expect(report.pauses[0].disposition == .unassessable)
        #expect(report.pauses[0].state == .neither)
        #expect(report.pauses[0].reason == reason)
        #expect(report.pauses[0].timestamp == 0.25)
        #expect(report.pauses[1].disposition == .match)
        #expect(report.pauses[1].state == .standing)
    }

    @Test func noStateIsUncoveredEvenWhenPictureIsUnclear() throws {
        let clip = ActivityClip(
            clipDuration: 1,
            role: .usable,
            pauses: [
                ActivityPause(timestamp: 0.25, picture: .unclear, imageReason: "The pose is hidden."),
                ActivityPause(timestamp: 0.75, picture: .paddling, imageReason: nil)
            ]
        )
        let report = try ActivityCheck.score(clip: clip, timeline: missingNeckThenPaddling())

        #expect(report.pauses[0].disposition == .uncovered)
        #expect(report.pauses[0].state == nil)
        #expect(report.pauses[0].reason.contains("neck"))
        #expect(report.pauses[0].timestamp == 0.25)
        #expect(report.pauses[1].disposition == .match)
        #expect(report.pauses[1].state == .paddling)
    }

    @Test func labeledPauseWithNoObservationIsUncovered() throws {
        let clip = usableClip(first: .standing, second: .standing)
        let duration = 1.0
        let frame = FrameObservation(start: 0, end: 0.5, clipDuration: duration, body: standingBody())!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!
        let report = try ActivityCheck.score(clip: clip, timeline: timeline)

        #expect(report.pauses[0].disposition == .match)
        #expect(report.pauses[1].disposition == .uncovered)
        #expect(report.pauses[1].state == nil)
        #expect(report.pauses[1].reason.contains("observation"))
        #expect(report.pauses[1].timestamp == 0.75)
    }

    @Test func uncoveredClipDurationHasNoPausesAndNoMatchOrMismatch() throws {
        let clip = ActivityClip(clipDuration: 4.517, role: .uncovered, pauses: [])
        let report = try ActivityCheck.score(clip: clip, timeline: standingThenPaddling())

        #expect(report.clipDuration == 4.517)
        #expect(report.role == .uncovered)
        #expect(report.pauses.isEmpty)
        #expect(report.statement == ActivityReport.pictureHypothesisStatement)
    }

    @Test func sheetWithAComputedStateOrOutcomeIsRejected() throws {
        #expect(throws: ActivitySheetError.computedStatePresent) {
            try ActivityCheck.decodeSheet(sheetJSON(#"{"state":"paddling"}"#))
        }
        #expect(throws: ActivitySheetError.scoredOutcomePresent) {
            try ActivityCheck.decodeSheet(sheetJSON(#"{"outcome":"match"}"#))
        }
    }

    @Test func fivePausesKneeLabelsExpectedSignAndOppositeLeanAreRejected() throws {
        let five = (0..<5).map { index in
            #"{"timestamp":\#(Double(index) / 10),"picture":"paddling"}"#
        }.joined(separator: ",")
        #expect(throws: ActivitySheetError.usablePauseCount) {
            try ActivityCheck.decodeSheet(sheetJSON(#"{"pauses":[\#(five)]}"#))
        }
        #expect(throws: ActivitySheetError.kneePicture) {
            try ActivityCheck.decodeSheet(sheetJSON(
                #"{"pauses":[{"timestamp":0.25,"picture":"moreBent"},{"timestamp":0.75,"picture":"lessBent"}]}"#
            ))
        }
        #expect(throws: ActivitySheetError.expectedSignPresent) {
            try ActivityCheck.decodeSheet(sheetJSON(#"{"expectedSign":"left"}"#))
        }
        #expect(throws: ActivitySheetError.oppositeLeanPresent) {
            try ActivityCheck.decodeSheet(sheetJSON(#"{"oppositeLean":false}"#))
        }
    }

    @Test func imageReasonIsRequiredOnlyOnUnclear() throws {
        #expect(throws: ActivitySheetError.missingImageReason) {
            try ActivityCheck.decodeSheet(sheetJSON(
                #"{"pauses":[{"timestamp":0.25,"picture":"unclear"},{"timestamp":0.75,"picture":"standing"}]}"#
            ))
        }
        #expect(throws: ActivitySheetError.unexpectedImageReason) {
            try ActivityCheck.decodeSheet(sheetJSON(
                #"{"pauses":[{"timestamp":0.25,"picture":"paddling","imageReason":"not allowed"},{"timestamp":0.75,"picture":"standing"}]}"#
            ))
        }
    }

    private func usableClip(first: ActivityPause.Picture, second: ActivityPause.Picture) -> ActivityClip {
        ActivityClip(
            clipDuration: 1,
            role: .usable,
            pauses: [
                ActivityPause(timestamp: 0.25, picture: first, imageReason: nil),
                ActivityPause(timestamp: 0.75, picture: second, imageReason: nil)
            ]
        )
    }

    private func sheetJSON(_ clipObject: String) -> Data {
        let fields = clipObject.dropFirst().dropLast()
        return Data(#"{"clips":[{"clipDuration":1,"role":"usable",\#(fields)}]}"#.utf8)
    }

    private func standingThenPaddling() -> PoseTimeline {
        twoFrames(first: standingBody(), second: paddlingBody())
    }

    private func emptyBodyThenStanding() -> PoseTimeline {
        twoFrames(first: nil, second: standingBody())
    }

    private func missingNeckThenPaddling() -> PoseTimeline {
        twoFrames(
            first: body([
                point(.root, x: 0.5, y: 0.5),
                point(.leftAnkle, x: 0.25, y: 0.25),
                point(.rightAnkle, x: 0.75, y: 0.25)
            ]),
            second: paddlingBody()
        )
    }

    private func twoFrames(first: BodyObservation?, second: BodyObservation?) -> PoseTimeline {
        let duration = 1.0
        let opening = FrameObservation(start: 0, end: 0.5, clipDuration: duration, body: first)!
        let closing = FrameObservation(start: 0.5, end: 1, clipDuration: duration, body: second)!
        return PoseTimeline(clipDuration: duration, observations: [opening, closing])!
    }

    private func standingBody() -> BodyObservation? {
        body([
            point(.neck, x: 0.5, y: 1),
            point(.root, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.25, y: 0.25),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ])
    }

    private func paddlingBody() -> BodyObservation? {
        body([
            point(.neck, x: 0.75, y: 0.5),
            point(.root, x: 0.25, y: 0.5),
            point(.leftWrist, x: 0.125, y: 0.875),
            point(.rightWrist, x: 0.875, y: 0.125)
        ])
    }

    private func body(_ landmarks: [Landmark]) -> BodyObservation? {
        BodyObservation(landmarks: landmarks, selectionArea: 0.1)
    }

    private func point(_ joint: JointName, x: Double, y: Double) -> Landmark {
        Landmark(joint: joint, x: x, y: y, confidence: 1)!
    }
}
