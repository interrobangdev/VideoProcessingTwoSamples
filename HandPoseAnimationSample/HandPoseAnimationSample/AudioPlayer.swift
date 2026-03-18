//
//  AudioPlayer.swift
//  HandPoseAnimationSample
//
//  Handles audio playback and amplitude extraction
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

public class AudioPlayer: NSObject, ObservableObject {
    @Published public var isPlaying = false
    @Published public var duration: TimeInterval = 0.0

    private var audioPlayer: AVAudioPlayer?
    private var smoothedAmplitude: Float = 0.0

    public var currentAmplitude: Float {
        guard let audioPlayer = audioPlayer, audioPlayer.isPlaying else {
            smoothedAmplitude = 0.0
            return 0.0
        }

        audioPlayer.updateMeters()
        let averagePower = audioPlayer.averagePower(forChannel: 0)
        let peakPower = audioPlayer.peakPower(forChannel: 0)

        // Convert the metering values from decibels into a linear 0...1 range.
        let averageLinear = pow(10.0, averagePower / 20.0)
        let peakLinear = pow(10.0, peakPower / 20.0)

        // Blend average and peak so we keep punch without becoming jittery.
        let blendedAmplitude = min(1.0, (averageLinear * 0.7) + (peakLinear * 0.3))

        // Drop the very low noise floor, then expand the mid-range a bit so
        // typical music produces more nuanced values than just 0.5 or 1.0.
        let noiseFloor: Float = 0.015
        let normalizedAmplitude = max(0.0, (blendedAmplitude - noiseFloor) / (1.0 - noiseFloor))
        let shapedAmplitude = pow(normalizedAmplitude, 0.6)

        // Light smoothing keeps the meter responsive without flickering wildly.
        let smoothingFactor: Float = 0.2
        smoothedAmplitude = (smoothedAmplitude * (1.0 - smoothingFactor)) + (shapedAmplitude * smoothingFactor)

        return max(0.0, min(1.0, smoothedAmplitude))
    }

    override public init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    public func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.isMeteringEnabled = true
            duration = audioPlayer?.duration ?? 0.0
        } catch {
            print("Error loading audio: \(error)")
        }
    }

    public func play() {
        audioPlayer?.play()
        isPlaying = true
    }

    public func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    public func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
    }

    public func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }

    public func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        pause()
    }

    public func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        if flags == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
            play()
        }
    }
}
