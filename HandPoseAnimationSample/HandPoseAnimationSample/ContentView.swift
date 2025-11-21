//
//  ContentView.swift
//  HandPoseAnimationSample
//

import SwiftUI
import VideoProcessingTwo
import AVFoundation
import MediaPlayer

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showMusicPicker = false

    var body: some View {
        ZStack {
            // Metal view for displaying camera feed
            if let ciImage = viewModel.displayCIImage {
                MetalView(ciImage: ciImage, isFrontCamera: viewModel.cameraManager.devicePosition == .front)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
            }

            VStack {
                // Top status bar with camera swap button
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hand Pose Detection")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            if viewModel.animationState.isHandPresent {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundColor(.green)
                                Text("Hand Detected")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                            } else {
                                Image(systemName: "hand.raised")
                                    .foregroundColor(.gray)
                                Text("No Hand")
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                            }
                        }

                        if let position = viewModel.handPosition {
                            Text(String(format: "Pos: (%.2f, %.2f)", position.x, position.y))
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    // Camera swap button
                    Button(action: {
                        viewModel.swapCamera()
                    }) {
                        Image(systemName: "camera.rotate")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding()

                Spacer()

                // Blur source selector
                VStack(spacing: 12) {
                    Picker("Blur Source", selection: $viewModel.blurSource) {
                        Text("Hand Position").tag(CameraViewModel.BlurSource.hand)
                        Text("Audio").tag(CameraViewModel.BlurSource.audio)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if viewModel.blurSource == .audio {
                        // Audio player controls
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Button(action: {
                                    if viewModel.audioPlayer.isPlaying {
                                        viewModel.pauseAudio()
                                    } else {
                                        viewModel.playAudio()
                                    }
                                }) {
                                    Image(systemName: viewModel.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.blue.opacity(0.7))
                                        .cornerRadius(8)
                                }

                                Button(action: {
                                    viewModel.stopAudio()
                                }) {
                                    Image(systemName: "stop.fill")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.red.opacity(0.7))
                                        .cornerRadius(8)
                                }

                                Button(action: {
                                    showMusicPicker = true
                                }) {
                                    Image(systemName: "music.note.list")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.green.opacity(0.7))
                                        .cornerRadius(8)
                                }

                                Spacer()
                            }

                            VStack(spacing: 4) {
                                Text("Audio Amplitude")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                ProgressView(value: Double(viewModel.audioPlayer.currentAmplitude))
                                    .tint(.cyan)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding()

                // Filter parameter values
                if let position = viewModel.handPosition, viewModel.blurSource == .hand {
                    let brightness = (position.y - 0.5)
                    let dx = position.x - 0.5
                    let dy = position.y - 0.5
                    let distance = sqrt(dx * dx + dy * dy) / 0.707
                    let scale = 0.8 + (distance * 0.5)
                    let angle = atan2(dy, dx)
                    let degrees = ((angle + .pi) / (2 * .pi)) * 360

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Filter Parameters")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Divider()
                            .background(Color.white.opacity(0.3))

                        HStack {
                            Text("Blur (X):")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.1f px", position.x * 20.0))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }

                        HStack {
                            Text("Brightness (Y):")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.2f", brightness))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }

                        HStack {
                            Text("Scale (Distance):")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.2f x", scale))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }

                        HStack {
                            Text("Rotation (Angle):")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.1f°", degrees))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }

                        HStack {
                            Text("Opacity (Y):")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.0f%%", position.y * 100))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding()
                }

                // Bottom stats
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hands: \(viewModel.detectedHands.count) | Frames: \(viewModel.handPoseCollector.frames.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding()
            }
        }
        .onAppear {
            viewModel.startCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .sheet(isPresented: $showMusicPicker) {
            MusicPickerView(viewModel: viewModel)
        }
    }
}

struct MusicPickerView: UIViewControllerRepresentable {
    let viewModel: CameraViewModel
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.delegate = context.coordinator
        picker.allowsPickingMultipleItems = false
        picker.prompt = "Select a song to use for audio-driven animation"
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, dismiss: dismiss)
    }

    class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let viewModel: CameraViewModel
        let dismiss: DismissAction

        init(viewModel: CameraViewModel, dismiss: DismissAction) {
            self.viewModel = viewModel
            self.dismiss = dismiss
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            if let song = mediaItemCollection.items.first, let url = song.assetURL {
                viewModel.loadAudio(from: url)
            }
            dismiss()
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            dismiss()
        }
    }
}

#Preview {
    ContentView()
}
