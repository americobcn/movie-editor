//
//  AudioTapProcessor.swift
//  Movie Editor
//
//  Created by Americo Cot on 25/12/25.
//  Copyright © 2025 Américo Cot Toloza. All rights reserved.
//


import Foundation
import MediaToolbox
import AVFoundation
import Accelerate

protocol AudioSpectrumProviderDelegate: AnyObject {
    func spectrumDidChange(spectrum: [Float], peaks: [Float])
}

final class AudioTapProcessor {
    weak var delegate: AudioSpectrumProviderDelegate?
    private let delegateQueue = DispatchQueue(label: "com.audioprocessor.delegate")
    
    let fftAnalyzer: FFTAnalyzer
    let channelCount: Int
    let sampleRate: Float
    let fftSize: Int
    var spectrumBands: Int
    var chDecibelsPeak: [Float]

    private var zero: Float = 0.0
    private var minVal: Float = 0.000_000_01
    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 1.0 / 30.0
    private var greatestFiniteMagnitude = Float.greatestFiniteMagnitude

    // Cache mapping from FFT bin -> log band index to avoid expensive per-frame log10 calls
    private var binToBandMap: [Int]? = nil
    private var cachedBandCount: Int = 0
    private var cachedMinFrequency: Float = 0
    private var cachedMaxFrequency: Float = 0
    private var cachedFFTSize: Int = 0
    private var cachedSampleRate: Float = 0

    // Reusable buffers to avoid per-frame allocations
    private var bandsBuffer: [Float]? = nil
    private var bandBinCountsBuffer: [Int]? = nil
    private var resultBuffer: [Float]? = nil
    
    init(sampleRate: Float, channelCount: Int, fftSize: Int = 4096, spectrumBands: Int) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.spectrumBands = spectrumBands
        self.chDecibelsPeak = [Float](repeating: 0, count: channelCount)
        self.fftAnalyzer = FFTAnalyzer(fftSize: fftSize, sampleRate: sampleRate, chCount: channelCount)
    }
    
    
    @MainActor
    func attachTap(
        to playerItem: AVPlayerItem,
        processor: AudioTapProcessor
    ) async throws {
        
        let asset = playerItem.asset
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return
        }

        let tap = try createAudioProcessingTap(processor: processor)

        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap // .takeUnretainedValue()

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [params]

        playerItem.audioMix = audioMix
        print("Successfully attached audio tap")
    }

        
    func process(buffer: UnsafeMutablePointer<AudioBufferList>) {
        let (magnitudes, peaks) = fftAnalyzer.processAudioBuffer(buffer) // frameCount: frameCount, channelCount: self.channelCount
                
        for (idx, peak) in peaks.enumerated() {
            self.chDecibelsPeak[idx] = 20 * log10(max(peak, 1e-8))
        }
        
        guard !magnitudes.isEmpty else { return }
        // print("Magnitudes: \(magnitudes[0])")
        // Build log spectrum directly from per-channel magnitudes (no intermediate averaged buffer).
        let spectrum = makeLogSpectrum(magnitudesPerChannel: magnitudes, bandCount: self.spectrumBands, minFrequency: 50.0, maxFrequency: 18_000.0 ,useMax: true)
                    
        // Throttle updates
        let now = CACurrentMediaTime()
        guard now - lastUpdateTime >= updateInterval else { return }
        lastUpdateTime = now
                
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.spectrumDidChange(spectrum: spectrum, peaks: self.chDecibelsPeak)
        }
    }
    
        
    func makeLogSpectrum(
        magnitudes: [Float],
        bandCount: Int = 20,
        minFrequency: Float = 50.0,
        maxFrequency: Float? = nil,
        useMax: Bool = false
    ) -> [Float] {
        // Delegate single-channel path to the multi-channel implementation
        return makeLogSpectrum(magnitudesPerChannel: [magnitudes], bandCount: bandCount, minFrequency: minFrequency, maxFrequency: maxFrequency, useMax: useMax)
    }
    
    func makeLogSpectrum(
        magnitudesPerChannel: [[Float]],
        bandCount: Int = 20,
        minFrequency: Float = 50.0,
        maxFrequency: Float? = nil,
        useMax: Bool = false
    ) -> [Float] {

        guard !magnitudesPerChannel.isEmpty else {
            return [Float](repeating: -140.0, count: bandCount)
        }

        let nyquist = sampleRate * 0.5
        let maxFreq = min(maxFrequency ?? nyquist, nyquist)

        // spectrumSize == fftSize/2 + 1
        let spectrumSize = magnitudesPerChannel[0].count

        // We intentionally skip DC (bin 0)
        let firstBin = 1
        let lastBin  = spectrumSize - 1        // Nyquist included if <= maxFreq

        // -------- Mapping cache validation --------
        if binToBandMap == nil ||
           cachedBandCount != bandCount ||
           cachedMinFrequency != minFrequency ||
           cachedMaxFrequency != maxFreq ||
           cachedFFTSize != fftSize ||
           cachedSampleRate != sampleRate {

            let binResolution = sampleRate / Float(fftSize)
            let logMin = log10(minFrequency)
            let logMax = log10(maxFreq)
            let logRange = logMax - logMin

            precondition(logRange > 0, "Invalid frequency range")

            var map = [Int](repeating: -1, count: spectrumSize)
            var binCounts = [Int](repeating: 0, count: bandCount)

            for bin in firstBin...lastBin {
                let frequency = Float(bin) * binResolution
                guard frequency >= minFrequency && frequency <= maxFreq else { continue }

                let normalizedLog = (log10(frequency) - logMin) / logRange
                let clamped = min(max(normalizedLog, 0.0), 1.0)
                let bandIndex = min(Int(clamped * Float(bandCount)), bandCount - 1)

                map[bin] = bandIndex
                binCounts[bandIndex] += 1
            }

            self.binToBandMap = map
            self.bandBinCountsBuffer = binCounts

            self.cachedBandCount = bandCount
            self.cachedMinFrequency = minFrequency
            self.cachedMaxFrequency = maxFreq
            self.cachedFFTSize = fftSize
            self.cachedSampleRate = sampleRate
        }

        guard let map = binToBandMap,
              let bandBinCounts = bandBinCountsBuffer else {
            return [Float](repeating: -140.0, count: bandCount)
        }

        // -------- Prepare output buffer --------
        if bandsBuffer == nil || bandsBuffer!.count != bandCount {
            bandsBuffer = [Float](repeating: 0.0, count: bandCount)
        } else {
            var zero: Float = 0.0
            bandsBuffer!.withUnsafeMutableBufferPointer { ptr in
                vDSP_vfill(&zero, ptr.baseAddress!, 1, vDSP_Length(bandCount))
            }
        }

        var bands = bandsBuffer!
        let channelCount = magnitudesPerChannel.count

        // -------- Aggregate bins --------
        if useMax {
            for ch in 0..<channelCount {
                let mags = magnitudesPerChannel[ch]
                for bin in firstBin...lastBin {
                    let idx = map[bin]
                    if idx >= 0 {
                        bands[idx] = max(bands[idx], mags[bin])
                    }
                }
            }
        } else {
            for ch in 0..<channelCount {
                let mags = magnitudesPerChannel[ch]
                for bin in firstBin...lastBin {
                    let idx = map[bin]
                    if idx >= 0 {
                        bands[idx] += mags[bin]
                    }
                }
            }

            // Average by channel count and bin count
            let channelScale = 1.0 / Float(channelCount)
            for i in 0..<bandCount {
                let count = bandBinCounts[i]
                if count > 0 {
                    bands[i] *= channelScale / Float(count)
                }
            }
        }

        // -------- Safe dB conversion --------
        var result = bands

        // Prevent log(0)
        var floor: Float = 1.0e-12    // ≈ -240 dBFS
        result.withUnsafeMutableBufferPointer { ptr in
            vDSP_vthr(ptr.baseAddress!, 1, &floor, ptr.baseAddress!, 1, vDSP_Length(bandCount))
        }
                        
        // Convert to dB: 20·log10(x / 1.0)
        var reference: Float = 1.0
        vDSP_vdbcon(result, 1, &reference, &result, 1, vDSP_Length(bandCount), 0)

        bandsBuffer = bands
        
        return result
    }

    /// Converts multi-channel linear amplitude magnitudes to dBFS in-place
    /// More efficient than processing each channel separately
    ///
    /// - Parameters:
    ///   - magnitudesPerChannel: 2D array of linear amplitudes [channel][bin]
    ///   - referenceAmplitude: The amplitude that represents 0 dBFS (default: 1.0)
    ///   - floor: Minimum dBFS value (default: -160.0)
