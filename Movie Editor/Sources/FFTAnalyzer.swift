//
//  FFTAnalyzer.swift
//  Movie Editor
//
//  Created by Americo Cot on 25/12/25.
//  Copyright © 2025 Américo Cot Toloza. All rights reserved.
//

import Foundation
import Accelerate
import AudioToolbox

final class FFTAnalyzer {

    // MARK: - Public Configuration

    let fftSize: Int
    let sampleRate: Float
    /// Number of frequency bins returned (fftSize / 2)
    var binCount: Int {
        fftSize / 2
    }

    
    // MARK: - Private DSP State

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private var window: [Float]
    private var windowedSamples: [Float]

    private var realp: [Float]
    private var imagp: [Float]
    private var splitComplex: DSPSplitComplex

    private var magnitudes: [[Float]]
    private var chDecibelsPeaks: [Float]
    
    // MARK: - Initialization

    init(fftSize: Int, sampleRate: Float, chCount: Int) {
        precondition(fftSize.isPowerOfTwo, "FFT size must be a power of two")

        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.chDecibelsPeaks = [Float](repeating: 0, count: chCount)
        self.log2n = vDSP_Length(log2(Float(fftSize)))

        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        self.window = [Float](repeating: 0, count: fftSize)
        self.windowedSamples = [Float](repeating: 0, count: fftSize)

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)

        var split: DSPSplitComplex! = nil
        
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                split = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )
            }
        }

        self.realp = real
        self.imagp = imag
        self.splitComplex = split

        // self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [[Float]](repeating: [Float](repeating: 0, count: fftSize / 2), count: chCount)

        // Hann window
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    
    
    // MARK: - Processing Entry Point

    /// Call this from your MTAudioProcessingTap callback // or UnsafePointer<Float>
    func processAudioBuffer(_ buffer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int, channelCount: Int) -> ([[Float]], [Float]) {

        guard frameCount >= fftSize else {
            return (magnitudes, chDecibelsPeaks)
        }
                    
        // TEST START
        var peakLevel: Float = 0
        for (channel, buffer) in UnsafeMutableAudioBufferListPointer(buffer).enumerated() {
            guard let floatBuffer = buffer.mData?.bindMemory(to: Float.self, capacity: frameCount) else {
                return (magnitudes, chDecibelsPeaks)
            }
                                        
            //Calculate maximun magnitude of the buffer
            vDSP_maxmgv(floatBuffer, 1, &peakLevel, vDSP_Length(frameCount)) // numElements / UInt(channelsCount)
            if peakLevel < 0.000_000_01 {
                peakLevel = 0.000_000_01   //-160 dB
            }
            //Convert magnitude to decibels and store
            self.chDecibelsPeaks[channel] = 20 * log10(peakLevel)
            
            
            /// CALCULATE FFT
             windowedSamples.withUnsafeMutableBufferPointer { dst in
                 dst.baseAddress!.update(from: floatBuffer, count: fftSize)
             }
            
            // Apply window
            vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))
            
            // Convert to split complex
            windowedSamples.withUnsafeBytes { rawPtr in
                rawPtr.bindMemory(to: DSPComplex.self).baseAddress!.withMemoryRebound(
                    to: DSPComplex.self,
                    capacity: fftSize / 2
                ) {
                    vDSP_ctoz($0, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                }
            }
                    
            // FFT
            vDSP_fft_zrip(
                fftSetup,
                &splitComplex,
                1,
                log2n,
                FFTDirection(FFT_FORWARD)
            )
            
            // Magnitude
            vDSP_zvmags(
                &splitComplex,
                1,
                &magnitudes[channel],
                1,
                vDSP_Length(fftSize / 2)
            )
            
            // Convert to dB (optional but recommended for display)
            var one: Float = 1.0
            vDSP_vdbcon(magnitudes[channel], 1, &one, &magnitudes[channel], 1, vDSP_Length(fftSize / 2), 1)
            
        }
                
        return (magnitudes, chDecibelsPeaks)
    }

    
    // MARK: - Helpers

    private func downmixToMono(
        buffer: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        let frames = min(frameCount, fftSize)

        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += buffer[frame * channelCount + channel]
            }
            windowedSamples[frame] = sum / Float(channelCount)
        }
    }
    
    private func magToDB(_ inMagnitude: Float) -> Float {
        // ceil to 128db in order to avoid log10'ing 0
        let magnitude = max(inMagnitude, 0.000000000001)
        return 10 * log10f(magnitude)
    }

}


private extension Int {
    var isPowerOfTwo: Bool {
        (self & (self - 1)) == 0 && self > 0
    }
}




// Convert to mono (average channels if needed)
// if channelCount == 1 {
//     buffer.withMemoryRebound(to: Float.self, capacity: fftSize) { pointer in
//         windowedSamples.withUnsafeMutableBufferPointer { dst in
//             dst.baseAddress!.update(from: buffer, count: fftSize)
//         }
//     }
// } else {
//     downmixToMono(
//         buffer: buffer,
//         frameCount: frameCount,
//         channelCount: channelCount
//     )
// }
