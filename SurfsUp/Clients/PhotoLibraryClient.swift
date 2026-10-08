import ComposableArchitecture
import Foundation
import Photos

nonisolated enum PhotoLibraryAccess: Equatable, Sendable {
    case granted
    case denied
}

nonisolated enum PhotoLibraryError: Error {
    case unimplemented
}

nonisolated struct PhotoLibraryClient: Sendable {
    var authorization: @Sendable () async -> PhotoLibraryAccess
    var makeClip: @Sendable (URL) async throws -> SelectedClip

    static let live = PhotoLibraryClient(
        authorization: { await liveAuthorization() },
        makeClip: { url in try await VideoFrameSource.loadClip(from: url) }
    )

    static let test = PhotoLibraryClient(
        authorization: { .granted },
        makeClip: { _ in throw PhotoLibraryError.unimplemented }
    )

    private static func liveAuthorization() async -> PhotoLibraryAccess {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .granted
        @unknown default:
            return .denied
        }
    }
}

extension PhotoLibraryClient: DependencyKey {
    nonisolated static let liveValue = PhotoLibraryClient.live
    nonisolated static let testValue = PhotoLibraryClient.test
}

extension DependencyValues {
    var photoLibraryClient: PhotoLibraryClient {
        get { self[PhotoLibraryClient.self] }
        set { self[PhotoLibraryClient.self] = newValue }
    }
}
