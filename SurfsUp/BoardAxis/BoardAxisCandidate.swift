import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import Vision

nonisolated struct BoardAxisPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// Corners use the rectangle request's names. Those names are not nose or tail.
nonisolated struct BoardAxisQuadrilateral: Equatable, Sendable {
    var topLeft: BoardAxisPoint
    var topRight: BoardAxisPoint
    var bottomLeft: BoardAxisPoint
    var bottomRight: BoardAxisPoint
}

nonisolated enum BoardAxisAnkleResolution: Equatable, Sendable {
    case missingSample
    case noAnkle
    case point(BoardAxisPoint)
}

nonisolated enum BoardAxisCandidateStatus: Equatable, Sendable {
    case directed(tail: BoardAxisPoint, nose: BoardAxisPoint, corners: BoardAxisQuadrilateral)
    case noCandidate(reason: String)
}

nonisolated struct BoardAxisCandidate: Equatable, Sendable {
    var frameId: String
    var status: BoardAxisCandidateStatus
}

nonisolated struct BoardAxisDecodedSampleTiming: Equatable, Sendable {
    var presentationTime: TimeInterval
    var duration: TimeInterval
}

nonisolated struct BoardAxisSampleWindow: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
}

nonisolated enum BoardAxisCandidateError: Error, Equatable, Sendable {
    case forbiddenLabelInput
    case copiedFromHumanLabel
    case incompleteInvocation
    case candidatesAlreadyExist
    case missingReason
    case missingEvidence(TimeInterval)
    case ambiguousEvidence(TimeInterval)
    case invalidEvidence(String)
    case sourceHashMismatch(String)
    case frameNotDecoded(String)
}

/// Frozen `VNDetectRectanglesRequest` settings. Creating the request does not run it.
nonisolated enum BoardAxisRectangleRequest {
    static func make() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.05
        request.maximumAspectRatio = 0.40
        request.minimumSize = 0.02
        request.quadratureTolerance = 30
        request.minimumConfidence = 0
        request.maximumObservations = 0
        return request
    }

    static func quadrilaterals(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> [BoardAxisQuadrilateral] {
        let request = make()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).map { observation in
            BoardAxisQuadrilateral(
                topLeft: point(observation.topLeft),
                topRight: point(observation.topRight),
                bottomLeft: point(observation.bottomLeft),
                bottomRight: point(observation.bottomRight)
            )
        }
    }

    private static func point(_ point: CGPoint) -> BoardAxisPoint {
        BoardAxisPoint(x: Double(point.x), y: Double(point.y))
    }
}

