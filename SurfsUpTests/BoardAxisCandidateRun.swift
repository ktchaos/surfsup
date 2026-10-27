import Foundation
import Testing
@testable import SurfsUp

/// Manual candidate entry. Returns without reading videos unless the four run variables are set.
/// `BOARD_AXIS_LABELS` and `BOARD_AXIS_MANIFEST` fail before a candidate file is written.
struct BoardAxisCandidateRun {
    @Test func manualCandidateRun() async throws {
        guard let input = try BoardAxisCandidateRunner.invocation(from: ProcessInfo.processInfo.environment) else {
            return
        }
        try await BoardAxisCandidateRunner.run(input)
    }
}
