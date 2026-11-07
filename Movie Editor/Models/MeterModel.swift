//
//  MeterModel.swift
//  Movie Editor
//
//  Holds the level-meter and spectrum values shown by SpectrumView / LevelMetersView.
//  Levels are normalized 0...1.
//

import Foundation
import Observation

@MainActor
@Observable
final class MeterModel: AudioSpectrumProviderDelegate {

    let spectrumBands = 32
    private(set) var spectrumLevels: [CGFloat]
    private(set) var channelLevels: [CGFloat]
    /// Effective player volume (0 when muted). Channel meters are scaled by it.
    var volume: Float = 1

    @ObservationIgnored private var smoothed: [Float]
    @ObservationIgnored private var isDecaying = false
    @ObservationIgnored private var decayTimer: Timer?
    @ObservationIgnored private let smoothingAlpha: Float = 0.4   // EMA factor

    init() {
        spectrumLevels = [CGFloat](repeating: 0, count: spectrumBands)
        channelLevels = [CGFloat](repeating: 0, count: 2)
        smoothed = [Float](repeating: -100, count: spectrumBands)
    }

    // MARK: AudioSpectrumProviderDelegate (called on the tap's delegate queue)
    nonisolated func spectrumDidChange(spectrum: [Float], peaks: [Float]) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.apply(spectrum: spectrum, peaks: peaks) }
        }
    }

    private func apply(spectrum: [Float], peaks: [Float]) {
        guard !isDecaying else { return }
        var bands = spectrumLevels
        for i in 0..<min(spectrumBands, spectrum.count) {
            smoothed[i] = smoothingAlpha * spectrum[i] + (1 - smoothingAlpha) * smoothed[i]
            bands[i] = Self.level(db: smoothed[i], minDB: -50)
        }
        var channels = channelLevels
        for i in 0..<min(channels.count, peaks.count) {
            channels[i] = Self.level(db: peaks[i], minDB: -120)
        }
        spectrumLevels = bands
        channelLevels = channels
    }

    static func level(db: Float, minDB: Float, maxDB: Float = 0) -> CGFloat {
        let clamped = min(max(db, minDB), maxDB)
        let normalized = (clamped - minDB) / (maxDB - minDB)
        return CGFloat(pow(normalized, 0.7))
    }

    // MARK: Control
    func configure(channelCount: Int) {
        channelLevels = [CGFloat](repeating: 0, count: max(channelCount, 1))
    }

    func reset() {
        stopDecay()
        isDecaying = false
        spectrumLevels = [CGFloat](repeating: 0, count: spectrumBands)
        channelLevels = [CGFloat](repeating: 0, count: channelLevels.count)
        smoothed = [Float](repeating: -100, count: spectrumBands)
    }

    /// Playing resumes live updates; pausing fades the bars to zero.
    func setPlaying(_ playing: Bool) {
        if playing {
            isDecaying = false
            stopDecay()
        } else {
            isDecaying = true
            guard decayTimer == nil else { return }
            decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.decayStep() }
            }
        }
    }

    private func stopDecay() {
        decayTimer?.invalidate()
        decayTimer = nil
    }

    private func decayStep() {
        let factor: CGFloat = 0.85
        let floorLevel: CGFloat = 0.004   // ~0.5pt of the old 130pt scale
        var allZero = true
        func decayed(_ v: CGFloat) -> CGFloat {
            if v > floorLevel { allZero = false; return v * factor }
            return 0
        }
        spectrumLevels = spectrumLevels.map(decayed)
        channelLevels = channelLevels.map(decayed)
        smoothed = smoothed.map { $0 * 0.9 }
        if allZero {
            isDecaying = false
            stopDecay()
        }
    }
}
