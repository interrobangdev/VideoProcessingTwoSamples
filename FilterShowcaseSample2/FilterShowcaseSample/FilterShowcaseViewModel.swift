import AVFoundation
import Combine
import CoreImage
import Foundation
import VideoProcessingTwo

struct ShowcaseParameter: Identifiable {
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

struct ShowcaseEntry: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let category: String
    let parameters: [ShowcaseParameter]
    let makeFilters: (_ values: [String: Double], _ size: CGSize) -> [Filter]
}

@MainActor
final class FilterShowcaseViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case filters = "Filters"
        case styles = "Style Presets"

        var id: String { rawValue }
    }

    @Published var player: AVPlayer?
    @Published var errorMessage: String?

    @Published var mode: Mode = .filters {
        didSet { handleSelectionChange(resetParameters: true) }
    }
    @Published var filterSearchText: String = ""
    @Published var styleSearchText: String = ""
    @Published var selectedFilterID: String = ""
    @Published var selectedStyleID: String = ""
    @Published var parameterValues: [String: Double] = [:]

    let filterEntries: [ShowcaseEntry]
    let styleEntries: [ShowcaseEntry]

    private var pendingRebuild: DispatchWorkItem?
    private var videoURL: URL?
    private var videoSource: VideoSource?

    init() {
        filterEntries = Self.makeFilterEntries()
        styleEntries = Self.makeStyleEntries()

        if let firstFilter = filterEntries.first {
            selectedFilterID = firstFilter.id
            parameterValues = Self.defaults(for: firstFilter.parameters)
        }
        if let firstStyle = styleEntries.first {
            selectedStyleID = firstStyle.id
        }

        loadBundledVideo()
    }

    var visibleFilterEntries: [ShowcaseEntry] {
        let query = filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return filterEntries }

        return filterEntries.filter { entry in
            entry.name.lowercased().contains(query) ||
            entry.subtitle.lowercased().contains(query) ||
            entry.category.lowercased().contains(query)
        }
    }

    var visibleStyleEntries: [ShowcaseEntry] {
        let query = styleSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return styleEntries }

        return styleEntries.filter { entry in
            entry.name.lowercased().contains(query) || entry.subtitle.lowercased().contains(query)
        }
    }

    var currentEntry: ShowcaseEntry? {
        switch mode {
        case .filters:
            return filterEntries.first { $0.id == selectedFilterID }
        case .styles:
            return styleEntries.first { $0.id == selectedStyleID }
        }
    }

    var currentParameters: [ShowcaseParameter] {
        currentEntry?.parameters ?? []
    }

    func loadComposition() {
        rebuildPlayer(seekToCurrentTime: false)
    }

    func selectFilter(_ id: String) {
        guard selectedFilterID != id else { return }
        selectedFilterID = id
        handleSelectionChange(resetParameters: true)
    }

    func selectStyle(_ id: String) {
        guard selectedStyleID != id else { return }
        selectedStyleID = id
        handleSelectionChange(resetParameters: true)
    }

    func setValue(_ value: Double, for parameter: ShowcaseParameter) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let stepped = (clamped / parameter.step).rounded() * parameter.step
        parameterValues[parameter.id] = stepped
        scheduleRebuild()
    }

    func value(for parameter: ShowcaseParameter) -> Double {
        parameterValues[parameter.id] ?? parameter.defaultValue
    }

    private func handleSelectionChange(resetParameters: Bool) {
        guard let entry = currentEntry else { return }
        if resetParameters {
            parameterValues = Self.defaults(for: entry.parameters)
        }
        scheduleRebuild()
    }

    private func scheduleRebuild() {
        pendingRebuild?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.rebuildPlayer(seekToCurrentTime: true)
        }
        pendingRebuild = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func loadBundledVideo() {
        if let url = Bundle.main.url(forResource: "download", withExtension: "mov") ??
            Bundle.main.url(forResource: "mountain", withExtension: "mp4") {
            videoURL = url
            videoSource = VideoSource(url: url)
        }
    }

    private func rebuildPlayer(seekToCurrentTime: Bool) {
        guard let videoURL, let videoSource else {
            errorMessage = "Could not load bundled sample video."
            return
        }
        guard let entry = currentEntry else {
            errorMessage = "No filter/style selected."
            return
        }

        let scene = VideoScene(duration: videoSource.duration, frameRate: 30.0, size: videoSource.naturalSize)
        _ = scene.addAsset(
            atLayerIndex: LayerObjectIndex(groupIndices: [], layerIndex: 0),
            type: .video,
            frame: CGRect(origin: .zero, size: videoSource.naturalSize),
            rotation: 0.0,
            assetURL: videoURL,
            text: ""
        )
        scene.group.filters = entry.makeFilters(parameterValues, videoSource.naturalSize)

        guard let compositionResult = SceneVideoComposition.createComposition(scene: scene) else {
            errorMessage = "Failed to build composition for \(entry.name)."
            return
        }

        let previousTime = seekToCurrentTime ? player?.currentTime() : nil
        let wasPlaying = (player?.rate ?? 0) > 0

        let item = AVPlayerItem(asset: compositionResult.composition)
        item.videoComposition = compositionResult.videoComposition
        item.audioMix = compositionResult.audioMix

        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.play()
        } else {
            player?.replaceCurrentItem(with: item)
            if let previousTime {
                player?.seek(to: previousTime)
            }
            if wasPlaying {
                player?.play()
            }
        }

        errorMessage = nil
    }
}

