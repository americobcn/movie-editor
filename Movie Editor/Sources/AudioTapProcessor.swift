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

protocol AudioSpectrumProviderDelegate: class {
    func spectrumDidChange(spectrum: [Float], peaks: [Float])
}

final class AudioTapProcessor {
    var delegate:AudioSpectrumProviderDelegate?
    
    let fftAnalyzer: FFTAnalyzer
    let channelCount: Int
    let  sampleRate: Float
    let fftSize: Int
    var spectrumBands: Int

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
        print("AudioTapProcessor initialized wtih \(channelCount) channels, sampleRate: \(sampleRate),fftSize: \(fftSize), spectrumBands: \(spectrumBands)")
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

    
    // func process(buffer: UnsafePointer<Float>, frameCount: Int, numberOfChannels: Int) {
    func process(buffer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let (magnitudes, peaks) = fftAnalyzer.processAudioBuffer(
            buffer,
            frameCount: frameCount,
            channelCount: self.channelCount
        )
        
        self.delegate?.spectrumDidChange(spectrum: makeLogSpectrum(magnitudes: magnitudes[0], bandCount: self.spectrumBands), peaks: peaks)
    }
    
    
    func makeLogSpectrum(
        magnitudes: [Float],
        bandCount: Int = 20,
        minFrequency: Float = 20.0,
        maxFrequency: Float? = nil,
        useMax: Bool = false
    ) -> [Float] {
        
        let nyquist = self.sampleRate * 0.5
        let maxFreq = min(maxFrequency ?? nyquist, nyquist)

        let binCount = magnitudes.count
        let binResolution = self.sampleRate / Float(self.fftSize)

        var bands = [Float](repeating: -140.0, count: bandCount)
        var bandBinCounts = [Int](repeating: 0, count: bandCount)

        let logMin = log10(minFrequency)
        let logMax = log10(maxFreq)
        let logRange = logMax - logMin

        for bin in 0..<binCount {
            let frequency = Float(bin) * binResolution
            if frequency < minFrequency || frequency > maxFreq {
                continue
            }

            let normalizedLog =
                (log10(frequency) - logMin) / logRange

            let bandIndex = Int(
                normalizedLog * Float(bandCount)
            )

            guard bandIndex >= 0 && bandIndex < bandCount else {
                continue
            }

            let magnitude = magnitudes[bin]

            if useMax {
                bands[bandIndex] = max(bands[bandIndex], magnitude)
            } else {
                bands[bandIndex] += magnitude
                bandBinCounts[bandIndex] += 1
            }
        }

        // Average bands if not using peak
        if !useMax {
            for i in 0..<bandCount {
                if bandBinCounts[i] > 0 {
                    bands[i] /= Float(bandBinCounts[i])
                }
            }
        }
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

