//
//  CameraViewModel.swift
//  HandPoseAnimationSample
//

import Foundation
import SwiftUI
import Combine
import VideoProcessingTwo
import Vision
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import MediaPlayer
import Photos

public class CameraViewModel: NSObject, ObservableObject {
    @Published public var detectedHands: [VNHumanHandPoseObservation] = []
    @Published public var handPosition: (x: Double, y: Double)? = nil
    @Published public var animationState: HandAnimationState = .idle
    @Published public var analysisMode: AnalysisMode = .handPosition {
        didSet {
            updateFiltersForCurrentMode()
        }
    }
    @Published public var displayCIImage: CIImage?
    @Published public var handSpeed: Double = 0.0
    @Published public var handSpread: Double = 0.0
    @Published public var detectedFingerCount: Int = 0
    @Published public private(set) var isRecordingVideo: Bool = false
    @Published public private(set) var isSavingRecording: Bool = false
    @Published public var recordingStatusMessage: String?

    public let cameraManager: CameraManager
    public let handPoseCollector: HandPoseDataCollector
    public let cameraSource: CameraSource
    @Published public var audioPlayer: AudioPlayer

    private var cameraScene: VideoScene?
    private var modeFilters: [AnalysisMode: [Filter]] = [:]
    private var previousMetricsPosition: (x: Double, y: Double)?
    private var previousMetricsTimestamp: TimeInterval?
    private static let temporalAudioMaxFrameOffset: Double = 48.0
    private static let temporalAtlasAudioMaxFrameOffset: Double = 48.0
    private static let heatmapAtlasAudioMaxFrameOffset: Double = 48.0
    private static let linearHeatmapAtlasAudioMaxFrameOffset: Double = 48.0
    private static let temporalFadeAudioMaxFrameCount: Double = 15.0
    private static let temporalFadeAudioFrameSpacing: Int = 2
    private let recordingStateQueue = DispatchQueue(label: "com.handpose.recording.state")
    private let recordingColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var movieWriter: MovieWriter?
    private var recordingOutputURL: URL?
    private var recordingRenderSize: CGSize = .zero
    private var recordingStartTime: CMTime?
    private var recordedFrameCount: Int = 0

