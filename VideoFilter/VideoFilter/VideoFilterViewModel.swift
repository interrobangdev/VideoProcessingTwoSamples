import AVFoundation
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import VideoProcessingTwo

struct VideoFilterParameter: Identifiable {
    let id: String
    let title: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let step: Double

    init(
        id: String,
        title: String,
        range: ClosedRange<Double>,
        defaultValue: Double,
        step: Double = 0.01
    ) {
        self.id = id
        self.title = title
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
    }
}

struct VideoFilterEntry: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let parameters: [VideoFilterParameter]
    let makeFilters: (_ values: [String: Double], _ size: CGSize) -> [Filter]
}

@MainActor
final class VideoFilterViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var errorMessage: String?
    @Published var isExporting = false
    @Published var exportProgress = 0.0
    @Published var exportedVideoURL: URL?
    @Published var selectedFilterID: String = ""
    @Published var parameterValues: [String: Double] = [:]
    @Published var videoLoaded = false
    @Published var selectedVideoName: String = "Bundled Sample"

    let filterEntries: [VideoFilterEntry]

    private var pendingRebuild: DispatchWorkItem?
    private var videoURL: URL?
    private var videoSource: VideoSource?
    private var loopObserver: NSObjectProtocol?
    private var currentSecurityScopedURL: URL?

    init() {
        filterEntries = Self.makeFilterEntries()
        if let firstEntry = filterEntries.first {
            selectedFilterID = firstEntry.id
            parameterValues = Self.defaults(for: firstEntry.parameters)
        }
        loadBundledVideo()
    }

    deinit {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        currentSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var currentEntry: VideoFilterEntry? {
        filterEntries.first(where: { $0.id == selectedFilterID })
    }

    var currentParameters: [VideoFilterParameter] {
        currentEntry?.parameters ?? []
    }

    func loadComposition() {
        rebuildPlayer(seekToCurrentTime: false)
    }

    func selectFilter(_ id: String) {
        guard selectedFilterID != id else { return }
        selectedFilterID = id
        if let entry = currentEntry {
            parameterValues = Self.defaults(for: entry.parameters)
        }
        scheduleRebuild()
    }

    func setValue(_ value: Double, for parameter: VideoFilterParameter) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let stepped = (clamped / parameter.step).rounded() * parameter.step
        parameterValues[parameter.id] = stepped
        scheduleRebuild()
    }

    func value(for parameter: VideoFilterParameter) -> Double {
        parameterValues[parameter.id] ?? parameter.defaultValue
    }

    func loadVideo(url: URL) {
        if let currentSecurityScopedURL {
            currentSecurityScopedURL.stopAccessingSecurityScopedResource()
            self.currentSecurityScopedURL = nil
        }

        if url.startAccessingSecurityScopedResource() {
            currentSecurityScopedURL = url
        }

        videoURL = url
        videoSource = VideoSource(url: url)
        selectedVideoName = url.lastPathComponent
        exportedVideoURL = nil
        videoLoaded = true
        errorMessage = nil
        rebuildPlayer(seekToCurrentTime: false)
    }

    func exportFilteredVideo() {
        guard !isExporting else { return }
        guard let scene = makeScene() else {
            errorMessage = "Load a video before exporting."
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("videofilter-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        isExporting = true
        exportProgress = 0.0
        exportedVideoURL = nil
        errorMessage = nil

        ExportManager.shared.exportScene(
            scene: scene,
            outpuURL: outputURL,
            progress: { [weak self] _, progress in
                DispatchQueue.main.async {
                    self?.exportProgress = progress
                }
            },
            completion: { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isExporting = false
                    if success {
                        self.exportProgress = 1.0
                        self.exportedVideoURL = outputURL
                    } else {
                        self.errorMessage = "Export failed."
                    }
                }
            }
        )
    }

    func resetExportState() {
        exportedVideoURL = nil
        exportProgress = 0.0
    }

    private func loadBundledVideo() {
        guard let url = Bundle.main.url(forResource: "mountain", withExtension: "mp4") ??
                Bundle.main.url(forResource: "download", withExtension: "mov") else {
            errorMessage = "Could not find the bundled sample video."
            return
        }

        videoURL = url
        videoSource = VideoSource(url: url)
        selectedVideoName = url.lastPathComponent
        videoLoaded = true
    }

    private func scheduleRebuild() {
        pendingRebuild?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.rebuildPlayer(seekToCurrentTime: true)
            }
        }
        pendingRebuild = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func rebuildPlayer(seekToCurrentTime: Bool) {
        guard let composition = makeCompositionResult() else { return }

        let previousTime = seekToCurrentTime ? player?.currentTime() : nil
        let wasPlaying = (player?.rate ?? 0) > 0

        let item = AVPlayerItem(asset: composition.composition)
        item.videoComposition = composition.videoComposition
        item.audioMix = composition.audioMix

        if player == nil {
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            self.player = player
            installLoopObserver(for: item)
            player.play()
        } else {
            player?.pause()
            player?.replaceCurrentItem(with: item)
            player?.actionAtItemEnd = .none
            installLoopObserver(for: item)
            if let previousTime {
                player?.seek(to: previousTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            if wasPlaying || !seekToCurrentTime {
                player?.play()
            }
        }
    }

    private func makeCompositionResult() -> SceneCompositionResult? {
        guard let scene = makeScene() else { return nil }
        guard let result = SceneVideoComposition.createComposition(scene: scene) else {
            errorMessage = "Failed to build the filtered composition."
            return nil
        }
        errorMessage = nil
        return result
    }

    private func makeScene() -> VideoScene? {
        guard let videoURL, let videoSource else {
            errorMessage = "No video loaded."
            return nil
        }
        guard let entry = currentEntry else {
            errorMessage = "Choose a filter first."
            return nil
        }

        let scene = VideoScene(
            duration: videoSource.duration,
            frameRate: 30.0,
            size: videoSource.naturalSize
        )

        _ = scene.addAsset(
            atLayerIndex: LayerObjectIndex(groupIndices: [], layerIndex: 0),
            type: .video,
            frame: CGRect(origin: .zero, size: videoSource.naturalSize),
            rotation: 0.0,
            assetURL: videoURL,
            text: ""
        )
        scene.group.filters = entry.makeFilters(parameterValues, videoSource.naturalSize)
        return scene
    }

    private func installLoopObserver(for item: AVPlayerItem) {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                self.player?.play()
            }
        }
    }
}

