//
//  ContentView.swift
//  MultiLayerCompositionSample
//

import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = MultiLayerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Multi-Layer Composition")
                    .font(.title2.bold())
                Text("3 Videos + GIF + Image + Text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Video player
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(Color.black)
            } else if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(Color.black)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        Button {
                            viewModel.buildComposition()
                        } label: {
                            Label("Build Composition", systemImage: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
            }

            Divider()

            // Info section
            VStack(alignment: .leading, spacing: 16) {
                Text("Composition Details")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Resolution", value: "1280 × 720")
                    InfoRow(label: "Duration", value: "10 seconds")
                    InfoRow(label: "Frame Rate", value: "30 fps")
                    InfoRow(label: "Layers", value: "5 (3 videos, 1 GIF, 1 image, 1 text)")
                }
                .font(.caption)

                Spacer()
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    ContentView()
}
