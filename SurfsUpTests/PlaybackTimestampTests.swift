import Testing
@testable import SurfsUp

struct PlaybackTimestampTests {
    @Test func formatsWholeSecondsAndFractionalSeconds() {
        #expect(PlaybackTimestamp.label(for: 2) == "00:02.000")
        #expect(PlaybackTimestamp.label(for: 12.45) == "00:12.450")
    }

    @Test func roundsToTheNearestMillisecond() {
        #expect(PlaybackTimestamp.label(for: 12.4504) == "00:12.450")
        #expect(PlaybackTimestamp.label(for: 12.4505) == "00:12.451")
    }

    @Test func carriesMinutes() {
        #expect(PlaybackTimestamp.label(for: 65.001) == "01:05.001")
        #expect(PlaybackTimestamp.label(for: 0) == "00:00.000")
    }

    @Test func nonFiniteOrNegativeTimeIsZero() {
        #expect(PlaybackTimestamp.label(for: -0.2) == "00:00.000")
        #expect(PlaybackTimestamp.label(for: .nan) == "00:00.000")
        #expect(PlaybackTimestamp.label(for: .infinity) == "00:00.000")
    }
}
