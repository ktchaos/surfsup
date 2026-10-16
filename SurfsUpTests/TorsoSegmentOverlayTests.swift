import CoreGraphics
import Foundation
import Testing
@testable import SurfsUp

struct TorsoSegmentOverlayTests {
    @Test func markersUseTheSameStoredPointsAsTheAngle() throws {
        let timeline = timeline(
            neck: (0.7, 0.5),
            root: (0.4, 0.5),
            start: 0,
            end: 1,
            duration: 1
        )
        let points = ImagePlaneTorsoLean.storedPoints(at: 0.2, in: timeline)
        let sample = try #require(ImagePlaneTorsoLean.sample(at: 0.2, in: timeline))
        let neck = try #require(points.neck)
        let root = try #require(points.root)

        #expect(neck.x == 0.7)
        #expect(neck.y == 0.5)
        #expect(root.x == 0.4)
        #expect(root.y == 0.5)
        #expect(points.drawsSegment)
        #expect(sample.angleDegrees == atan2(neck.x - root.x, neck.y - root.y) * 180 / .pi)
        #expect(sample.ordinarySign == .right)
    }

    @Test func aMissingLandmarkDoesNotInventTheSegment() throws {
        let duration = 1.0
        let missingNeck = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([landmark(.root, x: 0.4, y: 0.3)])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [missingNeck])!
        let points = ImagePlaneTorsoLean.storedPoints(at: 0.2, in: timeline)

        #expect(points.neck == nil)
        #expect(points.root?.x == 0.4)
        #expect(!points.drawsSegment)
        #expect(ImagePlaneTorsoLean.sample(at: 0.2, in: timeline) == nil)
    }

    @Test func screenXKeepsTheViewersLeftAndRight() throws {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
        let neck = try #require(landmark(.neck, x: 0.2, y: 0.8))
        let root = try #require(landmark(.root, x: 0.8, y: 0.2))
        let neckScreen = PoseLayout.point(neck, in: rect)
        let rootScreen = PoseLayout.point(root, in: rect)

        #expect(neckScreen.x < rootScreen.x)
        #expect(neckScreen.y < rootScreen.y)
    }

    @Test func thePlayheadSelectsThatFramesLandmarks() throws {
        let duration = 2.0
        let first = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([landmark(.neck, x: 0.2, y: 0.8), landmark(.root, x: 0.5, y: 0.4)])
        )!
        let second = FrameObservation(
            start: 1,
            end: 2,
            clipDuration: duration,
            body: body([landmark(.neck, x: 0.8, y: 0.8), landmark(.root, x: 0.5, y: 0.4)])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [first, second])!
        let early = ImagePlaneTorsoLean.storedPoints(at: 0.2, in: timeline)
        let late = ImagePlaneTorsoLean.storedPoints(at: 1.2, in: timeline)

        #expect(early.neck?.x == 0.2)
        #expect(late.neck?.x == 0.8)
        #expect(ImagePlaneTorsoLean.sample(at: 0.2, in: timeline)?.ordinarySign == .left)
        #expect(ImagePlaneTorsoLean.sample(at: 1.2, in: timeline)?.ordinarySign == .right)
        #expect(ImagePlaneTorsoLean.storedPoints(at: 1, in: timeline).neck?.x == 0.8)
    }

    private func timeline(
        neck: (Double, Double),
        root: (Double, Double),
        start: TimeInterval,
        end: TimeInterval,
        duration: TimeInterval
    ) -> PoseTimeline {
        let frame = FrameObservation(
            start: start,
            end: end,
            clipDuration: duration,
            body: body([
                landmark(.neck, x: neck.0, y: neck.1),
                landmark(.root, x: root.0, y: root.1)
            ])
        )!
        return PoseTimeline(clipDuration: duration, observations: [frame])!
    }

    private func body(_ landmarks: [Landmark?]) -> BodyObservation? {
        BodyObservation(landmarks: landmarks.compactMap { $0 }, selectionArea: 0.1)
    }

    private func landmark(_ joint: JointName, x: Double, y: Double) -> Landmark? {
        Landmark(joint: joint, x: x, y: y, confidence: 1)
    }
}
