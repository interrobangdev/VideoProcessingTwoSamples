//
//  HandPoseDataCollector.swift
//  HandPoseAnimationSample
//
//  Collects hand pose data from live camera feed using Vision framework
//

import Foundation
import VideoProcessingTwo
import Vision
import CoreImage

/// Represents a single hand pose frame
public struct HandPoseFrame {
    public let timestamp: TimeInterval
    public let handObservations: [VNHumanHandPoseObservation]
    public let frameSize: CGSize

    public init(timestamp: TimeInterval, observations: [VNHumanHandPoseObservation], frameSize: CGSize) {
        self.timestamp = timestamp
        self.handObservations = observations
        self.frameSize = frameSize
    }
}

/// Collects hand pose data from camera frames
public class HandPoseDataCollector: NSObject, CameraManagerDelegate {
    public var frames: [HandPoseFrame] = []
    private var startTime: TimeInterval?
    private let frameQueue = DispatchQueue(label: "com.handpose.collector")

    /// Latest hand observations (thread-safe)
    public private(set) var latestObservations: [VNHumanHandPoseObservation] = []
    public private(set) var latestFrameSize: CGSize = .zero

    /// Called when new hand data is available
    public var onHandPoseUpdated: (([VNHumanHandPoseObservation]) -> Void)?

    override init() {
        super.init()
    }

    public func start() {
        frameQueue.async {
            self.startTime = Date().timeIntervalSince1970
            self.frames.removeAll()
        }
    }

    public func stop() {
        frameQueue.async {
            self.startTime = nil
        }
    }

    // MARK: - CameraManagerDelegate

    public func didOutputFrame(frame: Frame) {
        frameQueue.async {
            guard let startTime = self.startTime else { return }

            // Get CIImage for display
            guard let ciImage = frame.ciImageRepresentation() else { return }

            // Detect hand poses using Vision framework
            let handObservations = self.detectHandPoses(in: frame)

            let timestamp = Date().timeIntervalSince1970 - startTime
            let frameSize = frame.size

            let poseFrame = HandPoseFrame(timestamp: timestamp, observations: handObservations, frameSize: frameSize)
            self.frames.append(poseFrame)

            // Update latest observations on main thread for UI updates
            DispatchQueue.main.async {
                self.latestObservations = handObservations
                self.latestFrameSize = frameSize
                self.onHandPoseUpdated?(handObservations)
            }
        }
    }

    public func didOutputPhotoFrame(photo: CIImage) {
        // Not used for live collection
    }

    // MARK: - Hand Pose Detection

    private func detectHandPoses(in frame: Frame) -> [VNHumanHandPoseObservation] {
        guard let ciImage = frame.ciImageRepresentation() else {
            return []
        }

        let request = VNDetectHumanHandPoseRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)

        do {
            try handler.perform([request])
            guard let observations = request.results as? [VNHumanHandPoseObservation] else {
                return []
            }
            return observations
        } catch {
            print("Hand pose detection error: \(error)")
            return []
        }
    }

    // MARK: - Public API

    /// Get normalized hand position (0.0 to 1.0) from observations
    public func getNormalizedHandPosition() -> (x: Double, y: Double)? {
        guard let observation = latestObservations.first else { return nil }

        do {
            // Get wrist position (typically the main hand position)
            let wristPoint = try observation.recognizedPoint(.wrist)

            // Convert from Vision coordinates (0-1, top-left origin) to normalized screen coordinates
            let x = Double(wristPoint.location.x)
            let y = Double(1.0 - wristPoint.location.y) // Flip Y

            return (x: x, y: y)
        } catch {
            return nil
        }
    }

    /// Get all detected hand positions (for multi-hand scenarios)
    public func getAllHandPositions() -> [(x: Double, y: Double)] {
        var positions: [(x: Double, y: Double)] = []

        for observation in latestObservations {
            do {
                let wristPoint = try observation.recognizedPoint(.wrist)
                let x = Double(wristPoint.location.x)
                let y = Double(1.0 - wristPoint.location.y)
                positions.append((x: x, y: y))
            } catch {
                continue
            }
        }

        return positions
    }

    /// Get specific hand landmark position
    public func getHandLandmarkPosition(_ landmark: VNHumanHandPoseObservation.JointName) -> (x: Double, y: Double)? {
        guard let observation = latestObservations.first else { return nil }

        do {
            let point = try observation.recognizedPoint(landmark)
            let x = Double(point.location.x)
            let y = Double(1.0 - point.location.y)
            return (x: x, y: y)
        } catch {
            return nil
        }
    }
}
