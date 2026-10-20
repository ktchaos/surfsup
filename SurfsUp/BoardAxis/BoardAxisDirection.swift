import Foundation

/// Tail-to-nose direction in the upright picture.
///
/// Coordinates use the stored pose space: origin at the bottom-left, `x` to the
/// viewer's right, `y` upward. This type does not read a rectangle or an ankle.
nonisolated struct BoardAxisDirection: Equatable, Sendable {
    var angleDegrees: Double

    /// `nil` when the tail and nose are the same point.
    static func make(tailX: Double, tailY: Double, noseX: Double, noseY: Double) -> BoardAxisDirection? {
        let rightward = noseX - tailX
        let upward = noseY - tailY
        guard rightward != 0 || upward != 0 else { return nil }
        return BoardAxisDirection(angleDegrees: atan2(rightward, upward) * 180 / .pi)
    }
}

enum BoardAxisDocumentError: Error, Equatable, Sendable {
    case malformed
    case clipCount
    case frameCount
    case duplicateClipDuration
    case duplicateFrameId
    case timestampOrder
    case timestampRange
    case forbiddenField
    case labelCoverage
    case coordinateRange
    case coincidentPoints
    case missingImageReason
    case unexpectedImageReason
    case unexpectedCoordinates
    case sourceHash
    case judgment
}

nonisolated struct BoardAxisSchedule: Equatable, Sendable {
    struct Frame: Equatable, Sendable {
        var frameId: String
        var timestamp: TimeInterval
        var samplingNote: String
    }

    struct Clip: Equatable, Sendable {
        var sourceFilename: String
        var sourceSha256: String
        var clipDuration: TimeInterval
        var frames: [Frame]
    }

    var clips: [Clip]

    static func decode(_ data: Data) throws -> BoardAxisSchedule {
        let root = try jsonObject(data)
        try rejectUnknownKeys(root, allowed: ["clips"])
        guard let clipValues = root["clips"] as? [Any] else { throw BoardAxisDocumentError.malformed }
        guard clipValues.count == 5 else { throw BoardAxisDocumentError.clipCount }

        var clips: [Clip] = []
        var seenDurations: [TimeInterval] = []
        var seenFrameIds: [String] = []
        for clipValue in clipValues {
            guard let clip = clipValue as? [String: Any] else { throw BoardAxisDocumentError.malformed }
            try rejectUnknownKeys(clip, allowed: ["sourceFilename", "sourceSha256", "clipDuration", "frames"])
            guard let sourceFilename = clip["sourceFilename"] as? String, !sourceFilename.isEmpty,
                  let sourceSha256 = clip["sourceSha256"] as? String,
                  let clipDuration = jsonDouble(clip["clipDuration"]),
                  let frameValues = clip["frames"] as? [Any]
            else { throw BoardAxisDocumentError.malformed }
            guard sourceSha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw BoardAxisDocumentError.sourceHash
            }
            guard frameValues.count == 5 else { throw BoardAxisDocumentError.frameCount }
            guard !seenDurations.contains(clipDuration) else { throw BoardAxisDocumentError.duplicateClipDuration }
            seenDurations.append(clipDuration)

            var frames: [Frame] = []
            for frameValue in frameValues {
                guard let frame = frameValue as? [String: Any] else { throw BoardAxisDocumentError.malformed }
                try rejectUnknownKeys(frame, allowed: ["frameId", "timestamp", "samplingNote"])
                guard let frameId = frame["frameId"] as? String, !frameId.isEmpty,
                      let timestamp = jsonDouble(frame["timestamp"]),
                      let samplingNote = frame["samplingNote"] as? String
                else { throw BoardAxisDocumentError.malformed }
                guard !seenFrameIds.contains(frameId) else { throw BoardAxisDocumentError.duplicateFrameId }
                seenFrameIds.append(frameId)
                guard timestamp >= 0, timestamp < clipDuration else { throw BoardAxisDocumentError.timestampRange }
                if let previous = frames.last, timestamp <= previous.timestamp {
                    throw BoardAxisDocumentError.timestampOrder
                }
                frames.append(Frame(frameId: frameId, timestamp: timestamp, samplingNote: samplingNote))
            }
            clips.append(Clip(
                sourceFilename: sourceFilename,
                sourceSha256: sourceSha256,
                clipDuration: clipDuration,
                frames: frames
            ))
        }
        return BoardAxisSchedule(clips: clips)
    }

    var frameIds: [String] {
        clips.flatMap { $0.frames.map(\.frameId) }
    }
}