/// Pure candidate selection. This type does not read a label file.
nonisolated enum BoardAxisCandidateSelection {
    static let noQuadrilateralReason = "No quadrilateral passed the frozen rectangle gates."
    static let equalAreaReason = "Two or more quadrilaterals share the largest area."
    static let equalSidePairReason = "The opposite side pairs have equal length, so the long axis is not unique."
    static let coincidentAxisReason = "The long-axis endpoints coincide."
    static let noAnkleReason = "Neither ankle is present in the matched pose sample."
    static let missingSampleReason = "The matched pose sample is missing."
    static let equalDistanceReason = "The long-axis endpoints are equally far from the ankle point."

    static func select(
        quadrilaterals: [BoardAxisQuadrilateral],
        ankle: BoardAxisAnkleResolution
    ) -> BoardAxisCandidateStatus {
        let usable = quadrilaterals.filter(isFinite)
        guard !usable.isEmpty else { return .noCandidate(reason: noQuadrilateralReason) }

        let ranked = usable.map { (quad: $0, area: shoelaceArea($0)) }
        guard let largest = ranked.map(\.area).max() else { return .noCandidate(reason: noQuadrilateralReason) }
        let winners = ranked.filter { $0.area == largest }
        guard winners.count == 1, let winner = winners.first else {
            return .noCandidate(reason: equalAreaReason)
        }

        switch longAxisEndpoints(winner.quad) {
        case .equalPairs:
            return .noCandidate(reason: equalSidePairReason)
        case .coincident:
            return .noCandidate(reason: coincidentAxisReason)
        case .points(let first, let second):
            return orient(first: first, second: second, ankle: ankle, corners: winner.quad)
        }
    }

    static func ankleResolution(at time: TimeInterval, in timeline: PoseTimeline) -> BoardAxisAnkleResolution {
        guard let observation = PlayheadLookup.observation(at: time, in: timeline) else {
            return .missingSample
        }
        let left = observation.body?.landmarks.first { $0.joint == .leftAnkle }
        let right = observation.body?.landmarks.first { $0.joint == .rightAnkle }
        switch (left, right) {
        case let (left?, right?):
            return .point(BoardAxisPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2))
        case let (left?, nil):
            return .point(BoardAxisPoint(x: left.x, y: left.y))
        case let (nil, right?):
            return .point(BoardAxisPoint(x: right.x, y: right.y))
        case (nil, nil):
            return .noAnkle
        }
    }

    static func timeline(forClipDuration duration: TimeInterval, records: [EvidenceRecord]) throws -> PoseTimeline {
        let matches = records.filter { $0.clipDuration == duration }
        guard let first = matches.first else { throw BoardAxisCandidateError.missingEvidence(duration) }
        let series = first.observations
        guard matches.allSatisfy({ $0.observations == series }) else {
            throw BoardAxisCandidateError.ambiguousEvidence(duration)
        }
        guard let timeline = PoseTimeline(clipDuration: first.clipDuration, observations: series) else {
            throw BoardAxisCandidateError.invalidEvidence("clipDuration \(duration)")
        }
        return timeline
    }

    /// Audit helper for a candidate whose endpoint equals a human nose or tail point.
    /// The candidate runner does not call this, because it never receives the label.
    static func rejectEndpointsCopied(
        fromHumanTail humanTail: BoardAxisPoint,
        humanNose: BoardAxisPoint,
        candidate: BoardAxisCandidateStatus
    ) throws {
        guard case .directed(let tail, let nose, _) = candidate else { return }
        let humanPoints = [humanTail, humanNose]
        if humanPoints.contains(tail) || humanPoints.contains(nose) {
            throw BoardAxisCandidateError.copiedFromHumanLabel
        }
    }

    private static func orient(
        first: BoardAxisPoint,
        second: BoardAxisPoint,
        ankle: BoardAxisAnkleResolution,
        corners: BoardAxisQuadrilateral
    ) -> BoardAxisCandidateStatus {
        let anklePoint: BoardAxisPoint
        switch ankle {
        case .missingSample:
            return .noCandidate(reason: missingSampleReason)
        case .noAnkle:
            return .noCandidate(reason: noAnkleReason)
        case .point(let point):
            guard point.x.isFinite, point.y.isFinite else { return .noCandidate(reason: noAnkleReason) }
            anklePoint = point
        }

        let firstDistance = distanceSquared(anklePoint, first)
        let secondDistance = distanceSquared(anklePoint, second)
        if firstDistance == secondDistance {
            return .noCandidate(reason: equalDistanceReason)
        }
        let nose = firstDistance > secondDistance ? first : second
        let tail = firstDistance > secondDistance ? second : first
        guard BoardAxisDirection.make(tailX: tail.x, tailY: tail.y, noseX: nose.x, noseY: nose.y) != nil else {
            return .noCandidate(reason: coincidentAxisReason)
        }
        return .directed(tail: tail, nose: nose, corners: corners)
    }

    private enum AxisEnds {
        case points(BoardAxisPoint, BoardAxisPoint)
        case equalPairs
        case coincident
    }

    private static func longAxisEndpoints(_ quad: BoardAxisQuadrilateral) -> AxisEnds {
        let acrossTopAndBottom = length(quad.topLeft, quad.topRight) + length(quad.bottomLeft, quad.bottomRight)
        let acrossLeftAndRight = length(quad.topLeft, quad.bottomLeft) + length(quad.topRight, quad.bottomRight)
        if acrossTopAndBottom == acrossLeftAndRight {
            return .equalPairs
        }
        let ends: (BoardAxisPoint, BoardAxisPoint)
        if acrossTopAndBottom < acrossLeftAndRight {
            ends = (midpoint(quad.topLeft, quad.topRight), midpoint(quad.bottomLeft, quad.bottomRight))
        } else {
            ends = (midpoint(quad.topLeft, quad.bottomLeft), midpoint(quad.topRight, quad.bottomRight))
        }
        if ends.0 == ends.1 {
            return .coincident
        }
        return .points(ends.0, ends.1)
    }

    private static func isFinite(_ quad: BoardAxisQuadrilateral) -> Bool {
        [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight].allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    private static func shoelaceArea(_ quad: BoardAxisQuadrilateral) -> Double {
        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        var sum = 0.0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return abs(sum) / 2
    }

    private static func midpoint(_ start: BoardAxisPoint, _ end: BoardAxisPoint) -> BoardAxisPoint {
        BoardAxisPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    private static func length(_ start: BoardAxisPoint, _ end: BoardAxisPoint) -> Double {
        distanceSquared(start, end).squareRoot()
    }

    private static func distanceSquared(_ start: BoardAxisPoint, _ end: BoardAxisPoint) -> Double {
        let dx = start.x - end.x
        let dy = start.y - end.y
        return dx * dx + dy * dy
    }
}

/// Schedule, video, and read-only pose evidence in. Candidate file out.
/// A label path or a manifest path fails before any file is written.
nonisolated enum BoardAxisCandidateRunner {
    struct Input: Equatable, Sendable {
        var scheduleURL: URL
        var videoDirectoryURL: URL
        var evidenceDirectoryURL: URL
        var candidatesURL: URL
        var labelURL: URL?
        var manifestURL: URL?
    }

    static func invocation(from environment: [String: String]) throws -> Input? {
        func value(_ key: String) -> String? {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return raw
        }
        if value("BOARD_AXIS_LABELS") != nil || value("BOARD_AXIS_MANIFEST") != nil {
            throw BoardAxisCandidateError.forbiddenLabelInput
        }
        let schedule = value("BOARD_AXIS_SCHEDULE")
        let videos = value("BOARD_AXIS_VIDEO_DIRECTORY")
        let evidence = value("BOARD_AXIS_EVIDENCE_DIRECTORY")
        let candidates = value("BOARD_AXIS_CANDIDATES")
        if schedule == nil, videos == nil, evidence == nil, candidates == nil {
            return nil
        }
        guard let schedule, let videos, let evidence, let candidates else {
            throw BoardAxisCandidateError.incompleteInvocation
        }
        return Input(
            scheduleURL: URL(fileURLWithPath: schedule),
            videoDirectoryURL: URL(fileURLWithPath: videos),
            evidenceDirectoryURL: URL(fileURLWithPath: evidence),
            candidatesURL: URL(fileURLWithPath: candidates),
            labelURL: nil,
            manifestURL: nil
        )
    }

    static func run(_ input: Input) async throws {
        if input.labelURL != nil || input.manifestURL != nil {
            throw BoardAxisCandidateError.forbiddenLabelInput
        }
        if FileManager.default.fileExists(atPath: input.candidatesURL.path) {
            throw BoardAxisCandidateError.candidatesAlreadyExist
        }

        let schedule = try BoardAxisSchedule.decode(Data(contentsOf: input.scheduleURL))
        let records = try loadEvidence(in: input.evidenceDirectoryURL)
        var candidates: [BoardAxisCandidate] = []
        candidates.reserveCapacity(schedule.frameIds.count)

        for clip in schedule.clips {
            let timeline = try BoardAxisCandidateSelection.timeline(forClipDuration: clip.clipDuration, records: records)
            let videoURL = input.videoDirectoryURL.appendingPathComponent(clip.sourceFilename)
            try verifySourceHash(clip, videoURL: videoURL)
            let detected = try await quadrilaterals(for: clip.frames, in: videoURL)
            for frame in clip.frames {
                guard let quadrilaterals = detected[frame.frameId] else {
                    throw BoardAxisCandidateError.frameNotDecoded(frame.frameId)
                }
                let ankle = BoardAxisCandidateSelection.ankleResolution(at: frame.timestamp, in: timeline)
                candidates.append(BoardAxisCandidate(
                    frameId: frame.frameId,
                    status: BoardAxisCandidateSelection.select(quadrilaterals: quadrilaterals, ankle: ankle)
                ))
            }
        }

        guard candidates.map(\.frameId) == schedule.frameIds else {
            throw BoardAxisCandidateError.frameNotDecoded(schedule.frameIds.first ?? "")
        }
        let data = try encode(candidates)
        let parent = input.candidatesURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: input.candidatesURL, options: .atomic)
    }

    private static func loadEvidence(in directory: URL) throws -> [EvidenceRecord] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        let jsonURLs = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var records: [EvidenceRecord] = []
        records.reserveCapacity(jsonURLs.count)
        for url in jsonURLs {
            let data = try Data(contentsOf: url)
            do {
                records.append(try JSONDecoder().decode(EvidenceRecord.self, from: data))
            } catch {
                throw BoardAxisCandidateError.invalidEvidence(url.lastPathComponent)
            }
        }
        return records
    }

    private static func verifySourceHash(_ clip: BoardAxisSchedule.Clip, videoURL: URL) throws {
        let digest = SHA256.hash(data: try Data(contentsOf: videoURL))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == clip.sourceSha256.lowercased() else {
            throw BoardAxisCandidateError.sourceHashMismatch(clip.sourceFilename)
        }
    }

    /// Windows match `PoseAnalysisClient.assembleTimeline`: sorted by presentation time,
    /// each sample ends at the next presentation time, and the last sample ends at the clip
    /// duration when its own duration is missing, not finite, or not positive.
    static func sampleWindows(
        samples: [BoardAxisDecodedSampleTiming],
        clipDuration: TimeInterval
    ) -> [BoardAxisSampleWindow] {
        let ordered = samples.sorted { $0.presentationTime < $1.presentationTime }
        return ordered.indices.map { index in
            let start = max(0, ordered[index].presentationTime)
            let end: TimeInterval
            if index + 1 < ordered.count {
                end = max(0, ordered[index + 1].presentationTime)
            } else if !ordered[index].duration.isFinite || ordered[index].duration <= 0 {
                end = clipDuration
            } else {
                let proposed = start + ordered[index].duration
                end = proposed > start ? proposed : clipDuration
            }
            return BoardAxisSampleWindow(start: start, end: min(end, clipDuration))
        }
    }

    private static func quadrilaterals(
        for frames: [BoardAxisSchedule.Frame],
        in videoURL: URL
    ) async throws -> [String: [BoardAxisQuadrilateral]] {
        let clip = try await VideoFrameSource.loadClip(from: videoURL)
        var timings: [(decodeIndex: Int, timing: BoardAxisDecodedSampleTiming)] = []
        try await VideoFrameSource.forEachDecodedFrame(of: clip) { decoded in
            timings.append((
                timings.count,
                BoardAxisDecodedSampleTiming(
                    presentationTime: decoded.presentationTime,
                    duration: decoded.duration
                )
            ))
        }
        let ordered = timings.sorted { $0.timing.presentationTime < $1.timing.presentationTime }
        let windows = sampleWindows(samples: ordered.map(\.timing), clipDuration: clip.duration)
        var framesByDecodeIndex: [Int: [BoardAxisSchedule.Frame]] = [:]
        for frame in frames {
            let hits = windows.indices.filter { windows[$0].start <= frame.timestamp && frame.timestamp < windows[$0].end }
            guard hits.count <= 1 else { throw BoardAxisCandidateError.frameNotDecoded(frame.frameId) }
            if let hit = hits.first {
                framesByDecodeIndex[ordered[hit].decodeIndex, default: []].append(frame)
            }
        }

        let scratch = DetectionScratch()
        var decodeIndex = 0
        try await VideoFrameSource.forEachDecodedFrame(of: clip) { decoded in
            let index = decodeIndex
            decodeIndex += 1
            guard let matches = framesByDecodeIndex[index] else { return }
            let found = try BoardAxisRectangleRequest.quadrilaterals(
                in: decoded.pixelBuffer,
                orientation: VideoFrameSource.imageOrientation(from: decoded.preferredTransform)
            )
            for frame in matches {
                if scratch.values[frame.frameId] != nil {
                    throw BoardAxisCandidateError.frameNotDecoded(frame.frameId)
                }
                scratch.values[frame.frameId] = found
            }
        }
        return scratch.values
    }

    static func encode(_ candidates: [BoardAxisCandidate]) throws -> Data {
        let objects: [[String: Any]] = try candidates.map { candidate in
            switch candidate.status {
            case .directed(let tail, let nose, let corners):
                return [
                    "frameId": candidate.frameId,
                    "status": "directed",
                    "tailX": tail.x,
                    "tailY": tail.y,
                    "noseX": nose.x,
                    "noseY": nose.y,
                    "cornerTopLeftX": corners.topLeft.x,
                    "cornerTopLeftY": corners.topLeft.y,
                    "cornerTopRightX": corners.topRight.x,
                    "cornerTopRightY": corners.topRight.y,
                    "cornerBottomLeftX": corners.bottomLeft.x,
                    "cornerBottomLeftY": corners.bottomLeft.y,
                    "cornerBottomRightX": corners.bottomRight.x,
                    "cornerBottomRightY": corners.bottomRight.y,
                ]
            case .noCandidate(let reason):
                guard !reason.isEmpty else { throw BoardAxisCandidateError.missingReason }
                return [
                    "frameId": candidate.frameId,
                    "status": "noCandidate",
                    "reason": reason,
                ]
            }
        }
        return try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
    }
}

private nonisolated final class DetectionScratch: @unchecked Sendable {
    var values: [String: [BoardAxisQuadrilateral]] = [:]
}
