//
//  ContentView.swift
//  FourVideoGridSample
//

import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import VideoProcessingTwo

struct ContentView: View {
    @StateObject private var viewModel = FourVideoGridViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if viewModel.isLoading {
                ProgressView("Loading...")
                    .tint(.white)
                    .foregroundColor(.white)
            } else if !viewModel.hasVideos || viewModel.isSelectingAlternateVideos {
                // No videos loaded or selecting alternate videos
                // Alternate video selection UI
                VStack(spacing: 20) {
                    if viewModel.isLoadingPickedVideos {
                        ProgressView("Loading videos...")
                            .tint(.white)
                    } else {
                        Image(systemName: "film.stack")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text(viewModel.isSelectingAlternateVideos ? "Select 4 Videos from Library" : "Select 4 Videos to Start")
                            .font(.title2)
                            .foregroundColor(.white)

                        Text("Tap to open picker, select exactly 4 videos")
                            .foregroundColor(.gray)
                            .font(.caption)

                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 4,
                            matching: .videos
                        ) {
                            Label("Select 4 Videos", systemImage: "photo.on.rectangle.angled")
                        }
                        .buttonStyle(.borderedProminent)
                        .onChange(of: selectedItems) { _, newItems in
                            guard newItems.count == 4 else { return }
                            viewModel.isLoadingPickedVideos = true
                            Task {
                                for item in newItems {
                                    if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                                        await MainActor.run {
                                            viewModel.addVideo(url: movie.url)
                                        }
                                    }
                                }
                                await MainActor.run {
                                    viewModel.isLoadingPickedVideos = false
                                }
                                selectedItems.removeAll()
                            }
                        }

                        if viewModel.isSelectingAlternateVideos {
                            Button("Cancel") {
                                viewModel.cancelAlternateSelection()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        viewModel.loadComposition()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if viewModel.hasVideos && viewModel.displayCIImage == nil {
                // Videos loaded but waiting for first frame
                ProgressView("Preparing...")
                    .tint(.white)
                    .foregroundColor(.white)
            } else if let ciImage = viewModel.displayCIImage {
                VStack(spacing: 0) {
                    // MetalView with puzzle grid overlay - anchored to top
                    ZStack {
                        MetalView(ciImage: ciImage, isFrontCamera: false)

                        // Puzzle grid overlay for tap interaction
                        PuzzleGridOverlay(viewModel: viewModel)
                    }
                    .aspectRatio(1, contentMode: .fit)  // Square for puzzle

                    // Win indicator
                    if viewModel.isPuzzleSolved {
                        Text("Solved!")
                            .font(.title)
                            .foregroundColor(.green)
                            .padding()
                    }

                    Spacer()

                    // Controls at bottom
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Button(viewModel.isPlaying ? "Pause" : "Play") {
                                viewModel.togglePlayPause()
                            }
                            .buttonStyle(.bordered)

                            Button("Shuffle") {
                                viewModel.shufflePuzzle()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isSolving)

                            Button {
                                if viewModel.isSolving {
                                    viewModel.stopSolving()
                                } else {
                                    viewModel.solvePuzzle()
                                }
                            } label: {
                                if viewModel.isFindingSolution {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Text(viewModel.isSolving ? "Stop" : "Solve")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(viewModel.isSolving ? .red : .green)
                            .disabled(viewModel.isFindingSolution)
                        }

                        Button("Load Alternate Videos") {
                            viewModel.startSelectingAlternateVideos()
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .padding()
                    .padding(.bottom)
                }
            }
        }
    }
}

struct PuzzleGridOverlay: View {
    @ObservedObject var viewModel: FourVideoGridViewModel

    var gridSize: Int { viewModel.gridSize }

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / CGFloat(gridSize)
            let cellHeight = geometry.size.height / CGFloat(gridSize)

            ZStack {
                // Grid of tap targets
                // We iterate by visual position (row, col) and calculate the filter position
                ForEach(0..<gridSize, id: \.self) { visualRow in
                    ForEach(0..<gridSize, id: \.self) { visualCol in
                        // Map visual position to filter position
                        // If x/y are swapped (90 degree rotation), swap row/col
                        // Visual (row, col) -> Filter position with swapped coordinates
                        let filterPosition = visualCol * gridSize + visualRow

                        Rectangle()
                            .fill(Color.white.opacity(0.001))  // Nearly invisible but tappable
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: CGFloat(visualCol) * cellWidth + cellWidth / 2,
                                y: CGFloat(visualRow) * cellHeight + cellHeight / 2
                            )
                            .onTapGesture {
                                viewModel.moveTile(at: filterPosition)
                            }
                    }
                }

                // Grid lines for visual reference
                Path { path in
                    // Vertical lines
                    for i in 1..<gridSize {
                        let x = CGFloat(i) * cellWidth
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    // Horizontal lines
                    for i in 1..<gridSize {
                        let y = CGFloat(i) * cellHeight
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.15), lineWidth: 2)
            }
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to temporary location
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "\(UUID().uuidString).\(received.file.pathExtension)"
            let destination = tempDir.appendingPathComponent(filename)

            try FileManager.default.copyItem(at: received.file, to: destination)
            return VideoTransferable(url: destination)
        }
    }
}

#Preview {
    ContentView()
}
