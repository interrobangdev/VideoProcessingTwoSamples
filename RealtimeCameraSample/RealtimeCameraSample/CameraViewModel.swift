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
    @Published var currentFrame: CIImage?
    @Published var selectedFilter: FilterType = .none
    @Published var filterIntensity: Double = 0.5

    private let cameraManager = CameraManager()
    private let context = CIContext()

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
        super.init()
        setupCamera()
        setupOrientationObserver()
    }

    private func setupCamera() {
        cameraManager.delegate = self
        cameraManager.setup()

        // Request camera permission
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.cameraManager.start()
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

    private func rotationAngleForOrientation() -> CGFloat {
        // Camera buffer comes in landscape left by default
        // We need to rotate to match the device orientation
        switch currentOrientation {
        case .portrait:
            return -.pi / 2 // -90 degrees (rotate counter-clockwise)
        case .landscapeLeft:
            return 0 // No rotation
        case .landscapeRight:
            return .pi // 180 degrees (flip)
        default:
            return -.pi / 2 // Default to portrait
        }
    }

    private func applyFilter(to image: CIImage) -> CIImage {
        switch selectedFilter {
        case .none:
            return image

        case .blur:
            let filter = GaussianBlur(radius: 10.0, filterAnimators: [])
            filter.radius = filterIntensity * 20.0 // 0-20 radius
            return filter.filterContent(image: image, sourceTime: nil, sceneTime: nil, compositionTime: nil) ?? image

        case .crystallize:
            let filter = Crystallize()
            filter.radius = filterIntensity * 30.0 + 5.0 // 5-35 radius
            return filter.filterContent(image: image, sourceTime: nil, sceneTime: nil, compositionTime: nil) ?? image

        case .colorAdjustment:
            let filter = ColorAdjustment()
            filter.saturation = filterIntensity * 2.0 // 0-2 saturation
            filter.brightness = (filterIntensity - 0.5) * 0.4 // -0.2 to 0.2
            filter.contrast = 1.0 + (filterIntensity - 0.5) * 0.4 // 0.8 to 1.2
            return filter.filterContent(image: image, sourceTime: nil, sceneTime: nil, compositionTime: nil) ?? image

        case .glitch:
            let filter = GlitchEffect()
            filter.intensity = filterIntensity
            return filter.filterContent(image: image, sourceTime: nil, sceneTime: nil, compositionTime: nil) ?? image
        }
    }
}

// MARK: - CameraManagerDelegate
extension CameraViewModel: CameraManagerDelegate {
    func didOutputFrame(frame: Frame) {
        guard let ciImage = frame.ciImageRepresentation() else { return }

        // Apply rotation based on device orientation
        let angle = rotationAngleForOrientation()
        let rotatedImage = ciImage.transformed(by: CGAffineTransform(rotationAngle: angle))

        // Apply selected filter
        let filteredImage = applyFilter(to: rotatedImage)

        DispatchQueue.main.async {
            self.currentFrame = filteredImage
        }
    }

    func didOutputPhotoFrame(photo: CIImage) {
        // Handle photo capture if needed
    }
}
