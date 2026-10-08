import Testing
@testable import SurfsUp

struct ProminentBodyTests {
    @Test func largestBoxWinsEvenWhenItsObservationConfidenceIsLower() {
        let small = ProminentBody.Candidate(
            observationConfidence: 0.95,
            resultIndex: 0,
            landmarks: [point(.nose, 0, 0), point(.leftAnkle, 0.2, 0.2)]
        )
        let large = ProminentBody.Candidate(
            observationConfidence: 0.2,
            resultIndex: 1,
            landmarks: [point(.nose, 0, 0), point(.rightAnkle, 0.5, 0.5)]
        )

        let winner = ProminentBody.select([small, large])

        #expect(winner?.landmarks.contains { $0.joint == .rightAnkle } == true)
        #expect(winner?.selectionArea == 0.25)
    }

    @Test func equalAreaUsesHigherObservationConfidence() {
        let low = ProminentBody.Candidate(
            observationConfidence: 0.2,
            resultIndex: 0,
            landmarks: [point(.nose, 0, 0), point(.leftAnkle, 0.4, 0.4)]
        )
        let high = ProminentBody.Candidate(
            observationConfidence: 0.9,
            resultIndex: 1,
            landmarks: [point(.nose, 0, 0), point(.rightAnkle, 0.4, 0.4)]
        )

        let winner = ProminentBody.select([low, high])

        #expect(winner?.landmarks.contains { $0.joint == .rightAnkle } == true)
    }

    @Test func equalAreaAndConfidenceUsesLowerResultIndex() {
        let first = ProminentBody.Candidate(
            observationConfidence: 0.5,
            resultIndex: 0,
            landmarks: [point(.nose, 0, 0), point(.leftWrist, 0.4, 0.4)]
        )
        let second = ProminentBody.Candidate(
            observationConfidence: 0.5,
            resultIndex: 1,
            landmarks: [point(.nose, 0, 0), point(.rightWrist, 0.4, 0.4)]
        )

        let winner = ProminentBody.select([second, first])

        #expect(winner?.landmarks.contains { $0.joint == .leftWrist } == true)
    }

    @Test func confidenceZeroIsNotALandmarkAndASmallConfidenceIsKept() {
        #expect(Landmark(joint: .nose, x: 0.5, y: 0.5, confidence: 0) == nil)
        let kept = Landmark(joint: .nose, x: 0.2, y: 0.3, confidence: 0.01)
        #expect(kept != nil)
        let winner = ProminentBody.select([
            ProminentBody.Candidate(observationConfidence: 1, resultIndex: 0, landmarks: kept.map { [$0] } ?? []),
        ])
        #expect(winner?.landmarks.first?.confidence == 0.01)
    }

    private func point(_ joint: JointName, _ x: Double, _ y: Double, _ confidence: Double = 1) -> Landmark {
        Landmark(joint: joint, x: x, y: y, confidence: confidence)!
    }
}
