//
//  FFTAnalyzer.swift
//  Movie Editor
//
//  Created by Americo Cot on 25/12/25.
//  Copyright © 2025 Américo Cot Toloza. All rights reserved.
//

import Foundation
import Accelerate

final class FFTAnalyzer {

    // MARK: - Public Configuration

    let fftSize: Int
    let sampleRate: Float
    let spectrumSize: Int
    
    var binCount: Int {
        fftSize / 2
    }

    
    // MARK: - Private DSP State

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private var window: [Float]
    private var windowed: [Float]
    private let windowCorrection: Float
    private let fftNormalization: Float
    
    private var realp: [Float]
    private var imagp: [Float]
    private var splitComplex: DSPSplitComplex

    private var magnitudes: [[Float]]
    private var chDecibelsPeaks: [Float]
    // private var scale: Float!
    private var one: Float = 1.0
    private var peakLevel: Float = 0.0
    private var epsilon: Float = 0.000_000_01 //1e-12
    private(set) var spectrumDB: [Float]
    
    // MARK: - Initialization

    init(fftSize: Int, sampleRate: Float, chCount: Int) {
        precondition(fftSize.isPowerOfTwo, "FFT size must be a power of two")

        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.spectrumSize = fftSize / 2 + 1
        
        self.chDecibelsPeaks = [Float](repeating: 0, count: chCount)
        self.log2n = vDSP_Length(log2(Float(fftSize)))

        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Window gain correction
        var sum: Float = 0
        vDSP_sve(window, 1, &sum, vDSP_Length(fftSize))
        let mean = sum / Float(fftSize)
        self.windowCorrection = 1.0 / mean
        self.fftNormalization = 1.0 / Float(fftSize)
        
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.spectrumDB = [Float](repeating: -120, count: spectrumSize)
        self.magnitudes = [[Float]](repeating: [Float](repeating: 0, count: spectrumSize), count: chCount)
        
        // self.scale = 4.0 / Float(fftSize)
        
        var real = [Float](repeating: 0, count: spectrumSize)
        var imag = [Float](repeating: 0, count: spectrumSize)

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
             // windowed.withUnsafeMutableBufferPointer { dst in
             //     dst.baseAddress!.update(from: floatBuffer, count: fftSize)
             // }
            
            // Apply window
            // vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
            vDSP_vmul(floatBuffer, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
            
            // Convert to split complex
            // windowed.withUnsafeBytes { rawPtr in
            //     rawPtr.bindMemory(to: DSPComplex.self).baseAddress!.withMemoryRebound(
            //         to: DSPComplex.self,
            //         capacity: fftSize / 2
            //     ) {
            //         vDSP_ctoz($0, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            //     }
            // }
            
            windowed.withUnsafeBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                            vDSP_ctoz(complexPtr,2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                }
            }
            
            
            // Perform FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            
            
            // 4. Vectorized magnitude extraction (bins 1...N/2-1)
            let binCount = fftSize / 2
            let bodyCount = binCount - 1

            var bodySplit = DSPSplitComplex(
                realp: splitComplex.realp.advanced(by: 1),
                imagp: splitComplex.imagp.advanced(by: 1)
            )

            magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
                let bodyMag = magPtr.baseAddress!.advanced(by: 1)
                vDSP_zvabs(&bodySplit, 1, bodyMag, 1, vDSP_Length(bodyCount))
            }
                        
            // 5. DC and Nyquist
            magnitudes[channel][0] = abs(splitComplex.realp[0])
            magnitudes[channel][binCount] = abs(splitComplex.imagp[0])
            
            // 6. Normalize FFT + window correction
            var scale = fftNormalization * windowCorrection
            vDSP_vsmul(magnitudes[channel], 1, &scale, &magnitudes[channel], 1, vDSP_Length(spectrumSize))
            
            // 7. One-sided ×2 compensation (excluding DC and Nyquist)
            var two: Float = 2.0
            magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
                let body = magPtr.baseAddress!.advanced(by: 1)
                vDSP_vsmul(body, 1, &two, body, 1, vDSP_Length(bodyCount))
            }
            
            // 8. Peak normalize to 0 dBFS
            var maxMag: Float = 0.0
            vDSP_maxv(magnitudes[channel], 1, &maxMag, vDSP_Length(spectrumSize))
            maxMag = max(maxMag, epsilon)

            var invMax = 1.0 / maxMag
            vDSP_vsmul(magnitudes[channel], 1, &invMax, &magnitudes[channel], 1, vDSP_Length(spectrumSize))
            
            
            // 9. Clamp
            // var floor = epsilon
            vDSP_vthr(magnitudes[channel], 1, &epsilon, &magnitudes[channel], 1, vDSP_Length(spectrumSize))
            
            // var one: Float = 1.0
            vDSP_vdbcon(magnitudes[channel], 1, &one, &spectrumDB, 1, vDSP_Length(spectrumSize), 0)
            // print("Spectrum dB: \(spectrumDB)\n")
            // Read spectrum
            for i in 0..<spectrumSize {
                let db = spectrumDB[i]
                if db > -6 {
                    let freq = frequency(at: i)
                    print("Peak near \(freq) Hz → \(db) dBFS")
                }
            }
            // After real FFT, imagp[0] contains Nyquist, clear it for magnitude calculation
            // splitComplex.imagp[0] = 0
            // splitComplex.realp[0] = 0
                                
            // Magnitudes
            // vDSP_zvabs(&splitComplex, 1, &magnitudes[channel], 1, vDSP_Length(fftSize / 2))
            
            // Hanning window coherent gain = 0.5
            // Combined scaling: (2.0 / fftSize) / 0.5 = 4.0 / fftSize
            // vDSP_vsmul(magnitudes[channel], 1, &scale, &magnitudes[channel], 1, vDSP_Length(fftSize / 2))
            
            // Convert to dB (optional but recommended for display)
            // vDSP_vdbcon(magnitudes[channel], 1, &one, &magnitudes[channel], 1, vDSP_Length(fftSize / 2), 0)
        }
        
        return (magnitudes, chDecibelsPeaks)
    }
    
    func frequency(at index: Int) -> Float {
            return Float(index) * sampleRate / Float(fftSize)
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
//         windowed.withUnsafeMutableBufferPointer { dst in
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

/*
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
         windowed[frame] = sum / Float(channelCount)
     }
 }
 
 private func magToDB(_ inMagnitude: Float) -> Float {
     // ceil to 128db in order to avoid log10'ing 0
     let magnitude = max(inMagnitude, 0.000000000001)
     return 10 * log10f(magnitude)
 }
*/
