import Foundation

/// A bone is a pair of joint names. Coordinates are not stored here.
nonisolated struct SkeletonEdge: Equatable, Sendable {
    var start: JointName
    var end: JointName
}

nonisolated enum SkeletonEdges {
    static let pairs: [SkeletonEdge] = [
        SkeletonEdge(start: .nose, end: .neck),
        SkeletonEdge(start: .leftEye, end: .nose),
        SkeletonEdge(start: .rightEye, end: .nose),
        SkeletonEdge(start: .leftEar, end: .leftEye),
        SkeletonEdge(start: .rightEar, end: .rightEye),
        SkeletonEdge(start: .neck, end: .leftShoulder),
        SkeletonEdge(start: .neck, end: .rightShoulder),
        SkeletonEdge(start: .leftShoulder, end: .leftElbow),
        SkeletonEdge(start: .leftElbow, end: .leftWrist),
        SkeletonEdge(start: .rightShoulder, end: .rightElbow),
        SkeletonEdge(start: .rightElbow, end: .rightWrist),
        SkeletonEdge(start: .leftShoulder, end: .leftHip),
        SkeletonEdge(start: .rightShoulder, end: .rightHip),
        SkeletonEdge(start: .neck, end: .root),
        SkeletonEdge(start: .root, end: .leftHip),
        SkeletonEdge(start: .root, end: .rightHip),
        SkeletonEdge(start: .leftHip, end: .leftKnee),
        SkeletonEdge(start: .leftKnee, end: .leftAnkle),
        SkeletonEdge(start: .rightHip, end: .rightKnee),
        SkeletonEdge(start: .rightKnee, end: .rightAnkle),
    ]

    /// Bones whose two joints are both present. A missing end drops the bone.
    static func visible(in landmarks: [Landmark]) -> [SkeletonEdge] {
        let present = Set(landmarks.map(\.joint))
        return pairs.filter { present.contains($0.start) && present.contains($0.end) }
    }
}
