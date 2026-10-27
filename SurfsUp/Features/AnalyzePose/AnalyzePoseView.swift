import ComposableArchitecture
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AnalyzePoseView: View {
    @Bindable var store: StoreOf<AnalyzePoseFeature>
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingScheduledSource: BoardAxisScheduledSource?
    @State private var isOriginalImporterPresented = false

    var body: some View {
        VStack(spacing: AppConstants.UI.spacing) {
            screen
            if let notice = store.notice {
                Text(LocalizedStringKey(notice))
                    .font(Typography.body)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppConstants.UI.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .foregroundStyle(AppColors.text)
        .photosPicker(
            isPresented: Binding(
                get: { store.isPickerPresented },
                set: { store.send(.pickerPresentedChanged($0)) }
            ),
            selection: $pickerItem,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: store.session.clip?.id) { _, _ in
            pickerItem = nil
        }
        .fileImporter(
            isPresented: $isOriginalImporterPresented,
            allowedContentTypes: [.movie],
            onCompletion: importOriginal
        )
    }

    @ViewBuilder
    private var screen: some View {
        switch store.screen {
        case .needsAccess:
            Text("photoAccessRequired")
                .font(Typography.body)
                .multilineTextAlignment(.center)
            settingsButton
            chooseButton
            importOriginalMenu
        case .empty:
            chooseButton
            importOriginalMenu
        case .ready:
            chooseButton
            importOriginalMenu
            startButton
        case .running:
            Text("analyzing")
                .font(Typography.title)
            if let total = store.session.run?.framesTotal, total > 0 {
                ProgressView(
                    value: Double(store.session.run?.framesCompleted ?? 0),
                    total: Double(total)
                )
                .tint(AppColors.accent)
            } else {
                ProgressView()
                    .tint(AppColors.accent)
            }
            Text("\(store.session.run?.framesCompleted ?? 0)")
                .font(Typography.body)
                .monospacedDigit()
            Button("cancel") { store.send(.cancelTapped) }
                .buttonStyle(.bordered)
                .frame(minHeight: AppConstants.UI.controlHeight)
        case .review:
            if let clip = store.session.clip, let timeline = store.session.run?.timeline {
                PoseOverlayView(
                    clip: clip,
                    timeline: timeline,
                    playhead: store.playhead,
                    isPlaying: store.isPlaying,
                    onPlayhead: { store.send(.playheadMoved($0)) }
                )
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.UI.cornerRadius))
                TorsoLeanReadoutView(timeline: timeline, playhead: store.playhead)
                playbackControls(duration: clip.duration)
                if store.session.evidenceMissing {
                    Text("evidenceNotSaved")
                        .font(Typography.body)
                        .multilineTextAlignment(.center)
                }
            }
            chooseButton
            importOriginalMenu
        case .failed:
            Text(LocalizedStringKey(store.session.run?.failure ?? "analysisFailed"))
                .font(Typography.body)
                .multilineTextAlignment(.center)
            chooseButton
            importOriginalMenu
        }
    }

    private var importOriginalMenu: some View {
        Menu {
            ForEach(BoardAxisScheduledSource.boardAxisClips) { source in
                Button(source.sourceFilename) {
                    pendingScheduledSource = source
                    isOriginalImporterPresented = true
                }
            }
        } label: {
            Text("importOriginalVideo")
        }
        .buttonStyle(.bordered)
        .frame(minHeight: AppConstants.UI.controlHeight)
    }

    private func importOriginal(_ result: Result<URL, Error>) {
        guard let expected = pendingScheduledSource else {
            store.send(.analysisFailed("analysisFailed"))
            return
        }
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                return
            }
            store.send(.analysisFailed("analysisFailed"))
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let loadClipURL = try BoardAxisSourceIdentity.fileForLoadClip(importedFrom: url, expected: expected)
                store.send(.videoURLPicked(loadClipURL))
            } catch BoardAxisSourceIdentityError.mismatch {
                store.send(.analysisFailed("sourceFileMismatch"))
            } catch {
                store.send(.analysisFailed("analysisFailed"))
            }
        }
    }

    private var chooseButton: some View {
        Button("chooseVideo") { store.send(.chooseTapped) }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .frame(minHeight: AppConstants.UI.controlHeight)
    }

    private var startButton: some View {
        Button("startAnalysis") { store.send(.startTapped) }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .frame(minHeight: AppConstants.UI.controlHeight)
    }

    private var settingsButton: some View {
        Button("openSettings") {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
        .buttonStyle(.bordered)
        .frame(minHeight: AppConstants.UI.controlHeight)
    }

    private func playbackControls(duration: TimeInterval) -> some View {
        let canStep = store.session.clip
            .map { FrameStep.duration(nominalFrameRate: $0.nominalFrameRate) != nil } ?? false
        return VStack(spacing: AppConstants.UI.spacing) {
            HStack(spacing: AppConstants.UI.spacing) {
                Button { store.send(.stepBackwardTapped) } label: {
                    Label("stepBackward", systemImage: "backward.frame")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(!canStep)
                Button("play") { store.send(.playTapped) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                Button("pause") { store.send(.pauseTapped) }
                    .buttonStyle(.bordered)
                Button { store.send(.stepForwardTapped) } label: {
                    Label("stepForward", systemImage: "forward.frame")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(!canStep)
            }
            .frame(minHeight: AppConstants.UI.controlHeight)
            Slider(
                value: Binding(
                    get: { store.playhead },
                    set: { store.send(.playheadMoved($0)) }
                ),
                in: 0...duration,
                onEditingChanged: { editing in
                    if editing { store.send(.pauseTapped) }
                }
            )
            .tint(AppColors.accent)
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let picked = try await item.loadTransferable(type: PickedVideo.self) else { return }
            store.send(.videoURLPicked(picked.url))
        } catch {
            store.send(.analysisFailed("analysisFailed"))
        }
    }
}

struct PickedVideo: Transferable {
    var url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}
