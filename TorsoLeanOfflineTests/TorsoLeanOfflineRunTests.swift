import Foundation
import Testing
@testable import SurfsUp

/// Explicit entry point. This target is not part of the SurfsUp test scheme.
/// It runs only when the TorsoLeanOffline scheme is invoked with the three paths.
struct TorsoLeanOfflineRunTests {
    @Test func runWithSuppliedPaths() throws {
        let lines = pathFileLines()
        let environment = ProcessInfo.processInfo.environment
        let request = try TorsoLeanOfflineInvocation.request(
            pauseSheetPath: suppliedPath(
                TorsoLeanOfflineInvocation.pauseSheetEnvironmentKey,
                fileLine: lines.first,
                environment: environment
            ),
            evidenceDirectoryPath: suppliedPath(
                TorsoLeanOfflineInvocation.evidenceDirectoryEnvironmentKey,
                fileLine: lines.dropFirst().first,
                environment: environment
            ),
            reportPath: suppliedPath(
                TorsoLeanOfflineInvocation.reportEnvironmentKey,
                fileLine: lines.dropFirst(2).first,
                environment: environment
            )
        )
        _ = try TorsoLeanOfflineRunner.run(request)
    }

    private func suppliedPath(_ key: String, fileLine: String?, environment: [String: String]) -> String? {
        let candidates = [environment[key], environment["TEST_RUNNER_\(key)"], fileLine]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return trimmed
            }
        }
        return nil
    }

    private func pathFileLines() -> [String] {
        final class Token {}
        guard let url = Bundle(for: Token.self).url(forResource: "TorsoLeanOfflinePaths", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
