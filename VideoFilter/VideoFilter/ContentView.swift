import SwiftUI
import UIKit
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import VideoProcessingTwo

private struct VideoPreviewView: View {
    @ObservedObject var previewState: VideoFilterPreviewState

    var body: some View {
        Group {
            if let image = previewState.displayCIImage {
                MetalView(ciImage: image, isFrontCamera: false, rotateForDeviceOrientation: false)
                    .background(Color.black)
            } else {
                Color.black
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Preparing video preview...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = VideoFilterViewModel()
    @State private var showingLoadSourceDialog = false
    @State private var showingImporter = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoPickerItem: PhotosPickerItem?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                previewSection
                Divider()
                controls
            }
            .navigationTitle("VideoFilter")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.startPreview()
            }
            .onDisappear {
                viewModel.stopPreview()
            }
            .confirmationDialog(
                "Load Video",
                isPresented: $showingLoadSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Files") {
                    showingImporter = true
                }

                Button("Camera Roll") {
                    showingPhotoPicker = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose where to load your video from.")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.movie, .video],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.loadVideo(url: url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoPickerItem,
                matching: .videos,
                preferredItemEncoding: .current
            )
            .task(id: selectedPhotoPickerItem) {
                guard let selectedPhotoPickerItem else { return }

                do {
                    if let pickedVideo = try await selectedPhotoPickerItem.loadTransferable(type: PickedVideo.self) {
                        viewModel.loadVideo(url: pickedVideo.url)
                    }
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }

                self.selectedPhotoPickerItem = nil
            }
            .sheet(isPresented: $showingShareSheet) {
                if let exportedVideoURL = viewModel.exportedVideoURL {
                    ShareSheet(items: [exportedVideoURL])
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("MovieReader-driven Metal preview with the full filter showcase catalog.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    showingLoadSourceDialog = true
                } label: {
                    Label("Load Video", systemImage: "video.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.exportFilteredVideo()
                } label: {
                    Label(viewModel.isExporting ? "Exporting..." : "Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.videoLoaded || viewModel.isExporting)
            }

            VStack(spacing: 4) {
                Text(viewModel.selectedVideoName)
                    .font(.caption.weight(.semibold))
                if let entry = viewModel.currentEntry {
                    Text("Current Filter: \(entry.name) · \(entry.category)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private var previewSection: some View {
        VideoPreviewView(previewState: viewModel.previewState)
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
    }

    private var controls: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("Filter") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Search filters", text: $viewModel.filterSearchText)
                            .textFieldStyle(.roundedBorder)

                        if viewModel.visibleFilterEntries.isEmpty {
                            Text("No filters match your search.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Picker(
                                "Filter",
                                selection: Binding(
                                    get: { viewModel.selectedFilterID },
                                    set: { viewModel.selectFilter($0) }
                                )
                            ) {
                                ForEach(viewModel.visibleFilterEntries) { entry in
                                    Text("\(entry.name) · \(entry.category)").tag(entry.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if let entry = viewModel.currentEntry {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                    .font(.headline)
                                Text(entry.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Category: \(entry.category)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                GroupBox("Parameters") {
                    if viewModel.currentParameters.isEmpty {
                        Text("This filter has no adjustable parameters.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.currentParameters) { parameter in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(parameter.title)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text(formatValue(viewModel.value(for: parameter)))
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }

                                    Slider(
                                        value: Binding(
                                            get: { viewModel.value(for: parameter) },
                                            set: { viewModel.setValue($0, for: parameter) }
                                        ),
                                        in: parameter.range,
                                        step: parameter.step
                                    )
                                }
                            }
                        }
                    }
                }

                GroupBox("Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.isExporting {
                            ProgressView(value: viewModel.exportProgress) {
                                Text("Exporting filtered video...")
                                    .font(.headline)
                            }
                            .progressViewStyle(.linear)
                        }

                        if let exportedVideoURL = viewModel.exportedVideoURL {
                            Label("Export ready", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.headline)

                            Text(exportedVideoURL.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                showingShareSheet = true
                            } label: {
                                Label("Share Export", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Clear Export") {
                                viewModel.resetExportState()
                            }
                            .buttonStyle(.plain)
                        } else if !viewModel.isExporting {
                            Text("Export preserves the selected filter and current parameter values.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let exportStatusMessage = viewModel.exportStatusMessage {
                            Text(exportStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let originalURL = received.file
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("VideoFilterImports", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

            let destinationURL = tempDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(originalURL.pathExtension.isEmpty ? "mov" : originalURL.pathExtension)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: originalURL, to: destinationURL)
            return Self(url: destinationURL)
        }
    }
}

#Preview {
    ContentView()
}
