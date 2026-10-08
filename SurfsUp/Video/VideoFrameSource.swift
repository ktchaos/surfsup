import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO

nonisolated enum VideoReadError: Error, Equatable {
    case unreadableAsset
}

nonisolated struct DecodedFrame: @unchecked Sendable {
    var presentationTime: TimeInterval
    var duration: TimeInterval
    var preferredTransform: CGAffineTransform
    var pixelBuffer: CVPixelBuffer
}

/// Reads every decoded video frame. This type does not skip, scale, or sample.
nonisolated enum VideoFrameSource {
    static func imageOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0):
            return .right
        case (0, -1, 1, 0):
            return .left
        case (-1, 0, 0, -1):
            return .down
        case (0, 1, 1, 0):
            return .leftMirrored
        case (0, -1, -1, 0):
            return .rightMirrored
        case (1, 0, 0, -1):
            return .upMirrored
        case (-1, 0, 0, 1):
            return .downMirrored
        default:
            return .up
        }
    }

    static func loadClip(from url: URL) async throws -> SelectedClip {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0, duration.isFinite else { throw VideoReadError.unreadableAsset }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoReadError.unreadableAsset }
        let rate = try await track.load(.nominalFrameRate)
        let transform = try await track.load(.preferredTransform)
        let natural = try await track.load(.naturalSize)
        let display = CGRect(origin: .zero, size: natural).applying(transform).standardized.size
        guard let clip = SelectedClip(
            id: UUID(),
            url: url,
            duration: duration,
            nominalFrameRate: rate,
            displaySize: display,
            displayTransform: transform
        ) else {
            throw VideoReadError.unreadableAsset
        }
        return clip
    }

    /// Calls `consume` once per decoded frame and does not retain the pixel buffer after it returns.
    static func forEachDecodedFrame(
        of clip: SelectedClip,
        consume: (DecodedFrame) throws -> Void
    ) async throws {
        let asset = AVURLAsset(url: clip.url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw VideoReadError.unreadableAsset
        }
        guard let track = tracks.first else { throw VideoReadError.unreadableAsset }
        let transform = try await track.load(.preferredTransform)
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoReadError.unreadableAsset
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoReadError.unreadableAsset }
        reader.add(output)
        guard reader.startReading() else { throw VideoReadError.unreadableAsset }

        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                CMSampleBufferInvalidate(sample)
                throw CancellationError()
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                CMSampleBufferInvalidate(sample)
                continue
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration = CMSampleBufferGetDuration(sample).seconds
            do {
                try consume(DecodedFrame(
                    presentationTime: presentationTime,
                    duration: duration,
                    preferredTransform: transform,
                    pixelBuffer: pixelBuffer
                ))
            } catch {
                CMSampleBufferInvalidate(sample)
                throw error
            }
            CMSampleBufferInvalidate(sample)
        }
        if reader.status == .failed {
            throw reader.error ?? VideoReadError.unreadableAsset
        }
    }
}