    public enum AnalysisMode: String, CaseIterable, Identifiable {
        case handPosition
        case audio
        case temporalAudio
        case temporalAtlasAudio
        case heatmapAtlasAudio
        case linearHeatmapAtlasAudio
        case temporalFadeAudio
        case handDistance
        case handHeight
        case handVelocity
        case fingerCount
        case handStability
        case handSpread

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .handPosition:
                return "Hand Position"
            case .audio:
                return "Audio"
            case .temporalAudio:
                return "Temporal Audio"
            case .temporalAtlasAudio:
                return "Temporal Atlas Audio"
            case .heatmapAtlasAudio:
                return "Heatmap Atlas Audio"
            case .linearHeatmapAtlasAudio:
                return "Linear Heatmap Atlas Audio"
            case .temporalFadeAudio:
                return "Temporal Fade Audio"
            case .handDistance:
                return "Hand Distance"
            case .handHeight:
                return "Hand Height"
            case .handVelocity:
                return "Hand Velocity"
            case .fingerCount:
                return "Finger Count"
            case .handStability:
                return "Hand Stability"
            case .handSpread:
                return "Hand Spread"
            }
        }

        public var usesAudioInput: Bool {
            self == .audio || self == .temporalAudio || self == .temporalAtlasAudio || self == .heatmapAtlasAudio || self == .linearHeatmapAtlasAudio || self == .temporalFadeAudio
        }
    }

    public var isAudioMode: Bool {
        analysisMode.usesAudioInput
    }

    public var currentModeMetrics: [(label: String, value: String)] {
        if analysisMode.usesAudioInput {
            let amplitude = Double(audioPlayer.currentAmplitude)
            switch analysisMode {
            case .audio:
                return [("Amplitude", String(format: "%.2f", amplitude))]
            case .temporalAudio:
                let maxOffset = Int((amplitude * Self.temporalAudioMaxFrameOffset).rounded())
                return [
                    ("Amplitude", String(format: "%.2f", amplitude)),
                    ("Max Frame Offset", "\(maxOffset)"),
                    ("Filter", "Perlin Flow Atlas"),
                    ("Noise Scale", "2.0"),
                    ("Flow Speed", "0.0"),
                    ("Input Frame", "1024")
                ]
            case .temporalAtlasAudio:
                let maxOffset = Int((amplitude * Self.temporalAtlasAudioMaxFrameOffset).rounded())
                return [
                    ("Amplitude", String(format: "%.2f", amplitude)),
                    ("Max Frame Offset", "\(maxOffset)"),
                    ("Filter", "Temporal Atlas"),
                    ("Input Frame", "1024")
                ]
            case .heatmapAtlasAudio:
                let maxOffset = Int((amplitude * Self.heatmapAtlasAudioMaxFrameOffset).rounded())
                return [
                    ("Amplitude", String(format: "%.2f", amplitude)),
                    ("Max Frame Offset", "\(maxOffset)"),
                    ("Filter", "Heatmap Atlas"),
                    ("Heatmap", "Radial Gradient"),
                    ("Input Frame", "1024")
                ]
            case .linearHeatmapAtlasAudio:
                let maxOffset = Int((amplitude * Self.linearHeatmapAtlasAudioMaxFrameOffset).rounded())
                return [
                    ("Amplitude", String(format: "%.2f", amplitude)),
                    ("Max Frame Offset", "\(maxOffset)"),
                    ("Filter", "Heatmap Atlas"),
                    ("Heatmap", "Vertical Gradient"),
                    ("Input Frame", "1024")
                ]
            case .temporalFadeAudio:
                let frameCount = max(1, Int((amplitude * (Self.temporalFadeAudioMaxFrameCount - 1.0)).rounded()) + 1)
                return [
                    ("Amplitude", String(format: "%.2f", amplitude)),
                    ("Frame Count", "\(frameCount)"),
                    ("Frame Spacing", "\(Self.temporalFadeAudioFrameSpacing)"),
                    ("Filter", "Temporal Fade Atlas"),
                    ("Input Frame", "1024")
                ]
            default:
                break
            }
        }

        guard let position = handPosition else {
            return [("Status", "No hand detected")]
        }

        let distance = normalizedDistance(fromCenterFor: position)

        switch analysisMode {
        case .handPosition:
            return [
                ("X Position", String(format: "%.2f", position.x)),
                ("Y Position", String(format: "%.2f", position.y)),
                ("Blur Radius", String(format: "%.1f px", position.x * 20.0)),
                ("Brightness", String(format: "%.2f", position.y - 0.5))
            ]
        case .handDistance:
            return [
                ("Distance", String(format: "%.2f", distance)),
                ("Blur Radius", String(format: "%.1f px", distance * 24.0)),
                ("Contrast", String(format: "%.2f", 0.8 + (distance * 0.8)))
            ]
        case .handHeight:
            return [
                ("Height", String(format: "%.2f", position.y)),
                ("Blur Radius", String(format: "%.1f px", position.y * 18.0)),
                ("Brightness", String(format: "%.2f", (position.y * 0.7) - 0.35))
            ]
        case .handVelocity:
            return [
                ("Speed", String(format: "%.2f", handSpeed)),
                ("Blur Radius", String(format: "%.1f px", handSpeed * 30.0)),
                ("Saturation", String(format: "%.2f", 0.7 + (handSpeed * 1.1)))
            ]
        case .fingerCount:
            let normalizedCount = Double(detectedFingerCount) / 5.0
            return [
                ("Finger Count", "\(detectedFingerCount) / 5"),
                ("Blur Radius", String(format: "%.1f px", normalizedCount * 22.0)),
                ("Saturation", String(format: "%.2f", 0.8 + (normalizedCount * 1.2)))
            ]
        case .handStability:
            let stability = max(0.0, 1.0 - handSpeed)
            return [
                ("Stability", String(format: "%.0f%%", stability * 100.0)),
                ("Speed", String(format: "%.2f", handSpeed)),
                ("Blur Radius", String(format: "%.1f px", (1.0 - stability) * 20.0))
            ]
        case .handSpread:
            return [
                ("Spread", String(format: "%.2f", handSpread)),
                ("Blur Radius", String(format: "%.1f px", handSpread * 20.0)),
                ("Brightness", String(format: "%.2f", (handSpread * 0.45) - 0.2))
            ]
        case .audio, .temporalAudio, .temporalAtlasAudio, .heatmapAtlasAudio, .linearHeatmapAtlasAudio, .temporalFadeAudio:
            return [("Amplitude", String(format: "%.2f", Double(audioPlayer.currentAmplitude)))]
        }
    }

    override public init() {
        cameraManager = CameraManager()
        handPoseCollector = HandPoseDataCollector()
        audioPlayer = AudioPlayer()
        cameraSource = CameraSource(cameraManager: cameraManager)

        super.init()

        // Set up hand pose detection as a delegate
        cameraSource.delegate = self

        // Setup filters driven by hand pose
        setupFilters()

        // Setup the scene with camera source and filters
        setupScene()

        // Subscribe to pose updates
        handPoseCollector.onHandPoseUpdated = { [weak self] observations in
            DispatchQueue.main.async {
                self?.updateAnimationState(from: observations)
                self?.detectedHands = observations
                let position = self?.handPoseCollector.getNormalizedHandPosition()
                self?.handPosition = position
                self?.updateHandMetrics(observations: observations, position: position)
            }
        }

        // Subscribe to frame updates from camera source for rendering
//        cameraSource.cameraManager.delegate = self
    }

    private func setupScene() {
        let filters = modeFilters[analysisMode] ?? []

        // Create a surface with the camera source
        let surface = Surface(source: cameraSource, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), rotation: 0)
        let layer = Layer(surfaces: [surface])

        // Create the main group with the camera layer
        let mainGroup = LayerGroup(groups: [], layers: [layer], filters: filters, mask: nil)

        // Create the scene with the main group
        let scene = VideoScene(duration: .infinity, frameRate: 30.0)
        scene.group = mainGroup
        cameraScene = scene
    }

    private func drawHandBoundingBoxes(on image: CIImage, observations: [VNHumanHandPoseObservation]) -> CIImage {
        var resultImage = image
        let imageSize = image.extent.size

        for observation in observations {
            // Calculate bounding box from all hand points
            guard let boundingBox = calculateBoundingBox(from: observation) else {
                continue
            }

            // Convert from Vision coordinates (normalized, top-left origin) to Core Image coordinates
            let rect = CGRect(
                x: boundingBox.minX * imageSize.width,
                y: boundingBox.minY * imageSize.height,
                width: boundingBox.width * imageSize.width,
                height: boundingBox.height * imageSize.height
            )

            // Draw bounding box using Core Image
            resultImage = drawBoundingBox(on: resultImage, rect: rect, strokeWidth: 4.0)
        }

        return resultImage
    }

    private func calculateBoundingBox(from observation: VNHumanHandPoseObservation) -> CGRect? {
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        // Get all recognized points
        let joints: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        for joint in joints {
            do {
                let point = try observation.recognizedPoint(joint)
                minX = min(minX, point.location.x)
                maxX = max(maxX, point.location.x)
                minY = min(minY, point.location.y)
                maxY = max(maxY, point.location.y)
            } catch {
                continue
            }
        }

        // Add padding around the bounding box
        let padding = CGFloat(0.05)
        let width = maxX - minX
        let height = maxY - minY
        let paddedRect = CGRect(
            x: max(0, minX - padding * width),
            y: max(0, minY - padding * height),
            width: width + 2 * padding * width,
            height: height + 2 * padding * height
        )

        return paddedRect.width > 0 && paddedRect.height > 0 ? paddedRect : nil
    }

    private func drawBoundingBox(on image: CIImage, rect: CGRect, strokeWidth: CGFloat) -> CIImage {
        // Create green box for the entire bounding box
        let greenBox = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1))
            .cropped(to: rect)

        // Composite green box over original image
        let withGreenStroke = greenBox.composited(over: image)

        // Extract the inner portion of the original image (before green was added)
        let innerRect = rect.insetBy(dx: strokeWidth, dy: strokeWidth)
        let innerImage = image.cropped(to: innerRect)

        // Composite the inner (original) image back on top to cover the green in the center
        let final = innerImage.composited(over: withGreenStroke)

        return final
    }

    private func setupFilters() {
        let handBlurTween = HandPositionTweenFunction(
            collector: handPoseCollector,
            duration: 1.0,
            coordinate: .x
        )
        let handHeightTween = HandPositionTweenFunction(
            collector: handPoseCollector,
            duration: 1.0,
            coordinate: .y
        )
        let handDistanceTween = HandPositionTweenFunction(
            collector: handPoseCollector,
            duration: 1.0,
            coordinate: .distance
        )
        let audioBlurTween = AudioAmplitudeTweenFunction(audioPlayer: audioPlayer)
        let speedTween = LiveMetricTweenFunction { [weak self] in
            self?.handSpeed ?? 0.0
        }
        let fingerCountTween = LiveMetricTweenFunction { [weak self] in
            Double(self?.detectedFingerCount ?? 0) / 5.0
        }
        let spreadTween = LiveMetricTweenFunction { [weak self] in
            self?.handSpread ?? 0.0
        }
        let stabilityTween = LiveMetricTweenFunction { [weak self] in
            1.0 - (self?.handSpeed ?? 0.0)
        }

        let handPositionFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 20.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: handBlurTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .brightness,
                        startValue: -0.5,
                        endValue: 0.5,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: handHeightTween
                    )
                ]
            )
        ]

        let audioFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 20.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: audioBlurTween
                )
            ])
        ]

        let radialHeatmap = Self.radialHeatmapImage(size: CGSize(width: 1024, height: 1024))
        let verticalHeatmap = Self.verticalHeatmapImage(size: CGSize(width: 1024, height: 1024))

        let temporalAudioFilters: [Filter] = [
            PerlinFlowFieldAtlasFilter(
                maxFrameOffset: Int(Self.temporalAudioMaxFrameOffset.rounded()),
                noiseScale: 2.0,
                flowSpeed: 0.0,
                inputFrameSize: CGSize(width: 1024, height: 1024),
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .intensity,
                        startValue: 0.0,
                        endValue: Self.temporalAudioMaxFrameOffset,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: audioBlurTween
                    )
                ]
            )
        ]

        let heatmapAtlasAudioFilters: [Filter] = [
            HeatmapFrameOffsetAtlasFilter(
                maxFrameOffset: Int(Self.heatmapAtlasAudioMaxFrameOffset.rounded()),
                heatmapImage: radialHeatmap,
                inputFrameSize: CGSize(width: 1024, height: 1024),
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .intensity,
                        startValue: 0.0,
                        endValue: Self.heatmapAtlasAudioMaxFrameOffset,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: audioBlurTween
                    )
                ]
            )
        ]

        let linearHeatmapAtlasAudioFilters: [Filter] = [
            HeatmapFrameOffsetAtlasFilter(
                maxFrameOffset: Int(Self.linearHeatmapAtlasAudioMaxFrameOffset.rounded()),
                heatmapImage: verticalHeatmap,
                inputFrameSize: CGSize(width: 1024, height: 1024),
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .intensity,
                        startValue: 0.0,
                        endValue: Self.linearHeatmapAtlasAudioMaxFrameOffset,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: audioBlurTween
                    )
                ]
            )
        ]

        let temporalFadeAudioFilters: [Filter] = [
            TemporalFadeAtlasFilter(
                frameCount: Int(Self.temporalFadeAudioMaxFrameCount.rounded()),
                frameSpacing: Self.temporalFadeAudioFrameSpacing,
                inputFrameSize: CGSize(width: 1024, height: 1024),
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .frameCount,
                        startValue: 1.0,
                        endValue: Self.temporalFadeAudioMaxFrameCount,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: audioBlurTween
                    )
                ]
            )
        ]

        let temporalAtlasAudioFilters: [Filter] = [
            TemporalTextureAtlas(
                frameOffset: Int(Self.temporalAtlasAudioMaxFrameOffset.rounded()),
                inputFrameSize: CGSize(width: 1024, height: 1024),
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .intensity,
                        startValue: 0.0,
                        endValue: Self.temporalAtlasAudioMaxFrameOffset,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: audioBlurTween
                    )
                ]
            )
        ]

        let handDistanceFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 24.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: handDistanceTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .contrast,
                        startValue: 0.8,
                        endValue: 1.6,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: handDistanceTween
                    )
                ]
            )
        ]

        let handHeightFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 18.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: handHeightTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .brightness,
                        startValue: -0.35,
                        endValue: 0.35,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: handHeightTween
                    )
                ]
            )
        ]

        let handVelocityFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 30.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: speedTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .saturation,
                        startValue: 0.7,
                        endValue: 1.8,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: speedTween
                    )
                ]
            )
        ]

        let fingerCountFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 22.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: fingerCountTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .contrast,
                        startValue: 0.9,
                        endValue: 1.4,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: fingerCountTween
                    ),
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .saturation,
                        startValue: 0.8,
                        endValue: 2.0,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: fingerCountTween
                    )
                ]
            )
        ]

        let handStabilityFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 20.0,
                    endValue: 0.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: stabilityTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .contrast,
                        startValue: 0.9,
                        endValue: 1.3,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: stabilityTween
                    )
                ]
            )
        ]

        let handSpreadFilters: [Filter] = [
            GaussianBlur(radius: 0.0, filterAnimators: [
                FilterAnimator(
                    type: .SingleValue,
                    animationProperty: .radius,
                    startValue: 0.0,
                    endValue: 20.0,
                    startTime: 0.0,
                    endTime: 1.0,
                    tweenFunctionProvider: spreadTween
                )
            ]),
            ColorAdjustment(
                brightness: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                filterAnimators: [
                    FilterAnimator(
                        type: .SingleValue,
                        animationProperty: .brightness,
                        startValue: -0.2,
                        endValue: 0.25,
                        startTime: 0.0,
                        endTime: 1.0,
                        tweenFunctionProvider: spreadTween
                    )
                ]
            )
        ]

        modeFilters = [
            .handPosition: handPositionFilters,
            .audio: audioFilters,
            .temporalAudio: temporalAudioFilters,
            .temporalAtlasAudio: temporalAtlasAudioFilters,
            .heatmapAtlasAudio: heatmapAtlasAudioFilters,
            .linearHeatmapAtlasAudio: linearHeatmapAtlasAudioFilters,
            .temporalFadeAudio: temporalFadeAudioFilters,
            .handDistance: handDistanceFilters,
            .handHeight: handHeightFilters,
            .handVelocity: handVelocityFilters,
            .fingerCount: fingerCountFilters,
            .handStability: handStabilityFilters,
            .handSpread: handSpreadFilters
        ]
    }

    private func updateFiltersForCurrentMode() {
        cameraScene?.group.filters = modeFilters[analysisMode] ?? []
    }

    private func updateHandMetrics(
        observations: [VNHumanHandPoseObservation],
        position: (x: Double, y: Double)?
    ) {
        if let observation = observations.first {
            detectedFingerCount = countExtendedFingers(from: observation)
            handSpread = normalizedHandSpread(from: observation)
        } else {
            detectedFingerCount = 0
            handSpread = 0.0
        }

        guard let position else {
            handSpeed = 0.0
            previousMetricsPosition = nil
            previousMetricsTimestamp = nil
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        if let previousPosition = previousMetricsPosition, let previousTimestamp = previousMetricsTimestamp {
            let deltaTime = max(now - previousTimestamp, 1.0 / 120.0)
            let dx = position.x - previousPosition.x
            let dy = position.y - previousPosition.y
            let rawSpeed = sqrt(dx * dx + dy * dy) / deltaTime
            let normalizedSpeed = clamp(rawSpeed / 2.0)
            handSpeed = (handSpeed * 0.75) + (normalizedSpeed * 0.25)
        } else {
            handSpeed = 0.0
        }

        previousMetricsPosition = position
        previousMetricsTimestamp = now
    }

    private func normalizedDistance(fromCenterFor position: (x: Double, y: Double)) -> Double {
        let dx = position.x - 0.5
        let dy = position.y - 0.5
        return clamp(sqrt(dx * dx + dy * dy) / 0.707)
    }

    private static func radialHeatmapImage(size: CGSize) -> CIImage {
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

    private static func verticalHeatmapImage(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: size.width * 0.5, y: size.height)
        gradient.point1 = CGPoint(x: size.width * 0.5, y: 0)
        gradient.color0 = CIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        gradient.color1 = CIColor.black

        let fallback = CIImage(color: CIColor.black).cropped(to: extent)
        return (gradient.outputImage ?? fallback).cropped(to: extent)
    }

    private func recognizedPoint(
        _ joint: VNHumanHandPoseObservation.JointName,
        from observation: VNHumanHandPoseObservation
    ) -> VNRecognizedPoint? {
        guard let point = try? observation.recognizedPoint(joint), point.confidence > 0.25 else {
            return nil
        }
        return point
    }

    private func normalizedHandSpread(from observation: VNHumanHandPoseObservation) -> Double {
        guard
            let indexTip = recognizedPoint(.indexTip, from: observation),
            let littleTip = recognizedPoint(.littleTip, from: observation)
        else {
            return 0.0
        }

        let dx = Double(indexTip.location.x - littleTip.location.x)
        let dy = Double(indexTip.location.y - littleTip.location.y)
        let distance = sqrt(dx * dx + dy * dy)

        return clamp(distance / 0.55)
    }

    private func countExtendedFingers(from observation: VNHumanHandPoseObservation) -> Int {
        func isFingerExtended(
            tip: VNHumanHandPoseObservation.JointName,
            pip: VNHumanHandPoseObservation.JointName
        ) -> Bool {
            guard
                let tipPoint = recognizedPoint(tip, from: observation),
                let pipPoint = recognizedPoint(pip, from: observation)
            else {
                return false
            }

            return tipPoint.location.y > pipPoint.location.y + 0.02
        }

        var count = 0

        if isFingerExtended(tip: .indexTip, pip: .indexPIP) { count += 1 }
        if isFingerExtended(tip: .middleTip, pip: .middlePIP) { count += 1 }
        if isFingerExtended(tip: .ringTip, pip: .ringPIP) { count += 1 }
        if isFingerExtended(tip: .littleTip, pip: .littlePIP) { count += 1 }

        if
            let thumbTip = recognizedPoint(.thumbTip, from: observation),
            let thumbIP = recognizedPoint(.thumbIP, from: observation),
            abs(thumbTip.location.x - thumbIP.location.x) > 0.06 || thumbTip.location.y > thumbIP.location.y + 0.03
        {
            count += 1
        }

        return count
    }

    private func clamp(_ value: Double, min minimum: Double = 0.0, max maximum: Double = 1.0) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    public func startCamera() {
        cameraManager.setup()
        cameraSource.startCamera()
        handPoseCollector.start()
    }

    public func stopCamera() {
        cameraManager.stop()
        handPoseCollector.stop()
        if isRecordingVideo {
            stopRecording()
        }
    }

    public func swapCamera() {
        let newPosition: AVCaptureDevice.Position = cameraManager.devicePosition == .back ? .front : .back
        cameraManager.swapCamera(position: newPosition)
    }

    public func loadAudio(from url: URL) {
        audioPlayer.loadAudio(from: url)
    }

    public func playAudio() {
        audioPlayer.play()
    }

    public func pauseAudio() {
        audioPlayer.pause()
    }

    public func stopAudio() {
        audioPlayer.stop()
    }

    public func requestMusicLibraryAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            Task {
                do {
                    let status = try await MPMediaLibrary.requestAuthorization()
                    DispatchQueue.main.async {
                        completion(status == .authorized)
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        } else {
            MPMediaLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        }
    }

    public func startRecording() {
        if isRecordingVideo || isSavingRecording {
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hand-pose-\(timestamp)-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        let targetSize = recordingTargetSize(for: displayCIImage?.extent.size ?? CGSize(width: 1920, height: 1080))
        let writer = MovieWriter(url: outputURL, size: targetSize, transform: .identity)
        writer.startWriter()

        recordingStateQueue.sync {
            movieWriter = writer
            recordingOutputURL = outputURL
            recordingRenderSize = targetSize
            recordingStartTime = nil
            recordedFrameCount = 0
        }

        isRecordingVideo = true
        recordingStatusMessage = "Recording…"
    }

    public func stopRecording() {
        if !isRecordingVideo {
            return
        }

        isRecordingVideo = false
        isSavingRecording = true
        recordingStatusMessage = "Saving recording…"

        var writerToFinish: MovieWriter?
        var outputURL: URL?
        var frameCount = 0

        recordingStateQueue.sync {
            writerToFinish = movieWriter
            outputURL = recordingOutputURL
            frameCount = recordedFrameCount

            movieWriter = nil
            recordingOutputURL = nil
            recordingStartTime = nil
            recordedFrameCount = 0
        }

        guard
            let writer = writerToFinish,
            let outputURL
        else {
            isSavingRecording = false
            recordingStatusMessage = "Recording failed to finalize."
            return
        }

        if frameCount == 0 {
            isSavingRecording = false
            recordingStatusMessage = "No frames captured."
            cleanupRecordingFile(at: outputURL)
            return
        }

        writer.finishWriting { [weak self] success in
            guard let self else { return }

            if !success {
                DispatchQueue.main.async {
                    self.isSavingRecording = false
                    self.recordingStatusMessage = "Failed to write video."
                    self.cleanupRecordingFile(at: outputURL)
                }
                return
            }

            let fileSize = self.recordingFileSize(at: outputURL)
            guard FileManager.default.fileExists(atPath: outputURL.path), fileSize > 0 else {
                DispatchQueue.main.async {
                    self.isSavingRecording = false
                    self.recordingStatusMessage = "Recorded file was empty."
                    self.cleanupRecordingFile(at: outputURL)
                }
                return
            }

            self.saveRecordingToPhotoLibrary(fileURL: outputURL)
        }
    }

    private func recordFrameIfNeeded(_ image: CIImage, at frameTime: CMTime) {
        var writer: MovieWriter?
        var startTime: CMTime?
        var renderSize: CGSize = .zero

        recordingStateQueue.sync {
            guard isRecordingVideo, let movieWriter else {
                return
            }

            writer = movieWriter
            renderSize = recordingRenderSize

            if recordingStartTime == nil {
                recordingStartTime = frameTime
            }

            startTime = recordingStartTime
            recordedFrameCount += 1
        }

        guard
            let writer,
            let startTime
        else {
            return
        }

        let presentationTime = CMTimeSubtract(frameTime, startTime)
        let outputImage = preparedRecordingImage(image, targetSize: renderSize)

        guard let pixelBuffer = writer.getPixelBuffer() else {
            return
        }

        MetalEnvironment.shared.context.render(
            outputImage,
            to: pixelBuffer,
            bounds: CGRect(origin: .zero, size: renderSize),
            colorSpace: recordingColorSpace
        )
        writer.appendFrame(pixelBuffer: pixelBuffer, time: presentationTime)
    }

    private func preparedRecordingImage(_ image: CIImage, targetSize: CGSize) -> CIImage {
        guard image.extent.origin != .zero else {
            return image
        }

        let translated = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y)
        )

        if translated.extent.size == targetSize {
            return translated
        }

        return translated.cropped(to: CGRect(origin: .zero, size: targetSize))
    }

    private func recordingTargetSize(for size: CGSize) -> CGSize {
        let fallback = CGSize(width: 1920, height: 1080)
        let sourceSize = size.width > 0 && size.height > 0 ? size : fallback

        let width = max(2, Int(sourceSize.width.rounded()))
        let height = max(2, Int(sourceSize.height.rounded()))

        let evenWidth = width.isMultiple(of: 2) ? width : width - 1
        let evenHeight = height.isMultiple(of: 2) ? height : height - 1

        return CGSize(width: evenWidth, height: evenHeight)
    }

    private func saveRecordingToPhotoLibrary(fileURL: URL) {
        requestPhotoLibraryAddAccess { [weak self] granted in
            guard let self else { return }

            guard granted else {
                DispatchQueue.main.async {
                    self.isSavingRecording = false
                    self.recordingStatusMessage = "Photos access is required to save video."
                }
                self.cleanupRecordingFile(at: fileURL)
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: fileURL, options: options)
            }) { success, error in
                DispatchQueue.main.async {
                    self.isSavingRecording = false
                    if success {
                        self.recordingStatusMessage = "Saved to Photos."
                    } else {
                        self.recordingStatusMessage = error?.localizedDescription ?? "Failed to save video."
                    }
                }
                self.cleanupRecordingFile(at: fileURL)
            }
        }
    }

    private func requestPhotoLibraryAddAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14.0, *) {
            let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if currentStatus == .authorized || currentStatus == .limited {
                DispatchQueue.main.async {
                    completion(true)
                }
                return
            }
            if currentStatus == .denied || currentStatus == .restricted {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    completion(status == .authorized || status == .limited)
                }
            }
        } else {
            let currentStatus = PHPhotoLibrary.authorizationStatus()
            if currentStatus == .authorized {
                DispatchQueue.main.async {
                    completion(true)
                }
                return
            }
            if currentStatus == .denied || currentStatus == .restricted {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        }
    }

    private func recordingFileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func cleanupRecordingFile(at url: URL) {
        recordingStateQueue.async {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Animation State

    private func updateAnimationState(from observations: [VNHumanHandPoseObservation]) {
        guard let position = handPoseCollector.getNormalizedHandPosition() else {
            animationState = .noHand
            return
        }

        let newState = HandAnimationState(fromHandPosition: position)
        if newState != animationState {
            animationState = newState
        }
    }
}

// MARK: - Animation State Enum

public enum HandAnimationState: Equatable {
    case idle
    case noHand
    case handDetected(x: Double, y: Double)

    init(fromHandPosition position: (x: Double, y: Double)) {
        self = .handDetected(x: position.x, y: position.y)
    }

    var isHandPresent: Bool {
        if case .handDetected = self {
            return true
        }
        return false
    }

    public static func == (lhs: HandAnimationState, rhs: HandAnimationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.noHand, .noHand):
            return true
        case let (.handDetected(x1, y1), .handDetected(x2, y2)):
            return x1 == x2 && y1 == y2
        default:
            return false
        }
    }
}

