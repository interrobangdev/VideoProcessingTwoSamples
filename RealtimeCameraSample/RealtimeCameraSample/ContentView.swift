//
//  ContentView.swift
//  RealtimeCameraSample
//
//  Main view with camera preview and filter controls
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(image: viewModel.currentFrame)
                .ignoresSafeArea()

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

struct CameraPreviewView: View {
    let image: CIImage?

    var body: some View {
        GeometryReader { geometry in
            if let ciImage = image {
                Image(decorative: convertCIImageToCGImage(ciImage), scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Color.black
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
    }

    private func convertCIImageToCGImage(_ ciImage: CIImage) -> CGImage {
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return cgImage
        }
        // Fallback to a 1x1 transparent image
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { _ in }
        return uiImage.cgImage!
    }
}

#Preview {
    ContentView()
}
