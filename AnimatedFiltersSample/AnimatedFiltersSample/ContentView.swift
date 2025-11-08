//
//  ContentView.swift
//  AnimatedFiltersSample
//
//  UI for playing video with animated filter effects in real-time
//

import SwiftUI
import AVKit
import VideoProcessingTwo

struct ContentView: View {
    @StateObject private var viewModel = AnimationViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Animated Filter Effects")
                        .font(.title2.bold())
                    Text("Demonstrates FilterAnimator system")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()

                Divider()

                // Video player
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16/9, contentMode: .fit)
                        .background(Color.black)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            Button {
                                viewModel.loadComposition()
                            } label: {
                                Label("Load Video", systemImage: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                        }
                }

                Divider()

                ScrollView {
                    VStack(spacing: 24) {
                        // Animation type selector
                        GroupBox("Animation Type") {
                            VStack(spacing: 12) {
                                ForEach(AnimationViewModel.AnimationType.allCases, id: \.self) { type in
                                    Button {
                                        viewModel.selectedAnimation = type
                                    } label: {
                                        HStack {
                                            Image(systemName: viewModel.selectedAnimation == type ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(viewModel.selectedAnimation == type ? .blue : .gray)
                                            Text(type.rawValue)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if type != AnimationViewModel.AnimationType.allCases.last {
                                        Divider()
                                    }
                                }
                            }
                        }

                        // Animation descriptions
                        GroupBox("Description") {
                            Text(descriptionForAnimation(viewModel.selectedAnimation))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Bezier curve editor (shown only for custom bezier)
                        if viewModel.selectedAnimation == .customBezier {
                            GroupBox("Custom Bezier Curve Editor") {
                                VStack(spacing: 12) {
                                    Text("Drag the control points to shape your animation curve")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    BezierCurveEditorView(controlPoints: $viewModel.customBezierPoints)
                                        .frame(height: 250)

                                    Button("Apply Curve") {
                                        viewModel.updatePlayer()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func descriptionForAnimation(_ type: AnimationViewModel.AnimationType) -> String {
        switch type {
        case .fadeInOut:
            return "Video fades in over 2 seconds at the start, then fades out over the last 2 seconds. Demonstrates basic opacity animation."
        case .blurAnimation:
            return "Blur increases to maximum at the midpoint, then decreases back to zero. Shows animated blur radius parameter."
        case .colorPulse:
            return "Saturation pulses up and down in 3-second cycles. Demonstrates repeating color animations."
        case .zoomInOut:
            return "Video slowly zooms in to 1.5x scale, then zooms back out. Shows scale animation with FilterAnimator."
        case .combined:
            return "Combines multiple effects: fade in/out, zoom, and brightness pulse. Demonstrates using multiple FilterAnimators together."
        case .bezierEase:
            return "Smooth fade in using multi-point BezierPathTweenFunction with custom ease curve. Shows bezier curve interpolation."
        case .bounce:
            return "Scale bounces up through multiple points using BezierPathTweenFunction.multiBounce preset. Creates organic bounce effect."
        case .wave:
            return "Brightness oscillates in a wave pattern using BezierPathTweenFunction.wave. Shows complex multi-point bezier curves."
        case .threeStep:
            return "Fades in with three distinct steps using BezierPathTweenFunction.threeStep. Pauses at 33% and 66% before final value."
        case .customBezier:
            return "Create your own animation curve! Drag the control points in the editor below to design a custom bezier curve that will control the fade animation."
        }
    }
}

#Preview {
    ContentView()
}
