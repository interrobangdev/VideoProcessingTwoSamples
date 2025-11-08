//
//  MultiLayerViewModel.swift
//  MultiLayerCompositionSample
//

import SwiftUI
import Foundation
import AVKit
import VideoProcessingTwo
internal import Combine

class MultiLayerViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func buildComposition() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let scene = try self.buildScene()
                try self.createAVComposition(from: scene)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to build composition: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func buildScene() throws -> VideoScene {
        let scene = VideoScene(duration: 10.0, frameRate: 30.0, size: CGSize(width: 1280, height: 720))

        
        // Video 1 - left third
        if let videoURL = Bundle.main.url(forResource: "desk", withExtension: "mov") {
            let videoSource = VideoSource(url: videoURL)
            let surface1 = Surface(
                source: videoSource,
                frame: CGRect(x: 0, y: 0, width: 426, height: 720),
                rotation: 0
            )
            let layer1 = Layer(surfaces: [surface1])
            let group1 = Group(groups: [], layers: [layer1], filters: [], mask: nil)
            scene.group.groups.append(group1)
        }

        
        // Video 2 - middle third
        if let videoURL = Bundle.main.url(forResource: "mountain", withExtension: "mov") {
            let videoSource = VideoSource(url: videoURL)
            let surface2 = Surface(
                source: videoSource,
                frame: CGRect(x: 427, y: 0, width: 426, height: 720),
                rotation: 0
            )
            let layer2 = Layer(surfaces: [surface2])
            let group2 = Group(groups: [], layers: [layer2], filters: [], mask: nil)
            scene.group.groups.append(group2)
        }

        
        // Video 3 - right third
        if let videoURL = Bundle.main.url(forResource: "download", withExtension: "mov") {
            let videoSource = VideoSource(url: videoURL)
            let surface3 = Surface(
                source: videoSource,
                frame: CGRect(x: 853, y: 0, width: 427, height: 720),
                rotation: 0
            )
            let layer3 = Layer(surfaces: [surface3])
            let group3 = Group(groups: [], layers: [layer3], filters: [], mask: nil)
            scene.group.groups.append(group3)
        } 

        // GIF overlay - bottom center
        if let gifURL = Bundle.main.url(forResource: "horse", withExtension: "gif") {
            if let gifData = try? Data(contentsOf: gifURL),
               let gifImage = GIFImage(gifData: gifData) {
                let gifSource = GIFImageSource(image: gifImage)
                let surfaceGIF = Surface(
                    source: gifSource,
                    frame: CGRect(x: 440, y: 540, width: 400, height: 180),
                    rotation: 0
                )
                let gifLayer = Layer(surfaces: [surfaceGIF])
                let gifGroup = Group(groups: [], layers: [gifLayer], filters: [], mask: nil)
                scene.group.groups.append(gifGroup)
            }
        }

        // Image - top right
        if let image = UIImage(named: "art"),
           let cgImage = image.cgImage {
            let imageSource = ImageSource(image: cgImage)
            let surfaceImage = Surface(
                source: imageSource,
                frame: CGRect(x: 1088, y: 36, width: 192, height: 108),
                rotation: 0
            )
            let imageLayer = Layer(surfaces: [surfaceImage])
            let imageGroup = Group(groups: [], layers: [imageLayer], filters: [], mask: nil)
            scene.group.groups.append(imageGroup)
        }

        // Text label - bottom
        let textStyle = TextSource.TextStyle(
            font: "Helvetica",
            fontSize: 48,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            alignment: .center,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        )
        let textSource = TextSource(
            words: ["Multi-Layer", "Composition"],
            textStyle: textStyle,
            canvasSize: CGSize(width: 880, height: 72),
            wordDuration: 5.0
        )
        let surfaceText = Surface(
            source: textSource,
            frame: CGRect(x: 200, y: 100, width: 880, height: 72),
            rotation: 0
        )
        let textLayer = Layer(surfaces: [surfaceText])
        let textGroup = Group(groups: [], layers: [textLayer], filters: [], mask: nil)
        scene.group.groups.append(textGroup)

        return scene
    }

    private func createAVComposition(from scene: VideoScene) throws {
        // Create the composition with custom video compositing using SceneVideoComposition
        guard let compositionResult = SceneVideoComposition.createComposition(scene: scene) else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create composition"
                self.isLoading = false
            }
            return
        }

        DispatchQueue.main.async {
            let playerItem = AVPlayerItem(asset: compositionResult.composition)
            playerItem.videoComposition = compositionResult.videoComposition
            if let audioMix = compositionResult.audioMix {
                playerItem.audioMix = audioMix
            }

            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            self.isLoading = false
        }
    }
}
