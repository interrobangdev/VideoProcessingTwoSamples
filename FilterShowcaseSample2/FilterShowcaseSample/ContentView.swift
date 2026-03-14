import AVKit
import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = FilterShowcaseViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                playerView
                Divider()
                controls
            }
            .navigationTitle("Filter Showcase")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.loadComposition()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("VideoProcessingTwo Filter Showcase")
                .font(.title3.weight(.semibold))
            Text("Preview filters and tune live parameters")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var playerView: some View {
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
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(FilterShowcaseViewModel.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.mode == .filters {
                    searchAndFilterPicker
                } else {
                    searchAndStylePicker
                }

                selectedEntryCard
                parametersCard

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    private var searchAndFilterPicker: some View {
        GroupBox("Filter Selection") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search filters", text: $viewModel.filterSearchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Filter", selection: Binding(
                    get: { viewModel.selectedFilterID },
                    set: { viewModel.selectFilter($0) }
                )) {
                    ForEach(viewModel.visibleFilterEntries) { entry in
                        Text("\(entry.name) · \(entry.category)").tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var searchAndStylePicker: some View {
        GroupBox("Style Selection") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search styles", text: $viewModel.styleSearchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Style", selection: Binding(
                    get: { viewModel.selectedStyleID },
                    set: { viewModel.selectStyle($0) }
                )) {
                    ForEach(viewModel.visibleStyleEntries) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var selectedEntryCard: some View {
        GroupBox("Selected") {
            if let entry = viewModel.currentEntry {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                        .font(.headline)
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if viewModel.mode == .filters {
                        Text("Category: \(entry.category)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No entry selected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var parametersCard: some View {
        GroupBox("Parameters") {
            if viewModel.currentParameters.isEmpty {
                Text("This entry has no adjustable parameters.")
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
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

#Preview {
    ContentView()
}
