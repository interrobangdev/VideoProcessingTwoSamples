//
//  ContentView.swift
//  RealtimeCameraSample
//
//  Main view with camera preview and filter controls
//

import SwiftUI
import VideoProcessingTwo

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            // Metal view for displaying camera feed
            if let ciImage = viewModel.displayCIImage {
                MetalView(ciImage: ciImage, isFrontCamera: false)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
                    .edgesIgnoringSafeArea(.all)
            }

            // Filter controls overlay
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    // Filter selection
                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        ForEach(CameraViewModel.FilterType.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Filter intensity slider (hidden when no filter is selected)
                    if viewModel.selectedFilter != .none {
                        VStack(spacing: 8) {
                            Text("Intensity")
                                .font(.caption)
                                .foregroundColor(.white)

                            Slider(value: $viewModel.filterIntensity, in: 0...1)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .padding()
            }
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
}

#Preview {
    ContentView()
}
