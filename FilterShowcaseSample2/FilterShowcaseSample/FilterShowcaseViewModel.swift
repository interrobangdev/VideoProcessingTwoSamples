import AVFoundation
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import VideoProcessingTwo

final class FilterShowcasePreviewState: ObservableObject {
    @Published var displayCIImage: CIImage?
}

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
    let makeFilters: (_ values: [String: Double], _ renderSize: CGSize) -> [Filter]
}

final class FilterShowcaseViewModel: NSObject, ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case filters = "Filters"
        case recipes = "Recipes"

        var id: String { rawValue }
    }

    @Published var errorMessage: String?
    @Published private(set) var isFrontCamera: Bool = false

    @Published var mode: Mode = .filters {
        didSet {
            ensureValidSelectionForCurrentMode()
            applyCurrentSelection()
        }
    }
    @Published var filterSearchText: String = ""
    @Published var recipeSearchText: String = ""
    @Published var selectedFilterID: String = ""
    @Published var selectedRecipeID: String = ""
    @Published var parameterValues: [String: Double] = [:]

    let filterEntries: [ShowcaseEntry]
    let recipeEntries: [ShowcaseEntry]
    let previewState = FilterShowcasePreviewState()

    private let cameraManager = CameraManager()
    private let cameraSource: CameraSource
    private var scene: VideoScene?
    private let sceneQueue = DispatchQueue(label: "com.interrobang.FilterShowcaseSample2.sceneQueue")

    private var currentRenderSize = CGSize(width: 1920, height: 1080)
    private var hasAppliedFirstFrameSize = false
    private var activeMode: Mode?
    private var activeSelectionID: String?

    override init() {
        cameraSource = CameraSource(cameraManager: cameraManager)
        filterEntries = Self.makeFilterEntries()
        recipeEntries = Self.makeRecipeEntries()

        super.init()

        cameraSource.delegate = self
        setupScene()
        setupCamera()

        if let firstFilter = filterEntries.first {
            selectedFilterID = firstFilter.id
            parameterValues = Self.defaults(for: firstFilter.parameters)
        }
        if let firstRecipe = recipeEntries.first {
            selectedRecipeID = firstRecipe.id
        }

        ensureValidSelectionForCurrentMode()
        applyCurrentSelection()
    }

    deinit {
        stopCamera()
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

    var visibleRecipeEntries: [ShowcaseEntry] {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipeEntries }

        return recipeEntries.filter { entry in
            entry.name.lowercased().contains(query) ||
            entry.subtitle.lowercased().contains(query)
        }
    }

    var currentEntry: ShowcaseEntry? {
        switch mode {
        case .filters:
            return filterEntries.first { $0.id == selectedFilterID }
        case .recipes:
            return recipeEntries.first { $0.id == selectedRecipeID }
        }
    }

    var currentParameters: [ShowcaseParameter] {
        guard mode == .filters else { return [] }
        return currentEntry?.parameters ?? []
    }

    func selectFilter(_ id: String) {
        guard selectedFilterID != id else { return }
        selectedFilterID = id
        if let entry = filterEntries.first(where: { $0.id == id }) {
            parameterValues = Self.defaults(for: entry.parameters)
        }
        applyCurrentSelection()
    }

    func selectRecipe(_ id: String) {
        guard selectedRecipeID != id else { return }
        selectedRecipeID = id
        applyCurrentSelection()
    }

    func value(for parameter: ShowcaseParameter) -> Double {
        parameterValues[parameter.id] ?? parameter.defaultValue
    }

    func setValue(_ value: Double, for parameter: ShowcaseParameter) {
        let clamped = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        let stepped = (clamped / parameter.step).rounded() * parameter.step
        parameterValues[parameter.id] = stepped
        applyCurrentSelection(rebuildFilters: false)
    }

    func stopCamera() {
        cameraManager.stop()
    }

    #if os(iOS)
    func swapCamera() {
        let nextPosition: AVCaptureDevice.Position = isFrontCamera ? .back : .front
        cameraManager.swapCamera(position: nextPosition)
        isFrontCamera = cameraManager.devicePosition == .front
    }
    #endif

    private func setupScene() {
        let cameraSurface = Surface(
            source: cameraSource,
            frame: CGRect(x: 0, y: 0, width: currentRenderSize.width, height: currentRenderSize.height),
            rotation: 0
        )
        let layer = Layer(surfaces: [cameraSurface])
        let group = LayerGroup(groups: [], layers: [layer], filters: [], mask: nil)

        let liveScene = VideoScene(duration: .infinity, frameRate: 30.0, size: currentRenderSize)
        liveScene.group = group
        scene = liveScene
    }

    private func setupCamera() {
        cameraManager.setup()

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.cameraSource.startCamera()
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Camera permission denied. Enable camera access in Settings."
                }
            }
        }
    }

    private func ensureValidSelectionForCurrentMode() {
        switch mode {
        case .filters:
            if filterEntries.first(where: { $0.id == selectedFilterID }) == nil, let first = filterEntries.first {
                selectedFilterID = first.id
                parameterValues = Self.defaults(for: first.parameters)
            }
        case .recipes:
            if recipeEntries.first(where: { $0.id == selectedRecipeID }) == nil, let first = recipeEntries.first {
                selectedRecipeID = first.id
            }
        }
    }

    private func applyCurrentSelection(rebuildFilters: Bool = true) {
        let size = currentRenderSize

        switch mode {
        case .filters:
            guard let entry = filterEntries.first(where: { $0.id == selectedFilterID }) else { return }
            let selectionID = entry.id
            let values = parameterValues

            if rebuildFilters || activeMode != .filters || activeSelectionID != selectionID {
                let filters = entry.makeFilters(values, size)
                activeMode = .filters
                activeSelectionID = selectionID
                sceneQueue.async { [weak self] in
                    guard let self, let scene = self.scene else { return }
                    scene.group.filters = filters
                }
                return
            }

            sceneQueue.async { [weak self] in
                guard let self, let scene = self.scene else { return }
                var filters = scene.group.filters
                guard !filters.isEmpty else { return }
                self.updateFiltersInPlace(&filters, entryID: selectionID, values: values, size: size)
                scene.group.filters = filters
            }
        case .recipes:
            guard let entry = recipeEntries.first(where: { $0.id == selectedRecipeID }) else { return }
            let filters = entry.makeFilters([:], size)
            let selectionID = entry.id
            activeMode = .recipes
            activeSelectionID = selectionID
            sceneQueue.async { [weak self] in
                guard let self, let scene = self.scene else { return }
                scene.group.filters = filters
            }
        }
    }

    private func updateFiltersInPlace(
        _ filters: inout [Filter],
        entryID: String,
        values: [String: Double],
        size: CGSize
    ) {
        for (id, value) in values {
            if let property = filterProperty(forParameterID: id) {
                for filter in filters {
                    filter.updateFilterValue(filterProperty: property, value: value)
                }
            }
        }

        guard let firstFilter = filters.first else { return }

        switch entryID {
        case "scale":
            if let filter = firstFilter as? Scale {
                filter.centerPoint = CGPoint(
                    x: size.width * (values["centerX"] ?? 0.5),
                    y: size.height * (values["centerY"] ?? 0.5)
                )
            }
        case "rotate":
            if let filter = firstFilter as? Rotate {
                filter.centerPoint = CGPoint(
                    x: size.width * (values["centerX"] ?? 0.5),
                    y: size.height * (values["centerY"] ?? 0.5)
                )
            }
        case "mirror":
            if let filter = firstFilter as? Mirror {
                filter.point = CGPoint(
                    x: size.width * (values["centerX"] ?? 0.5),
                    y: size.height * (values["centerY"] ?? 0.5)
                )
                filter.angle = values["angle"] ?? filter.angle
            }
        case "translate":
            if let filter = firstFilter as? Translate {
                filter.translation = CGPoint(
                    x: values["tx"] ?? 0.0,
                    y: values["ty"] ?? 0.0
                )
            }
        case "line_sketch":
            if let filter = firstFilter as? LineSketch {
                filter.edgeStrength = values["edge"] ?? filter.edgeStrength
            }
        case "voronoi":
            if let filter = firstFilter as? Voronoi {
                filter.scale = values["scale"] ?? filter.scale
                filter.radius = values["radius"] ?? filter.radius
                filter.intensity = values["intensity"] ?? filter.intensity
                filter.edgeIntensity = values["edge"] ?? filter.edgeIntensity
                filter.colorVariation = values["color"] ?? filter.colorVariation
                filter.driftSpeed = values["drift"] ?? filter.driftSpeed
            }
        case "jfa_voronoi":
            if let filter = firstFilter as? JFAVoronoiFilter {
                filter.particleCount = max(1, Int((values["particles"] ?? Double(filter.particleCount)).rounded()))
                filter.intensity = values["intensity"] ?? filter.intensity
                filter.edgeIntensity = values["edge"] ?? filter.edgeIntensity
                filter.colorVariation = values["color"] ?? filter.colorVariation
                filter.particleVelocity = values["velocity"] ?? filter.particleVelocity
                filter.particleOrbitAmplitude = values["orbit"] ?? filter.particleOrbitAmplitude
                filter.particleDriftSpeed = values["speed"] ?? filter.particleDriftSpeed
                filter.particleJitter = values["jitter"] ?? filter.particleJitter
            }
        case "impressionist":
            if let filter = firstFilter as? ImpressionistPaint {
                filter.strokeRadius = values["radius"] ?? filter.strokeRadius
                filter.softness = values["softness"] ?? filter.softness
            }
        case "body_electric":
            if let filter = firstFilter as? BodyElectric {
                filter.edgeIntensity = values["edge"] ?? filter.edgeIntensity
                filter.glowAmount = values["glow"] ?? filter.glowAmount
                filter.colorShift = values["hue"] ?? filter.colorShift
            }
        case "edge_overlay":
            if let filter = firstFilter as? EdgeOverlay {
                filter.edgeIntensity = values["edge"] ?? filter.edgeIntensity
                filter.overlayAmount = values["mix"] ?? filter.overlayAmount
            }
        case "panel_split":
            if let filter = firstFilter as? PanelSplitEffect {
                filter.columns = max(1, Int((values["columns"] ?? Double(filter.columns)).rounded()))
                filter.rows = max(1, Int((values["rows"] ?? Double(filter.rows)).rounded()))
                filter.gap = values["gap"] ?? filter.gap
                filter.hueShiftPerPanel = values["hueShift"] ?? filter.hueShiftPerPanel
                filter.saturation = values["saturation"] ?? filter.saturation
                filter.brightness = values["brightness"] ?? filter.brightness
            }
        case "flash_pulse":
            if let filter = firstFilter as? FlashPulse {
                filter.baseBrightness = values["brightness"] ?? filter.baseBrightness
                filter.pulseAmplitude = values["amp"] ?? filter.pulseAmplitude
                filter.speedHz = values["speed"] ?? filter.speedHz
                filter.saturation = values["saturation"] ?? filter.saturation
                filter.baseContrast = values["contrast"] ?? filter.baseContrast
            }
        case "zoom_pulse":
            if let filter = firstFilter as? ZoomPulse {
                filter.baseScale = values["baseScale"] ?? filter.baseScale
                filter.amplitude = values["amp"] ?? filter.amplitude
                filter.speedHz = values["speed"] ?? filter.speedHz
                filter.normalizedCenter = CGPoint(
                    x: values["centerX"] ?? filter.normalizedCenter.x,
                    y: values["centerY"] ?? filter.normalizedCenter.y
                )
            }
        case "temporal_grid_shift":
            if let filter = firstFilter as? TemporalGridShift {
                filter.columns = max(1, Int((values["cols"] ?? Double(filter.columns)).rounded()))
                filter.rows = max(1, Int((values["rows"] ?? Double(filter.rows)).rounded()))
                filter.frameOffset = max(1, Int((values["offset"] ?? Double(filter.frameOffset)).rounded()))
            }
        case "temporal_texture_atlas":
            if let filter = firstFilter as? TemporalTextureAtlasOutputsFilter {
                let offset = max(0, Int((values["frameOffset"] ?? 0.0).rounded()))
                let side = max(1, Int((values["frameSize"] ?? Double(Int(filter.inputFrameSize.width))).rounded()))
                filter.frameOffsets = [offset]
                filter.inputFrameSize = CGSize(width: CGFloat(side), height: CGFloat(side))
            }
        case "heatmap_frame_offset_atlas":
            if let filter = firstFilter as? HeatmapFrameOffsetAtlasFilter {
                let maxOffset = max(0, Int((values["maxOffset"] ?? Double(filter.maxFrameOffset)).rounded()))
                let side = max(1, Int((values["frameSize"] ?? Double(Int(filter.inputFrameSize.width))).rounded()))
                filter.maxFrameOffset = maxOffset
                filter.inputFrameSize = CGSize(width: CGFloat(side), height: CGFloat(side))
                filter.heatmapImage = Self.radialHeatmapImage(size: size)
            }
        case "linear_heatmap_frame_offset_atlas":
            if let filter = firstFilter as? HeatmapFrameOffsetAtlasFilter {
                let maxOffset = max(0, Int((values["maxOffset"] ?? Double(filter.maxFrameOffset)).rounded()))
                let side = max(1, Int((values["frameSize"] ?? Double(Int(filter.inputFrameSize.width))).rounded()))
                filter.maxFrameOffset = maxOffset
                filter.inputFrameSize = CGSize(width: CGFloat(side), height: CGFloat(side))
                filter.heatmapImage = Self.verticalHeatmapImage(size: size)
            }
        case "temporal_fade_atlas":
            if let filter = firstFilter as? TemporalFadeAtlasFilter {
                let frameCount = max(1, Int((values["frameCount"] ?? Double(filter.frameCount)).rounded()))
                let frameSpacing = max(1, Int((values["frameSpacing"] ?? Double(filter.frameSpacing)).rounded()))
                let side = max(1, Int((values["frameSize"] ?? Double(Int(filter.inputFrameSize.width))).rounded()))
                filter.frameCount = frameCount
                filter.frameSpacing = frameSpacing
                filter.inputFrameSize = CGSize(width: CGFloat(side), height: CGFloat(side))
            }
        case "temporal_color_split_atlas":
            if let filter = firstFilter as? TemporalColorSplitAtlasFilter {
                let frameCount = max(1, Int((values["frameCount"] ?? Double(filter.frameCount)).rounded()))
                let frameSpacing = max(1, Int((values["frameSpacing"] ?? Double(filter.frameSpacing)).rounded()))
                let componentCount = max(1, Int((values["componentCount"] ?? Double(filter.componentCount)).rounded()))
                let side = max(1, Int((values["frameSize"] ?? Double(Int(filter.inputFrameSize.width))).rounded()))
                filter.frameCount = frameCount
                filter.frameSpacing = frameSpacing
                filter.componentCount = componentCount
                filter.inputFrameSize = CGSize(width: CGFloat(side), height: CGFloat(side))
            }
        case "perlin_flow_field_atlas":
            if let filter = firstFilter as? PerlinFlowFieldAtlasFilter {
                let maxOffset = max(0, Int((values["maxOffset"] ?? Double(filter.maxFrameOffset)).rounded()))
                let side = max(1, Int((values["frameSize"] ?? Double(Int(filter.inputFrameSize.width))).rounded()))
                filter.maxFrameOffset = maxOffset
                filter.noiseScale = values["noiseScale"] ?? filter.noiseScale
                filter.flowSpeed = values["flowSpeed"] ?? filter.flowSpeed
                filter.inputFrameSize = CGSize(width: CGFloat(side), height: CGFloat(side))
            }
        case "shake_jitter":
            if let filter = firstFilter as? ShakeJitter {
                filter.translationAmplitude = CGPoint(
                    x: values["tx"] ?? filter.translationAmplitude.x,
                    y: values["ty"] ?? filter.translationAmplitude.y
                )
                filter.rotationAmplitude = values["rotation"] ?? filter.rotationAmplitude
                filter.scaleAmplitude = values["scale"] ?? filter.scaleAmplitude
                filter.speedHz = values["speed"] ?? filter.speedHz
            }
        case "hue_pulse":
            if let filter = firstFilter as? HuePulse {
                filter.baseHue = values["baseHue"] ?? filter.baseHue
                filter.hueAmplitude = values["amp"] ?? filter.hueAmplitude
                filter.speedHz = values["speed"] ?? filter.speedHz
                filter.saturation = values["saturation"] ?? filter.saturation
                filter.brightness = values["brightness"] ?? filter.brightness
                filter.contrast = values["contrast"] ?? filter.contrast
            }
        case "twirl_pulse":
            if let filter = firstFilter as? TwirlPulse {
                filter.normalizedCenter = CGPoint(
                    x: values["centerX"] ?? filter.normalizedCenter.x,
                    y: values["centerY"] ?? filter.normalizedCenter.y
                )
                filter.normalizedRadius = values["radius"] ?? filter.normalizedRadius
                filter.angleAmplitude = values["angle"] ?? filter.angleAmplitude
                filter.speedHz = values["speed"] ?? filter.speedHz
            }
        case "alpha_vignette":
            if let filter = firstFilter as? AlphaVignette {
                filter.center = CGPoint(
                    x: values["centerX"] ?? filter.center.x,
                    y: values["centerY"] ?? filter.center.y
                )
                filter.start = values["start"] ?? filter.start
                filter.end = values["end"] ?? filter.end
                filter.innerAlpha = values["inner"] ?? filter.innerAlpha
                filter.outerAlpha = values["outer"] ?? filter.outerAlpha
            }
        case "color_vignette":
            if let filter = firstFilter as? ColorVignette {
                filter.center = CGPoint(
                    x: values["centerX"] ?? filter.center.x,
                    y: values["centerY"] ?? filter.center.y
                )
                filter.start = values["start"] ?? filter.start
                filter.end = values["end"] ?? filter.end
                let alpha = values["alpha"] ?? Double(filter.ringColor.alpha)
                filter.ringColor = CIColor(red: 0, green: 0, blue: 0, alpha: alpha)
            }
        default:
            break
        }
    }

    private func filterProperty(forParameterID id: String) -> FilterProperty? {
        if let property = FilterProperty(rawValue: id) {
            return property
        }

        switch id {
        case "image1":
            return .image1Amount
        case "image2":
            return .image2Amount
        case "strength":
            return .filterStrength
        default:
            return nil
        }
    }
}

