import Foundation

/// Baseline heuristic for keeping one body in a frame.
///
/// This is not identification of the surfer. The winner is the largest
/// axis-aligned box of valid joints, then the higher observation confidence,
/// then the lower result index. A person closer to the camera can beat the
/// surfer. How often that happens is measured in T031. There is no tracking
/// and no tap-to-select in this slice.
nonisolated enum ProminentBody {
    struct Candidate: Equatable, Sendable {
        var observationConfidence: Double
        var resultIndex: Int
        var landmarks: [Landmark]
    }

    static func area(of landmarks: [Landmark]) -> Double {
        guard let first = landmarks.first else { return 0 }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for landmark in landmarks.dropFirst() {
            minX = min(minX, landmark.x)
            maxX = max(maxX, landmark.x)
            minY = min(minY, landmark.y)
            maxY = max(maxY, landmark.y)
        }
        return (maxX - minX) * (maxY - minY)
    }

    static func select(_ candidates: [Candidate]) -> BodyObservation? {
        var winner: (candidate: Candidate, area: Double)?
        for candidate in candidates {
            guard !candidate.landmarks.isEmpty else { continue }
            let area = area(of: candidate.landmarks)
            guard let current = winner else {
                winner = (candidate, area)
                continue
            }
            let larger = area > current.area
            let sameArea = area == current.area
            let higherConfidence = candidate.observationConfidence > current.candidate.observationConfidence
            let sameConfidence = candidate.observationConfidence == current.candidate.observationConfidence
            let lowerIndex = candidate.resultIndex < current.candidate.resultIndex
            if larger || (sameArea && higherConfidence) || (sameArea && sameConfidence && lowerIndex) {
                winner = (candidate, area)
            }
        }
        guard let winner else { return nil }
        return BodyObservation(landmarks: winner.candidate.landmarks, selectionArea: winner.area)
    }
}
