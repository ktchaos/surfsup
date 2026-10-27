import Foundation
import Testing
@testable import SurfsUp

/// The frame duration and the step target. No video, no view, no `TestStore`.
struct FrameStepTests {
    private let frame = 1.0 / 30

    @Test func thirtyFramesPerSecondIsOneThirtieth() {
        #expect(FrameStep.duration(nominalFrameRate: 30) == 1.0 / 30)
    }

    @Test func sixtyFramesPerSecondIsOneSixtieth() {
        #expect(FrameStep.duration(nominalFrameRate: 60) == 1.0 / 60)
    }

    @Test func aRateThatIsNotPositiveHasNoDuration() {
        #expect(FrameStep.duration(nominalFrameRate: 0) == nil)
        #expect(FrameStep.duration(nominalFrameRate: -24) == nil)
        #expect(FrameStep.duration(nominalFrameRate: .nan) == nil)
        #expect(FrameStep.duration(nominalFrameRate: .infinity) == nil)
    }

    @Test func aStepAddsOrSubtractsOneFrame() {
        #expect(step(from: 1, .forward) == 1 + frame)
        #expect(step(from: 1, .backward) == 1 - frame)
    }

    @Test func aStepDoesNotSnapToAFrameGrid() {
        #expect(step(from: 0.5, .forward) == 0.5 + frame)
    }

    @Test func aStepStopsAtTheStart() {
        #expect(step(from: 0.02, .backward) == 0)
        #expect(step(from: 0, .backward) == 0)
    }

    @Test func aStepStopsAtTheEnd() {
        #expect(step(from: 1.99, .forward) == 2)
        #expect(step(from: 2, .forward) == 2)
        #expect(step(from: 2, .backward) == 2 - frame)
    }

    @Test func forwardThenBackwardReturnsToTheStart() {
        let forward = step(from: 0.5, .forward)
        let back = FrameStep.target(from: forward, direction: .backward, frameDuration: frame, clipDuration: 2)
        #expect(abs(back - 0.5) <= .ulpOfOne)
    }

    private func step(from playhead: TimeInterval, _ direction: FrameStep.Direction) -> TimeInterval {
        FrameStep.target(from: playhead, direction: direction, frameDuration: frame, clipDuration: 2)
    }
}