extension CameraViewModel: CameraSourceDelegate {
    public func didReceiveFrame(frame: any Frame) {
        // Also pass to hand pose collector for detection
        handPoseCollector.didOutputFrame(frame: frame)

        // Render the scene and apply filters
        guard let scene = cameraScene else { return }
        
        let cmTime = frame.time
        if let renderedImage = scene.group.renderGroup(frameTime: cmTime.seconds, compositionTimeOffset: 0, inputImage: nil) {
            let finalImage = drawHandBoundingBoxes(on: renderedImage, observations: detectedHands)
            recordFrameIfNeeded(finalImage, at: cmTime)
            
            DispatchQueue.main.async {
                self.displayCIImage = finalImage
            }
        }
    }
}

// MARK: - Tween Functions

/// Tween function that reads hand position and maps to animation parameter
public class HandPositionTweenFunction: TweenFunctionProvider {
    private let collector: HandPoseDataCollector
    private let duration: Double
    private let coordinate: Coordinate

    public enum Coordinate {
        case x
        case y
        case distance
    }

    public init(
        collector: HandPoseDataCollector,
        duration: Double,
        coordinate: Coordinate
    ) {
        self.collector = collector
        self.duration = duration
        self.coordinate = coordinate
    }

    public func tweenValue(input: Double) -> Double {
        guard let position = collector.getNormalizedHandPosition() else {
            switch coordinate {
            case .x:
                return 0.0

            case .y:
                return 0.5

            case .distance:
                return 0.5
            }
        }

        let value: Double

        switch coordinate {
        case .x:
            value = position.x

        case .y:
            value = position.y

        case .distance:
            // Distance from center (0.5, 0.5)
            let dx = position.x - 0.5
            let dy = position.y - 0.5
            let distance = sqrt(dx * dx + dy * dy)
            // Max distance is sqrt(0.5^2 + 0.5^2) ≈ 0.707
            value = distance / 0.707
        }

        return value
    }
}

// MARK: - Audio Amplitude Tween Function

public class AudioAmplitudeTweenFunction: TweenFunctionProvider {
    private let audioPlayer: AudioPlayer

    public init(audioPlayer: AudioPlayer) {
        self.audioPlayer = audioPlayer
    }

    public func tweenValue(input: Double) -> Double {
        // Get current audio amplitude (0.0 to 1.0)
        return Double(audioPlayer.currentAmplitude)
    }
}

public class LiveMetricTweenFunction: TweenFunctionProvider {
    private let valueProvider: () -> Double

    public init(valueProvider: @escaping () -> Double) {
        self.valueProvider = valueProvider
    }

    public func tweenValue(input: Double) -> Double {
        let value = valueProvider()
        return Swift.max(0.0, Swift.min(1.0, value))
    }
}
