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
            seekTolerance: tolerance,
            frameDuration: nil
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
            seekTolerance: tolerance,
            frameDuration: nil
        )
        let playing = PlaybackSync.command(
            itemReady: true,
            isPlaying: true,
            playhead: 0,
            currentTime: 3.57,
            hasAlignedStart: false,
            seekTolerance: tolerance,
            frameDuration: nil
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
            seekTolerance: tolerance,
            frameDuration: nil
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
            seekTolerance: tolerance,
            frameDuration: nil
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
            seekTolerance: tolerance,
            frameDuration: nil
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
            seekTolerance: tolerance,
            frameDuration: 1.0 / 30
        )
        #expect(
            command == PlaybackSync.Command(
                transport: .pause,
                seek: PlaybackSync.Seek(time: 0, precision: .startOfClip),
                markStartAligned: true
            )
        )
    }

    @Test func pausedSeekThresholdIsHalfAFrameOrTheStartTolerance() {
        #expect(PlaybackSync.pausedSeekThreshold(frameDuration: 1.0 / 30, seekTolerance: tolerance) == 1.0 / 60)
        #expect(PlaybackSync.pausedSeekThreshold(frameDuration: nil, seekTolerance: tolerance) == tolerance)
    }

    @Test func aPausedStepOfOneFrameSeeksExactly() {
        let frame = 1.0 / 30
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 1.5,
            currentTime: 1.5 - frame,
            hasAlignedStart: true,
            seekTolerance: tolerance,
            frameDuration: frame
        )
        #expect(
            command == PlaybackSync.Command(
                transport: .pause,
                seek: PlaybackSync.Seek(time: 1.5, precision: .exactFrame),
                markStartAligned: true
            )
        )
    }

    @Test func aPausedDriftOfAQuarterFrameDoesNotSeek() {
        let frame = 1.0 / 30
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 1.5,
            currentTime: 1.5 + frame / 4,
            hasAlignedStart: true,
            seekTolerance: tolerance,
            frameDuration: frame
        )
        #expect(command.seek == nil)
        #expect(command.transport == .pause)
    }

    @Test func steppingOffTheFirstFrameSeeksInexactlyToThatFrame() {
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 1.0 / 30,
            currentTime: 0,
            hasAlignedStart: true,
            seekTolerance: tolerance,
            frameDuration: 1.0 / 30
        )
        #expect(
            command == PlaybackSync.Command(
                transport: .pause,
                seek: PlaybackSync.Seek(time: 1.0 / 30, precision: .startOfClip),
                markStartAligned: true
            )
        )
    }

    @Test func steppingBackToZeroSeeksInexactlyToZero() {
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: false,
            playhead: 0,
            currentTime: 1.0 / 30,
            hasAlignedStart: true,
            seekTolerance: tolerance,
            frameDuration: 1.0 / 30
        )
        #expect(
            command == PlaybackSync.Command(
                transport: .pause,
                seek: PlaybackSync.Seek(time: 0, precision: .startOfClip),
                markStartAligned: true
            )
        )
    }

    @Test func playingOneFrameApartDoesNotSeek() {
        let frame = 1.0 / 30
        let command = PlaybackSync.command(
            itemReady: true,
            isPlaying: true,
            playhead: 1.5,
            currentTime: 1.5 - frame,
            hasAlignedStart: true,
            seekTolerance: tolerance,
            frameDuration: frame
        )
        #expect(command.seek == nil)
        #expect(command.transport == .play)
    }
}
