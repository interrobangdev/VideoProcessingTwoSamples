//
//  OverlayViewModel.swift
//  VideoOverlaySample
//
//  ViewModel for compositing and exporting video with overlays
//

import SwiftUI
//import AVFoundation
import Combine
import VideoProcessingTwo

class OverlayViewModel: ObservableObject {
    @Published var exportProgress: Double = 0.0
    @Published var isExporting = false
    @Published var exportedVideoURL: URL?
    @Published var errorMessage: String?

    @Published var videoLoaded = false
    @Published var photoLoaded = false
    @Published var gifLoaded = false

    // Overlay controls with default positions
    @Published var photoOpacity: Double = 0.8
    @Published var photoPosition: CGPoint = CGPoint(x: 0.85, y: 0.15) // Top-right corner
    @Published var photoScale: Double = 0.25

    @Published var gifOpacity: Double = 0.9
    @Published var gifPosition: CGPoint = CGPoint(x: 0.15, y: 0.85) // Bottom-left corner
    @Published var gifScale: Double = 0.2

    private var videoURL: URL?
    private var videoSource: VideoSource?
    private var photoImageSource: ImageSource?
    private var gifImageSource: GIFImageSource?

    private let context = CIContext()

    init() {
        // Load bundled resources
        loadBundledResources()
    }

    private func loadBundledResources() {
        // Load video
        if let videoURL = Bundle.main.url(forResource: "mountain", withExtension: "mp4") {
            self.videoURL = videoURL
            self.videoSource = VideoSource(url: videoURL)
            self.videoLoaded = true
        }

        // Load photo
        if let photoURL = Bundle.main.url(forResource: "art", withExtension: "jpg"),
           let image = UIImage(contentsOfFile: photoURL.path),
           let cgImage = image.cgImage {
            photoImageSource = ImageSource(image: cgImage)
            photoLoaded = true
        }

        // Load GIF
        if let gifURL = Bundle.main.url(forResource: "horse", withExtension: "gif") {
            do {
                let gifData = try Data(contentsOf: gifURL)
                if let gifImage = GIFImage(gifData: gifData) {
                    gifImageSource = GIFImageSource(image: gifImage)
                    gifLoaded = true
                }
            } catch {
                errorMessage = "Failed to load bundled GIF: \(error.localizedDescription)"
            }
        }
    }

    func loadVideo(url: URL) {
        self.videoURL = url
        self.videoSource = VideoSource(url: url)
        self.exportedVideoURL = nil
        self.videoLoaded = true
    }

    func loadPhoto(url: URL) {
        if let image = UIImage(contentsOfFile: url.path),
           let cgImage = image.cgImage {
            photoImageSource = ImageSource(image: cgImage)
            photoLoaded = true
        }
    }

    func loadGIF(url: URL) {
        do {
            let gifData = try Data(contentsOf: url)
            if let gifImage = GIFImage(gifData: gifData) {
                gifImageSource = GIFImageSource(image: gifImage)
                gifLoaded = true
            }
        } catch {
            errorMessage = "Failed to load GIF: \(error.localizedDescription)"
        }
    }

    func exportVideo() {
        guard let videoSource = videoSource else {
            errorMessage = "No video loaded"
            return
        }

        isExporting = true
        exportProgress = 0.0
        errorMessage = nil

        // Get video properties
        let videoDuration = videoSource.duration
        let videoSize = videoSource.naturalSize

        // Create scene
        let scene = VideoScene(duration: videoDuration, frameRate: 30.0, size: videoSize)

        // Add video as base layer (layer 0)
        let videoLayerIndex = LayerObjectIndex(groupIndices: [], layerIndex: 0)
        let videoFrame = CGRect(origin: .zero, size: videoSize)
        _ = scene.addAsset(
            atLayerIndex: videoLayerIndex,
            type: .video,
            frame: videoFrame,
            rotation: 0.0,
            assetURL: videoURL!,
            text: ""
        )

        // Add photo overlay if loaded (group 0, layer 0)
        if let photoSource = photoImageSource {
            // Calculate photo frame based on position and scale
            let photoWidth = videoSize.width * photoScale
            let photoHeight = videoSize.width * photoScale // Keep square aspect
            let photoX = (videoSize.width * photoPosition.x) - (photoWidth / 2)
            let photoY = (videoSize.height * photoPosition.y) - (photoHeight / 2)
            let photoFrame = CGRect(x: photoX, y: photoY, width: photoWidth, height: photoHeight)

            // Create surface and layer
            let surface = Surface(source: photoSource, frame: photoFrame, rotation: 0.0)
            let layer = Layer(surfaces: [surface])

            // Create fade filter for opacity
            let fadeFilter = Fade(fade: photoOpacity, filterAnimators: [])

            // Create group with layer and filter
            let photoGroup = LayerGroup(groups: [], layers: [layer], filters: [fadeFilter], mask: nil)
            scene.group.groups.append(photoGroup)
        }

        // Add GIF overlay if loaded (group 1, layer 0)
        if let gifSource = gifImageSource {
            // Calculate GIF frame based on position and scale
            let gifWidth = videoSize.width * gifScale
            let gifHeight = videoSize.width * gifScale // Keep square aspect
            let gifX = (videoSize.width * gifPosition.x) - (gifWidth / 2)
            let gifY = (videoSize.height * gifPosition.y) - (gifHeight / 2)
            let gifFrame = CGRect(x: gifX, y: gifY, width: gifWidth, height: gifHeight)

            // Create surface and layer
            let surface = Surface(source: gifSource, frame: gifFrame, rotation: 0.0)
            let layer = Layer(surfaces: [surface])

            // Create fade filter for opacity
            let fadeFilter = Fade(fade: gifOpacity, filterAnimators: [])

            // Create group with layer and filter
            let gifGroup = LayerGroup(groups: [], layers: [layer], filters: [fadeFilter], mask: nil)
            scene.group.groups.append(gifGroup)
        }

        // Setup output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Export using ExportManager
        ExportManager.shared.exportScene(
            scene: scene,
            outpuURL: outputURL,
            progress: { [weak self] sceneId, progress in
                print("Export progress: \(progress) for scene: \(sceneId)")
                DispatchQueue.main.async {
                    print("Setting exportProgress to: \(progress)")
                    self?.exportProgress = progress
                }
            },
            completion: { [weak self] success in
                print("Export completion: \(success)")
                DispatchQueue.main.async {
                    if success {
                        self?.exportedVideoURL = outputURL
                        self?.exportProgress = 1.0
                    } else {
                        self?.errorMessage = "Export failed"
                    }
                    self?.isExporting = false
                }
            }
        )
    }

}