/*
    func convertToDBFS(
        magnitudesPerChannel: inout [[Float]],
        referenceAmplitude: Float = 1.0,
        floor: Float = -160.0
    ) {
        let minAmplitude = pow(10.0, floor / 20.0)
        var minVal = minAmplitude
        var reference = referenceAmplitude
        
        for channel in 0..<magnitudesPerChannel.count {
            let count = vDSP_Length(magnitudesPerChannel[channel].count)
            
            // Clamp minimum
            vDSP_vclip(magnitudesPerChannel[channel], 1, &minVal, &greatestFiniteMagnitude, &magnitudesPerChannel[channel], 1, count)
                                
            // Convert to dBFS
            vDSP_vdbcon(magnitudesPerChannel[channel], 1, &reference, &magnitudesPerChannel[channel], 1, count, 0)
        }
    }
*/
}


    

//MARK: tap callbacks
private func tapInitCallback(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalizeCallback(tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapContext>.fromOpaque(storage).release()
}

private func tapPrepareCallback(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    // No-op (FFT already configured)
    
}

private func tapUnprepareCallback(tap: MTAudioProcessingTap) {
    // No-op
}


private func tapProcessCallback(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)

    guard status == noErr else { return }

    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<TapContext>
        .fromOpaque(storage)
        .takeUnretainedValue()
        
    context.processor.process(buffer: bufferListInOut) //frameCount: numberFramesOut.pointee
}


func createAudioProcessingTap(
    processor: AudioTapProcessor
) throws ->  MTAudioProcessingTap { //  Unmanaged<MTAudioProcessingTap>

    let context = TapContext(processor: processor)
        
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: Unmanaged.passRetained(context).toOpaque(),
        init: tapInitCallback,
        finalize: tapFinalizeCallback,
        prepare: tapPrepareCallback,
        unprepare: tapUnprepareCallback,
        process: tapProcessCallback
    )
    
    var tap: MTAudioProcessingTap? //  Unmanaged<MTAudioProcessingTap>?
    let status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault,
        &callbacks,
        kMTAudioProcessingTapCreationFlag_PostEffects,
        &tap
    )

    guard status == noErr, let createdTap = tap else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    return createdTap
}


private final class TapContext {
    let processor: AudioTapProcessor

    init(processor: AudioTapProcessor) {
        self.processor = processor
    }
}
