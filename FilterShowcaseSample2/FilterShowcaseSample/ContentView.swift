import Foundation
import SwiftUI
import VideoProcessingTwo

private struct CameraPreviewView: View {
    @ObservedObject var previewState: FilterShowcasePreviewState
    let isFrontCamera: Bool

    var body: some View {
        Group {
            if let image = previewState.displayCIImage {
                MetalView(ciImage: image, isFrontCamera: isFrontCamera)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Starting camera...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .ignoresSafeArea()
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = FilterShowcaseViewModel()
    @State private var activePanel: ActivePanel?
    @GestureState private var panelDragOffset: CGFloat = 0

    private enum ActivePanel {
        case selection
        case parameters
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                cameraPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if let activePanel {
                    presentedPanel(activePanel, in: proxy.size)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }

                bottomControls(in: proxy)
                    .zIndex(3)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: activePanel != nil)
            .ignoresSafeArea()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }

    private var cameraPreview: some View {
        CameraPreviewView(
            previewState: viewModel.previewState,
            isFrontCamera: viewModel.isFrontCamera
        )
    }

    private func bottomControls(in proxy: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            panelButton(
                title: "Selection",
                systemImage: "line.3.horizontal.decrease.circle",
                isActive: activePanel == .selection
            ) {
                togglePanel(.selection)
            }

            panelButton(
                title: "Parameters",
                systemImage: "slider.horizontal.3",
                isActive: activePanel == .parameters
            ) {
                togglePanel(.parameters)
            }

            #if os(iOS)
            panelButton(
                title: "Camera",
                systemImage: "arrow.triangle.2.circlepath.camera",
                isActive: viewModel.isFrontCamera
            ) {
                viewModel.swapCamera()
            }
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .padding(.bottom, max(16, proxy.safeAreaInsets.bottom + 8))
    }

    private func panelButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.24) : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private func presentedPanel(_ panel: ActivePanel, in size: CGSize) -> some View {
        let panelHeight = min(max(size.height * 0.62, 340), size.height - 22)
        let clampedDrag = max(0, panelDragOffset)

        return VStack(spacing: 0) {
            panelHandle(title: panel == .selection ? "Selection" : "Parameters")
            Divider().opacity(0.25)
            panelBody(panel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.20)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .offset(y: clampedDrag)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func panelHandle(title: String) -> some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
            Text("\(title) (swipe down to dismiss)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(panelDismissGesture())
    }

    private func panelBody(_ panel: ActivePanel) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if panel == .selection {
                    Picker("Mode", selection: $viewModel.mode) {
                        ForEach(FilterShowcaseViewModel.Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.mode == .filters {
                        GroupBox("Filter") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Search filters", text: $viewModel.filterSearchText)
                                    .textFieldStyle(.roundedBorder)

                                if viewModel.visibleFilterEntries.isEmpty {
                                    Text("No filters match your search.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker(
                                        "Filter",
                                        selection: Binding(
                                            get: { viewModel.selectedFilterID },
                                            set: { viewModel.selectFilter($0) }
                                        )
                                    ) {
                                        ForEach(viewModel.visibleFilterEntries) { entry in
                                            Text("\(entry.name) · \(entry.category)").tag(entry.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    } else {
                        GroupBox("Recipe") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Search recipes", text: $viewModel.recipeSearchText)
                                    .textFieldStyle(.roundedBorder)

                                if viewModel.visibleRecipeEntries.isEmpty {
                                    Text("No recipes match your search.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker(
                                        "Recipe",
                                        selection: Binding(
                                            get: { viewModel.selectedRecipeID },
                                            set: { viewModel.selectRecipe($0) }
                                        )
                                    ) {
                                        ForEach(viewModel.visibleRecipeEntries) { entry in
                                            Text(entry.name).tag(entry.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    }

                    GroupBox("Selected") {
                        if let entry = viewModel.currentEntry {
                            VStack(alignment: .leading, spacing: 4) {
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
                            Text("No selection.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    GroupBox("Parameters") {
                        if viewModel.currentParameters.isEmpty {
                            Text("No adjustable parameters for this selection.")
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

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
    }

    private func panelDismissGesture() -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($panelDragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let threshold: CGFloat = 80
                if value.translation.height > threshold {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        activePanel = nil
                    }
                }
            }
    }

    private func togglePanel(_ panel: ActivePanel) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if activePanel == panel {
                activePanel = nil
            } else {
                activePanel = panel
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
