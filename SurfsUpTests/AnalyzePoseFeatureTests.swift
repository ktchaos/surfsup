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
                    continuation.yield(.finished(timeline, evidenceMissing: false))
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
        await store.receive(.analysisFinished(timeline, evidenceMissing: false)) {
            $0.session.run = self.finished(clip: clip, timeline: timeline)
            $0.session.evidenceMissing = false
        }
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

    private func sampleClip() -> SelectedClip {
        SelectedClip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(fileURLWithPath: "/tmp/clip.mov"),
            duration: 2,
            nominalFrameRate: 30,
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
