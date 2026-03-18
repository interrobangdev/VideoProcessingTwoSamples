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
    @State private var showsOverlayUI = true

    var body: some View {
        ZStack {
            // Metal view for displaying camera feed
            if let ciImage = viewModel.displayCIImage {
                MetalView(ciImage: ciImage, isFrontCamera: viewModel.cameraManager.devicePosition == .front)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
            }

            if showsOverlayUI {
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
                        HStack {
                            Text("Mode")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Picker("Analysis Mode", selection: $viewModel.analysisMode) {
                                ForEach(CameraViewModel.AnalysisMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal)

                        if viewModel.isAudioMode {
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

                    // Mode analysis values
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(viewModel.analysisMode.displayName) Metrics")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Divider()
                            .background(Color.white.opacity(0.3))

                        ForEach(viewModel.currentModeMetrics, id: \.label) { metric in
                            HStack {
                                Text(metric.label + ":")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(metric.value)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding()

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

            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsOverlayUI.toggle()
                            }
                        }) {
                            Image(systemName: showsOverlayUI ? "eye.slash.fill" : "eye.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Circle())
                        }

                        Button(action: {
                            if viewModel.isRecordingVideo {
                                viewModel.stopRecording()
                            } else {
                                viewModel.startRecording()
                            }
                        }) {
                            Image(systemName: viewModel.isRecordingVideo ? "stop.fill" : "record.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(viewModel.isRecordingVideo ? Color.red.opacity(0.9) : Color.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                        .disabled(viewModel.isSavingRecording)
                        .opacity(viewModel.isSavingRecording ? 0.6 : 1.0)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal)

                Spacer()

                if let status = viewModel.recordingStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.72))
                        .cornerRadius(12)
                        .padding(.bottom, 24)
                }
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
