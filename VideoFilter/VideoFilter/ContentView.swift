import AVKit
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = VideoFilterViewModel()
    @State private var showingImporter = false
    @State private var showingShareSheet = false
    @State private var showingExportPreview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                playerSection
                Divider()
                controls
            }
            .navigationTitle("VideoFilter")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.loadComposition()
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
            .sheet(isPresented: $showingShareSheet) {
                if let exportedVideoURL = viewModel.exportedVideoURL {
                    ShareSheet(items: [exportedVideoURL])
                }
            }
            .sheet(isPresented: $showingExportPreview) {
                if let exportedVideoURL = viewModel.exportedVideoURL {
                    ExportPreviewView(url: exportedVideoURL)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Load a video, audition filters, tweak the parameters, and export the result.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    showingImporter = true
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
                    Text("Current Filter: \(entry.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private var playerSection: some View {
        Group {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        Button {
                            viewModel.loadComposition()
                        } label: {
                            Label("Load Preview", systemImage: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
            }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("Filter") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Filter", selection: Binding(
                            get: { viewModel.selectedFilterID },
                            set: { viewModel.selectFilter($0) }
                        )) {
                            ForEach(viewModel.filterEntries) { entry in
                                Text(entry.name).tag(entry.id)
                            }
                        }
                        .pickerStyle(.menu)

                        if let entry = viewModel.currentEntry {
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
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

                            HStack(spacing: 12) {
                                Button {
                                    showingExportPreview = true
                                } label: {
                                    Label("Preview", systemImage: "play.rectangle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    showingShareSheet = true
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button("Clear Export") {
                                viewModel.resetExportState()
                            }
                            .buttonStyle(.plain)
                        } else if !viewModel.isExporting {
                            Text("Export writes the current filtered scene to a video file you can preview or share.")
                                .font(.caption)
                                .foregroundColor(.secondary)
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

private struct ExportPreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Export Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    player.play()
                }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
