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
    
    let fftAnalyzer: FFTAnalyzer
    let channelCount: Int
    let  sampleRate: Float
    let fftSize: Int
    var spectrumBands: Int
    
    // Cache mapping from FFT bin -> log band index to avoid expensive per-frame log10 calls
    private var binToBandMap: [Int]? = nil
    private var cachedBandCount: Int = 0
    private var cachedMinFrequency: Float = 0
    private var cachedMaxFrequency: Float = 0
    // Reusable buffers to avoid per-frame allocations
    private var bandsBuffer: [Float]? = nil
    private var bandBinCountsBuffer: [Int]? = nil

    init(sampleRate: Float, channelCount: Int, fftSize: Int = 2048, spectrumBands: Int) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.spectrumBands = spectrumBands
        
        self.fftAnalyzer = FFTAnalyzer(
            fftSize: fftSize,
            sampleRate: sampleRate,
            chCount: channelCount
        )
        // print("AudioTapProcessor initialized wtih \(channelCount) channels, sampleRate: \(sampleRate),fftSize: \(fftSize), spectrumBands: \(spectrumBands)")
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
        params.audioTapProcessor = tap

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [params]

        playerItem.audioMix = audioMix
        print("Successfully attached audio tap")
    }

        
    func process(buffer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let (magnitudes, peaks) = fftAnalyzer.processAudioBuffer(
            buffer,
            frameCount: frameCount,
            channelCount: self.channelCount
        )
        // Build log spectrum directly from per-channel magnitudes (no intermediate averaged buffer).
        let spectrum = makeLogSpectrum(magnitudesPerChannel: magnitudes, bandCount: self.spectrumBands)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.spectrumDidChange(spectrum: spectrum, peaks: peaks)
        }
    }
    
    
    func makeLogSpectrum(
        magnitudes: [Float],
        bandCount: Int = 20,
        minFrequency: Float = 20.0,
        maxFrequency: Float? = nil,
        useMax: Bool = false
    ) -> [Float] {
        // Delegate single-channel path to the multi-channel implementation
        return makeLogSpectrum(magnitudesPerChannel: [magnitudes], bandCount: bandCount, minFrequency: minFrequency, maxFrequency: maxFrequency, useMax: useMax)
    }

    /// Aggregate per-channel magnitude buffers directly into log-spaced bands.
    func makeLogSpectrum(
        magnitudesPerChannel: [[Float]],
        bandCount: Int = 20,
        minFrequency: Float = 20.0,
        maxFrequency: Float? = nil,
        useMax: Bool = false
    ) -> [Float] {

        guard !magnitudesPerChannel.isEmpty else { return [Float](repeating: -140.0, count: bandCount) }

        let nyquist = self.sampleRate * 0.5
        let maxFreq = min(maxFrequency ?? nyquist, nyquist)

        let binCount = magnitudesPerChannel[0].count
        // If band mapping is not cached for this configuration, build it once.
        if binToBandMap == nil || cachedBandCount != bandCount || cachedMinFrequency != minFrequency || cachedMaxFrequency != maxFreq {
            var map = [Int](repeating: -1, count: binCount)

            let binResolution = self.sampleRate / Float(self.fftSize)
            let logMin = log10(minFrequency)
            let logMax = log10(maxFreq)
            let logRange = logMax - logMin

            for bin in 0..<binCount {
                let frequency = Float(bin) * binResolution
                if frequency < minFrequency || frequency > maxFreq {
                    continue
                }
                let normalizedLog = (log10(frequency) - logMin) / logRange
                var bandIndex = Int(normalizedLog * Float(bandCount))
                if bandIndex < 0 { bandIndex = 0 }
                if bandIndex >= bandCount { bandIndex = bandCount - 1 }
                map[bin] = bandIndex
            }

            self.binToBandMap = map
            self.cachedBandCount = bandCount
            self.cachedMinFrequency = minFrequency
            self.cachedMaxFrequency = maxFreq
        }


        // Prepare reusable buffers
        if bandsBuffer == nil || bandsBuffer!.count != bandCount {
            bandsBuffer = [Float](repeating: -140.0, count: bandCount)
        } else {
            var fillVal: Float = -140.0
            bandsBuffer!.withUnsafeMutableBufferPointer { ptr in
                vDSP_vfill(&fillVal, ptr.baseAddress!, 1, vDSP_Length(bandCount))
            }
        }

        if bandBinCountsBuffer == nil || bandBinCountsBuffer!.count != bandCount {
            bandBinCountsBuffer = [Int](repeating: 0, count: bandCount)
        } else {
            for i in 0..<bandCount { bandBinCountsBuffer![i] = 0 }
        }

        guard let map = binToBandMap, var bands = bandsBuffer, var bandBinCounts = bandBinCountsBuffer else { return [Float](repeating: -140.0, count: bandCount) }

        let channelCount = magnitudesPerChannel.count

        if useMax {
            for bin in 0..<binCount {
                let idx = map[bin]
                if idx < 0 { continue }
                var maxVal: Float = -Float.greatestFiniteMagnitude
                for ch in 0..<channelCount {
                    let val = magnitudesPerChannel[ch][bin]
                    if val > maxVal { maxVal = val }
                }
                bands[idx] = max(bands[idx], maxVal)
            }
        } else {
            for bin in 0..<binCount {
                let idx = map[bin]
                if idx < 0 { continue }
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += magnitudesPerChannel[ch][bin]
                }
                let avg = sum / Float(channelCount)
                bands[idx] += avg
                bandBinCounts[idx] += 1
            }

            for i in 0..<bandCount {
                if bandBinCounts[i] > 0 {
                    bands[i] /= Float(bandBinCounts[i])
                }
            }
        }

        // Commit mutated buffers back to storage to keep reusing them
        bandsBuffer = bands
        bandBinCountsBuffer = bandBinCounts

        return bands
    }
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
    
    // let audioBufferList = bufferListInOut.pointee
    // let audioBuffer = bufferListInOut.pointee.mBuffers
    // let numChannels = audioBuffer.mNumberChannels
    // guard let data = bufferListInOut.pointee.mBuffers.mData else { return }
    
    let framesCount = Int(numberFramesOut.pointee)
        
    context.processor.process(
        buffer: bufferListInOut,
        frameCount: framesCount
    )
}


func createAudioProcessingTap(
    processor: AudioTapProcessor
) throws -> MTAudioProcessingTap {

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

    var tap: MTAudioProcessingTap?
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

