import Foundation

/// Failures of the offline pause-sheet run. Scoring rules stay in `TorsoLeanVisualCheck`.
nonisolated enum TorsoLeanOfflineError: Error, Equatable, Sendable {
    case outputCollidesWithPauseSheet
    case outputCollidesWithEvidence
    case evidenceDirectoryMissing
    case missingEvidence(TimeInterval)
    case ambiguousEvidence(TimeInterval)
    case invalidEvidence(String)
}

/// File written by `TorsoLeanOfflineRunner`. It is not a pause sheet.
nonisolated struct TorsoLeanOfflineReport: Equatable, Sendable, Codable {
    var clips: [TorsoLeanClipReport]
    var matchedEvidence: [MatchedEvidence]

    struct MatchedEvidence: Equatable, Sendable, Codable {
        var clipDuration: TimeInterval
        var files: [String]
    }
}

/// Scores an already-written pause sheet against evidence files in one directory.
///
/// Call this only with the three paths supplied for that run. It does not search
/// other folders and nothing in the app calls it at launch.
///
/// Exact `clipDuration` separates different clips. More than one file can share a
/// duration. Those files are one match only when their observations are equal.
/// Observations that disagree are an error; the runner does not choose a file.
nonisolated enum TorsoLeanOfflineRunner {
    struct Request: Sendable {
        var pauseSheetURL: URL
        var evidenceDirectoryURL: URL
        var reportURL: URL
    }

    static func run(_ request: Request, fileManager: FileManager = .default) throws -> TorsoLeanOfflineReport {
        let sheetURL = canonical(request.pauseSheetURL)
        let evidenceDirectoryURL = canonical(request.evidenceDirectoryURL)
        let reportURL = canonical(request.reportURL)

        if sameFile(reportURL, sheetURL) {
            throw TorsoLeanOfflineError.outputCollidesWithPauseSheet
        }
        if sameFile(reportURL, evidenceDirectoryURL) {
            throw TorsoLeanOfflineError.outputCollidesWithEvidence
        }

        let sheetData = try Data(contentsOf: sheetURL)
        let sheet = try TorsoLeanVisualCheck.decodeSheet(sheetData)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: evidenceDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw TorsoLeanOfflineError.evidenceDirectoryMissing
        }

        let contents = try fileManager.contentsOfDirectory(
            at: evidenceDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        if contents.contains(where: { sameFile(canonical($0), reportURL) }) {
            throw TorsoLeanOfflineError.outputCollidesWithEvidence
        }

        let jsonURLs = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var loaded: [LoadedEvidence] = []
        loaded.reserveCapacity(jsonURLs.count)
        for url in jsonURLs {
            let data = try Data(contentsOf: url)
            do {
                let record = try JSONDecoder().decode(EvidenceRecord.self, from: data)
                loaded.append(LoadedEvidence(url: url, record: record))
            } catch {
                throw TorsoLeanOfflineError.invalidEvidence(url.lastPathComponent)
            }
        }

        var clips: [TorsoLeanClipReport] = []
        var matched: [TorsoLeanOfflineReport.MatchedEvidence] = []
        clips.reserveCapacity(sheet.clips.count)
        for clip in sheet.clips {
            let matches = loaded.filter { $0.record.clipDuration == clip.clipDuration }
            guard let first = matches.first else {
                throw TorsoLeanOfflineError.missingEvidence(clip.clipDuration)
            }
            let series = first.record.observations
            guard matches.allSatisfy({ $0.record.observations == series }) else {
                throw TorsoLeanOfflineError.ambiguousEvidence(clip.clipDuration)
            }
            guard let timeline = PoseTimeline(clipDuration: first.record.clipDuration, observations: series) else {
                throw TorsoLeanOfflineError.invalidEvidence(first.url.lastPathComponent)
            }
            clips.append(try TorsoLeanVisualCheck.score(clip: clip, timeline: timeline))
            matched.append(
                TorsoLeanOfflineReport.MatchedEvidence(
                    clipDuration: clip.clipDuration,
                    files: matches.map(\.url.lastPathComponent).sorted()
                )
            )
        }

        let report = TorsoLeanOfflineReport(clips: clips, matchedEvidence: matched)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let parent = reportURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        return report
    }

    private struct LoadedEvidence {
        var url: URL
        var record: EvidenceRecord
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        canonical(lhs).path == canonical(rhs).path
    }
}
