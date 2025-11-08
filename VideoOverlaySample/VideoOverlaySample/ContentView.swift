//
//  ContentView.swift
//  VideoOverlaySample
//
//  Main view with overlay controls and video export
//

import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = OverlayViewModel()
    @State private var showingVideoPicker = false
    @State private var showingPhotoPicker = false
    @State private var showingGIFPicker = false
    @State private var showingVideoPlayer = false

    enum PickerType {
        case video, photo, gif
    }
    @State private var activePickerType: PickerType?
    @State private var pendingPickerType: PickerType?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Video Overlay Composer")
                .font(.title2.bold())
                .padding()

            // File selection buttons
            HStack(spacing: 12) {
                Button {
                    pendingPickerType = .video
                    activePickerType = .video
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.videoLoaded ? "checkmark.circle.fill" : "video")
                            .foregroundColor(viewModel.videoLoaded ? .green : .primary)
                        Text("Load Video")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    pendingPickerType = .photo
                    activePickerType = .photo
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.photoLoaded ? "checkmark.circle.fill" : "photo")
                            .foregroundColor(viewModel.photoLoaded ? .green : .primary)
                        Text("Load Photo")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    pendingPickerType = .gif
                    activePickerType = .gif
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.gifLoaded ? "checkmark.circle.fill" : "square.stack.3d.forward.dottedline")
                            .foregroundColor(viewModel.gifLoaded ? .green : .primary)
                        Text("Load GIF")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Photo overlay controls
                    GroupBox("Photo Overlay") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Opacity")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.photoOpacity, in: 0...1)
                                Text("\(Int(viewModel.photoOpacity * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Scale")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.photoScale, in: 0.1...1.0)
                                Text("\(Int(viewModel.photoScale * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("X Position")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.photoPosition.x, in: 0...1)
                                Text("\(Int(viewModel.photoPosition.x * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Y Position")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.photoPosition.y, in: 0...1)
                                Text("\(Int(viewModel.photoPosition.y * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                    }

                    // GIF overlay controls
                    GroupBox("GIF Overlay") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Opacity")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.gifOpacity, in: 0...1)
                                Text("\(Int(viewModel.gifOpacity * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Scale")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.gifScale, in: 0.1...1.0)
                                Text("\(Int(viewModel.gifScale * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("X Position")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.gifPosition.x, in: 0...1)
                                Text("\(Int(viewModel.gifPosition.x * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Y Position")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $viewModel.gifPosition.y, in: 0...1)
                                Text("\(Int(viewModel.gifPosition.y * 100))%")
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                    }

                    // Export section
                    GroupBox("Export") {
                        VStack(spacing: 16) {
                            if viewModel.isExporting {
                                VStack(spacing: 12) {
                                    ProgressView(value: viewModel.exportProgress) {
                                        Text("Exporting video...")
                                            .font(.headline)
                                    }
                                    .progressViewStyle(.linear)

                                    Text("\(Int(viewModel.exportProgress * 100))% complete")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else if let _ = viewModel.exportedVideoURL {
                                VStack(spacing: 12) {
                                    Label("Export Complete!", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.headline)

                                    Button {
                                        showingVideoPlayer = true
                                    } label: {
                                        Label("Play Video", systemImage: "play.circle.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Export Again") {
                                        viewModel.exportVideo()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                Button {
                                    print("ContentView: Export button tapped, videoLoaded = \(viewModel.videoLoaded)")
                                    viewModel.exportVideo()
                                } label: {
                                    Label("Export Video with Overlays", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.isExporting || !viewModel.videoLoaded)
                            }

                            if let errorMessage = viewModel.errorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { activePickerType != nil },
                set: { if !$0 { activePickerType = nil } }
            ),
            allowedContentTypes: {
                switch activePickerType {
                case .video:
                    return [.movie, .video]
                case .photo:
                    return [.image]
                case .gif:
                    return [.gif]
                case .none:
                    return [.data]
                }
            }(),
            allowsMultipleSelection: false
        ) { result in
            print("File picker result received for type: \(String(describing: pendingPickerType))")

            switch result {
            case .success(let urls):
                if let url = urls.first {
                    print("File selected: \(url)")
                    let accessing = url.startAccessingSecurityScopedResource()
                    print("Security scoped resource access started: \(accessing)")

                    switch pendingPickerType {
                    case .video:
                        viewModel.loadVideo(url: url)
                        // Don't stop accessing - we need it for export later
                    case .photo:
                        viewModel.loadPhoto(url: url)
                        url.stopAccessingSecurityScopedResource()
                    case .gif:
                        viewModel.loadGIF(url: url)
                        url.stopAccessingSecurityScopedResource()
                    case .none:
                        break
                    }
                }
            case .failure(let error):
                print("File picker error: \(error)")
                viewModel.errorMessage = error.localizedDescription
            }

            activePickerType = nil
            pendingPickerType = nil
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let url = viewModel.exportedVideoURL {
                VideoPlayerView(url: url)
            }
        }
    }
}

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: url))
                .navigationTitle("Exported Video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
}
