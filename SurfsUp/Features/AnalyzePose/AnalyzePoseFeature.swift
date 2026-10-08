import ComposableArchitecture
import Foundation

@Reducer
struct AnalyzePoseFeature {
    @ObservableState
    struct State: Equatable {
        var access: Access = .unknown
        var session = AnalysisSession()
        var isPlaying = false
        var playhead: TimeInterval = 0
        var isPickerPresented = false
        var notice: String?

        enum Access: Equatable {
            case unknown
            case granted
            case denied
        }

        enum Screen: Equatable {
            case needsAccess
            case empty
            case ready
            case running
            case review
            case failed
        }

        var screen: Screen {
            if access == .denied, session.clip == nil, session.run == nil {
                return .needsAccess
            }
            switch session.kind {
            case .empty:
                return .empty
            case .ready:
                return .ready
            case .running:
                return .running
            case .review:
                return .review
            case .failed:
                return .failed
            }
        }
    }

    enum Delegate: Equatable {
        case reviewReady
    }

    enum Action: Equatable {
        case chooseTapped
        case accessResolved(PhotoLibraryAccess)
        case pickerPresentedChanged(Bool)
        case pickerDismissed
        case videoURLPicked(URL)
        case selectVideo(SelectedClip)
        case startTapped
        case cancelTapped
        case progressUpdated(framesCompleted: Int, framesTotal: Int?)
        case analysisFinished(PoseTimeline, evidenceMissing: Bool)
        case analysisFailed(String)
        case playTapped
        case pauseTapped
        case playheadMoved(TimeInterval)
        case delegate(Delegate)
    }

    @Dependency(\.poseAnalysisClient) var poseAnalysisClient
    @Dependency(\.photoLibraryClient) var photoLibraryClient
    @Dependency(\.date) var date

    private nonisolated enum CancelID: Hashable, Sendable {
        case analysis
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .chooseTapped:
                state.notice = nil
                return .run { [photoLibraryClient] send in
                    let access = await photoLibraryClient.authorization()
                    await send(.accessResolved(access))
                }

            case .accessResolved(.denied):
                state.access = .denied
                state.isPickerPresented = false
                return .none

            case .accessResolved(.granted):
                state.access = .granted
                state.isPickerPresented = true
                return .none

            case .pickerPresentedChanged(let presented):
                state.isPickerPresented = presented
                return presented ? .none : .send(.pickerDismissed)

            case .pickerDismissed:
                return .none

            case .videoURLPicked(let url):
                state.isPickerPresented = false
                return .run { [photoLibraryClient] send in
                    do {
                        let clip = try await photoLibraryClient.makeClip(url)
                        await send(.selectVideo(clip))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.analysisFailed("analysisFailed"))
                    }
                }

            case .selectVideo(let clip):
                state.session.clip = clip
                state.session.run = nil
                state.session.evidenceMissing = false
                state.isPlaying = false
                state.playhead = 0
                state.notice = nil
                state.isPickerPresented = false
                return .cancel(id: CancelID.analysis)

            case .startTapped:
                guard state.session.kind == .ready, let clip = state.session.clip else { return .none }
                guard let run = AnalysisRun(
                    clip: clip,
                    phase: .running,
                    framesCompleted: 0,
                    framesTotal: nil,
                    startedAt: date.now,
                    finishedAt: nil,
                    timeline: nil,
                    failure: nil
                ) else { return .none }
                state.session.run = run
                state.session.evidenceMissing = false
                state.isPlaying = false
                state.playhead = 0
                return .run { [poseAnalysisClient] send in
                    do {
                        for try await update in poseAnalysisClient.analyze(clip, .everyFrame) {
                            switch update {
                            case let .progress(framesCompleted, framesTotal):
                                await send(.progressUpdated(framesCompleted: framesCompleted, framesTotal: framesTotal))
                            case let .finished(timeline, evidenceMissing):
                                await send(.analysisFinished(timeline, evidenceMissing: evidenceMissing))
                            }
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.analysisFailed("analysisFailed"))
                    }
                }
                .cancellable(id: CancelID.analysis, cancelInFlight: true)

            case let .progressUpdated(framesCompleted, framesTotal):
                guard let run = state.session.run, run.phase == .running else { return .none }
                state.session.run = AnalysisRun(
                    clip: run.clip,
                    phase: .running,
                    framesCompleted: framesCompleted,
                    framesTotal: framesTotal,
                    startedAt: run.startedAt,
                    finishedAt: nil,
                    timeline: nil,
                    failure: nil
                )
                return .none

            case let .analysisFinished(timeline, evidenceMissing):
                guard let run = state.session.run, run.phase == .running else { return .none }
                state.session.run = AnalysisRun(
                    clip: run.clip,
                    phase: .finished,
                    framesCompleted: timeline.observations.count,
                    framesTotal: timeline.observations.count,
                    startedAt: run.startedAt,
                    finishedAt: date.now,
                    timeline: timeline,
                    failure: nil
                )
                state.session.evidenceMissing = evidenceMissing
                state.isPlaying = false
                state.playhead = 0
                return .none

            case let .analysisFailed(message):
                guard let run = state.session.run, run.phase == .running else {
                    state.notice = message
                    state.isPlaying = false
                    return .none
                }
                state.session.run = AnalysisRun(
                    clip: run.clip,
                    phase: .failed,
                    framesCompleted: run.framesCompleted,
                    framesTotal: run.framesTotal,
                    startedAt: run.startedAt,
                    finishedAt: date.now,
                    timeline: nil,
                    failure: message
                )
                state.session.evidenceMissing = false
                state.isPlaying = false
                return .none

            case .cancelTapped:
                guard let run = state.session.run, run.phase == .running else { return .none }
                state.session.run = AnalysisRun(
                    clip: run.clip,
                    phase: .cancelled,
                    framesCompleted: run.framesCompleted,
                    framesTotal: run.framesTotal,
                    startedAt: run.startedAt,
                    finishedAt: date.now,
                    timeline: nil,
                    failure: nil
                )
                state.session.evidenceMissing = false
                state.isPlaying = false
                return .cancel(id: CancelID.analysis)

            case .playTapped:
                guard state.session.kind == .review else { return .none }
                state.isPlaying = true
                return .none

            case .pauseTapped:
                guard state.session.kind == .review else { return .none }
                state.isPlaying = false
                return .none

            case let .playheadMoved(time):
                guard state.session.kind == .review, let duration = state.session.clip?.duration else { return .none }
                let upper = max(duration, 0)
                state.playhead = min(max(0, time), upper)
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
