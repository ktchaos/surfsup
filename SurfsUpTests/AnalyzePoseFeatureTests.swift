import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
@testable import SurfsUp

@MainActor
struct AnalyzePoseFeatureTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func startIsIgnoredUntilAVideoIsSelected() async {
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.startTapped)
        #expect(store.state.screen == .empty)
    }

    @Test func selectRunsProgressAndReviewCanPlayPauseAndScrub() async {
        let clip = sampleClip()
        let timeline = sampleTimeline(duration: clip.duration)
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.poseAnalysisClient.analyze = { received, schedule in
                #expect(received.id == clip.id)
                #expect(schedule == .everyFrame)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.progress(framesCompleted: 1, framesTotal: nil))
                    continuation.yield(.finished(timeline, evidenceMissing: false, savedRunID: nil))
                    continuation.finish()
                }
            }
        }

        await store.send(.selectVideo(clip)) {
            $0.session.clip = clip
        }
        await store.send(.startTapped) {
            $0.session.run = self.running(clip: clip, framesCompleted: 0)
        }
        await store.receive(.progressUpdated(framesCompleted: 1, framesTotal: nil)) {
            $0.session.run = self.running(clip: clip, framesCompleted: 1)
        }
        await store.receive(.analysisFinished(timeline, evidenceMissing: false, savedRunID: nil)) {
            $0.session.run = self.finished(clip: clip, timeline: timeline)
            $0.session.evidenceMissing = false
        }
        await store.receive(.savedRunsLoaded([]))
        #expect(store.state.screen == .review)
        let playhead = TimeInterval(1)
        await store.send(.playTapped) {
            $0.isPlaying = true
        }
        await store.send(.pauseTapped) {
            $0.isPlaying = false
        }
        await store.send(.playheadMoved(playhead)) {
            $0.playhead = playhead
        }
        #expect(PlayheadLookup.observation(at: store.state.playhead, in: timeline)?.start == 1)
    }

    @Test func progressCadenceIsAtLeastAsOftenAsTheNamedInterval() {
        #expect(UIConstants.AnalyzePose.progressInterval == 2)
        #expect(UIConstants.AnalyzePose.cancelBound == 1)
        var cadence = ProgressCadence(interval: UIConstants.AnalyzePose.progressInterval)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let first = cadence.shouldPublish(at: start)
        let second = cadence.shouldPublish(at: start.addingTimeInterval(2))
        let third = cadence.shouldPublish(at: start.addingTimeInterval(4))
        #expect(first)
        #expect(second)
        #expect(third)
    }

    @Test func cancelReturnsToTheSelectedClipWithoutATimeline() async {
        let clip = sampleClip()
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.poseAnalysisClient.analyze = { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.progress(framesCompleted: 1, framesTotal: nil))
                }
            }
        }

        await store.send(.selectVideo(clip)) {
            $0.session.clip = clip
        }
        await store.send(.startTapped) {
            $0.session.run = self.running(clip: clip, framesCompleted: 0)
        }
        await store.receive(.progressUpdated(framesCompleted: 1, framesTotal: nil)) {
            $0.session.run = self.running(clip: clip, framesCompleted: 1)
        }
        await store.send(.cancelTapped) {
            $0.session.run = self.cancelled(clip: clip, framesCompleted: 1)
        }
        #expect(store.state.screen == .ready)
        #expect(store.state.session.run?.timeline == nil)
        #expect(store.state.session.run?.phase == .cancelled)
    }

    @Test func failureDoesNotEnterReviewOrKeepATimeline() async {
        let clip = sampleClip()
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.poseAnalysisClient.analyze = { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unreadableAsset)
                }
            }
        }

        await store.send(.selectVideo(clip)) {
            $0.session.clip = clip
        }
        await store.send(.startTapped) {
            $0.session.run = self.running(clip: clip, framesCompleted: 0)
        }
        await store.receive(.analysisFailed("analysisFailed")) {
            $0.session.run = self.failed(clip: clip)
        }
        #expect(store.state.screen == .failed)
        #expect(store.state.session.run?.timeline == nil)
        #expect(store.state.session.evidenceMissing == false)
    }

    @Test func stepForwardMovesOneFrame() async {
        let store = TestStore(initialState: reviewState(playhead: 1)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepForwardTapped) {
            $0.playhead = 1 + 1.0 / 30
        }
    }

    @Test func stepBackwardWhilePlayingPausesAndMovesInOneSend() async {
        let store = TestStore(initialState: reviewState(playhead: 1, isPlaying: true)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepBackwardTapped) {
            $0.isPlaying = false
            $0.playhead = 1 - 1.0 / 30
        }
    }

    @Test func stepsOutsideReviewDoNothing() async {
        var ready = AnalyzePoseFeature.State()
        ready.session.clip = sampleClip()
        let store = TestStore(initialState: ready) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepForwardTapped)
        await store.send(.stepBackwardTapped)
    }

    @Test func stepsDoNothingWhenTheClipHasNoFrameRate() async {
        let store = TestStore(initialState: reviewState(nominalFrameRate: 0)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepForwardTapped)
        await store.send(.stepBackwardTapped)
    }

    @Test func steppingBackwardAtTheStartDoesNothing() async {
        let store = TestStore(initialState: reviewState(playhead: 0)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepBackwardTapped)
    }

    @Test func steppingForwardAtTheEndDoesNothing() async {
        let clip = sampleClip()
        let store = TestStore(initialState: reviewState(playhead: clip.duration)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepForwardTapped)
    }

    @Test func aStepThatWouldPassTheEndLandsOnTheEnd() async {
        let clip = sampleClip()
        let store = TestStore(initialState: reviewState(playhead: clip.duration - 1.0 / 60)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepForwardTapped) {
            $0.playhead = clip.duration
        }
    }

    @Test func aStepIntoAGapLeavesTheTimelineUnchanged() async {
        let timeline = sampleTimeline(duration: 2)
        let store = TestStore(initialState: reviewState(playhead: 1 - 1.0 / 60)) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.stepForwardTapped) {
            $0.playhead = 1 - 1.0 / 60 + 1.0 / 30
        }
        #expect(store.state.session.run?.timeline == timeline)
    }

    @Test func appearedLoadsSavedRunsAndDoesNotOpenAReview() async {
        let summary = SavedRunSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            displayName: "wave.mov",
            finishedAt: now,
            clipDuration: 2
        )
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.list = { [summary] }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        await store.send(.appeared)
        await store.receive(.savedRunsLoaded([summary])) {
            $0.savedRuns = [summary]
        }
        #expect(store.state.screen != .review)
    }

    @Test func reopenTappedReachesReviewWithoutDetection() async {
        let clip = sampleClip()
        let timeline = sampleTimeline(duration: clip.duration)
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.open = { _ in .success((clip, timeline)) }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        await store.send(.reopenTapped(id))
        await store.receive(.reopenSucceeded(id, clip, timeline)) {
            $0.session.clip = clip
            $0.session.run = self.finished(clip: clip, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.notice = nil
            $0.openedSavedRunID = id
        }
        #expect(store.state.screen == .review)
        #expect(store.state.session.evidenceMissing == false)
        #expect(store.state.isPlaying == false)
        #expect(store.state.playhead == 0)
    }

    @Test func twoSavedRunsWithTheSameDurationOpenDifferentVideos() async {
        let first = sampleClip()
        let second = SelectedClip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            url: URL(fileURLWithPath: "/tmp/other-clip.mov"),
            duration: first.duration,
            nominalFrameRate: 30,
            displaySize: first.displaySize,
            displayTransform: .identity
        )!
        let timeline = sampleTimeline(duration: first.duration)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        #expect(first.duration == second.duration)
        #expect(first.url != second.url)
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.open = { id in
                id == firstID ? .success((first, timeline)) : .success((second, timeline))
            }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        await store.send(.reopenTapped(firstID))
        await store.receive(.reopenSucceeded(firstID, first, timeline)) {
            $0.session.clip = first
            $0.session.run = self.finished(clip: first, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.notice = nil
            $0.openedSavedRunID = firstID
        }
        await store.send(.reopenTapped(secondID))
        await store.receive(.reopenSucceeded(secondID, second, timeline)) {
            $0.session.clip = second
            $0.session.run = self.finished(clip: second, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.notice = nil
            $0.openedSavedRunID = secondID
        }
        #expect(store.state.session.clip?.url == second.url)
    }

    @Test func reopenFailedExplainsWithoutEnteringReview() async {
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.open = { _ in .failure(.videoUnavailable) }
        }

        await store.send(.reopenTapped(UUID(uuidString: "00000000-0000-0000-0000-000000000023")!))
        await store.receive(.reopenFailed) {
            $0.notice = "videoUnavailable"
        }
        #expect(store.state.screen != .review)
    }

    @Test func reopenIsIgnoredWhileAnalysisIsRunning() async {
        let clip = sampleClip()
        let other = SelectedClip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            url: URL(fileURLWithPath: "/tmp/running-other.mov"),
            duration: clip.duration,
            nominalFrameRate: 30,
            displaySize: clip.displaySize,
            displayTransform: .identity
        )!
        let timeline = sampleTimeline(duration: clip.duration)
        var running = AnalyzePoseFeature.State()
        running.session.clip = clip
        running.session.run = self.running(clip: clip, framesCompleted: 1)
        let store = TestStore(initialState: running) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.open = { _ in .success((other, timeline)) }
        }

        await store.send(.reopenTapped(UUID(uuidString: "00000000-0000-0000-0000-000000000024")!))
        await store.send(.reopenSucceeded(
            UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            other,
            timeline
        ))
        await store.send(.reopenFailed)
        #expect(store.state.session.kind == .running)
        #expect(store.state.session.clip == clip)
    }

    @Test func reopenSucceededReplacesTheClipAlreadyOnScreen() async {
        let replacement = SelectedClip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            url: URL(fileURLWithPath: "/tmp/replacement.mov"),
            duration: 2,
            nominalFrameRate: 30,
            displaySize: CGSize(width: 1920, height: 1080),
            displayTransform: .identity
        )!
        let timeline = sampleTimeline(duration: replacement.duration)
        let store = TestStore(initialState: reviewState()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000026")!
        await store.send(.reopenSucceeded(id, replacement, timeline)) {
            $0.session.clip = replacement
            $0.session.run = self.finished(clip: replacement, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.notice = nil
            $0.openedSavedRunID = id
        }
        #expect(store.state.session.clip?.url == replacement.url)
    }

    @Test func savedRunsLoadedKeepsAnEarlierIdAfterSelectVideo() async {
        let clip = sampleClip()
        let summary = SavedRunSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            displayName: "earlier.mov",
            finishedAt: now,
            clipDuration: 2
        )
        var initial = AnalyzePoseFeature.State()
        initial.savedRuns = [summary]
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.selectVideo(clip)) {
            $0.session.clip = clip
        }
        await store.send(.savedRunsLoaded([summary]))
        #expect(store.state.savedRuns.map(\.id) == [summary.id])
    }

    @Test func deleteTappedSetsPendingDeletionAndDoesNotRemove() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let summary = SavedRunSummary(
            id: id,
            displayName: "keep.mov",
            finishedAt: now,
            clipDuration: 2
        )
        var initial = AnalyzePoseFeature.State()
        initial.savedRuns = [summary]
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { _ in
                Issue.record("persistenceClient.remove was called")
                return false
            }
        }

        await store.send(.deleteTapped(id)) {
            $0.pendingDeletionID = id
        }
        #expect(store.state.savedRuns == [summary])
        #expect(store.state.pendingDeletionID == id)
    }

    @Test func deleteDeclinedClearsPendingDeletionAndLeavesSavedRuns() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let summary = SavedRunSummary(
            id: id,
            displayName: "stay.mov",
            finishedAt: now,
            clipDuration: 2
        )
        var initial = AnalyzePoseFeature.State()
        initial.savedRuns = [summary]
        initial.pendingDeletionID = id
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { _ in
                Issue.record("persistenceClient.remove was called")
                return false
            }
        }

        await store.send(.deleteDeclined) {
            $0.pendingDeletionID = nil
        }
        #expect(store.state.savedRuns == [summary])
    }

    @Test func deleteConfirmedReloadsSavedRunsWithoutThatId() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        let removed = SavedRunSummary(
            id: id,
            displayName: "gone.mov",
            finishedAt: now,
            clipDuration: 2
        )
        let kept = SavedRunSummary(
            id: otherID,
            displayName: "kept.mov",
            finishedAt: now,
            clipDuration: 2
        )
        var initial = AnalyzePoseFeature.State()
        initial.savedRuns = [removed, kept]
        initial.pendingDeletionID = id
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { received in
                #expect(received == id)
                return true
            }
            $0.persistenceClient.list = { [kept] }
            $0.persistenceClient.open = { _ in
                Issue.record("persistenceClient.open was called")
                return .failure(.videoUnavailable)
            }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        await store.send(.deleteConfirmed)
        await store.receive(.deleteResolved(id: id, removed: true, runs: [kept])) {
            $0.savedRuns = [kept]
            $0.pendingDeletionID = nil
        }
        #expect(store.state.pendingDeletionID == nil)
        #expect(store.state.savedRuns.map(\.id) == [otherID])
    }

    @Test func reopenSucceededRecordsTheSavedRunID() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let clip = sampleClip()
        let timeline = sampleTimeline(duration: clip.duration)
        let store = TestStore(initialState: AnalyzePoseFeature.State()) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.reopenSucceeded(id, clip, timeline)) {
            $0.openedSavedRunID = id
            $0.session.clip = clip
            $0.session.run = self.finished(clip: clip, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.notice = nil
        }
    }

    @Test func deletingADifferentRunLeavesTheReviewOnScreen() async {
        let onScreen = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let other = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let clip = sampleClip()
        let kept = SavedRunSummary(
            id: onScreen,
            displayName: "a.mov",
            finishedAt: now,
            clipDuration: clip.duration
        )
        var initial = reviewState()
        initial.openedSavedRunID = onScreen
        initial.savedRuns = [
            kept,
            SavedRunSummary(
                id: other,
                displayName: "b.mov",
                finishedAt: now,
                clipDuration: clip.duration
            ),
        ]
        initial.pendingDeletionID = other
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { received in
                #expect(received == other)
                return true
            }
            $0.persistenceClient.list = { [kept] }
            $0.persistenceClient.open = { _ in
                Issue.record("persistenceClient.open was called")
                return .failure(.videoUnavailable)
            }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        await store.send(.deleteConfirmed)
        await store.receive(.deleteResolved(id: other, removed: true, runs: [kept])) {
            $0.savedRuns = [kept]
            $0.pendingDeletionID = nil
        }
        #expect(store.state.screen == .review)
        #expect(store.state.session.clip?.url == clip.url)
        #expect(store.state.openedSavedRunID == onScreen)
    }

    @Test func deletingTheOnScreenRunClearsTheReviewWithoutOpeningAnother() async {
        let onScreen = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        let summary = SavedRunSummary(
            id: onScreen,
            displayName: "visible.mov",
            finishedAt: now,
            clipDuration: 2
        )
        var initial = reviewState()
        initial.openedSavedRunID = onScreen
        initial.savedRuns = [summary]
        initial.pendingDeletionID = onScreen
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { received in
                #expect(received == onScreen)
                return true
            }
            $0.persistenceClient.list = { [] }
            $0.persistenceClient.open = { _ in
                Issue.record("persistenceClient.open was called")
                return .failure(.videoUnavailable)
            }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        await store.send(.deleteConfirmed)
        await store.receive(.deleteResolved(id: onScreen, removed: true, runs: [])) {
            $0.savedRuns = []
            $0.pendingDeletionID = nil
            $0.session.clip = nil
            $0.session.run = nil
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.notice = nil
            $0.openedSavedRunID = nil
        }
        #expect(store.state.screen != .review)
        #expect(store.state.openedSavedRunID == nil)
    }

    @Test func analysisFinishedRecordsTheSavedRunIDAndNilClearsIt() async {
        let clip = sampleClip()
        let timeline = sampleTimeline(duration: clip.duration)
        let previous = UUID(uuidString: "00000000-0000-0000-0000-000000000045")!
        let savedID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        var initial = AnalyzePoseFeature.State()
        initial.session.clip = clip
        initial.session.run = running(clip: clip, framesCompleted: 1)
        initial.openedSavedRunID = previous
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.list = { [] }
        }

        await store.send(.analysisFinished(timeline, evidenceMissing: false, savedRunID: savedID)) {
            $0.session.run = self.finished(clip: clip, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.openedSavedRunID = savedID
        }
        await store.receive(.savedRunsLoaded([]))

        initial.session.run = running(clip: clip, framesCompleted: 1)
        initial.openedSavedRunID = savedID
        let clearing = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.list = { [] }
        }
        await clearing.send(.analysisFinished(timeline, evidenceMissing: false, savedRunID: nil)) {
            $0.session.run = self.finished(clip: clip, timeline: timeline)
            $0.session.evidenceMissing = false
            $0.isPlaying = false
            $0.playhead = 0
            $0.openedSavedRunID = nil
        }
        await clearing.receive(.savedRunsLoaded([]))
    }

    @Test func selectVideoCancelAndFailureClearOpenedSavedRunID() async {
        let clip = sampleClip()
        let savedID = UUID(uuidString: "00000000-0000-0000-0000-000000000046")!
        var reviewing = reviewState()
        reviewing.openedSavedRunID = savedID
        let selecting = TestStore(initialState: reviewing) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        await selecting.send(.selectVideo(clip)) {
            $0.session.run = nil
            $0.openedSavedRunID = nil
        }

        var runningState = AnalyzePoseFeature.State()
        runningState.session.clip = clip
        runningState.session.run = running(clip: clip, framesCompleted: 0)
        runningState.openedSavedRunID = savedID
        let cancelling = TestStore(initialState: runningState) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        await cancelling.send(.cancelTapped) {
            $0.session.run = self.cancelled(clip: clip, framesCompleted: 0)
            $0.openedSavedRunID = nil
        }

        runningState.openedSavedRunID = savedID
        runningState.session.run = running(clip: clip, framesCompleted: 0)
        let failing = TestStore(initialState: runningState) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        await failing.send(.analysisFailed("analysisFailed")) {
            $0.session.run = self.failed(clip: clip)
            $0.openedSavedRunID = nil
        }
    }

    @Test func deleteIsIgnoredWhileAnalysisIsRunning() async {
        let clip = sampleClip()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000050")!
        var initial = AnalyzePoseFeature.State()
        initial.session.clip = clip
        initial.session.run = running(clip: clip, framesCompleted: 1)
        initial.savedRuns = [
            SavedRunSummary(id: id, displayName: "running.mov", finishedAt: now, clipDuration: 2),
        ]
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { _ in
                Issue.record("persistenceClient.remove was called")
                return true
            }
        }

        await store.send(.deleteTapped(id))
        await store.send(.deleteDeclined)
        await store.send(.deleteConfirmed)
        #expect(store.state.pendingDeletionID == nil)
        #expect(store.state.session.kind == .running)
        #expect(store.state.session.clip == clip)
    }

    @Test func failedRemoveKeepsTheSessionAndTheSavedRun() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let clip = sampleClip()
        let summary = SavedRunSummary(
            id: id,
            displayName: "still.mov",
            finishedAt: now,
            clipDuration: clip.duration
        )
        var initial = reviewState(playhead: 1)
        initial.openedSavedRunID = id
        initial.savedRuns = [summary]
        initial.pendingDeletionID = id
        let store = TestStore(initialState: initial) {
            AnalyzePoseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.persistenceClient.remove = { received in
                #expect(received == id)
                return false
            }
            $0.persistenceClient.list = { [summary] }
            $0.persistenceClient.open = { _ in
                Issue.record("persistenceClient.open was called")
                return .failure(.videoUnavailable)
            }
            $0.poseAnalysisClient.analyze = { _, _ in
                Issue.record("poseAnalysisClient.analyze was called")
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: PoseAnalysisError.unimplemented)
                }
            }
        }

        await store.send(.deleteConfirmed)
        await store.receive(.deleteResolved(id: id, removed: false, runs: [summary])) {
            $0.pendingDeletionID = nil
            $0.notice = "deleteFailed"
        }
        #expect(store.state.openedSavedRunID == id)
        #expect(store.state.session.clip?.url == clip.url)
        #expect(store.state.playhead == 1)
        #expect(store.state.savedRuns.map(\.id) == [id])
        #expect(store.state.screen == .review)
    }

    private func reviewState(
        playhead: TimeInterval = 0,
        isPlaying: Bool = false,
        nominalFrameRate: Float = 30
    ) -> AnalyzePoseFeature.State {
        let clip = sampleClip(nominalFrameRate: nominalFrameRate)
        let timeline = sampleTimeline(duration: clip.duration)
        var state = AnalyzePoseFeature.State()
        state.session.clip = clip
        state.session.run = finished(clip: clip, timeline: timeline)
        state.playhead = playhead
        state.isPlaying = isPlaying
        return state
    }

    private func sampleClip(nominalFrameRate: Float = 30) -> SelectedClip {
        SelectedClip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(fileURLWithPath: "/tmp/clip.mov"),
            duration: 2,
            nominalFrameRate: nominalFrameRate,
            displaySize: CGSize(width: 1920, height: 1080),
            displayTransform: .identity
        )!
    }

    private func sampleTimeline(duration: TimeInterval) -> PoseTimeline {
        let landmark = Landmark(joint: .nose, x: 0.5, y: 0.5, confidence: 1)!
        let body = BodyObservation(landmarks: [landmark], selectionArea: 0)!
        let first = FrameObservation(start: 0, end: 1, clipDuration: duration, body: body)!
        let second = FrameObservation(start: 1, end: duration, clipDuration: duration, body: nil)!
        return PoseTimeline(clipDuration: duration, observations: [first, second])!
    }

    private func running(clip: SelectedClip, framesCompleted: Int) -> AnalysisRun {
        AnalysisRun(
            clip: clip,
            phase: .running,
            framesCompleted: framesCompleted,
            framesTotal: nil,
            startedAt: now,
            finishedAt: nil,
            timeline: nil,
            failure: nil
        )!
    }

    private func finished(clip: SelectedClip, timeline: PoseTimeline) -> AnalysisRun {
        AnalysisRun(
            clip: clip,
            phase: .finished,
            framesCompleted: timeline.observations.count,
            framesTotal: timeline.observations.count,
            startedAt: now,
            finishedAt: now,
            timeline: timeline,
            failure: nil
        )!
    }

    private func cancelled(clip: SelectedClip, framesCompleted: Int) -> AnalysisRun {
        AnalysisRun(
            clip: clip,
            phase: .cancelled,
            framesCompleted: framesCompleted,
            framesTotal: nil,
            startedAt: now,
            finishedAt: now,
            timeline: nil,
            failure: nil
        )!
    }

    private func failed(clip: SelectedClip) -> AnalysisRun {
        AnalysisRun(
            clip: clip,
            phase: .failed,
            framesCompleted: 0,
            framesTotal: nil,
            startedAt: now,
            finishedAt: now,
            timeline: nil,
            failure: "analysisFailed"
        )!
    }
}
