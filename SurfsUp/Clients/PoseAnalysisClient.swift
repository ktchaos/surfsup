import AVFoundation
import ComposableArchitecture
import Foundation
import Vision

nonisolated enum AnalysisUpdate: Equatable, Sendable {
    case progress(framesCompleted: Int, framesTotal: Int?)
    case finished(PoseTimeline, evidenceMissing: Bool)
}

nonisolated enum PoseAnalysisError: Error, Equatable {
    case unreadableAsset
    case invalidTimeline
    case unimplemented
}

nonisolated struct PoseAnalysisClient: Sendable {
    var analyze: @Sendable (SelectedClip, FrameSchedule) -> AsyncThrowingStream<AnalysisUpdate, Error>

    static let live = PoseAnalysisClient { clip, schedule in
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    try await PoseAnalysisLive.run(clip: clip, schedule: schedule, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static let test = PoseAnalysisClient { _, _ in
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: PoseAnalysisError.unimplemented)
        }
    }
}

extension PoseAnalysisClient: DependencyKey {
    nonisolated static let liveValue = PoseAnalysisClient.live
    nonisolated static let testValue = PoseAnalysisClient.test
}

extension DependencyValues {
    var poseAnalysisClient: PoseAnalysisClient {
        get { self[PoseAnalysisClient.self] }
        set { self[PoseAnalysisClient.self] = newValue }
    }
}

nonisolated enum PoseAnalysisLive {
    static func run(
        clip: SelectedClip,
        schedule: FrameSchedule,
        continuation: AsyncThrowingStream<AnalysisUpdate, Error>.Continuation
    ) async throws {
        let started = Date()
        var cadence = ProgressCadence(interval: UIConstants.AnalyzePose.progressInterval)
        var drafts: [FrameDraft] = []
        var decodedCount = 0
        var attemptedCount = 0

        do {
            try await VideoFrameSource.forEachDecodedFrame(of: clip) { frame in
                if Task.isCancelled { throw CancellationError() }
                let index = decodedCount
                decodedCount += 1
                guard schedule.includes(frameIndex: index) else { return }
                attemptedCount += 1
                let body = BodyPoseDetector.body(
                    in: frame.pixelBuffer,
                    orientation: VideoFrameSource.imageOrientation(from: frame.preferredTransform)
                )
                drafts.append(FrameDraft(
                    start: frame.presentationTime,
                    duration: frame.duration,
                    body: body
                ))
                if cadence.shouldPublish(at: Date()) {
                    continuation.yield(.progress(framesCompleted: attemptedCount, framesTotal: nil))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PoseAnalysisError.unreadableAsset
        }

        if Task.isCancelled { throw CancellationError() }
        drafts.sort { $0.start < $1.start }
        guard decodedCount > 0, attemptedCount == drafts.count, attemptedCount > 0 else {
            throw PoseAnalysisError.invalidTimeline
        }

        let timeline: PoseTimeline
        do {
            timeline = try assembleTimeline(clip: clip, drafts: drafts)
        } catch {
            throw PoseAnalysisError.invalidTimeline
        }

        if Task.isCancelled { throw CancellationError() }
        let elapsed = Date().timeIntervalSince(started)
        guard let record = EvidenceRecord(
            timeline: timeline,
            elapsedSeconds: elapsed,
            decodedFrameCount: decodedCount,
            attemptedFrameCount: attemptedCount
        ) else {
            throw PoseAnalysisError.invalidTimeline
        }

        var evidenceMissing = false
        do {
            let url = try EvidenceFileWriter.write(record, to: EvidenceFileWriter.storageDirectory())
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: url)
                throw CancellationError()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            evidenceMissing = true
        }

        continuation.yield(.finished(timeline, evidenceMissing: evidenceMissing))
        continuation.finish()
    }

    private struct FrameDraft {
        var start: TimeInterval
        var duration: TimeInterval
        var body: BodyObservation?
    }

    private static func assembleTimeline(clip: SelectedClip, drafts: [FrameDraft]) throws -> PoseTimeline {
        var observations: [FrameObservation] = []
        for index in drafts.indices {
            let start = max(0, drafts[index].start)
            var end: TimeInterval
            if index + 1 < drafts.count {
                end = max(0, drafts[index + 1].start)
            } else {
                let proposed = start + max(drafts[index].duration, 0)
                end = min(clip.duration, proposed)
                if end <= start {
                    end = clip.duration
                }
            }
            if end > clip.duration {
                end = clip.duration
            }
            guard let observation = FrameObservation(
                start: start,
                end: end,
                clipDuration: clip.duration,
                body: drafts[index].body
            ) else {
                throw PoseAnalysisError.invalidTimeline
            }
            observations.append(observation)
        }
        guard let timeline = PoseTimeline(clipDuration: clip.duration, observations: observations) else {
            throw PoseAnalysisError.invalidTimeline
        }
        return timeline
    }
}

nonisolated enum BodyPoseDetector {
    static func body(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> BodyObservation? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let results = request.results ?? []
        let candidates = results.enumerated().compactMap { index, observation -> ProminentBody.Candidate? in
            let landmarks = landmarks(from: observation)
            guard !landmarks.isEmpty else { return nil }
            return ProminentBody.Candidate(
                observationConfidence: Double(observation.confidence),
                resultIndex: index,
                landmarks: landmarks
            )
        }
        return ProminentBody.select(candidates)
    }

    private static func landmarks(from observation: VNHumanBodyPoseObservation) -> [Landmark] {
        var landmarks: [Landmark] = []
        for joint in JointName.allCases {
            guard let recognized = try? observation.recognizedPoint(visionJoint(joint)) else { continue }
            guard let landmark = Landmark(
                joint: joint,
                x: recognized.location.x,
                y: recognized.location.y,
                confidence: Double(recognized.confidence)
            ) else {
                continue
            }
            landmarks.append(landmark)
        }
        return landmarks
    }

    private static func visionJoint(_ joint: JointName) -> VNHumanBodyPoseObservation.JointName {
        switch joint {
        case .nose: .nose
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .leftEar: .leftEar
        case .rightEar: .rightEar
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .root: .root
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}
