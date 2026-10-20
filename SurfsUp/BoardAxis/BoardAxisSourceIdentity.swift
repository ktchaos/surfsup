import CryptoKit
import Foundation

/// One locked schedule clip, identified by filename and source hash.
///
/// The hash is the identity check. The filename is only the label the user selects.
nonisolated struct BoardAxisScheduledSource: Equatable, Identifiable, Sendable {
    var sourceFilename: String
    var sourceSha256: String

    var id: String { sourceFilename }

    /// The five scheduled originals. Duration is intentionally absent.
    static let boardAxisClips: [BoardAxisScheduledSource] = [
        BoardAxisScheduledSource(
            sourceFilename: "videoplayback.mp4",
            sourceSha256: "3324ff9969f3ec1f1e28cdbb3d3c0e837f675cccb0168811ff1ed528d12f81e3"
        ),
        BoardAxisScheduledSource(
            sourceFilename: "videoplayback (1).mp4",
            sourceSha256: "d32eecd77f07c85ff9e4bb686ab59a36f8b7bceacd14389bec4bee4270112d2c"
        ),
        BoardAxisScheduledSource(
            sourceFilename: "videoplayback (2).mp4",
            sourceSha256: "d9f6b573f57a74b5d0e61a21934f392ea5863cd7ca37a49cfb861593692b6d50"
        ),
        BoardAxisScheduledSource(
            sourceFilename: "snapinsta-1791489771157.mp4",
            sourceSha256: "fd3fd8139ae57e8032ceb72de1b8de2f7556231f9af1799940ce150dfcb6249a"
        ),
        BoardAxisScheduledSource(
            sourceFilename: "snapinsta-1791470847744.mp4",
            sourceSha256: "3eeea5ba2a9e382e6b7dfbd6b7e92fa2fc5458f7dc3d89af3dfc7b998ef04182"
        ),
    ]
}

nonisolated enum BoardAxisSourceIdentityError: Error, Equatable, Sendable {
    case mismatch
    case unreadable
}

/// Hashes the file that `VideoFrameSource.loadClip` will open.
///
/// A mismatch throws before the caller may start pose analysis. The filename and duration are not consulted.
nonisolated enum BoardAxisSourceIdentity {
    static func digest(of url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BoardAxisSourceIdentityError.unreadable
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Copies `imported` to a stable temporary file and returns that URL only when its bytes match `expected`.
    static func fileForLoadClip(importedFrom imported: URL, expected: BoardAxisScheduledSource) throws -> URL {
        let ext = imported.pathExtension.isEmpty ? "mov" : imported.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: imported, to: destination)
        } catch {
            throw BoardAxisSourceIdentityError.unreadable
        }
        let computed: String
        do {
            computed = try digest(of: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        guard computed == expected.sourceSha256.lowercased() else {
            try? FileManager.default.removeItem(at: destination)
            throw BoardAxisSourceIdentityError.mismatch
        }
        return destination
    }
}
