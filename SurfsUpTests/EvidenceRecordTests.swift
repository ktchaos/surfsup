import Foundation
import Testing
@testable import SurfsUp

struct EvidenceRecordTests {
    @Test func aFinishedTimelineWritesOneRawFile() throws {
        let timeline = sampleTimeline()
        let record = try #require(EvidenceRecord(
            timeline: timeline,
            elapsedSeconds: 4.5,
            decodedFrameCount: timeline.observations.count,
            attemptedFrameCount: timeline.observations.count
        ))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = try EvidenceFileWriter.write(record, to: directory)
        let data = try Data(contentsOf: url)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["clipDuration"] as? Double == 2)
        #expect(object["elapsedSeconds"] as? Double == 4.5)
        #expect(object["framesCompleted"] as? Int == timeline.observations.count)
        let observations = try #require(object["observations"] as? [[String: Any]])
        #expect(observations.count == timeline.observations.count)
        #expect(record.framesCompleted == observations.count)
        #expect(observations[0]["start"] as? Double == 0)
        #expect(observations[0]["end"] as? Double == 1)
        let landmarks = try #require(observations[0]["landmarks"] as? [[String: Any]])
        #expect(landmarks[0]["joint"] as? String == "nose")
        #expect(landmarks[0]["x"] as? Double == 0.4)
        #expect(landmarks[0]["y"] as? Double == 0.6)
        #expect(landmarks[0]["confidence"] as? Double == 0.25)

        var keys = Set<String>()
        collectKeys(in: object, into: &keys)
        let forbidden: Set<String> = ["judgment", "score", "maneuver", "board", "biomechanical", "yes", "no", "angle"]
        #expect(keys.isDisjoint(with: forbidden))
    }

    @Test func aSecondFinishedRunDoesNotOverwriteTheFirstFile() throws {
        let record = try #require(EvidenceRecord(
            timeline: sampleTimeline(),
            elapsedSeconds: 1,
            decodedFrameCount: 2,
            attemptedFrameCount: 2
        ))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try EvidenceFileWriter.write(record, to: directory)
        let second = try EvidenceFileWriter.write(record, to: directory)
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func aCancelledOrFailedRunWritesNoFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = try EvidenceFileWriter.writeFinished(nil, to: directory)
        #expect(url == nil)
        let exists = FileManager.default.fileExists(atPath: directory.path)
        if exists {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            #expect(contents.isEmpty)
        }
    }

    private func sampleTimeline() -> PoseTimeline {
        let duration: Double = 2
        let landmark = Landmark(joint: .nose, x: 0.4, y: 0.6, confidence: 0.25)!
        let body = BodyObservation(landmarks: [landmark], selectionArea: 0)!
        let first = FrameObservation(start: 0, end: 1, clipDuration: duration, body: body)!
        let second = FrameObservation(start: 1, end: 2, clipDuration: duration, body: nil)!
        return PoseTimeline(clipDuration: duration, observations: [first, second])!
    }

    private func collectKeys(in value: Any, into keys: inout Set<String>) {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                keys.insert(key)
                collectKeys(in: nested, into: &keys)
            }
        } else if let array = value as? [Any] {
            for item in array {
                collectKeys(in: item, into: &keys)
            }
        }
    }
}
