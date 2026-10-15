import Foundation
import Testing
@testable import SurfsUp

struct TorsoLeanOfflineRunnerTests {
    private let duration = 1.25

    @Test func malformedSheetWritesNothing() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sheet = Data(#"{"clips":[{"clipDuration":1.25,"role":"usable","pauses":[{"timestamp":0.1,"expectedSign":"right","oppositeLean":false,"angleDegrees":12}]}]}"#.utf8)
        try sheet.write(to: workspace.sheet)
        try writeEvidence(rightTimeline(), elapsed: 0.2, name: "a.json", directory: workspace.evidence)

        #expect(throws: TorsoLeanSheetError.computedAnglePresent) {
            try TorsoLeanOfflineRunner.run(workspace.request)
        }
        #expect(try Data(contentsOf: workspace.sheet) == sheet)
        #expect(!FileManager.default.fileExists(atPath: workspace.report.path))
    }

    @Test func invalidPauseSheetWritesNothing() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sheet = Data(usableSheet(pauseCount: 2).utf8)
        try sheet.write(to: workspace.sheet)
        try writeEvidence(rightTimeline(), elapsed: 0.2, name: "a.json", directory: workspace.evidence)

        #expect(throws: TorsoLeanSheetError.usablePauseCount) {
            try TorsoLeanOfflineRunner.run(workspace.request)
        }
        #expect(!FileManager.default.fileExists(atPath: workspace.report.path))
    }

    @Test func missingEvidenceWritesNothing() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data(usableSheet().utf8).write(to: workspace.sheet)
        try writeEvidence(rightTimeline(duration: 3.5), elapsed: 0.2, name: "other.json", directory: workspace.evidence)

        #expect(throws: TorsoLeanOfflineError.missingEvidence(duration)) {
            try TorsoLeanOfflineRunner.run(workspace.request)
        }
        #expect(!FileManager.default.fileExists(atPath: workspace.report.path))
    }

    @Test func differingObservationsWithTheSameDurationAreAmbiguous() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data(usableSheet().utf8).write(to: workspace.sheet)
        try writeEvidence(rightTimeline(), elapsed: 0.2, name: "right.json", directory: workspace.evidence)
        try writeEvidence(leftTimeline(), elapsed: 0.2, name: "left.json", directory: workspace.evidence)
        let before = try evidenceBytes(in: workspace.evidence)

        #expect(throws: TorsoLeanOfflineError.ambiguousEvidence(duration)) {
            try TorsoLeanOfflineRunner.run(workspace.request)
        }
        #expect(try evidenceBytes(in: workspace.evidence) == before)
        #expect(!FileManager.default.fileExists(atPath: workspace.report.path))
    }

    @Test func identicalDetectionSeriesWritesASeparateReport() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sheet = Data(usableSheet().utf8)
        try sheet.write(to: workspace.sheet)
        try writeEvidence(rightTimeline(), elapsed: 0.2, name: "b.json", directory: workspace.evidence)
        try writeEvidence(rightTimeline(), elapsed: 0.8, name: "a.json", directory: workspace.evidence)
        let evidenceBefore = try evidenceBytes(in: workspace.evidence)
        #expect(evidenceBefore["a.json"] != evidenceBefore["b.json"])

        let report = try TorsoLeanOfflineRunner.run(workspace.request)
        let written = try JSONDecoder().decode(TorsoLeanOfflineReport.self, from: Data(contentsOf: workspace.report))

        #expect(written == report)
        #expect(report.clips.count == 1)
        #expect(report.clips[0].matchCount == 5)
        #expect(report.clips[0].signCheck == .passed)
        #expect(report.clips[0].pauseResults.allSatisfy { $0.outcome == .match })
        #expect(report.matchedEvidence == [
            TorsoLeanOfflineReport.MatchedEvidence(clipDuration: duration, files: ["a.json", "b.json"])
        ])
        let reportText = try String(contentsOf: workspace.report, encoding: .utf8)
        #expect(!reportText.contains("angleDegrees"))
        #expect(try Data(contentsOf: workspace.sheet) == sheet)
        #expect(try evidenceBytes(in: workspace.evidence) == evidenceBefore)
        #expect(workspace.report.path != workspace.sheet.path)
    }

    @Test func reportPathCannotReplaceThePauseSheet() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sheet = Data(usableSheet().utf8)
        try sheet.write(to: workspace.sheet)
        try writeEvidence(rightTimeline(), elapsed: 0.2, name: "a.json", directory: workspace.evidence)
        var request = workspace.request
        request.reportURL = workspace.sheet

        #expect(throws: TorsoLeanOfflineError.outputCollidesWithPauseSheet) {
            try TorsoLeanOfflineRunner.run(request)
        }
        #expect(try Data(contentsOf: workspace.sheet) == sheet)
    }

    @Test func reportPathCannotReplaceEvidence() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data(usableSheet().utf8).write(to: workspace.sheet)
        let evidenceURL = try writeEvidence(rightTimeline(), elapsed: 0.2, name: "a.json", directory: workspace.evidence)
        let evidence = try Data(contentsOf: evidenceURL)
        var request = workspace.request
        request.reportURL = evidenceURL

        #expect(throws: TorsoLeanOfflineError.outputCollidesWithEvidence) {
            try TorsoLeanOfflineRunner.run(request)
        }
        #expect(try Data(contentsOf: evidenceURL) == evidence)
        #expect(try Data(contentsOf: workspace.sheet) == Data(usableSheet().utf8))
    }

    private struct Workspace {
        var root: URL
        var sheet: URL
        var evidence: URL
        var report: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("torso-lean-offline-\(UUID().uuidString)", isDirectory: true)
            sheet = root.appendingPathComponent("sheet.json")
            evidence = root.appendingPathComponent("evidence", isDirectory: true)
            report = root.appendingPathComponent("report.json")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        }

        var request: TorsoLeanOfflineRunner.Request {
            TorsoLeanOfflineRunner.Request(
                pauseSheetURL: sheet,
                evidenceDirectoryURL: evidence,
                reportURL: report
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func usableSheet(pauseCount: Int = 5) -> String {
        let pauses = (0..<pauseCount).map { index in
            #"{"timestamp":\#(0.1 + Double(index) * 0.1),"expectedSign":"right","oppositeLean":false}"#
        }.joined(separator: ",")
        return #"{"clips":[{"clipDuration":\#(duration),"role":"usable","pauses":[\#(pauses)]}]}"#
    }

    private func rightTimeline(duration: TimeInterval? = nil) -> PoseTimeline {
        timeline(neckX: 0.8, duration: duration ?? self.duration)
    }

    private func leftTimeline() -> PoseTimeline {
        timeline(neckX: 0.2, duration: duration)
    }

    private func timeline(neckX: Double, duration: TimeInterval) -> PoseTimeline {
        let body = BodyObservation(
            landmarks: [
                Landmark(joint: .neck, x: neckX, y: 0.5, confidence: 1)!,
                Landmark(joint: .root, x: 0.5, y: 0.5, confidence: 1)!
            ],
            selectionArea: 0.1
        )
        let frame = FrameObservation(start: 0, end: duration, clipDuration: duration, body: body)!
        return PoseTimeline(clipDuration: duration, observations: [frame])!
    }

    @discardableResult
    private func writeEvidence(
        _ timeline: PoseTimeline,
        elapsed: TimeInterval,
        name: String,
        directory: URL
    ) throws -> URL {
        let record = EvidenceRecord(
            timeline: timeline,
            elapsedSeconds: elapsed,
            decodedFrameCount: timeline.observations.count,
            attemptedFrameCount: timeline.observations.count
        )!
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(record).write(to: url)
        return url
    }

    private func evidenceBytes(in directory: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var bytes: [String: Data] = [:]
        for url in urls where url.pathExtension == "json" {
            bytes[url.lastPathComponent] = try Data(contentsOf: url)
        }
        return bytes
    }
}
