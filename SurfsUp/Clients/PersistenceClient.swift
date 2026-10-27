import ComposableArchitecture
import Foundation

nonisolated struct SavedRunSidecar: Codable, Equatable, Sendable {
    var displayName: String
    var finishedAt: Date
    var clipDuration: TimeInterval
}

nonisolated struct SavedRunSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    var displayName: String
    var finishedAt: Date
    var clipDuration: TimeInterval
}

nonisolated struct SavedRunWrite: Equatable, Sendable {
    var id: UUID?
    var evidenceMissing: Bool
}

nonisolated enum PersistenceOpenFailure: Error, Equatable, Sendable {
    case videoUnavailable
}

nonisolated struct PersistenceClient: Sendable {
    var list: @Sendable () async -> [SavedRunSummary]
    var open: @Sendable (UUID) async -> Result<(SelectedClip, PoseTimeline), PersistenceOpenFailure>
    var writeFinished: @Sendable (SelectedClip, EvidenceRecord) async -> SavedRunWrite

    static let live = PersistenceClient(
        list: {
            await SavedRunStore.list(in: EvidenceFileWriter.storageDirectory())
        },
        open: { id in
            await SavedRunStore.open(id: id, in: EvidenceFileWriter.storageDirectory())
        },
        writeFinished: { clip, record in
            await SavedRunStore.writeFinished(clip: clip, record: record, in: EvidenceFileWriter.storageDirectory())
        }
    )

    static let test = PersistenceClient(
        list: { [] },
        open: { _ in .failure(.videoUnavailable) },
        writeFinished: { _, _ in SavedRunWrite(id: nil, evidenceMissing: true) }
    )
}

extension PersistenceClient: DependencyKey {
    nonisolated static let liveValue = PersistenceClient.live
    nonisolated static let testValue = PersistenceClient.test
}

extension DependencyValues {
    var persistenceClient: PersistenceClient {
        get { self[PersistenceClient.self] }
        set { self[PersistenceClient.self] = newValue }
    }
}

/// File operations for one evidence directory. `clipDuration` is stored and is not a match key.
nonisolated enum SavedRunStore {
    static func writeFinished(
        clip: SelectedClip,
        record: EvidenceRecord,
        in directory: URL,
        id: UUID = UUID()
    ) async -> SavedRunWrite {
        let videoURL = fileURL(id: id, in: directory, pathExtension: videoExtension(for: clip.url))
        let sidecarURL = fileURL(id: id, in: directory, pathExtension: "sidecar")
        let jsonURL = fileURL(id: id, in: directory, pathExtension: "json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: clip.url, to: videoURL)
            let sidecar = SavedRunSidecar(
                displayName: clip.url.lastPathComponent,
                finishedAt: Date(),
                clipDuration: record.clipDuration
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sidecar).write(to: sidecarURL, options: .atomic)
            _ = try EvidenceFileWriter.write(record, toFile: jsonURL)
            return SavedRunWrite(id: id, evidenceMissing: false)
        } catch {
            remove(id: id, in: directory)
            return SavedRunWrite(id: nil, evidenceMissing: true)
        }
    }

    static func list(in directory: URL) async -> [SavedRunSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let ids = Set(files.map { $0.deletingPathExtension().lastPathComponent }).compactMap(UUID.init(uuidString:))
        var summaries: [SavedRunSummary] = []
        for id in ids {
            let siblings = siblings(id: id, in: files)
            guard siblings.json != nil, siblings.sidecar != nil, siblings.video != nil else { continue }
            guard let sidecarURL = siblings.sidecar,
                  let data = try? Data(contentsOf: sidecarURL),
                  let sidecar = try? JSONDecoder().decode(SavedRunSidecar.self, from: data)
            else { continue }
            summaries.append(SavedRunSummary(
                id: id,
                displayName: sidecar.displayName,
                finishedAt: sidecar.finishedAt,
                clipDuration: sidecar.clipDuration
            ))
        }
        return summaries.sorted { lhs, rhs in
            if lhs.finishedAt != rhs.finishedAt {
                return lhs.finishedAt > rhs.finishedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func open(
        id: UUID,
        in directory: URL
    ) async -> Result<(SelectedClip, PoseTimeline), PersistenceOpenFailure> {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let siblings = siblings(id: id, in: files)
        guard let videoURL = siblings.video, siblings.json != nil else {
            return .failure(.videoUnavailable)
        }
        let clip: SelectedClip
        do {
            clip = try await VideoFrameSource.loadClip(from: videoURL)
        } catch {
            return .failure(.videoUnavailable)
        }
        guard let jsonURL = siblings.json,
              let data = try? Data(contentsOf: jsonURL),
              let record = try? JSONDecoder().decode(EvidenceRecord.self, from: data),
              let timeline = PoseTimeline(clipDuration: record.clipDuration, observations: record.observations)
        else {
            return .failure(.videoUnavailable)
        }
        guard clip.duration == record.clipDuration else {
            return .failure(.videoUnavailable)
        }
        return .success((clip, timeline))
    }

    /// Deletes this run's siblings. Not part of `PersistenceClient`.
    static func remove(id: UUID, in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in files where url.deletingPathExtension().lastPathComponent == id.uuidString {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func videoExtension(for url: URL) -> String {
        url.pathExtension.isEmpty ? "mov" : url.pathExtension
    }

    private static func fileURL(id: UUID, in directory: URL, pathExtension: String) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(pathExtension)
    }

    private static func siblings(id: UUID, in files: [URL]) -> (json: URL?, sidecar: URL?, video: URL?) {
        let mine = files.filter { $0.deletingPathExtension().lastPathComponent == id.uuidString }
        let json = mine.first { $0.pathExtension.lowercased() == "json" }
        let sidecar = mine.first { $0.pathExtension.lowercased() == "sidecar" }
        let video = mine.first { file in
            let pathExtension = file.pathExtension.lowercased()
            return pathExtension != "json" && pathExtension != "sidecar"
        }
        return (json, sidecar, video)
    }
}
