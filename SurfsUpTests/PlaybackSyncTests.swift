import AVFoundation
import Foundation
import Testing
@testable import SurfsUp

/// Locks the initial-seek decision. These tests do not load the surf clips and do not
/// prove that AVPlayer honors the tolerance on trimmed media.
struct PlaybackSyncTests {
    private let tolerance = UIConstants.AnalyzePose.seekTolerance

    @Test func waitsUntilTheItemIsReady() {
        let command = PlaybackSync.command(
            itemReady: false,
            isPlaying: true,
            playhead: 0,
            currentTime: 4,
            hasAlignedStart: false,
            seekTolerance: tolerance
        )
        #expect(command == .wait)
    }

    @Test func initialSeekToZeroIsNotExact() {
        let paused = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 0,
            currentTime: 3.57,
            hasAlignedStart: false,
            seekTolerance: tolerance
        )
        let playing = PlaybackSync.command(
            itemReady: true,
            isPlaying: true,
            playhead: 0,
            currentTime: 3.57,
            hasAlignedStart: false,
            seekTolerance: tolerance
        )
        let expected = PlaybackSync.Command(
            transport: .pause,
            seek: PlaybackSync.Seek(time: 0, precision: .startOfClip),
            markStartAligned: false
        )
        #expect(paused == expected)
        #expect(playing == expected)
        let tolerances = PlaybackSync.tolerances(for: .startOfClip)
        #expect(tolerances.before == .positiveInfinity)
        #expect(tolerances.after == .zero)
    }

    @Test func alreadyAtTheStartDoesNotSeek() {
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: true,
            playhead: 0,
            currentTime: 0.01,
            hasAlignedStart: false,
            seekTolerance: tolerance
        )
        #expect(command.seek == nil)
        #expect(command.transport == .play)
        #expect(command.markStartAligned)
    }

    @Test func scrubUsesAnExactSeek() {
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 1.5,
            currentTime: 0,
            hasAlignedStart: true,
            seekTolerance: tolerance
        )
        #expect(
            command == PlaybackSync.Command(
                transport: .pause,
                seek: PlaybackSync.Seek(time: 1.5, precision: .exactFrame),
                markStartAligned: true
            )
        )
        let tolerances = PlaybackSync.tolerances(for: .exactFrame)
        #expect(tolerances.before == .zero)
        #expect(tolerances.after == .zero)
    }

    @Test func playingDoesNotSeek() {
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: true,
            playhead: 1.5,
            currentTime: 0,
            hasAlignedStart: true,
            seekTolerance: tolerance
        )
        #expect(command.seek == nil)
        #expect(command.transport == .play)
    }

    @Test func returningToZeroDoesNotUseAnExactSeek() {
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 0,
            currentTime: 3.57,
            hasAlignedStart: true,
            seekTolerance: tolerance
        )
        #expect(command.seek == nil)
        #expect(command.transport == .pause)
    }
}
