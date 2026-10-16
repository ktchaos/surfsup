import Foundation
import Testing
@testable import SurfsUp

struct ImagePlaneTorsoLeanTests {
    @Test func neckDirectlyAboveRootIsZero() {
        let sample = sample(neckX: 0.4, neckY: 0.8, rootX: 0.4, rootY: 0.3)

        #expect(sample?.angleDegrees == 0)
        #expect(sample?.ordinarySign == .upright)
    }

    @Test func neckToTheViewersRightIsPositive() {
        let sample = sample(neckX: 0.7, neckY: 0.5, rootX: 0.4, rootY: 0.5)

        #expect(sample?.angleDegrees == 90)
        #expect(sample?.ordinarySign == .right)
    }

    @Test func neckToTheViewersLeftIsNegative() {
        let sample = sample(neckX: 0.2, neckY: 0.5, rootX: 0.6, rootY: 0.5)

        #expect(sample?.angleDegrees == -90)
        #expect(sample?.ordinarySign == .left)
    }

    @Test func neckBelowRootButNotStraightDownKeepsTheSide() {
        let neckX = 0.7
        let neckY = 0.2
        let rootX = 0.4
        let rootY = 0.7
        let sample = sample(neckX: neckX, neckY: neckY, rootX: rootX, rootY: rootY)
        let expected = atan2(neckX - rootX, neckY - rootY) * 180 / .pi

        #expect(sample?.angleDegrees == expected)
        #expect(sample?.ordinarySign == .right)
        #expect((sample?.angleDegrees ?? 0) > 90)
        #expect((sample?.angleDegrees ?? 0) < 180)
    }

    @Test func neckDirectlyBelowRootIsTheBranchCut() {
        let sample = sample(neckX: 0.5, neckY: 0.2, rootX: 0.5, rootY: 0.8)

        #expect(sample?.angleDegrees == 180)
        #expect(sample?.ordinarySign == .branchCut)
        #expect(sample?.ordinarySign != .left)
        #expect(sample?.ordinarySign != .right)
    }

    @Test func coincidentPointsProduceNoSample() {
        #expect(sample(neckX: 0.5, neckY: 0.5, rootX: 0.5, rootY: 0.5) == nil)
    }

    @Test func missingNeckOrRootProducesNoSample() {
        let duration = 1.0
        let missingNeck = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.root, x: 0.4, y: 0.3), point(.nose, x: 0.4, y: 0.9)])
        )!
        let missingRoot = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.neck, x: 0.4, y: 0.8), point(.nose, x: 0.4, y: 0.9)])
        )!
        let neckTimeline = PoseTimeline(clipDuration: duration, observations: [missingNeck])!
        let rootTimeline = PoseTimeline(clipDuration: duration, observations: [missingRoot])!

        #expect(ImagePlaneTorsoLean.sample(at: 0.2, in: neckTimeline) == nil)
        #expect(ImagePlaneTorsoLean.sample(at: 0.2, in: rootTimeline) == nil)
    }

    @Test func missingBodyProducesNoSampleAndDoesNotBorrowTheNeighbor() {
        let duration = 2.0
        let withBody = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.neck, x: 0.4, y: 0.8), point(.root, x: 0.4, y: 0.3)])
        )!
        let gap = FrameObservation(start: 1, end: 2, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [withBody, gap])!
        let before = timeline

        let first = ImagePlaneTorsoLean.sample(at: 0.4, in: timeline)
        let duringGap = ImagePlaneTorsoLean.sample(at: 1.2, in: timeline)
        let again = ImagePlaneTorsoLean.sample(at: 0.4, in: timeline)

        #expect(first?.ordinarySign == .upright)
        #expect(duringGap == nil)
        #expect(again == first)
        #expect(timeline == before)
    }

    @Test func readingTheSameMomentTwiceReturnsTheSameAngle() {
        let duration = 1.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.neck, x: 0.2, y: 0.5), point(.root, x: 0.6, y: 0.5)])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!
        let before = timeline

        let first = ImagePlaneTorsoLean.sample(at: 0.25, in: timeline)
        let second = ImagePlaneTorsoLean.sample(at: 0.25, in: timeline)

        #expect(first == second)
        #expect(first?.angleDegrees == -90)
        #expect(timeline == before)
    }

    private func sample(neckX: Double, neckY: Double, rootX: Double, rootY: Double) -> ImagePlaneTorsoSample? {
        let duration = 1.0
        let frame = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.neck, x: neckX, y: neckY), point(.root, x: rootX, y: rootY)])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [frame])!
        return ImagePlaneTorsoLean.sample(at: 0.25, in: timeline)
    }

    private func body(_ landmarks: [Landmark]) -> BodyObservation? {
        BodyObservation(landmarks: landmarks, selectionArea: 0.1)
    }

    private func point(_ joint: JointName, x: Double, y: Double) -> Landmark {
        Landmark(joint: joint, x: x, y: y, confidence: 1)!
    }
}
