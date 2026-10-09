import Foundation

nonisolated enum EvidenceWriteError: Error {
    case alreadyExists
}

nonisolated enum EvidenceFileWriter {
    static func storageDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PoseEvidence", isDirectory: true)
    }

    /// Writes a new file. A nil record is a cancelled or failed run and writes nothing.
    static func writeFinished(_ record: EvidenceRecord?, to directory: URL) throws -> URL? {
        guard let record else { return nil }
        return try write(record, to: directory)
    }

    static func write(_ record: EvidenceRecord, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw EvidenceWriteError.alreadyExists }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
        return url
    }
}
