import Testing
@testable import SurfsUp

struct SkeletonEdgesTests {
    @Test func aBoneIsOmittedWhenEitherJointIsAbsent() {
        let landmarks = [
            Landmark(joint: .leftHip, x: 0.4, y: 0.4, confidence: 1)!,
            Landmark(joint: .leftAnkle, x: 0.4, y: 0.1, confidence: 1)!,
        ]

        let edges = SkeletonEdges.visible(in: landmarks)

        #expect(!edges.contains(SkeletonEdge(start: .leftHip, end: .leftKnee)))
        #expect(!edges.contains(SkeletonEdge(start: .leftKnee, end: .leftAnkle)))
    }

    @Test func aBoneIsIncludedWhenBothJointsArePresent() {
        let landmarks = [
            Landmark(joint: .leftHip, x: 0.4, y: 0.5, confidence: 1)!,
            Landmark(joint: .leftKnee, x: 0.4, y: 0.3, confidence: 0.2)!,
            Landmark(joint: .leftAnkle, x: 0.4, y: 0.1, confidence: 1)!,
        ]

        let edges = SkeletonEdges.visible(in: landmarks)

        #expect(edges.contains(SkeletonEdge(start: .leftHip, end: .leftKnee)))
        #expect(edges.contains(SkeletonEdge(start: .leftKnee, end: .leftAnkle)))
    }
}
