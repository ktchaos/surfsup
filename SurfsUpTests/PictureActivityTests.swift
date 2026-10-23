import Foundation
import Testing
@testable import SurfsUp

struct PictureActivityTests {
    @Test func noRetainedBodyIsNeither() {
        let duration = 1.0
        let frame = FrameObservation(start: 0, end: duration, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        #expect(PictureActivity.state(at: 0.25, in: timeline) == .neither)
    }

    @Test func missingObservationIsNoStateNotNeither() {
        let duration = 2.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: standingBody()
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        #expect(PictureActivity.state(at: 1.25, in: timeline) == nil)
    }

    @Test func missingNeckOrRootIsNoState() {
        let duration = 1.0
        let missingNeck = timeline(duration: duration, landmarks: [
            point(.root, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.25, y: 0.25),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ])
        let missingRoot = timeline(duration: duration, landmarks: [
            point(.neck, x: 0.5, y: 1),
            point(.leftAnkle, x: 0.25, y: 0.25),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ])

        #expect(PictureActivity.state(at: 0.25, in: missingNeck) == nil)
        #expect(PictureActivity.state(at: 0.25, in: missingRoot) == nil)
    }

    @Test func moreVerticalWithBothAnklesBelowRootIsStanding() {
        let timeline = timeline(duration: 1, landmarks: standingLandmarks())

        #expect(PictureActivity.state(at: 0.25, in: timeline) == .standing)
    }

    @Test func moreVerticalWhenAnkleIsNotStrictlyBelowRootIsNeither() {
        let level = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.5, y: 1),
            point(.root, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.25, y: 0.5),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ])
        let above = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.5, y: 1),
            point(.root, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.25, y: 0.75),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ])

        #expect(PictureActivity.state(at: 0.25, in: level) == .neither)
        #expect(PictureActivity.state(at: 0.25, in: above) == .neither)
    }

    @Test func moreVerticalWithEitherAnkleMissingIsNoState() {
        let missingRight = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.5, y: 1),
            point(.root, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.25, y: 0.25)
        ])
        let missingLeft = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.5, y: 1),
            point(.root, x: 0.5, y: 0.5),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ])

        #expect(PictureActivity.state(at: 0.25, in: missingRight) == nil)
        #expect(PictureActivity.state(at: 0.25, in: missingLeft) == nil)
    }

    @Test func moreHorizontalWithBothWristsIsPaddlingRegardlessOfWristPosition() {
        let highWrists = timeline(duration: 1, landmarks: horizontalLandmarks(
            leftWrist: (0.125, 0.875),
            rightWrist: (0.875, 0.125)
        ))
        let otherWrists = timeline(duration: 1, landmarks: horizontalLandmarks(
            leftWrist: (0, 0),
            rightWrist: (1, 1)
        ))
        let anklesDoNotChangeIt = timeline(duration: 1, landmarks: horizontalLandmarks(
            leftWrist: (0.125, 0.875),
            rightWrist: (0.875, 0.125)
        ) + [
            point(.leftAnkle, x: 0.25, y: 0.75),
            point(.rightAnkle, x: 0.75, y: 0.75)
        ])

        #expect(PictureActivity.state(at: 0.25, in: highWrists) == .paddling)
        #expect(PictureActivity.state(at: 0.25, in: otherWrists) == .paddling)
        #expect(PictureActivity.state(at: 0.25, in: anklesDoNotChangeIt) == .paddling)
    }

    @Test func equalAbsoluteDifferencesIncludingZeroAreHorizontalPaddling() {
        let equal = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.75, y: 0.75),
            point(.root, x: 0.25, y: 0.25),
            point(.leftWrist, x: 0, y: 0.5),
            point(.rightWrist, x: 1, y: 0.5)
        ])
        let zero = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.5, y: 0.5),
            point(.root, x: 0.5, y: 0.5),
            point(.leftWrist, x: 0.25, y: 0.25),
            point(.rightWrist, x: 0.75, y: 0.75)
        ])

        #expect(PictureActivity.state(at: 0.25, in: equal) == .paddling)
        #expect(PictureActivity.state(at: 0.25, in: zero) == .paddling)
    }

    @Test func moreHorizontalWithEitherWristMissingIsNoState() {
        let missingRight = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.75, y: 0.5),
            point(.root, x: 0.25, y: 0.5),
            point(.leftWrist, x: 0.125, y: 0.875)
        ])
        let missingLeft = timeline(duration: 1, landmarks: [
            point(.neck, x: 0.75, y: 0.5),
            point(.root, x: 0.25, y: 0.5),
            point(.rightWrist, x: 0.875, y: 0.125)
        ])

        #expect(PictureActivity.state(at: 0.25, in: missingRight) == nil)
        #expect(PictureActivity.state(at: 0.25, in: missingLeft) == nil)
    }

    @Test func gapIsNotFilledAndPreviousStateIsNotHeld() {
        let duration = 3.0
        let standing = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: standingBody()
        )!
        let gap = FrameObservation(start: 1, end: 2, clipDuration: duration, body: nil)!
        let paddling = FrameObservation(
            start: 2,
            end: 3,
            clipDuration: duration,
            body: body(horizontalLandmarks(leftWrist: (0.125, 0.875), rightWrist: (0.875, 0.125)))
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [standing, gap, paddling])!
        let before = timeline

        let first = PictureActivity.state(at: 0.25, in: timeline)
        let duringGap = PictureActivity.state(at: 1.25, in: timeline)
        let later = PictureActivity.state(at: 2.25, in: timeline)
        let again = PictureActivity.state(at: 0.25, in: timeline)

        #expect(first == .standing)
        #expect(duringGap == .neither)
        #expect(later == .paddling)
        #expect(again == first)
        #expect(timeline == before)
    }

    @Test func lookupStaysHalfOpen() {
        let duration = 1.0
        let standing = FrameObservation(
            start: 0,
            end: 0.5,
            clipDuration: duration,
            body: standingBody()
        )!
        let empty = FrameObservation(start: 0.5, end: 1, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [standing, empty])!

        #expect(PictureActivity.state(at: 0.25, in: timeline) == .standing)
        #expect(PictureActivity.state(at: 0.5, in: timeline) == .neither)
    }

    @Test func lowConfidenceStoredPointStillProducesAState() {
        let timeline = timeline(duration: 1, landmarks: [
            Landmark(joint: .neck, x: 0.5, y: 1, confidence: 0.01)!,
            Landmark(joint: .root, x: 0.5, y: 0.5, confidence: 0.01)!,
            Landmark(joint: .leftAnkle, x: 0.25, y: 0.25, confidence: 0.01)!,
            Landmark(joint: .rightAnkle, x: 0.75, y: 0.25, confidence: 0.01)!
        ])

        #expect(PictureActivity.state(at: 0.25, in: timeline) == .standing)
    }

    private func standingLandmarks() -> [Landmark] {
        [
            point(.neck, x: 0.5, y: 1),
            point(.root, x: 0.5, y: 0.5),
            point(.leftAnkle, x: 0.25, y: 0.25),
            point(.rightAnkle, x: 0.75, y: 0.25)
        ]
    }

    private func standingBody() -> BodyObservation? {
        body(standingLandmarks())
    }

    private func horizontalLandmarks(
        leftWrist: (Double, Double),
        rightWrist: (Double, Double)
    ) -> [Landmark] {
        [
            point(.neck, x: 0.75, y: 0.5),
            point(.root, x: 0.25, y: 0.5),
            point(.leftWrist, x: leftWrist.0, y: leftWrist.1),
            point(.rightWrist, x: rightWrist.0, y: rightWrist.1)
        ]
    }

    private func timeline(duration: TimeInterval, landmarks: [Landmark]) -> PoseTimeline {
        let frame = FrameObservation(
            start: 0,
            end: duration,
            clipDuration: duration,
            body: body(landmarks)
        )!
        return PoseTimeline(clipDuration: duration, observations: [frame])!
    }

    private func body(_ landmarks: [Landmark]) -> BodyObservation? {
        BodyObservation(landmarks: landmarks, selectionArea: 0.1)
    }

    private func point(_ joint: JointName, x: Double, y: Double) -> Landmark {
        Landmark(joint: joint, x: x, y: y, confidence: 1)!
    }
}