nonisolated struct BoardAxisLabel: Equatable, Sendable {
    enum Judgment: String, Equatable, Sendable {
        case directed
        case unassessable
    }

    var frameId: String
    var judgment: Judgment
    var tailX: Double?
    var tailY: Double?
    var noseX: Double?
    var noseY: Double?
    var imageReason: String?
}

nonisolated struct BoardAxisLabelDocument: Equatable, Sendable {
    var labels: [BoardAxisLabel]

    static func decode(_ data: Data, schedule: BoardAxisSchedule) throws -> BoardAxisLabelDocument {
        let root = try jsonObject(data)
        try rejectUnknownKeys(root, allowed: ["labels"])
        guard let labelValues = root["labels"] as? [Any] else { throw BoardAxisDocumentError.malformed }

        var labels: [BoardAxisLabel] = []
        for labelValue in labelValues {
            guard let label = labelValue as? [String: Any] else { throw BoardAxisDocumentError.malformed }
            guard let frameId = label["frameId"] as? String, !frameId.isEmpty,
                  let judgmentRaw = label["judgment"] as? String
            else { throw BoardAxisDocumentError.malformed }
            guard let judgment = BoardAxisLabel.Judgment(rawValue: judgmentRaw) else {
                throw BoardAxisDocumentError.judgment
            }

            switch judgment {
            case .directed:
                try rejectUnknownKeys(
                    label,
                    allowed: ["frameId", "judgment", "tailX", "tailY", "noseX", "noseY"],
                    imageReasonKey: "imageReason"
                )
                guard let tailX = jsonDouble(label["tailX"]),
                      let tailY = jsonDouble(label["tailY"]),
                      let noseX = jsonDouble(label["noseX"]),
                      let noseY = jsonDouble(label["noseY"])
                else { throw BoardAxisDocumentError.coordinateRange }
                let coordinates = [tailX, tailY, noseX, noseY]
                guard coordinates.allSatisfy({ (0...1).contains($0) }) else {
                    throw BoardAxisDocumentError.coordinateRange
                }
                guard BoardAxisDirection.make(tailX: tailX, tailY: tailY, noseX: noseX, noseY: noseY) != nil else {
                    throw BoardAxisDocumentError.coincidentPoints
                }
                labels.append(BoardAxisLabel(
                    frameId: frameId,
                    judgment: .directed,
                    tailX: tailX,
                    tailY: tailY,
                    noseX: noseX,
                    noseY: noseY,
                    imageReason: nil
                ))
            case .unassessable:
                let coordinateKeys = ["tailX", "tailY", "noseX", "noseY"]
                if coordinateKeys.contains(where: { label[$0] != nil }) {
                    throw BoardAxisDocumentError.unexpectedCoordinates
                }
                try rejectUnknownKeys(label, allowed: ["frameId", "judgment", "imageReason"])
                guard let imageReason = label["imageReason"] as? String, !imageReason.isEmpty else {
                    throw BoardAxisDocumentError.missingImageReason
                }
                labels.append(BoardAxisLabel(
                    frameId: frameId,
                    judgment: .unassessable,
                    imageReason: imageReason
                ))
            }
        }

        let expected = schedule.frameIds
        let actual = labels.map(\.frameId)
        guard actual.count == expected.count, Set(actual) == Set(expected) else {
            throw BoardAxisDocumentError.labelCoverage
        }
        return BoardAxisLabelDocument(labels: labels)
    }
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw BoardAxisDocumentError.malformed
    }
    guard let dictionary = object as? [String: Any] else { throw BoardAxisDocumentError.malformed }
    return dictionary
}

private func jsonDouble(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
    return number.doubleValue
}

private func rejectUnknownKeys(
    _ object: [String: Any],
    allowed: Set<String>,
    imageReasonKey: String? = nil
) throws {
    for key in object.keys where !allowed.contains(key) {
        if key == imageReasonKey {
            throw BoardAxisDocumentError.unexpectedImageReason
        }
        throw BoardAxisDocumentError.forbiddenField
    }
}
