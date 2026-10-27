import Foundation
import Testing
@testable import SurfsUp

struct BoardAxisSourceIdentityTests {
    @Test func byteCopyProducesTheExpectedDigest() throws {
        let original = try temporaryFile(bytes: Data("scheduled-original".utf8))
        let expected = BoardAxisScheduledSource(
            sourceFilename: "unrelated-name.mov",
            sourceSha256: try BoardAxisSourceIdentity.digest(of: original)
        )

        let loadClipURL = try BoardAxisSourceIdentity.fileForLoadClip(importedFrom: original, expected: expected)

        #expect(loadClipURL != original)
        #expect(try BoardAxisSourceIdentity.digest(of: loadClipURL) == expected.sourceSha256)
        #expect(try Data(contentsOf: loadClipURL) == Data(contentsOf: original))
    }

    @Test func aChangedFileIsRejectedBeforePoseAnalysis() throws {
        let original = try temporaryFile(bytes: Data("scheduled-original".utf8))
        var changed = Data("scheduled-original".utf8)
        changed[0] ^= 0xFF
        let changedURL = try temporaryFile(bytes: changed)
        let expected = BoardAxisScheduledSource(
            sourceFilename: "videoplayback.mp4",
            sourceSha256: try BoardAxisSourceIdentity.digest(of: original)
        )
        var poseStarted = false

        #expect(throws: BoardAxisSourceIdentityError.mismatch) {
            let url = try BoardAxisSourceIdentity.fileForLoadClip(importedFrom: changedURL, expected: expected)
            poseStarted = true
            _ = url
        }
        #expect(poseStarted == false)
    }

    @Test func aSelectedEntryAcceptsOnlyItsOwnHash() throws {
        let firstURL = try temporaryFile(bytes: Data("clip-a".utf8))
        let secondURL = try temporaryFile(bytes: Data("clip-b".utf8))
        let first = BoardAxisScheduledSource(
            sourceFilename: "videoplayback.mp4",
            sourceSha256: try BoardAxisSourceIdentity.digest(of: firstURL)
        )
        let second = BoardAxisScheduledSource(
            sourceFilename: "videoplayback (1).mp4",
            sourceSha256: try BoardAxisSourceIdentity.digest(of: secondURL)
        )

        let admitted = try BoardAxisSourceIdentity.fileForLoadClip(importedFrom: firstURL, expected: first)
        #expect(try BoardAxisSourceIdentity.digest(of: admitted) == first.sourceSha256)
        #expect(throws: BoardAxisSourceIdentityError.mismatch) {
            try BoardAxisSourceIdentity.fileForLoadClip(importedFrom: firstURL, expected: second)
        }
        #expect(throws: BoardAxisSourceIdentityError.mismatch) {
            try BoardAxisSourceIdentity.fileForLoadClip(importedFrom: secondURL, expected: first)
        }
    }

    @Test func existingEvidenceJSONDecodesWithoutASourceHash() throws {
        let json = """
        {
          "clipDuration": 1.5,
          "elapsedSeconds": 0.5,
          "framesCompleted": 1,
          "decodedFrameCount": 1,
          "attemptedFrameCount": 1,
          "gapCount": 1,
          "observations": [
            {"start": 0, "end": 1.5, "landmarks": []}
          ]
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(EvidenceRecord.self, from: json)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]

        #expect(record.clipDuration == 1.5)
        #expect(record.observations.count == 1)
        #expect(record.observations[0].body == nil)
        #expect(encoded?["sourceSha256"] == nil)
        #expect(encoded?.keys.contains("sourceFilename") == false)
    }

    @Test func catalogMatchesTheLockedScheduleEntries() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scheduleURL = root.appendingPathComponent("specs/003-board-axis-feasibility/board-axis-schedule.json")
        let schedule = try JSONSerialization.jsonObject(with: Data(contentsOf: scheduleURL)) as? [String: Any]
        let clips = try #require(schedule?["clips"] as? [[String: Any]])
        let recorded = clips.map {
            BoardAxisScheduledSource(
                sourceFilename: $0["sourceFilename"] as? String ?? "",
                sourceSha256: $0["sourceSha256"] as? String ?? ""
            )
        }

        #expect(recorded == BoardAxisScheduledSource.boardAxisClips)
    }

    private func temporaryFile(bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try bytes.write(to: url)
        return url
    }
}
