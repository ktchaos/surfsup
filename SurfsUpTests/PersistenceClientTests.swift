import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import SurfsUp

struct PersistenceClientTests {
    @Test func sidecarRoundTripsDisplayNameFinishedAtAndClipDuration() throws {
        _ = PersistenceClient.self
        let sidecar = SavedRunSidecar(
            displayName: "wave.mov",
            finishedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            clipDuration: 2
        )
        let data = try JSONEncoder().encode(sidecar)
        let decoded = try JSONDecoder().decode(SavedRunSidecar.self, from: data)
        #expect(decoded.displayName == "wave.mov")
        #expect(decoded.finishedAt == sidecar.finishedAt)
        #expect(decoded.clipDuration == 2)
    }

    @Test func writeFinishedCopiesTheTripleAndListReturnsIt() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!directory.path.contains("PoseEvidence"))

        let clip = try makeClip(named: "wave.mov", bytes: Data("video-bytes".utf8))
        defer { try? FileManager.default.removeItem(at: clip.url.deletingLastPathComponent()) }
        let record = try makeRecord(clipDuration: 2)

        let written = await SavedRunStore.writeFinished(clip: clip, record: record, in: directory)
        let id = try #require(written.id)
        #expect(written.evidenceMissing == false)

        let stem = directory.appendingPathComponent(id.uuidString)
        let videoURL = stem.appendingPathExtension("mov")
        let sidecarURL = stem.appendingPathExtension("sidecar")
        let jsonURL = stem.appendingPathExtension("json")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == [
            videoURL.lastPathComponent,
            sidecarURL.lastPathComponent,
            jsonURL.lastPathComponent,
        ].sorted())
        #expect(try Data(contentsOf: videoURL) == Data("video-bytes".utf8))

        let sidecar = try JSONDecoder().decode(SavedRunSidecar.self, from: Data(contentsOf: sidecarURL))
        #expect(sidecar.displayName == "wave.mov")
        #expect(sidecar.clipDuration == record.clipDuration)
        let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: jsonURL))
        #expect(stored.clipDuration == record.clipDuration)
        #expect(stored.observations.count == record.observations.count)

        let listed = await SavedRunStore.list(in: directory)
        #expect(listed.count == 1)
        #expect(listed[0].id == id)
        #expect(listed[0].displayName == "wave.mov")
        #expect(listed[0].finishedAt == sidecar.finishedAt)
        #expect(listed[0].clipDuration == record.clipDuration)
    }

    @Test func twoWritesWithTheSameDurationListAsTwoIds() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord(clipDuration: 2)
        let firstClip = try makeClip(named: "first.mov", bytes: Data("first-video".utf8))
        let secondClip = try makeClip(named: "second.mov", bytes: Data("second-video".utf8))
        defer {
            try? FileManager.default.removeItem(at: firstClip.url.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: secondClip.url.deletingLastPathComponent())
        }

        let first = await SavedRunStore.writeFinished(clip: firstClip, record: record, in: directory)
        let second = await SavedRunStore.writeFinished(clip: secondClip, record: record, in: directory)
        let firstID = try #require(first.id)
        let secondID = try #require(second.id)
        #expect(firstID != secondID)

        let listed = await SavedRunStore.list(in: directory)
        #expect(Set(listed.map(\.id)) == Set([firstID, secondID]))
        #expect(listed.allSatisfy { $0.clipDuration == 2 })
        let firstVideo = try Data(contentsOf: directory.appendingPathComponent(firstID.uuidString).appendingPathExtension("mov"))
        let secondVideo = try Data(contentsOf: directory.appendingPathComponent(secondID.uuidString).appendingPathExtension("mov"))
        #expect(firstVideo != secondVideo)
        if listed[0].finishedAt == listed[1].finishedAt {
            #expect(listed[0].id.uuidString < listed[1].id.uuidString)
        } else {
            #expect(listed[0].finishedAt > listed[1].finishedAt)
        }
    }

    @Test func openingADeletedVideoDoesNotReadTheOtherRun() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("source-first.mov")
        let secondURL = directory.appendingPathComponent("source-second.mov")
        let firstDuration = try await writeMovie(to: firstURL, fill: 0x11)
        let secondDuration = try await writeMovie(to: secondURL, fill: 0x22)
        #expect(firstDuration > 0)
        #expect(firstDuration == secondDuration)

        let record = try makeRecord(clipDuration: firstDuration)
        let firstClip = makeClip(url: firstURL, duration: firstDuration)
        let secondClip = makeClip(url: secondURL, duration: secondDuration)
        let firstWrite = await SavedRunStore.writeFinished(clip: firstClip, record: record, in: directory)
        let secondWrite = await SavedRunStore.writeFinished(clip: secondClip, record: record, in: directory)
        let firstID = try #require(firstWrite.id)
        let secondID = try #require(secondWrite.id)

        let secondVideo = directory.appendingPathComponent(secondID.uuidString).appendingPathExtension("mov")
        let secondBytes = try Data(contentsOf: secondVideo)
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent(firstID.uuidString).appendingPathExtension("mov")
        )

        let opened = await SavedRunStore.open(id: firstID, in: directory)
        guard case .failure(.videoUnavailable) = opened else {
            Issue.record("A missing video must be unavailable")
            return
        }
        #expect(try Data(contentsOf: secondVideo) == secondBytes)

        let other = await SavedRunStore.open(id: secondID, in: directory)
        guard case let .success(value) = other else {
            Issue.record("The other run's video must still open")
            return
        }
        #expect(value.0.url == secondVideo)
        #expect(value.0.id != secondID)
    }

    @Test func aLoneJSONWithoutASidecarIsExcludedAndStaysOnDisk() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord(clipDuration: 2)
        let clip = try makeClip(named: "kept.mov", bytes: Data("kept".utf8))
        defer { try? FileManager.default.removeItem(at: clip.url.deletingLastPathComponent()) }
        let written = await SavedRunStore.writeFinished(clip: clip, record: record, in: directory)
        let savedID = try #require(written.id)

        let loneID = UUID()
        let loneURL = directory.appendingPathComponent(loneID.uuidString).appendingPathExtension("json")
        _ = try EvidenceFileWriter.write(record, toFile: loneURL)

        let listed = await SavedRunStore.list(in: directory)
        #expect(listed.map(\.id) == [savedID])
        #expect(FileManager.default.fileExists(atPath: loneURL.path))
    }

    @Test func openIsUnavailableWhenTheLoadedDurationDiffers() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let movieURL = directory.appendingPathComponent("short.mov")
        let loadedDuration = try await writeMovie(to: movieURL, fill: 0x33)
        let loaded = try await VideoFrameSource.loadClip(from: movieURL)
        #expect(loaded.duration == loadedDuration)
        #expect(loaded.duration > 0)
        let mismatched = loaded.duration + 0.001
        #expect(mismatched != loaded.duration)

        let record = try makeRecord(clipDuration: mismatched)
        let clip = makeClip(url: movieURL, duration: loaded.duration)
        let written = await SavedRunStore.writeFinished(clip: clip, record: record, in: directory)
        let id = try #require(written.id)
        let stored = try JSONDecoder().decode(
            EvidenceRecord.self,
            from: Data(contentsOf: directory.appendingPathComponent(id.uuidString).appendingPathExtension("json"))
        )
        let reloaded = try await VideoFrameSource.loadClip(
            from: directory.appendingPathComponent(id.uuidString).appendingPathExtension("mov")
        )
        #expect(reloaded.duration != stored.clipDuration)

        let opened = await SavedRunStore.open(id: id, in: directory)
        guard case .failure(.videoUnavailable) = opened else {
            Issue.record("A duration mismatch must be unavailable")
            return
        }
    }

    @Test func aFailedWriteDeletesPartialsAndReportsEvidenceMissing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let jsonURL = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try Data("{}".utf8).write(to: jsonURL)
        let clip = try makeClip(named: "partial.mov", bytes: Data("partial".utf8))
        defer { try? FileManager.default.removeItem(at: clip.url.deletingLastPathComponent()) }
        let record = try makeRecord(clipDuration: 2)

        let written = await SavedRunStore.writeFinished(clip: clip, record: record, in: directory, id: id)
        #expect(written == SavedRunWrite(id: nil, evidenceMissing: true))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.filter { $0.hasPrefix(id.uuidString) }.isEmpty)
    }

    @Test func removeDeletesTheJSONSidecarAndVideo() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try makeClip(named: "done.mov", bytes: Data("done".utf8))
        defer { try? FileManager.default.removeItem(at: clip.url.deletingLastPathComponent()) }
        let written = await SavedRunStore.writeFinished(
            clip: clip,
            record: try makeRecord(clipDuration: 2),
            in: directory
        )
        let id = try #require(written.id)
        let namesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(namesBefore.filter { $0.hasPrefix(id.uuidString) }.count == 3)

        SavedRunStore.remove(id: id, in: directory)
        let namesAfter = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(namesAfter.filter { $0.hasPrefix(id.uuidString) }.isEmpty)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeClip(named name: String, bytes: Data, duration: TimeInterval = 2) throws -> SelectedClip {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url)
        return makeClip(url: url, duration: duration)
    }

    private func makeClip(url: URL, duration: TimeInterval) -> SelectedClip {
        SelectedClip(
            id: UUID(),
            url: url,
            duration: duration,
            nominalFrameRate: 30,
            displaySize: CGSize(width: 64, height: 64),
            displayTransform: .identity
        )!
    }

    private func writeMovie(to url: URL, fill: UInt8) async throws -> TimeInterval {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoReadError.unreadableAsset }
        writer.startSession(atSourceTime: .zero)
        let times = [CMTime.zero, CMTime(value: 1, timescale: 30)]
        for time in times {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard adaptor.append(try pixelBuffer(fill: fill), withPresentationTime: time) else {
                throw writer.error ?? VideoReadError.unreadableAsset
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 30))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoReadError.unreadableAsset }
        return try await VideoFrameSource.loadClip(from: url).duration
    }

    private func pixelBuffer(fill: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw VideoReadError.unreadableAsset }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(fill), CVPixelBufferGetDataSize(buffer))
        }
        return buffer
    }

    private func makeRecord(clipDuration: TimeInterval) throws -> EvidenceRecord {
        let landmark = Landmark(joint: .nose, x: 0.5, y: 0.5, confidence: 1)!
        let body = BodyObservation(landmarks: [landmark], selectionArea: 0)!
        let observation = FrameObservation(
            start: 0,
            end: clipDuration,
            clipDuration: clipDuration,
            body: body
        )!
        let timeline = PoseTimeline(clipDuration: clipDuration, observations: [observation])!
        return EvidenceRecord(
            timeline: timeline,
            elapsedSeconds: 1,
            decodedFrameCount: 1,
            attemptedFrameCount: 1
        )!
    }
}