private extension VideoFilterViewModel {
    static func defaults(for parameters: [VideoFilterParameter]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.defaultValue) })
    }

    static func p(
        _ id: String,
        _ title: String,
        _ range: ClosedRange<Double>,
        _ defaultValue: Double,
        step: Double = 0.01
    ) -> VideoFilterParameter {
        VideoFilterParameter(id: id, title: title, range: range, defaultValue: defaultValue, step: step)
    }

    static func point(_ values: [String: Double], x: String, y: String, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * (values[x] ?? 0.5),
            y: size.height * (values[y] ?? 0.5)
        )
    }

    static func radialHeatmapImage(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        gradient.radius0 = Float(min(size.width, size.height) * 0.08)
        gradient.radius1 = Float(min(size.width, size.height) * 0.52)
        gradient.color0 = CIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        gradient.color1 = CIColor.black

        let fallback = CIImage(color: .black).cropped(to: extent)
        return (gradient.outputImage ?? fallback).cropped(to: extent)
    }

    static func makeFilterEntries() -> [VideoFilterEntry] {
        [
            VideoFilterEntry(
                id: "original",
                name: "Original",
                subtitle: "Preview the source video with no filter applied.",
                parameters: []
            ) { _, _ in
                []
            },
            VideoFilterEntry(
                id: "gaussian-blur",
                name: "Gaussian Blur",
                subtitle: "Softens the frame with a classic blur kernel.",
                parameters: [
                    p("radius", "Radius", 0.0...40.0, 12.0, step: 0.5)
                ]
            ) { values, _ in
                [GaussianBlur(radius: values["radius"] ?? 12.0, filterAnimators: [])]
            },
            VideoFilterEntry(
                id: "color-adjustment",
                name: "Color Adjustment",
                subtitle: "Tune brightness, contrast, and saturation in real time.",
                parameters: [
                    p("brightness", "Brightness", -0.6...0.6, 0.0, step: 0.01),
                    p("contrast", "Contrast", 0.5...2.0, 1.0, step: 0.01),
                    p("saturation", "Saturation", 0.0...2.5, 1.0, step: 0.01)
                ]
            ) { values, _ in
                [
                    ColorAdjustment(
                        brightness: values["brightness"] ?? 0.0,
                        contrast: values["contrast"] ?? 1.0,
                        saturation: values["saturation"] ?? 1.0,
                        filterAnimators: []
                    )
                ]
            },
            VideoFilterEntry(
                id: "crystallize",
                name: "Crystallize",
                subtitle: "Break the image into faceted color cells.",
                parameters: [
                    p("radius", "Radius", 2.0...120.0, 24.0, step: 1.0),
                    p("center-x", "Center X", 0.0...1.0, 0.5),
                    p("center-y", "Center Y", 0.0...1.0, 0.5)
                ]
            ) { values, size in
                [
                    Crystallize(
                        radius: values["radius"] ?? 24.0,
                        center: point(values, x: "center-x", y: "center-y", size: size),
                        filterAnimators: []
                    )
                ]
            },
            VideoFilterEntry(
                id: "bloom",
                name: "Bloom Glow",
                subtitle: "Add soft highlight glow with adjustable radius and strength.",
                parameters: [
                    p("radius", "Radius", 0.0...48.0, 14.0, step: 0.5),
                    p("intensity", "Intensity", 0.0...2.0, 0.65, step: 0.01)
                ]
            ) { values, _ in
                [
                    BloomGlow(
                        radius: values["radius"] ?? 14.0,
                        intensity: values["intensity"] ?? 0.65,
                        filterAnimators: []
                    )
                ]
            },
            VideoFilterEntry(
                id: "sepia",
                name: "Sepia",
                subtitle: "Warm the video with an adjustable sepia tone.",
                parameters: [
                    p("intensity", "Intensity", 0.0...1.0, 0.85, step: 0.01)
                ]
            ) { values, _ in
                [SepiaTone(intensity: values["intensity"] ?? 0.85, filterAnimators: [])]
            },
            VideoFilterEntry(
                id: "mirror",
                name: "Mirror",
                subtitle: "Mirror across a movable line defined by point and angle.",
                parameters: [
                    p("center-x", "Center X", 0.0...1.0, 0.5),
                    p("center-y", "Center Y", 0.0...1.0, 0.5),
                    p("angle", "Angle", 0.0...(Double.pi), 0.0, step: 0.01)
                ]
            ) { values, size in
                [
                    Mirror(
                        point: point(values, x: "center-x", y: "center-y", size: size),
                        angle: values["angle"] ?? 0.0,
                        filterAnimators: []
                    )
                ]
            },
            VideoFilterEntry(
                id: "temporal-fade",
                name: "Temporal Fade Atlas",
                subtitle: "Blend multiple frames across time with configurable spacing.",
                parameters: [
                    p("frame-count", "Frame Count", 1.0...15.0, 8.0, step: 1.0),
                    p("frame-spacing", "Frame Spacing", 1.0...12.0, 2.0, step: 1.0),
                    p("frame-size", "Input Frame Size", 256.0...1024.0, 768.0, step: 32.0)
                ]
            ) { values, _ in
                [
                    TemporalFadeAtlasFilter(
                        frameCount: Int(values["frame-count"] ?? 8.0),
                        frameSpacing: Int(values["frame-spacing"] ?? 2.0),
                        inputFrameSize: CGSize(width: values["frame-size"] ?? 768.0, height: values["frame-size"] ?? 768.0),
                        filterAnimators: []
                    )
                ]
            },
            VideoFilterEntry(
                id: "heatmap-atlas",
                name: "Heatmap Frame Offset Atlas",
                subtitle: "Use a radial heatmap to pull each pixel from a different point in recent history.",
                parameters: [
                    p("max-frame-offset", "Max Frame Offset", 0.0...72.0, 24.0, step: 1.0),
                    p("frame-size", "Input Frame Size", 256.0...1024.0, 768.0, step: 32.0)
                ]
            ) { values, size in
                [
                    HeatmapFrameOffsetAtlasFilter(
                        maxFrameOffset: Int(values["max-frame-offset"] ?? 24.0),
                        heatmapImage: radialHeatmapImage(size: size),
                        inputFrameSize: CGSize(width: values["frame-size"] ?? 768.0, height: values["frame-size"] ?? 768.0),
                        filterAnimators: []
                    )
                ]
            }
        ]
    }
}
