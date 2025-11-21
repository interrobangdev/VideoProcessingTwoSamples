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
    private var amplitudeHistory: [Float] = []
    private let movingAverageWindowSize = 20

    public var currentAmplitude: Float {
        guard let audioPlayer = audioPlayer, audioPlayer.isPlaying else {
            amplitudeHistory.removeAll()
            return 0.0
        }

        audioPlayer.updateMeters()
        let averagePower = audioPlayer.averagePower(forChannel: 0)

        // Convert dB to linear scale (0.0 - 1.0)
        // dB range is typically -160 to 0
        let instantAmplitude = max(0, 1.0 - (abs(averagePower) / 160.0))

        // Track moving average
        amplitudeHistory.append(instantAmplitude)
        if amplitudeHistory.count > movingAverageWindowSize {
            amplitudeHistory.removeFirst()
        }

        let movingAverage = amplitudeHistory.isEmpty ? 0.0 : amplitudeHistory.reduce(0, +) / Float(amplitudeHistory.count)

        // Calculate moving standard deviation
        let variance = amplitudeHistory.isEmpty ? 0.0 : amplitudeHistory.reduce(0) { sum, value in
            sum + pow(value - movingAverage, 2)
        } / Float(amplitudeHistory.count)
        let movingStdDev = sqrt(variance)

        // Normalize amplitude relative to moving average and scale by standard deviation
        // This makes local quiets quiet and local louds loud within the context of recent audio
        let normalizedDifference = instantAmplitude - movingAverage
        let scaledAmplitude = movingStdDev > 0.01 ? normalizedDifference / (movingStdDev * 2.0) : 0.0

        // Center around 0.5 and clamp to 0.0-1.0
        return max(0, min(1.0, scaledAmplitude + 0.5))
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