private extension FilterShowcaseViewModel {
    static func defaults(for parameters: [ShowcaseParameter]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.defaultValue) })
    }

    static func p(
        _ id: String,
        _ title: String,
        _ range: ClosedRange<Double>,
        _ defaultValue: Double,
        step: Double = 0.01
    ) -> ShowcaseParameter {
        ShowcaseParameter(id: id, title: title, range: range, defaultValue: defaultValue, step: step)
    }

    static func blendImage(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: 0)
        gradient.point1 = CGPoint(x: size.width, y: size.height)
        gradient.color0 = CIColor(red: 0.98, green: 0.22, blue: 0.18, alpha: 0.80)
        gradient.color1 = CIColor(red: 0.12, green: 0.56, blue: 1.00, alpha: 0.80)
        let fallback = CIImage(color: CIColor.black).cropped(to: extent)
        let base = (gradient.outputImage ?? fallback).cropped(to: extent)

        let controls = CIFilter.colorControls()
        controls.inputImage = base
        controls.saturation = 1.25
        controls.contrast = 1.05
        return (controls.outputImage ?? base).cropped(to: extent)
    }

    static func makeFilterEntries() -> [ShowcaseEntry] {
        [
            ShowcaseEntry(
                id: "fade",
                name: "Fade",
                subtitle: "Opacity",
                category: "Core",
                parameters: [p("fade", "Fade", 0.0...1.0, 1.0)],
                makeFilters: { values, _ in
                    [Fade(fade: values["fade"] ?? 1.0, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "gaussian_blur",
                name: "Gaussian Blur",
                subtitle: "Blur radius",
                category: "Core",
                parameters: [p("radius", "Radius", 0.0...40.0, 12.0, step: 0.5)],
                makeFilters: { values, _ in
                    [GaussianBlur(radius: values["radius"] ?? 12.0, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "color_adjustment",
                name: "Color Adjustment",
                subtitle: "Brightness, contrast, saturation",
                category: "Core",
                parameters: [
                    p("brightness", "Brightness", -0.7...0.7, 0.0),
                    p("contrast", "Contrast", 0.3...2.0, 1.0),
                    p("saturation", "Saturation", 0.0...2.0, 1.0)
                ],
                makeFilters: { values, _ in
                    [ColorAdjustment(
                        brightness: values["brightness"] ?? 0.0,
                        contrast: values["contrast"] ?? 1.0,
                        saturation: values["saturation"] ?? 1.0,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "scale",
                name: "Scale",
                subtitle: "Centered transform",
                category: "Core",
                parameters: [
                    p("scale", "Scale", 0.4...2.4, 1.0),
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, size in
                    let center = CGPoint(
                        x: size.width * (values["centerX"] ?? 0.5),
                        y: size.height * (values["centerY"] ?? 0.5)
                    )
                    return [Scale(scale: values["scale"] ?? 1.0, centerPoint: center, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "rotate",
                name: "Rotate",
                subtitle: "Rotation transform",
                category: "Core",
                parameters: [
                    p("rotation", "Rotation", -Double.pi...Double.pi, 0.0),
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, size in
                    let center = CGPoint(
                        x: size.width * (values["centerX"] ?? 0.5),
                        y: size.height * (values["centerY"] ?? 0.5)
                    )
                    return [Rotate(rotation: values["rotation"] ?? 0.0, centerPoint: center, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "translate",
                name: "Translate",
                subtitle: "Position shift",
                category: "Core",
                parameters: [
                    p("tx", "Translate X", -400.0...400.0, 0.0, step: 1.0),
                    p("ty", "Translate Y", -400.0...400.0, 0.0, step: 1.0)
                ],
                makeFilters: { values, _ in
                    let point = CGPoint(x: values["tx"] ?? 0.0, y: values["ty"] ?? 0.0)
                    return [Translate(translation: point, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "crystallize",
                name: "Crystallize",
                subtitle: "Faceted look",
                category: "Core",
                parameters: [p("radius", "Radius", 1.0...80.0, 20.0, step: 1.0)],
                makeFilters: { values, _ in
                    [Crystallize(radius: values["radius"] ?? 20.0, center: CGPoint(x: 150, y: 150), filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "dissolve_blend",
                name: "Dissolve Blend",
                subtitle: "Two-input dissolve",
                category: "Blend",
                parameters: [p("mix", "Mix", 0.0...1.0, 0.5)],
                makeFilters: { values, size in
                    [DissolveBlend(mix: values["mix"] ?? 0.5, blendImage: blendImage(size: size), filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "normal_amount_blend",
                name: "Normal Amount Blend",
                subtitle: "Alpha-scaled source-over",
                category: "Blend",
                parameters: [
                    p("image1", "Image 1 Amount", 0.0...1.5, 1.0),
                    p("image2", "Image 2 Amount", 0.0...1.5, 1.0)
                ],
                makeFilters: { values, size in
                    [NormalAmountBlend(
                        image1Amount: values["image1"] ?? 1.0,
                        image2Amount: values["image2"] ?? 1.0,
                        blendImage: blendImage(size: size),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "add_blend",
                name: "Add Blend",
                subtitle: "CIAdditionCompositing",
                category: "Blend",
                parameters: [],
                makeFilters: { _, size in [AddBlend(backgroundImage: blendImage(size: size), filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "multiply_blend",
                name: "Multiply Blend",
                subtitle: "CIMultiplyBlendMode",
                category: "Blend",
                parameters: [],
                makeFilters: { _, size in [MultiplyBlend(backgroundImage: blendImage(size: size), filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "hard_light_blend",
                name: "Hard Light Blend",
                subtitle: "CIHardLightBlendMode",
                category: "Blend",
                parameters: [],
                makeFilters: { _, size in [HardLightBlend(backgroundImage: blendImage(size: size), filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "color_dodge_blend",
                name: "Color Dodge Blend",
                subtitle: "CIColorDodgeBlendMode",
                category: "Blend",
                parameters: [],
                makeFilters: { _, size in [ColorDodgeBlend(backgroundImage: blendImage(size: size), filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "sepia",
                name: "Sepia Tone",
                subtitle: "Classic sepia",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.8)],
                makeFilters: { values, _ in [SepiaTone(intensity: values["intensity"] ?? 0.8, filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "film_grain",
                name: "Film Grain",
                subtitle: "Noise overlay",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...0.8, 0.22)],
                makeFilters: { values, _ in [FilmGrain(intensity: values["intensity"] ?? 0.22, filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "edge_overlay",
                name: "Edge Overlay",
                subtitle: "Sketch-like edge blend",
                category: "Migrated",
                parameters: [
                    p("edge", "Edge Intensity", 0.0...5.0, 2.0),
                    p("mix", "Overlay Amount", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, _ in
                    [EdgeOverlay(
                        edgeIntensity: values["edge"] ?? 2.0,
                        overlayAmount: values["mix"] ?? 0.5,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "panel_split",
                name: "Panel Split Effect",
                subtitle: "Grid/panel stylizer",
                category: "Migrated",
                parameters: [
                    p("columns", "Columns", 1.0...8.0, 3.0, step: 1.0),
                    p("rows", "Rows", 1.0...8.0, 3.0, step: 1.0),
                    p("gap", "Gap", 0.0...0.04, 0.008),
                    p("hueShift", "Hue Shift Per Panel", 0.0...0.20, 0.03),
                    p("saturation", "Saturation", 0.0...2.0, 1.08),
                    p("brightness", "Brightness", -0.4...0.4, 0.0)
                ],
                makeFilters: { values, _ in
                    [PanelSplitEffect(
                        columns: max(1, Int((values["columns"] ?? 3.0).rounded())),
                        rows: max(1, Int((values["rows"] ?? 3.0).rounded())),
                        gap: values["gap"] ?? 0.008,
                        hueShiftPerPanel: values["hueShift"] ?? 0.03,
                        saturation: values["saturation"] ?? 1.08,
                        brightness: values["brightness"] ?? 0.0,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "flash_pulse",
                name: "Flash Pulse",
                subtitle: "Pulsing brightness",
                category: "Migrated",
                parameters: [
                    p("brightness", "Base Brightness", -0.4...0.4, 0.0),
                    p("amp", "Pulse Amplitude", 0.0...0.5, 0.18),
                    p("speed", "Speed (Hz)", 0.2...12.0, 4.0),
                    p("saturation", "Saturation", 0.0...2.0, 1.0),
                    p("contrast", "Contrast", 0.5...2.0, 1.0)
                ],
                makeFilters: { values, _ in
                    [FlashPulse(
                        baseBrightness: values["brightness"] ?? 0.0,
                        pulseAmplitude: values["amp"] ?? 0.18,
                        speedHz: values["speed"] ?? 4.0,
                        saturation: values["saturation"] ?? 1.0,
                        baseContrast: values["contrast"] ?? 1.0,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "zoom_pulse",
                name: "Zoom Pulse",
                subtitle: "Time-varying zoom",
                category: "Migrated",
                parameters: [
                    p("baseScale", "Base Scale", 0.6...1.8, 1.0),
                    p("amp", "Amplitude", 0.0...0.8, 0.15),
                    p("speed", "Speed (Hz)", 0.1...8.0, 2.0),
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, _ in
                    [ZoomPulse(
                        baseScale: values["baseScale"] ?? 1.0,
                        amplitude: values["amp"] ?? 0.15,
                        speedHz: values["speed"] ?? 2.0,
                        normalizedCenter: CGPoint(x: values["centerX"] ?? 0.5, y: values["centerY"] ?? 0.5),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "temporal_low_pass",
                name: "Temporal Low Pass",
                subtitle: "Frame blending",
                category: "Migrated",
                parameters: [p("strength", "Filter Strength", 0.0...1.0, 0.35)],
                makeFilters: { values, _ in
                    [TemporalLowPass(filterStrength: values["strength"] ?? 0.35, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "comic",
                name: "Comic Stylize",
                subtitle: "CIComicEffect blend",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.9)],
                makeFilters: { values, _ in [ComicStylize(intensity: values["intensity"] ?? 0.9, filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "thermal",
                name: "Thermal Stylize",
                subtitle: "CIThermal blend",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.9)],
                makeFilters: { values, _ in [ThermalStylize(intensity: values["intensity"] ?? 0.9, filterAnimators: [])] }
            ),
            ShowcaseEntry(
                id: "monochrome",
                name: "Monochrome Tone",
                subtitle: "Color monochrome blend",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.8)],
                makeFilters: { values, _ in
                    [MonochromeTone(
                        color: CIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1.0),
                        intensity: values["intensity"] ?? 0.8,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "false_color",
                name: "False Color Blend",
                subtitle: "Two-color remap",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.6)],
                makeFilters: { values, _ in
                    [FalseColorBlend(
                        firstColor: CIColor(red: 0.08, green: 0.02, blue: 0.6, alpha: 1.0),
                        secondColor: CIColor(red: 1.0, green: 0.45, blue: 0.2, alpha: 1.0),
                        intensity: values["intensity"] ?? 0.6,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "hsb_adjust",
                name: "HSB Adjustment",
                subtitle: "Hue/saturation/brightness",
                category: "Migrated",
                parameters: [
                    p("hue", "Hue (rad)", -Double.pi...Double.pi, 0.0),
                    p("saturation", "Saturation", 0.0...2.0, 1.0),
                    p("brightness", "Brightness", -0.6...0.6, 0.0)
                ],
                makeFilters: { values, _ in
                    [HSBAdjustment(
                        hue: values["hue"] ?? 0.0,
                        saturation: values["saturation"] ?? 1.0,
                        brightness: values["brightness"] ?? 0.0,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "alpha_vignette",
                name: "Alpha Vignette",
                subtitle: "Alpha edge fade",
                category: "Migrated",
                parameters: [
                    p("start", "Start", 0.1...0.8, 0.3),
                    p("end", "End", 0.2...1.0, 0.85),
                    p("outerAlpha", "Outer Alpha", 0.0...1.0, 0.2)
                ],
                makeFilters: { values, _ in
                    [AlphaVignette(
                        center: CGPoint(x: 0.5, y: 0.5),
                        start: values["start"] ?? 0.3,
                        end: values["end"] ?? 0.85,
                        innerAlpha: 1.0,
                        outerAlpha: values["outerAlpha"] ?? 0.2,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "color_vignette",
                name: "Color Vignette",
                subtitle: "Tinted edge overlay",
                category: "Migrated",
                parameters: [
                    p("start", "Start", 0.1...0.8, 0.35),
                    p("end", "End", 0.2...1.0, 0.90),
                    p("alpha", "Ring Alpha", 0.0...1.0, 0.35)
                ],
                makeFilters: { values, _ in
                    [ColorVignette(
                        center: CGPoint(x: 0.5, y: 0.5),
                        centerColor: CIColor(red: 0, green: 0, blue: 0, alpha: 0.0),
                        ringColor: CIColor(red: 0, green: 0, blue: 0, alpha: values["alpha"] ?? 0.35),
                        start: values["start"] ?? 0.35,
                        end: values["end"] ?? 0.9,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "shake_jitter",
                name: "Shake Jitter",
                subtitle: "Time-varying transform shake",
                category: "Migrated",
                parameters: [
                    p("tx", "Translation X", 0.0...0.08, 0.02),
                    p("ty", "Translation Y", 0.0...0.08, 0.02),
                    p("rotation", "Rotation", 0.0...0.25, 0.05),
                    p("scale", "Scale Amp", 0.0...0.25, 0.06),
                    p("speed", "Speed (Hz)", 0.2...12.0, 5.5)
                ],
                makeFilters: { values, _ in
                    [ShakeJitter(
                        translationAmplitude: CGPoint(x: values["tx"] ?? 0.02, y: values["ty"] ?? 0.02),
                        rotationAmplitude: values["rotation"] ?? 0.05,
                        scaleAmplitude: values["scale"] ?? 0.06,
                        speedHz: values["speed"] ?? 5.5,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "hue_pulse",
                name: "Hue Pulse",
                subtitle: "Animated hue modulation",
                category: "Migrated",
                parameters: [
                    p("baseHue", "Base Hue", -Double.pi...Double.pi, 0.0),
                    p("amp", "Hue Amplitude", 0.0...Double.pi, 0.45),
                    p("speed", "Speed (Hz)", 0.1...8.0, 1.3),
                    p("saturation", "Saturation", 0.0...2.0, 1.2),
                    p("brightness", "Brightness", -0.5...0.5, 0.0),
                    p("contrast", "Contrast", 0.5...2.0, 1.06)
                ],
                makeFilters: { values, _ in
                    [HuePulse(
                        baseHue: values["baseHue"] ?? 0.0,
                        hueAmplitude: values["amp"] ?? 0.45,
                        speedHz: values["speed"] ?? 1.3,
                        saturation: values["saturation"] ?? 1.2,
                        brightness: values["brightness"] ?? 0.0,
                        contrast: values["contrast"] ?? 1.06,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "twirl_pulse",
                name: "Twirl Pulse",
                subtitle: "Animated twirl distortion",
                category: "Migrated",
                parameters: [
                    p("radius", "Radius", 0.05...1.0, 0.45),
                    p("angle", "Angle Amplitude", 0.0...3.0, 1.2),
                    p("speed", "Speed (Hz)", 0.1...6.0, 0.9),
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, _ in
                    [TwirlPulse(
                        normalizedCenter: CGPoint(x: values["centerX"] ?? 0.5, y: values["centerY"] ?? 0.5),
                        normalizedRadius: values["radius"] ?? 0.45,
                        angleAmplitude: values["angle"] ?? 1.2,
                        speedHz: values["speed"] ?? 0.9,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "glitch_effect",
                name: "Glitch Effect",
                subtitle: "Metal-backed glitch filter",
                category: "Migrated",
                parameters: [p("intensity", "Intensity", 0.0...3.0, 1.0)],
                makeFilters: { values, _ in
                    if #available(iOS 15.0, *) {
                        return [GlitchEffect(intensity: values["intensity"] ?? 1.0, filterAnimators: [])]
                    } else {
                        return [ColorAdjustment(brightness: 0.0, contrast: 1.0, saturation: 1.0, filterAnimators: [])]
                    }
                }
            ),
            ShowcaseEntry(
                id: "bloom_glow",
                name: "Bloom Glow",
                subtitle: "Highlight bloom",
                category: "Migrated",
                parameters: [
                    p("radius", "Radius", 0.0...40.0, 12.0, step: 0.5),
                    p("intensity", "Intensity", 0.0...2.0, 0.5)
                ],
                makeFilters: { values, _ in
                    [BloomGlow(
                        radius: values["radius"] ?? 12.0,
                        intensity: values["intensity"] ?? 0.5,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "kuwahara",
                name: "Kuwahara Stylize",
                subtitle: "Painterly abstraction",
                category: "Migrated",
                parameters: [
                    p("radius", "Radius", 1.0...20.0, 8.0, step: 1.0),
                    p("intensity", "Intensity", 0.0...1.0, 1.0)
                ],
                makeFilters: { values, _ in
                    [KuwaharaStylize(
                        radius: values["radius"] ?? 8.0,
                        intensity: values["intensity"] ?? 1.0,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "line_sketch",
                name: "Line Sketch",
                subtitle: "Take On Me-style edges",
                category: "Migrated",
                parameters: [p("edge", "Edge Strength", 0.0...4.0, 1.45)],
                makeFilters: { values, _ in
                    [LineSketch(edgeStrength: values["edge"] ?? 1.45, invert: true, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "impressionist",
                name: "Impressionist Paint",
                subtitle: "Brush-stroke abstraction",
                category: "Migrated",
                parameters: [
                    p("radius", "Stroke Radius", 1.0...30.0, 9.0, step: 1.0),
                    p("softness", "Softness", 0.0...1.0, 0.35)
                ],
                makeFilters: { values, _ in
                    [ImpressionistPaint(
                        strokeRadius: values["radius"] ?? 9.0,
                        softness: values["softness"] ?? 0.35,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "body_electric",
                name: "Body Electric",
                subtitle: "Neon edge glow",
                category: "Migrated",
                parameters: [
                    p("edge", "Edge Intensity", 0.0...5.0, 2.25),
                    p("glow", "Glow Amount", 0.0...1.5, 0.50),
                    p("hue", "Color Shift", 0.0...0.5, 0.11)
                ],
                makeFilters: { values, _ in
                    [BodyElectric(
                        edgeIntensity: values["edge"] ?? 2.25,
                        glowAmount: values["glow"] ?? 0.50,
                        colorShift: values["hue"] ?? 0.11,
                        filterAnimators: []
                    )]
                }
            )
        ]
    }

    static func makeStyleEntries() -> [ShowcaseEntry] {
        var seen = Set<String>()
        return ShimmeoStyleRecipeFactory.supportedStorageNames.compactMap { storageName in
            guard !seen.contains(storageName) else { return nil }
            seen.insert(storageName)

            return ShowcaseEntry(
                id: storageName,
                name: storageName,
                subtitle: "Shimmeo style recipe",
                category: "Styles",
                parameters: [],
                makeFilters: { _, _ in
                    guard let recipe = ShimmeoStyleRecipeFactory.recipe(forStorageName: storageName) else {
                        return []
                    }
                    return recipe.makeFilters()
                }
            )
        }
    }
}
