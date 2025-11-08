//
//  AnimationViewModel.swift
//  AnimatedFiltersSample
//
//  ViewModel for playing video with animated filter effects
//

import SwiftUI
import VideoProcessingTwo
import AVFoundation
import Combine

class AnimationViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var errorMessage: String?
    @Published var selectedAnimation: AnimationType = .fadeInOut {
        didSet {
            if selectedAnimation != oldValue {
                updatePlayer()
            }
        }
    }
    @Published var customBezierPoints: [CGPoint] = []

    enum AnimationType: String, CaseIterable {
        case fadeInOut = "Fade In/Out"
        case blurAnimation = "Animated Blur"
        case colorPulse = "Color Pulse"
        case zoomInOut = "Zoom In/Out"
        case combined = "Combined Effects"
        case bezierEase = "Bezier Ease"
        case bounce = "Multi Bounce"
        case wave = "Wave Effect"
        case threeStep = "Three Step"
        case customBezier = "Custom Bezier Curve"
    }

    private var videoURL: URL?
    private var videoSource: VideoSource?

    init() {
        loadBundledVideo()
    }

    func loadComposition() {
        setupPlayer()
    }

    private func loadBundledVideo() {
        if let videoURL = Bundle.main.url(forResource: "download", withExtension: "mov") {
            self.videoURL = videoURL
            self.videoSource = VideoSource(url: videoURL)
        }
    }

    private func setupPlayer() {
        guard let videoURL = videoURL, let videoSource = videoSource else {
            errorMessage = "No video loaded"
            return
        }

        let videoDuration = videoSource.duration
        let videoSize = videoSource.naturalSize
        
        // Create scene with animated filters
        let scene = createAnimatedScene(
            duration: videoDuration,
            videoSize: videoSize,
            videoURL: videoURL,
            animationType: selectedAnimation
        )

        // Create composition with scene
        guard let result = SceneVideoComposition.createComposition(videoURL: videoURL, scene: scene) else {
            errorMessage = "Failed to create composition"
            return
        }

//        let asset = AVURLAsset(url: videoURL)
//        let playerItem = AVPlayerItem(asset: asset)
        
        
        let playerItem = AVPlayerItem(asset: result.composition)
        playerItem.videoComposition = result.videoComposition
        playerItem.audioMix = result.audioMix
        
        player = AVPlayer(playerItem: playerItem)
        player?.play()
    }

    public func updatePlayer() {
        guard let videoURL = videoURL, let videoSource = videoSource else {
            return
        }

        let videoDuration = videoSource.duration
        let videoSize = videoSource.naturalSize

        // Create new scene with different animation
        let scene = createAnimatedScene(
            duration: videoDuration,
            videoSize: videoSize,
            videoURL: videoURL,
            animationType: selectedAnimation
        )

        // Create new composition with updated scene
        guard let result = SceneVideoComposition.createComposition(videoURL: videoURL, scene: scene) else {
            return
        }

        let playerItem = AVPlayerItem(asset: result.composition)
        playerItem.videoComposition = result.videoComposition
        playerItem.audioMix = result.audioMix

        player?.replaceCurrentItem(with: playerItem)
        player?.play()
    }

    private func createAnimatedScene(duration: Double, videoSize: CGSize, videoURL: URL, animationType: AnimationType) -> VideoScene {
        let scene = VideoScene(duration: duration, frameRate: 30.0, size: videoSize)

        // Add base video layer
        let videoLayerIndex = LayerObjectIndex(groupIndices: [], layerIndex: 0)
        let videoFrame = CGRect(origin: .zero, size: videoSize)
        _ = scene.addAsset(
            atLayerIndex: videoLayerIndex,
            type: .video,
            frame: videoFrame,
            rotation: 0.0,
            assetURL: videoURL,
            text: ""
        )

        // Apply animated filters based on selection
        switch animationType {
        case .fadeInOut:
            addFadeInOutAnimation(to: scene, duration: duration)

        case .blurAnimation:
            addBlurAnimation(to: scene, duration: duration)

        case .colorPulse:
            addColorPulseAnimation(to: scene, duration: duration)

        case .zoomInOut:
            addZoomAnimation(to: scene, duration: duration)

        case .combined:
            addCombinedAnimations(to: scene, duration: duration)

        case .bezierEase:
            addBezierEaseAnimation(to: scene, duration: duration)

        case .bounce:
            addBounceAnimation(to: scene, duration: duration)

        case .wave:
            addWaveAnimation(to: scene, duration: duration)

        case .threeStep:
            addThreeStepAnimation(to: scene, duration: duration)

        case .customBezier:
            addCustomBezierAnimation(to: scene, duration: duration)
        }

        return scene
    }

    // MARK: - Animation Configurations

    private func addFadeInOutAnimation(to scene: VideoScene, duration: Double) {
        // Fade in for first 2 seconds, fade out for last 2 seconds
        let fadeInAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 0.0,
            endValue: 1.0,
            startTime: 0.0,
            endTime: 2.0,
            tweenFunctionProvider: LinearFunction()
        )

        let fadeOutAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 1.0,
            endValue: 0.0,
            startTime: max(0, duration - 2.0),
            endTime: duration,
            tweenFunctionProvider: LinearFunction()
        )

        let fadeFilter = Fade(fade: 1.0, filterAnimators: [fadeInAnimator, fadeOutAnimator])
        scene.group.filters.append(fadeFilter)
    }

    private func addBlurAnimation(to scene: VideoScene, duration: Double) {
        // Blur increases then decreases
        let midPoint = duration / 2.0

        let blurUpAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .radius,
            startValue: 0.0,
            endValue: 30.0,
            startTime: 0.0,
            endTime: midPoint,
            tweenFunctionProvider: LinearFunction()
        )

        let blurDownAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .radius,
            startValue: 30.0,
            endValue: 0.0,
            startTime: midPoint,
            endTime: duration,
            tweenFunctionProvider: LinearFunction()
        )

        let blurFilter = GaussianBlur(radius: 0.0, filterAnimators: [blurUpAnimator, blurDownAnimator])
        scene.group.filters.append(blurFilter)
    }

    private func addColorPulseAnimation(to scene: VideoScene, duration: Double) {
        // Saturation pulses up and down
        let pulseDuration = 3.0 // 3-second cycles
        var animators: [FilterAnimator] = []

        var currentTime = 0.0
        while currentTime < duration {
            let pulseEnd = min(currentTime + pulseDuration / 2, duration)

            // Increase saturation
            let upAnimator = FilterAnimator(
                type: .SingleValue,
                animationProperty: .saturation,
                startValue: 1.0,
                endValue: 2.0,
                startTime: currentTime,
                endTime: pulseEnd,
                tweenFunctionProvider: LinearFunction()
            )
            animators.append(upAnimator)

            currentTime = pulseEnd
            let nextPulseEnd = min(currentTime + pulseDuration / 2, duration)

            // Decrease saturation
            let downAnimator = FilterAnimator(
                type: .SingleValue,
                animationProperty: .saturation,
                startValue: 2.0,
                endValue: 1.0,
                startTime: currentTime,
                endTime: nextPulseEnd,
                tweenFunctionProvider: LinearFunction()
            )
            animators.append(downAnimator)

            currentTime = nextPulseEnd
        }

        let colorFilter = ColorAdjustment(
            brightness: 0.0,
            contrast: 1.0,
            saturation: 1.0,
            filterAnimators: animators
        )
        scene.group.filters.append(colorFilter)
    }

    private func addZoomAnimation(to scene: VideoScene, duration: Double) {
        // Scale up from 1.0 to 1.5 and back down
        let midPoint = duration / 2.0

        let zoomInAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .scale,
            startValue: 1.0,
            endValue: 1.5,
            startTime: 0.0,
            endTime: midPoint,
            tweenFunctionProvider: LinearFunction()
        )

        let zoomOutAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .scale,
            startValue: 1.5,
            endValue: 1.0,
            startTime: midPoint,
            endTime: duration,
            tweenFunctionProvider: LinearFunction()
        )

        let scaleFilter = Scale(scale: 1.0, centerPoint: .zero, filterAnimators: [zoomInAnimator, zoomOutAnimator])
        scene.group.filters.append(scaleFilter)
    }

    private func addCombinedAnimations(to scene: VideoScene, duration: Double) {
        // Combine multiple effects
        addFadeInOutAnimation(to: scene, duration: duration)
        addZoomAnimation(to: scene, duration: duration)

        // Add brightness pulse
        let brightnessAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .brightness,
            startValue: 0.0,
            endValue: 0.2,
            startTime: 0.0,
            endTime: duration / 2,
            tweenFunctionProvider: LinearFunction()
        )

        let brightnessDownAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .brightness,
            startValue: 0.2,
            endValue: 0.0,
            startTime: duration / 2,
            endTime: duration,
            tweenFunctionProvider: LinearFunction()
        )

        let colorFilter = ColorAdjustment(
            brightness: 0.0,
            contrast: 1.0,
            saturation: 1.0,
            filterAnimators: [brightnessAnimator, brightnessDownAnimator]
        )
        scene.group.filters.append(colorFilter)
    }

    // MARK: - Bezier Curve Animations

    private func addBezierEaseAnimation(to scene: VideoScene, duration: Double) {
        // Smooth ease in/out using bezier path
        let easeInOutCurve = BezierPathTweenFunction.easeInOut

        let fadeAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 0.0,
            endValue: 1.0,
            startTime: 0.0,
            endTime: duration,
            tweenFunctionProvider: easeInOutCurve
        )

        let fadeFilter = Fade(fade: 1.0, filterAnimators: [fadeAnimator])
        scene.group.filters.append(fadeFilter)
    }

    private func addBounceAnimation(to scene: VideoScene, duration: Double) {
        // Multi-bounce effect using custom bezier path
        let bounceCurve = BezierPathTweenFunction.multiBounce

        let scaleAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .scale,
            startValue: 0.5,
            endValue: 1.0,
            startTime: 0.0,
            endTime: duration,
            tweenFunctionProvider: bounceCurve
        )

        let scaleFilter = Scale(scale: 1.0, centerPoint: .zero, filterAnimators: [scaleAnimator])
        scene.group.filters.append(scaleFilter)
    }

    private func addWaveAnimation(to scene: VideoScene, duration: Double) {
        // Wave pattern using multi-point bezier curve
        let waveCurve = BezierPathTweenFunction.wave

        let brightnessAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .brightness,
            startValue: -0.2,
            endValue: 0.2,
            startTime: 0.0,
            endTime: duration,
            tweenFunctionProvider: waveCurve
        )

        let colorFilter = ColorAdjustment(
            brightness: 0.0,
            contrast: 1.0,
            saturation: 1.0,
            filterAnimators: [brightnessAnimator]
        )
        scene.group.filters.append(colorFilter)
    }

    private func addThreeStepAnimation(to scene: VideoScene, duration: Double) {
        // Three distinct steps using bezier path
        let stepCurve = BezierPathTweenFunction.threeStep

        let fadeAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 0.0,
            endValue: 1.0,
            startTime: 0.0,
            endTime: duration,
            tweenFunctionProvider: stepCurve
        )

        let fadeFilter = Fade(fade: 1.0, filterAnimators: [fadeAnimator])
        scene.group.filters.append(fadeFilter)
    }

    private func addCustomBezierAnimation(to scene: VideoScene, duration: Double) {
        // Use user-defined bezier curve from the editor
        guard !customBezierPoints.isEmpty else {
            // If no custom curve, use a default
            addBezierEaseAnimation(to: scene, duration: duration)
            return
        }

        // Convert CGPoint array to BezierPoint array
        let bezierPoints = customBezierPoints.map { point in
            BezierPoint(x: point.x, y: point.y)
        }

        // Create bezier curve from control points
        let customCurve = BezierPathTweenFunction(points: bezierPoints)

        let fadeAnimator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 0.0,
            endValue: 1.0,
            startTime: 0.0,
            endTime: duration,
            tweenFunctionProvider: customCurve
        )

        let fadeFilter = Fade(fade: 1.0, filterAnimators: [fadeAnimator])
        scene.group.filters.append(fadeFilter)
    }
}
