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
import MediaPlayer

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

    public let cameraManager: CameraManager
    public let handPoseCollector: HandPoseDataCollector
    public let cameraSource: CameraSource
    @Published public var audioPlayer: AudioPlayer

    private var cameraScene: VideoScene?
    private var modeFilters: [AnalysisMode: [Filter]] = [:]
    private var previousMetricsPosition: (x: Double, y: Double)?
    private var previousMetricsTimestamp: TimeInterval?
    private static let temporalAudioMaxFrameOffset: Double = 48.0

    public enum AnalysisMode: String, CaseIterable, Identifiable {
        case handPosition
        case audio
        case temporalAudio
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
            self == .audio || self == .temporalAudio
        }
    }

    public var isAudioMode: Bool {
        analysisMode.usesAudioInput
    }

    public var currentModeMetrics: [(label: String, value: String)] {
        if analysisMode.usesAudioInput {
            let amplitude = Double(audioPlayer.currentAmplitude)
            if analysisMode == .audio {
                return [("Amplitude", String(format: "%.2f", amplitude))]
            }

            let maxOffset = Int((amplitude * Self.temporalAudioMaxFrameOffset).rounded())
            return [
                ("Amplitude", String(format: "%.2f", amplitude)),
                ("Max Frame Offset", "\(maxOffset)"),
                ("Noise Scale", "2.0"),
                ("Flow Speed", "0.0"),
                ("Input Frame", "1024")
            ]
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
        case .audio:
            return [("Amplitude", String(format: "%.2f", audioPlayer.currentAmplitude))]
        case .temporalAudio:
            let amplitude = Double(audioPlayer.currentAmplitude)
            let maxOffset = Int((amplitude * Self.temporalAudioMaxFrameOffset).rounded())
            return [
                ("Amplitude", String(format: "%.2f", amplitude)),
                ("Max Frame Offset", "\(maxOffset)"),
                ("Noise Scale", "2.0"),
                ("Flow Speed", "0.0"),
                ("Input Frame", "1024")
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
