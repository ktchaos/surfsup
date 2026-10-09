import Testing
@testable import SurfsUp

struct PlayheadLookupTests {
    @Test func halfOpenRangeIncludesTheStartAndExcludesTheEnd() {
        let timeline = sampleTimeline()

        #expect(PlayheadLookup.observation(at: 0, in: timeline)?.start == 0)
        #expect(PlayheadLookup.observation(at: 0.5, in: timeline)?.start == 0)
        #expect(PlayheadLookup.observation(at: 1, in: timeline)?.start == 1)
        #expect(PlayheadLookup.observation(at: 1.5, in: timeline)?.start == 1)
    }

    @Test func aTimeOutsideTheTimelineReturnsNoObservation() {
        let timeline = sampleTimeline()

        #expect(PlayheadLookup.observation(at: -0.01, in: timeline) == nil)
        #expect(PlayheadLookup.observation(at: 2, in: timeline) == nil)
        #expect(PlayheadLookup.observation(at: 3, in: timeline) == nil)
    }

    private func sampleTimeline() -> PoseTimeline {
        let duration: Double = 2
        let first = FrameObservation(start: 0, end: 1, clipDuration: duration, body: nil)!
        let second = FrameObservation(start: 1, end: 2, clipDuration: duration, body: nil)!
        return PoseTimeline(clipDuration: duration, observations: [first, second])!
    }
}