extension FilterShowcaseViewModel: CameraSourceDelegate {
    func didReceiveFrame(frame: Frame) {
        let frameTime = CMTimeGetSeconds(frame.time)
        let renderedImage: CIImage? = sceneQueue.sync { [weak self] in
            guard let self, let scene = self.scene else { return nil }
            return scene.group.renderGroup(
                frameTime: frameTime,
                compositionTimeOffset: 0.0,
                inputImage: nil
            )
        }
        
        guard let renderedImage else {
            return
        }

        let renderedSize = renderedImage.extent.size
        let shouldApplyNewSize = !hasAppliedFirstFrameSize && renderedSize.width > 0 && renderedSize.height > 0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previewState.displayCIImage = renderedImage

            if shouldApplyNewSize {
                self.hasAppliedFirstFrameSize = true
                self.currentRenderSize = renderedSize
                self.applyCurrentSelection()
            }
        }
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

        let fallback = CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 0.8)).cropped(to: extent)
        let base = (gradient.outputImage ?? fallback).cropped(to: extent)

        let controls = CIFilter.colorControls()
        controls.inputImage = base
        controls.saturation = 1.25
        controls.contrast = 1.05
        return (controls.outputImage ?? base).cropped(to: extent)
    }

    static func radialHeatmapImage(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        gradient.radius0 = Float(min(size.width, size.height)) * 0.08
        gradient.radius1 = Float(min(size.width, size.height)) * 0.52
        gradient.color0 = CIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        gradient.color1 = CIColor.black

        let fallback = CIImage(color: CIColor.black).cropped(to: extent)
        return (gradient.outputImage ?? fallback).cropped(to: extent)
    }

    static func verticalHeatmapImage(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: size.width * 0.5, y: size.height)
        gradient.point1 = CGPoint(x: size.width * 0.5, y: 0)
        gradient.color0 = CIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        gradient.color1 = CIColor.black

        let fallback = CIImage(color: CIColor.black).cropped(to: extent)
        return (gradient.outputImage ?? fallback).cropped(to: extent)
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
                id: "mirror",
                name: "Mirror",
                subtitle: "Reflect across a point-and-angle axis",
                category: "Core",
                parameters: [
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5),
                    p("angle", "Angle", -Double.pi...Double.pi, 0.0)
                ],
                makeFilters: { values, size in
                    let point = CGPoint(
                        x: size.width * (values["centerX"] ?? 0.5),
                        y: size.height * (values["centerY"] ?? 0.5)
                    )
                    return [Mirror(point: point, angle: values["angle"] ?? 0.0, filterAnimators: [])]
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
                    [Translate(
                        translation: CGPoint(x: values["tx"] ?? 0.0, y: values["ty"] ?? 0.0),
                        filterAnimators: []
                    )]
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
                id: "voronoi",
                name: "Voronoi",
                subtitle: "Cellular stylize",
                category: "Core",
                parameters: [
                    p("scale", "Cell Size", 4.0...120.0, 32.0, step: 1.0),
                    p("radius", "Jitter", 0.0...1.0, 0.9),
                    p("intensity", "Intensity", 0.0...1.0, 1.0),
                    p("edge", "Edge", 0.0...1.0, 0.75),
                    p("color", "Color Variation", 0.0...1.0, 0.35),
                    p("drift", "Drift Speed", 0.0...2.0, 0.25)
                ],
                makeFilters: { values, _ in
                    [Voronoi(
                        scale: values["scale"] ?? 32.0,
                        radius: values["radius"] ?? 0.9,
                        intensity: values["intensity"] ?? 1.0,
                        edgeIntensity: values["edge"] ?? 0.75,
                        colorVariation: values["color"] ?? 0.35,
                        driftSpeed: values["drift"] ?? 0.25,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "jfa_voronoi",
                name: "JFA Voronoi",
                subtitle: "Multipass jump flood Voronoi",
                category: "Core",
                parameters: [
                    p("particles", "Particles", 16.0...512.0, 160.0, step: 1.0),
                    p("intensity", "Intensity", 0.0...1.0, 1.0),
                    p("edge", "Edge", 0.0...1.0, 0.8),
                    p("color", "Color Variation", 0.0...1.0, 0.35),
                    p("velocity", "Particle Velocity", 0.0...0.8, 0.10),
                    p("orbit", "Orbit Amount", 0.0...0.4, 0.07),
                    p("speed", "Drift Speed", 0.0...2.0, 0.45),
                    p("jitter", "Particle Jitter", 0.0...1.0, 0.25)
                ],
                makeFilters: { values, _ in
                    let generator = AnimatedParticleGenerator(
                        velocity: Float(values["velocity"] ?? 0.10),
                        orbitAmplitude: Float(values["orbit"] ?? 0.07),
                        orbitSpeed: Float(values["speed"] ?? 0.45),
                        jitterAmount: Float(values["jitter"] ?? 0.25)
                    )
                    return [JFAVoronoiFilter(
                        particleCount: max(1, Int((values["particles"] ?? 160.0).rounded())),
                        intensity: values["intensity"] ?? 1.0,
                        edgeIntensity: values["edge"] ?? 0.8,
                        colorVariation: values["color"] ?? 0.35,
                        particleVelocity: values["velocity"] ?? 0.10,
                        particleOrbitAmplitude: values["orbit"] ?? 0.07,
                        particleDriftSpeed: values["speed"] ?? 0.45,
                        particleJitter: values["jitter"] ?? 0.25,
                        particleGenerator: generator,
                        filterAnimators: []
                    )]
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
                id: "divide_blend",
                name: "Divide Blend",
                subtitle: "CIDivideBlendMode",
                category: "Blend",
                parameters: [],
                makeFilters: { _, size in [DivideBlend(backgroundImage: blendImage(size: size), filterAnimators: [])] }
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
                id: "normal_blend",
                name: "Normal Blend",
                subtitle: "CISourceOverCompositing",
                category: "Blend",
                parameters: [],
                makeFilters: { _, size in [NormalBlend(backgroundImage: blendImage(size: size), filterAnimators: [])] }
            ),

            ShowcaseEntry(
                id: "sepia",
                name: "Sepia Tone",
                subtitle: "Classic sepia",
                category: "Color",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.8)],
                makeFilters: { values, _ in
                    [SepiaTone(intensity: values["intensity"] ?? 0.8, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "monochrome",
                name: "Monochrome Tone",
                subtitle: "Color monochrome blend",
                category: "Color",
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
                category: "Color",
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
                category: "Color",
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
                id: "comic",
                name: "Comic Stylize",
                subtitle: "CIComicEffect blend",
                category: "Stylize",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.9)],
                makeFilters: { values, _ in
                    [ComicStylize(intensity: values["intensity"] ?? 0.9, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "thermal",
                name: "Thermal Stylize",
                subtitle: "CIThermal blend",
                category: "Stylize",
                parameters: [p("intensity", "Intensity", 0.0...1.0, 0.9)],
                makeFilters: { values, _ in
                    [ThermalStylize(intensity: values["intensity"] ?? 0.9, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "kuwahara",
                name: "Kuwahara (Metal)",
                subtitle: "Painterly abstraction (custom Metal)",
                category: "Stylize",
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
                category: "Stylize",
                parameters: [p("edge", "Edge Strength", 0.0...4.0, 1.45)],
                makeFilters: { values, _ in
                    [LineSketch(edgeStrength: values["edge"] ?? 1.45, invert: true, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "impressionist",
                name: "Impressionist Paint",
                subtitle: "Brush-stroke abstraction",
                category: "Stylize",
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
                category: "Stylize",
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
            ),
            ShowcaseEntry(
                id: "glitch_effect",
                name: "Glitch Effect",
                subtitle: "Metal-backed glitch filter",
                category: "Stylize",
                parameters: [p("intensity", "Intensity", 0.0...3.0, 1.0)],
                makeFilters: { values, _ in
                    if #available(iOS 15.0, *) {
                        return [GlitchEffect(intensity: values["intensity"] ?? 1.0, filterAnimators: [])]
                    }
                    return [ColorAdjustment(brightness: 0.0, contrast: 1.0, saturation: 1.0, filterAnimators: [])]
                }
            ),

            ShowcaseEntry(
                id: "film_grain",
                name: "Film Grain",
                subtitle: "Noise overlay",
                category: "Effects",
                parameters: [p("intensity", "Intensity", 0.0...0.8, 0.22)],
                makeFilters: { values, _ in
                    [FilmGrain(intensity: values["intensity"] ?? 0.22, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "edge_overlay",
                name: "Edge Overlay",
                subtitle: "Sketch-like edge blend",
                category: "Effects",
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
                category: "Effects",
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
                category: "Temporal",
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
                category: "Temporal",
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
                category: "Temporal",
                parameters: [p("strength", "Filter Strength", 0.0...1.0, 0.35)],
                makeFilters: { values, _ in
                    [TemporalLowPass(filterStrength: values["strength"] ?? 0.35, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "temporal_grid_shift",
                name: "Temporal Grid Shift",
                subtitle: "Grid cells shift up over time",
                category: "Temporal",
                parameters: [
                    p("cols", "Columns", 2.0...6.0, 3.0, step: 1.0),
                    p("rows", "Rows", 2.0...6.0, 3.0, step: 1.0),
                    p("offset", "Frame Offset", 1.0...12.0, 1.0, step: 1.0)
                ],
                makeFilters: { values, _ in
                    let cols = max(1, Int((values["cols"] ?? 3.0).rounded()))
                    let rows = max(1, Int((values["rows"] ?? 3.0).rounded()))
                    let offset = max(1, Int((values["offset"] ?? 1.0).rounded()))
                    return [TemporalGridShift(columns: cols, rows: rows, frameOffset: offset, filterAnimators: [])]
                }
            ),
            ShowcaseEntry(
                id: "temporal_texture_atlas",
                name: "Temporal Texture Atlas",
                subtitle: "Max-texture ring buffer with frame offset",
                category: "Temporal",
                parameters: [
                    p("frameOffset", "Frame Offset", 0.0...240.0, 0.0, step: 1.0),
                    p("frameSize", "Input Frame Size", 128.0...2048.0, 1024.0, step: 64.0)
                ],
                makeFilters: { values, _ in
                    let offset = Int((values["frameOffset"] ?? 0.0).rounded())
                    let side = max(1, Int((values["frameSize"] ?? 1024.0).rounded()))
                    return [TemporalTextureAtlasOutputsFilter(
                        frameOffsets: [offset],
                        primaryOutputIndex: 0,
                        inputFrameSize: CGSize(width: CGFloat(side), height: CGFloat(side)),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "heatmap_frame_offset_atlas",
                name: "Heatmap Frame Offset Atlas",
                subtitle: "Radial heatmap drives per-pixel temporal history",
                category: "Temporal",
                parameters: [
                    p("maxOffset", "Max Frame Offset", 0.0...240.0, 48.0, step: 1.0),
                    p("frameSize", "Input Frame Size", 128.0...2048.0, 1024.0, step: 64.0)
                ],
                makeFilters: { values, size in
                    let maxOffset = max(0, Int((values["maxOffset"] ?? 48.0).rounded()))
                    let side = max(1, Int((values["frameSize"] ?? 1024.0).rounded()))
                    return [HeatmapFrameOffsetAtlasFilter(
                        maxFrameOffset: maxOffset,
                        heatmapImage: radialHeatmapImage(size: size),
                        inputFrameSize: CGSize(width: CGFloat(side), height: CGFloat(side)),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "linear_heatmap_frame_offset_atlas",
                name: "Linear Heatmap Frame Offset Atlas",
                subtitle: "Top-to-bottom heatmap drives per-pixel temporal history",
                category: "Temporal",
                parameters: [
                    p("maxOffset", "Max Frame Offset", 0.0...240.0, 48.0, step: 1.0),
                    p("frameSize", "Input Frame Size", 128.0...2048.0, 1024.0, step: 64.0)
                ],
                makeFilters: { values, size in
                    let maxOffset = max(0, Int((values["maxOffset"] ?? 48.0).rounded()))
                    let side = max(1, Int((values["frameSize"] ?? 1024.0).rounded()))
                    return [HeatmapFrameOffsetAtlasFilter(
                        maxFrameOffset: maxOffset,
                        heatmapImage: verticalHeatmapImage(size: size),
                        inputFrameSize: CGSize(width: CGFloat(side), height: CGFloat(side)),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "temporal_fade_atlas",
                name: "Temporal Fade Atlas",
                subtitle: "Averages spaced frame samples across time",
                category: "Temporal",
                parameters: [
                    p("frameCount", "Frame Count", 1.0...15.0, 8.0, step: 1.0),
                    p("frameSpacing", "Frame Spacing", 1.0...12.0, 2.0, step: 1.0),
                    p("frameSize", "Input Frame Size", 128.0...2048.0, 1024.0, step: 64.0)
                ],
                makeFilters: { values, _ in
                    let frameCount = max(1, Int((values["frameCount"] ?? 8.0).rounded()))
                    let frameSpacing = max(1, Int((values["frameSpacing"] ?? 2.0).rounded()))
                    let side = max(1, Int((values["frameSize"] ?? 1024.0).rounded()))
                    return [TemporalFadeAtlasFilter(
                        frameCount: frameCount,
                        frameSpacing: frameSpacing,
                        inputFrameSize: CGSize(width: CGFloat(side), height: CGFloat(side)),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "temporal_color_split_atlas",
                name: "Temporal Color Split Atlas",
                subtitle: "Palette-tinted temporal samples blended across time",
                category: "Temporal",
                parameters: [
                    p("frameCount", "Frame Count", 1.0...15.0, 8.0, step: 1.0),
                    p("frameSpacing", "Frame Spacing", 1.0...12.0, 2.0, step: 1.0),
                    p("componentCount", "Color Components", 3.0...9.0, 6.0, step: 1.0),
                    p("frameSize", "Input Frame Size", 128.0...2048.0, 1024.0, step: 64.0)
                ],
                makeFilters: { values, _ in
                    let frameCount = max(1, Int((values["frameCount"] ?? 8.0).rounded()))
                    let frameSpacing = max(1, Int((values["frameSpacing"] ?? 2.0).rounded()))
                    let componentCount = max(1, Int((values["componentCount"] ?? 6.0).rounded()))
                    let side = max(1, Int((values["frameSize"] ?? 1024.0).rounded()))
                    return [TemporalColorSplitAtlasFilter(
                        frameCount: frameCount,
                        frameSpacing: frameSpacing,
                        componentCount: componentCount,
                        inputFrameSize: CGSize(width: CGFloat(side), height: CGFloat(side)),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "perlin_flow_field_atlas",
                name: "Perlin Flow Field Atlas",
                subtitle: "Per-pixel temporal offsets from Metal noise field",
                category: "Temporal",
                parameters: [
                    p("maxOffset", "Max Frame Offset", 0.0...240.0, 24.0, step: 1.0),
                    p("noiseScale", "Noise Scale", 1.0...40.0, 8.0, step: 0.25),
                    p("flowSpeed", "Flow Speed", 0.0...2.0, 0.18, step: 0.01),
                    p("frameSize", "Input Frame Size", 128.0...2048.0, 1024.0, step: 64.0)
                ],
                makeFilters: { values, _ in
                    let maxOffset = max(0, Int((values["maxOffset"] ?? 24.0).rounded()))
                    let side = max(1, Int((values["frameSize"] ?? 1024.0).rounded()))
                    return [PerlinFlowFieldAtlasFilter(
                        maxFrameOffset: maxOffset,
                        noiseScale: values["noiseScale"] ?? 8.0,
                        flowSpeed: values["flowSpeed"] ?? 0.18,
                        inputFrameSize: CGSize(width: CGFloat(side), height: CGFloat(side)),
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "shake_jitter",
                name: "Shake Jitter",
                subtitle: "Transform shake",
                category: "Temporal",
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
                category: "Temporal",
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
                category: "Temporal",
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
                id: "alpha_vignette",
                name: "Alpha Vignette",
                subtitle: "Alpha edge fade",
                category: "Vignette",
                parameters: [
                    p("start", "Start", 0.1...0.8, 0.3),
                    p("end", "End", 0.2...1.0, 0.85),
                    p("inner", "Inner Alpha", 0.0...1.0, 1.0),
                    p("outer", "Outer Alpha", 0.0...1.0, 0.2),
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, _ in
                    [AlphaVignette(
                        center: CGPoint(x: values["centerX"] ?? 0.5, y: values["centerY"] ?? 0.5),
                        start: values["start"] ?? 0.3,
                        end: values["end"] ?? 0.85,
                        innerAlpha: values["inner"] ?? 1.0,
                        outerAlpha: values["outer"] ?? 0.2,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "color_vignette",
                name: "Color Vignette",
                subtitle: "Tinted edge overlay",
                category: "Vignette",
                parameters: [
                    p("start", "Start", 0.1...0.8, 0.35),
                    p("end", "End", 0.2...1.0, 0.90),
                    p("alpha", "Ring Alpha", 0.0...1.0, 0.35),
                    p("centerX", "Center X", 0.0...1.0, 0.5),
                    p("centerY", "Center Y", 0.0...1.0, 0.5)
                ],
                makeFilters: { values, _ in
                    [ColorVignette(
                        center: CGPoint(x: values["centerX"] ?? 0.5, y: values["centerY"] ?? 0.5),
                        centerColor: CIColor(red: 0, green: 0, blue: 0, alpha: 0.0),
                        ringColor: CIColor(red: 0, green: 0, blue: 0, alpha: values["alpha"] ?? 0.35),
                        start: values["start"] ?? 0.35,
                        end: values["end"] ?? 0.90,
                        filterAnimators: []
                    )]
                }
            ),
            ShowcaseEntry(
                id: "bloom_glow",
                name: "Bloom Glow",
                subtitle: "Highlight bloom",
                category: "Vignette",
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
            )
        ]
    }

    static func makeRecipeEntries() -> [ShowcaseEntry] {
        var seenStorageNames = Set<String>()
        var entries: [ShowcaseEntry] = []

        for key in ShimmeoStyleRecipeFactory.supportedStorageNames {
            guard let recipe = ShimmeoStyleRecipeFactory.recipe(forStorageName: key) else { continue }
            guard seenStorageNames.insert(recipe.storageName).inserted else { continue }

            entries.append(
                ShowcaseEntry(
                    id: recipe.storageName,
                    name: recipe.displayName,
                    subtitle: "Storage: \(recipe.storageName)",
                    category: "Recipe",
                    parameters: [],
                    makeFilters: { _, _ in recipe.makeFilters() }
                )
            )
        }

        return entries
    }
}
