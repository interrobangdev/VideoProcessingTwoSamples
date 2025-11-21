//
//  CameraViewModel.swift
//  RealtimeCameraSample
//
//  ViewModel for managing camera and filter processing
//

import SwiftUI
import AVFoundation
import CoreImage
import Combine
import VideoProcessingTwo

class CameraViewModel: NSObject, ObservableObject {
    @Published var displayCIImage: CIImage?
    @Published var selectedFilter: FilterType = .none {
        didSet {
            updateFilters()
        }
    }
    @Published var filterIntensity: Double = 0.5 {
        didSet {
            updateFilters()
        }
    }

    private let cameraManager = CameraManager()
    private let cameraSource: CameraSource
    private var cameraScene: VideoScene?

    private var blurFilter: GaussianBlur?
    private var crystallizeFilter: Crystallize?
    private var colorAdjustmentFilter: ColorAdjustment?
    private var glitchFilter: GlitchEffect?

    // Track device orientation
    private var currentOrientation: UIDeviceOrientation = .portrait

    // Available filter types
    enum FilterType: String, CaseIterable, Identifiable {
        case none = "None"
        case blur = "Gaussian Blur"
        case crystallize = "Crystallize"
        case colorAdjustment = "Color Adjustment"
        case glitch = "Glitch Effect"

        var id: String { rawValue }
    }

    override init() {
        cameraSource = CameraSource(cameraManager: cameraManager)
        super.init()
        cameraSource.delegate = self
        setupScene()
        setupCamera()
        setupOrientationObserver()
    }

    private func setupScene() {
        // Create a surface with the camera source
        let surface = Surface(source: cameraSource, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), rotation: 0)
        let layer = Layer(surfaces: [surface])

        // Create the main group
        let mainGroup = LayerGroup(groups: [], layers: [layer], filters: [], mask: nil)

        // Create the scene
        let scene = VideoScene(duration: .infinity, frameRate: 30.0)
        scene.group = mainGroup
        cameraScene = scene
    }

    private func setupCamera() {
        cameraManager.setup()

        // Request camera permission
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.cameraSource.startCamera()
                }
            } else {
                print("Camera permission denied")
            }
        }
    }

    private func setupOrientationObserver() {
        // Enable device orientation notifications
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        // Get initial orientation
        currentOrientation = UIDevice.current.orientation

        // If current orientation is unknown or invalid, default to portrait
        if !currentOrientation.isValidInterfaceOrientation {
            currentOrientation = .portrait
        }

        // Observe orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    @objc private func orientationDidChange() {
        let newOrientation = UIDevice.current.orientation
        // Update for valid orientations (excluding portrait upside down)
        switch newOrientation {
        case .portrait, .landscapeLeft, .landscapeRight:
            currentOrientation = newOrientation
        default:
            break // Keep previous orientation for face up/down/unknown/upside down
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func stopCamera() {
        cameraManager.stop()
    }

    private func updateFilters() {
        var filters: [Filter] = []

        switch selectedFilter {
        case .none:
            break

        case .blur:
            let filter = GaussianBlur(radius: filterIntensity * 20.0, filterAnimators: [])
            filters.append(filter)

        case .crystallize:
            let filter = Crystallize()
            filter.radius = filterIntensity * 30.0 + 5.0 // 5-35 radius
            filters.append(filter)

        case .colorAdjustment:
            let filter = ColorAdjustment()
            filter.saturation = filterIntensity * 2.0 // 0-2 saturation
            filter.brightness = (filterIntensity - 0.5) * 0.4 // -0.2 to 0.2
            filter.contrast = 1.0 + (filterIntensity - 0.5) * 0.4 // 0.8 to 1.2
            filters.append(filter)

        case .glitch:
            let filter = GlitchEffect()
            filter.intensity = filterIntensity
            filters.append(filter)
        }

        cameraScene?.group.filters = filters
    }
}

// MARK: - CameraSourceDelegate
extension CameraViewModel: CameraSourceDelegate {
    func didReceiveFrame(frame: any Frame) {
        guard let scene = cameraScene else { return }

        let cmTime = frame.time
        if let renderedImage = scene.group.renderGroup(frameTime: cmTime.seconds, compositionTimeOffset: 0, inputImage: nil) {
            DispatchQueue.main.async {
                self.displayCIImage = renderedImage
            }
        }
    }
}
