import Foundation

/// Joints a 2D body-pose detector can return. These names are not surf events or board parts.
nonisolated enum JointName: String, Codable, CaseIterable, Equatable, Sendable {
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case root
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}
