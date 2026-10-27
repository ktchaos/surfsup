import Foundation
import Testing
@testable import SurfsUp

struct ImagePlaneKneeTests {
    @Test func straightKneeOnTheHipToAnkleSegmentIs180() {
        let sample = sample(
            side: .left,
            hip: (0.40, 0.20),
            knee: (0.40, 0.50),
            ankle: (0.40, 0.80)
        )

        #expect(sample?.angleDegrees == 180)
        #expect(sample?.side == .left)
    }

    @Test func sharperBendIsSmallerAndStaysInsideZeroThrough180() {
        let straight = sample(
            side: .left,
            hip: (0.20, 0.80),
            knee: (0.20, 0.40),
            ankle: (0.20, 0.10)
        )
        let bent = sample(
            side: .left,
            hip: (0.20, 0.80),
            knee: (0.20, 0.40),
            ankle: (0.55, 0.25)
        )

        let bentAngle = bent?.angleDegrees
        #expect(bentAngle != nil)
        #expect(straight?.angleDegrees == 180)
        #expect(bentAngle! > 0)
        #expect(bentAngle! < 180)
        #expect(bentAngle! < straight!.angleDegrees)
        #expect(bentAngle == includedAngle(
            hip: (0.20, 0.80),
            knee: (0.20, 0.40),
            ankle: (0.55, 0.25)
        ))
    }

    @Test func oppositeFoldsOfTheSameSharpnessAreEqual() {
        let leftFold = sample(
            side: .right,
            hip: (0.50, 1.00),
            knee: (0.50, 0.50),
            ankle: (0.25, 0.875)
        )
        let rightFold = sample(
            side: .right,
            hip: (0.50, 1.00),
            knee: (0.50, 0.50),
            ankle: (0.75, 0.875)
        )

        #expect(leftFold?.angleDegrees != nil)
        #expect(leftFold?.angleDegrees == rightFold?.angleDegrees)
        #expect((leftFold?.angleDegrees ?? -1) > 0)
        #expect((leftFold?.angleDegrees ?? 181) < 180)
    }

    @Test func colinearKneeNotBetweenHipAndAnkleIsZeroAndStillASample() {
        let sample = sample(
            side: .left,
            hip: (0.30, 0.90),
            knee: (0.30, 0.20),
            ankle: (0.30, 0.60)
        )

        #expect(sample != nil)
        #expect(sample?.angleDegrees == 0)
    }

    @Test func leftAndRightAreIndependentStoredSides() {
        let duration = 1.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([
                point(.leftHip, x: 0.40, y: 0.20),
                point(.leftKnee, x: 0.40, y: 0.50),
                point(.leftAnkle, x: 0.40, y: 0.80),
                point(.rightHip, x: 0.70, y: 0.20),
                point(.rightKnee, x: 0.70, y: 0.50)
            ])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        let left = ImagePlaneKnee.sample(.left, at: 0.25, in: timeline)
        let right = ImagePlaneKnee.sample(.right, at: 0.25, in: timeline)

        #expect(left?.angleDegrees == 180)
        #expect(left?.side == .left)
        #expect(right == nil)
    }

    @Test func rightRemainsWhenLeftHipIsMissing() {
        let duration = 1.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([
                point(.leftKnee, x: 0.40, y: 0.50),
                point(.leftAnkle, x: 0.40, y: 0.80),
                point(.rightHip, x: 0.70, y: 0.20),
                point(.rightKnee, x: 0.70, y: 0.50),
                point(.rightAnkle, x: 0.70, y: 0.80)
            ])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: timeline) == nil)
        #expect(ImagePlaneKnee.sample(.right, at: 0.25, in: timeline)?.angleDegrees == 180)
    }

    @Test func missingObservationProducesNoSample() {
        let duration = 2.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: straightLeftBody()
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        #expect(ImagePlaneKnee.sample(.left, at: 0, in: timeline)?.angleDegrees == 180)
        #expect(ImagePlaneKnee.sample(.left, at: 1, in: timeline) == nil)
    }

    @Test func missingBodyProducesNoSample() {
        let duration = 1.0
        let frame = FrameObservation(start: 0, end: 1, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: timeline) == nil)
        #expect(ImagePlaneKnee.sample(.right, at: 0.25, in: timeline) == nil)
    }

    @Test func missingHipKneeOrAnkleProducesNoSampleForThatSideOnly() {
        let duration = 1.0
        let missingHip = timeline(duration: duration, landmarks: [
            point(.leftKnee, x: 0.40, y: 0.50),
            point(.leftAnkle, x: 0.40, y: 0.80),
            point(.rightHip, x: 0.70, y: 0.20),
            point(.rightKnee, x: 0.70, y: 0.50),
            point(.rightAnkle, x: 0.70, y: 0.80)
        ])
        let missingKnee = timeline(duration: duration, landmarks: [
            point(.leftHip, x: 0.40, y: 0.20),
            point(.leftAnkle, x: 0.40, y: 0.80),
            point(.rightHip, x: 0.70, y: 0.20),
            point(.rightKnee, x: 0.70, y: 0.50),
            point(.rightAnkle, x: 0.70, y: 0.80)
        ])
        let missingAnkle = timeline(duration: duration, landmarks: [
            point(.leftHip, x: 0.40, y: 0.20),
            point(.leftKnee, x: 0.40, y: 0.50),
            point(.rightHip, x: 0.70, y: 0.20),
            point(.rightKnee, x: 0.70, y: 0.50),
            point(.rightAnkle, x: 0.70, y: 0.80)
        ])

        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: missingHip) == nil)
        #expect(ImagePlaneKnee.sample(.right, at: 0.25, in: missingHip)?.angleDegrees == 180)
        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: missingKnee) == nil)
        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: missingAnkle) == nil)
        #expect(ImagePlaneKnee.sample(.right, at: 0.25, in: missingAnkle)?.angleDegrees == 180)
    }

    @Test func exactlyCoincidentPairsProduceNoSampleForThatSideOnly() {
        let hipAndKnee = timeline(duration: 1, landmarks: [
            point(.leftHip, x: 0.40, y: 0.50),
            point(.leftKnee, x: 0.40, y: 0.50),
            point(.leftAnkle, x: 0.40, y: 0.80),
            point(.rightHip, x: 0.70, y: 0.20),
            point(.rightKnee, x: 0.70, y: 0.50),
            point(.rightAnkle, x: 0.70, y: 0.80)
        ])
        let kneeAndAnkle = timeline(duration: 1, landmarks: [
            point(.leftHip, x: 0.40, y: 0.20),
            point(.leftKnee, x: 0.40, y: 0.80),
            point(.leftAnkle, x: 0.40, y: 0.80),
            point(.rightHip, x: 0.70, y: 0.20),
            point(.rightKnee, x: 0.70, y: 0.50),
            point(.rightAnkle, x: 0.70, y: 0.80)
        ])
        let hipAndAnkle = timeline(duration: 1, landmarks: [
            point(.leftHip, x: 0.20, y: 0.20),
            point(.leftKnee, x: 0.20, y: 0.80),
            point(.leftAnkle, x: 0.20, y: 0.20),
            point(.rightHip, x: 0.70, y: 0.20),
            point(.rightKnee, x: 0.70, y: 0.50),
            point(.rightAnkle, x: 0.70, y: 0.80)
        ])

        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: hipAndKnee) == nil)
        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: kneeAndAnkle) == nil)
        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: hipAndAnkle) == nil)
        #expect(ImagePlaneKnee.sample(.right, at: 0.25, in: hipAndAnkle)?.angleDegrees == 180)
    }

    @Test func zeroLengthSegmentProducesNoSample() {
        let timeline = timeline(duration: 1, landmarks: [
            point(.leftHip, x: 0.25, y: 0.25),
            point(.leftKnee, x: 0.25, y: 0.25),
            point(.leftAnkle, x: 0.25, y: 0.70)
        ])

        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: timeline) == nil)
    }

    @Test func nearCoincidentPointsStillProduceASample() {
        let sample = sample(
            side: .left,
            hip: (0.50, 0.50),
            knee: (0.50, 0.5000000001),
            ankle: (0.80, 0.20)
        )

        #expect(sample != nil)
    }

    @Test func lowConfidenceStoredPointStillProducesASample() {
        let duration = 1.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([
                Landmark(joint: .leftHip, x: 0.40, y: 0.20, confidence: 0.01)!,
                Landmark(joint: .leftKnee, x: 0.40, y: 0.50, confidence: 0.01)!,
                Landmark(joint: .leftAnkle, x: 0.40, y: 0.80, confidence: 0.01)!
            ])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!

        #expect(ImagePlaneKnee.sample(.left, at: 0.25, in: timeline)?.angleDegrees == 180)
    }

    @Test func gapIsNotFilledAndPreviousSampleIsNotHeld() {
        let duration = 2.0
        let withBody = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: straightLeftBody()
        )!
        let gap = FrameObservation(start: 1, end: 2, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [withBody, gap])!
        let before = timeline

        let first = ImagePlaneKnee.sample(.left, at: 0.4, in: timeline)
        let duringGap = ImagePlaneKnee.sample(.left, at: 1.2, in: timeline)
        let again = ImagePlaneKnee.sample(.left, at: 0.4, in: timeline)

        #expect(first?.angleDegrees == 180)
        #expect(duringGap == nil)
        #expect(again == first)
        #expect(timeline == before)
    }

    @Test func readingTheSameMomentTwiceReturnsTheSameAngle() {
        let duration = 1.0
        let timeline = timeline(duration: duration, landmarks: [
            point(.leftHip, x: 0.20, y: 0.80),
            point(.leftKnee, x: 0.20, y: 0.40),
            point(.leftAnkle, x: 0.55, y: 0.25)
        ])
        let before = timeline

        let first = ImagePlaneKnee.sample(.left, at: 0.25, in: timeline)
        let second = ImagePlaneKnee.sample(.left, at: 0.25, in: timeline)

        #expect(first == second)
        #expect(first?.angleDegrees == includedAngle(
            hip: (0.20, 0.80),
            knee: (0.20, 0.40),
            ankle: (0.55, 0.25)
        ))
        #expect(timeline == before)
    }

    private func sample(
        side: ImagePlaneKneeSide,
        hip: (Double, Double),
        knee: (Double, Double),
        ankle: (Double, Double)
    ) -> ImagePlaneKneeSample? {
        let hipJoint: JointName = side == .left ? .leftHip : .rightHip
        let kneeJoint: JointName = side == .left ? .leftKnee : .rightKnee
        let ankleJoint: JointName = side == .left ? .leftAnkle : .rightAnkle
        let timeline = timeline(duration: 1, landmarks: [
            point(hipJoint, x: hip.0, y: hip.1),
            point(kneeJoint, x: knee.0, y: knee.1),
            point(ankleJoint, x: ankle.0, y: ankle.1)
        ])
        return ImagePlaneKnee.sample(side, at: 0.25, in: timeline)
    }

    /// Expected angle from stored `x` and `y` only. This is not `PoseLayout`.
    private func includedAngle(
        hip: (Double, Double),
        knee: (Double, Double),
        ankle: (Double, Double)
    ) -> Double {
        let hipX = hip.0 - knee.0
        let hipY = hip.1 - knee.1
        let ankleX = ankle.0 - knee.0
        let ankleY = ankle.1 - knee.1
        let hipLength = (hipX * hipX + hipY * hipY).squareRoot()
        let ankleLength = (ankleX * ankleX + ankleY * ankleY).squareRoot()
        let cosine = min(1, max(-1, (hipX * ankleX + hipY * ankleY) / (hipLength * ankleLength)))
        return acos(cosine) * 180 / .pi
    }

    private func straightLeftBody() -> BodyObservation? {
        body([
            point(.leftHip, x: 0.40, y: 0.20),
            point(.leftKnee, x: 0.40, y: 0.50),
            point(.leftAnkle, x: 0.40, y: 0.80)
        ])
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
