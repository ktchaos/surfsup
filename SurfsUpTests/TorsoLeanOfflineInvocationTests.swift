import Foundation
import Testing
@testable import SurfsUp

struct TorsoLeanOfflineInvocationTests {
    @Test func missingPathsAreRejected() {
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.missingPauseSheetPath) {
            try TorsoLeanOfflineInvocation.request(pauseSheetPath: nil, evidenceDirectoryPath: "/evidence", reportPath: "/report.json")
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.missingPauseSheetPath) {
            try TorsoLeanOfflineInvocation.request(pauseSheetPath: "  ", evidenceDirectoryPath: "/evidence", reportPath: "/report.json")
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.missingEvidenceDirectoryPath) {
            try TorsoLeanOfflineInvocation.request(pauseSheetPath: "/sheet.json", evidenceDirectoryPath: nil, reportPath: "/report.json")
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.missingReportPath) {
            try TorsoLeanOfflineInvocation.request(pauseSheetPath: "/sheet.json", evidenceDirectoryPath: "/evidence", reportPath: "")
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.missingPauseSheetPath) {
            try TorsoLeanOfflineInvocation.requestFromEnvironment([:])
        }
    }

    @Test func relativePathsAreRejected() {
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.pauseSheetPathNotAbsolute) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: "sheet.json",
                evidenceDirectoryPath: "/evidence",
                reportPath: "/report.json"
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.evidenceDirectoryPathNotAbsolute) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: "/sheet.json",
                evidenceDirectoryPath: "evidence",
                reportPath: "/report.json"
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.reportPathNotAbsolute) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: "/sheet.json",
                evidenceDirectoryPath: "/evidence",
                reportPath: "report.json"
            )
        }
    }

    @Test func missingOrMisplacedInputsAreRejected() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.pauseSheetMissing) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: workspace.report.path
            )
        }

        try Data("{}".utf8).write(to: workspace.sheet)
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.evidenceDirectoryNotADirectory) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.sheet.path,
                reportPath: workspace.report.path
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.evidenceDirectoryMissing) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.root.appendingPathComponent("missing-evidence").path,
                reportPath: workspace.report.path
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.pauseSheetNotAFile) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.evidence.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: workspace.report.path
            )
        }
    }

    @Test func sheetInsideTheEvidenceDirectoryIsRejected() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sheet = workspace.evidence.appendingPathComponent("sheet.json")
        try Data("{}".utf8).write(to: sheet)

        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.pauseSheetInsideEvidenceDirectory) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: sheet.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: workspace.report.path
            )
        }
    }

    @Test func reportPathCannotReplaceEitherInput() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data("{}".utf8).write(to: workspace.sheet)
        let evidenceFile = workspace.evidence.appendingPathComponent("a.json")
        try Data("{}".utf8).write(to: evidenceFile)

        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.outputCollidesWithPauseSheet) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: workspace.sheet.path
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.outputCollidesWithEvidence) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: workspace.evidence.path
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.outputCollidesWithEvidence) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: evidenceFile.path
            )
        }
        #expect(throws: TorsoLeanOfflineInvocation.ValidationError.outputCollidesWithEvidence) {
            try TorsoLeanOfflineInvocation.request(
                pauseSheetPath: workspace.sheet.path,
                evidenceDirectoryPath: workspace.evidence.path,
                reportPath: workspace.evidence.appendingPathComponent("new-report.json").path
            )
        }
        #expect(!FileManager.default.fileExists(atPath: workspace.report.path))
    }

    @Test func absolutePathsBecomeTheRunnerRequest() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data("{}".utf8).write(to: workspace.sheet)
        let environment = [
            TorsoLeanOfflineInvocation.pauseSheetEnvironmentKey: workspace.sheet.path,
            TorsoLeanOfflineInvocation.evidenceDirectoryEnvironmentKey: workspace.evidence.path,
            TorsoLeanOfflineInvocation.reportEnvironmentKey: workspace.report.path
        ]

        let request = try TorsoLeanOfflineInvocation.requestFromEnvironment(environment)

        #expect(request.pauseSheetURL.path == workspace.sheet.path)
        #expect(request.evidenceDirectoryURL.path == workspace.evidence.path)
        #expect(request.reportURL.path == workspace.report.path)
        #expect(!FileManager.default.fileExists(atPath: workspace.report.path))
    }

    @Test func testRunnerPrefixSuppliesPathsWhenTheSchemeValueIsEmpty() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data("{}".utf8).write(to: workspace.sheet)

        let request = try TorsoLeanOfflineInvocation.requestFromEnvironment([
            TorsoLeanOfflineInvocation.pauseSheetEnvironmentKey: "$(TORSO_LEAN_PAUSE_SHEET)",
            "TEST_RUNNER_\(TorsoLeanOfflineInvocation.pauseSheetEnvironmentKey)": workspace.sheet.path,
            "TEST_RUNNER_\(TorsoLeanOfflineInvocation.evidenceDirectoryEnvironmentKey)": workspace.evidence.path,
            "TEST_RUNNER_\(TorsoLeanOfflineInvocation.reportEnvironmentKey)": workspace.report.path
        ])

        #expect(request.pauseSheetURL.path == workspace.sheet.path)
        #expect(request.evidenceDirectoryURL.path == workspace.evidence.path)
        #expect(request.reportURL.path == workspace.report.path)
    }

    private struct Workspace {
        var root: URL
        var sheet: URL
        var evidence: URL
        var report: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("torso-lean-invoke-\(UUID().uuidString)", isDirectory: true)
            sheet = root.appendingPathComponent("sheet.json")
            evidence = root.appendingPathComponent("evidence", isDirectory: true)
            report = root.appendingPathComponent("report.json")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
