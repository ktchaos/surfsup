import Foundation

/// Turns three supplied paths into a `TorsoLeanOfflineRunner.Request`.
///
/// The app does not call this. The explicit entry point is the `TorsoLeanOffline`
/// test scheme, which passes the three paths in from the environment and then
/// calls `TorsoLeanOfflineRunner.run`.
nonisolated enum TorsoLeanOfflineInvocation {
    static let pauseSheetEnvironmentKey = "TORSO_LEAN_PAUSE_SHEET"
    static let evidenceDirectoryEnvironmentKey = "TORSO_LEAN_EVIDENCE_DIRECTORY"
    static let reportEnvironmentKey = "TORSO_LEAN_REPORT"

    enum ValidationError: Error, Equatable, Sendable {
        case missingPauseSheetPath
        case missingEvidenceDirectoryPath
        case missingReportPath
        case pauseSheetPathNotAbsolute
        case evidenceDirectoryPathNotAbsolute
        case reportPathNotAbsolute
        case pauseSheetMissing
        case pauseSheetNotAFile
        case evidenceDirectoryMissing
        case evidenceDirectoryNotADirectory
        case pauseSheetInsideEvidenceDirectory
        case outputCollidesWithPauseSheet
        case outputCollidesWithEvidence
    }

    static func requestFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> TorsoLeanOfflineRunner.Request {
        try request(
            pauseSheetPath: environmentValue(pauseSheetEnvironmentKey, in: environment),
            evidenceDirectoryPath: environmentValue(evidenceDirectoryEnvironmentKey, in: environment),
            reportPath: environmentValue(reportEnvironmentKey, in: environment),
            fileManager: fileManager
        )
    }

    /// A real environment value wins. An empty value or an unexpanded `$(...)`
    /// build setting does not. `TEST_RUNNER_` is the name `xcodebuild` can forward.
    private static func environmentValue(_ key: String, in environment: [String: String]) -> String? {
        if let direct = usablePath(environment[key]) {
            return direct
        }
        return usablePath(environment["TEST_RUNNER_\(key)"])
    }

    private static func usablePath(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    static func request(
        pauseSheetPath: String?,
        evidenceDirectoryPath: String?,
        reportPath: String?,
        fileManager: FileManager = .default
    ) throws -> TorsoLeanOfflineRunner.Request {
        let sheetPath = try required(pauseSheetPath, missing: .missingPauseSheetPath)
        let evidencePath = try required(evidenceDirectoryPath, missing: .missingEvidenceDirectoryPath)
        let outputPath = try required(reportPath, missing: .missingReportPath)
        guard (sheetPath as NSString).isAbsolutePath else { throw ValidationError.pauseSheetPathNotAbsolute }
        guard (evidencePath as NSString).isAbsolutePath else { throw ValidationError.evidenceDirectoryPathNotAbsolute }
        guard (outputPath as NSString).isAbsolutePath else { throw ValidationError.reportPathNotAbsolute }

        let sheetURL = canonical(URL(fileURLWithPath: sheetPath))
        let evidenceURL = canonical(URL(fileURLWithPath: evidencePath))
        let reportURL = canonical(URL(fileURLWithPath: outputPath))

        var sheetIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sheetURL.path, isDirectory: &sheetIsDirectory) else {
            throw ValidationError.pauseSheetMissing
        }
        guard !sheetIsDirectory.boolValue else {
            throw ValidationError.pauseSheetNotAFile
        }

        var evidenceIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: evidenceURL.path, isDirectory: &evidenceIsDirectory) else {
            throw ValidationError.evidenceDirectoryMissing
        }
        guard evidenceIsDirectory.boolValue else {
            throw ValidationError.evidenceDirectoryNotADirectory
        }
        if isInside(sheetURL, evidenceURL) {
            throw ValidationError.pauseSheetInsideEvidenceDirectory
        }
        if sheetURL.path == reportURL.path {
            throw ValidationError.outputCollidesWithPauseSheet
        }
        if isInside(reportURL, evidenceURL) {
            throw ValidationError.outputCollidesWithEvidence
        }

        return TorsoLeanOfflineRunner.Request(
            pauseSheetURL: sheetURL,
            evidenceDirectoryURL: evidenceURL,
            reportURL: reportURL
        )
    }

    private static func required(_ value: String?, missing: ValidationError) throws -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { throw missing }
        return trimmed
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isInside(_ url: URL, _ directory: URL) -> Bool {
        url.path == directory.path || url.path.hasPrefix(directory.path + "/")
    }
}
