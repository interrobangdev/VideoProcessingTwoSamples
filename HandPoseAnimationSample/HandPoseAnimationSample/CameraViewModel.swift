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
    @Published public var blurSource: BlurSource = .hand {
        didSet {
            updateBlurFilter()
        }
    }
    @Published public var displayCIImage: CIImage?

    public let cameraManager: CameraManager
    public let handPoseCollector: HandPoseDataCollector
    public let cameraSource: CameraSource
    @Published public var audioPlayer: AudioPlayer

    private var cameraScene: VideoScene?
    private var blurFilterFramework: GaussianBlur?
    private var brightnessFilterFramework: ColorAdjustment?
    private var audioBlurFilterFramework: GaussianBlur?
    private var handBlurFilterFramework: GaussianBlur?

    public enum BlurSource {
        case hand
        case audio
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
                self?.handPosition = self?.handPoseCollector.getNormalizedHandPosition()
                
                
            }
        }

        // Subscribe to frame updates from camera source for rendering
//        cameraSource.cameraManager.delegate = self
    }

    private func setupScene() {
        // Create the filter group with blur and brightness filters
        var filters: [Filter] = []
        if let blur = blurFilterFramework {
            filters.append(blur)
        }
        if let brightness = brightnessFilterFramework {
            filters.append(brightness)
        }
//        filterGroup = LayerGroup(groups: [], layers: [], filters: filters, mask: nil)

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
        // Create hand position blur animator
        let handBlurTween = HandPositionTweenFunction(
            collector: handPoseCollector,
            duration: 1.0,
            coordinate: .x
        )
        let handBlurAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .radius,
            startValue: 0.0,
            endValue: 20.0,
            startTime: 0.0,
            endTime: 1.0,
            tweenFunctionProvider: handBlurTween
        )

        // Create audio amplitude blur animator
        let audioBlurTween = AudioAmplitudeTweenFunction(audioPlayer: audioPlayer)
        let audioBlurAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .radius,
            startValue: 0.0,
            endValue: 20.0,
            startTime: 0.0,
            endTime: 1.0,
            tweenFunctionProvider: audioBlurTween
        )

        // Create brightness animator driven by hand Y position
        let brightnessTween = HandPositionTweenFunction(
            collector: handPoseCollector,
            duration: 1.0,
            coordinate: .y
        )
        let brightnessAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .brightness,
            startValue: -0.5,
            endValue: 0.5,
            startTime: 0.0,
            endTime: 1.0,
            tweenFunctionProvider: brightnessTween
        )

        // Create both blur filters
        handBlurFilterFramework = GaussianBlur(radius: 0.0, filterAnimators: [handBlurAnimator])
        audioBlurFilterFramework = GaussianBlur(radius: 0.0, filterAnimators: [audioBlurAnimator])

        // Start with hand blur
        blurFilterFramework = handBlurFilterFramework

        // Create brightness filter
        brightnessFilterFramework = ColorAdjustment(
            brightness: 0.0,
            contrast: 1.0,
            saturation: 1.0,
            filterAnimators: [brightnessAnimator]
        )
    }

    private func updateBlurFilter() {
        // Swap the blur filter based on the selected source
        blurFilterFramework = blurSource == .audio ? audioBlurFilterFramework : handBlurFilterFramework

        // Update the filter group
        var filters: [Filter] = []
        if let blur = blurFilterFramework {
            filters.append(blur)
        }
        if blurSource != .audio,
           let brightness = brightnessFilterFramework {
            filters.append(brightness)
        }
        
        cameraScene?.group.filters = filters
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
