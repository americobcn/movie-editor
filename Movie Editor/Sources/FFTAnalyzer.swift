//
//  FFTAnalyzer.swift
//  Movie Editor
//
//  Created by Americo Cot on 25/12/25.
//  Copyright © 2025 Américo Cot Toloza. All rights reserved.
//

import Foundation
import Accelerate
import AVFoundation

final class FFTAnalyzer {

    // MARK: - Public Configuration

    let fftSize: Int
    let sampleRate: Float
    let spectrumSize: Int

    
    // MARK: - Private DSP State

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private var hannWindow: [Float]
    private let fftCorrection: Float
    // private let fftNormalization: Float
    
    private var realp: UnsafeMutablePointer<Float> // [Float] = [Float]()
    private var imagp: UnsafeMutablePointer<Float> // [Float] = [Float]()
    private var splitComplex: DSPSplitComplex

    private var magnitudes: [[Float]]
    private var channelsPeak: [Float]  //chDecibelsPeaks
    
    private var one: Float = 1.0
    private var peakLevel: Float = 0.0
    private var epsilon: Float = 0.000_000_01 //1e-12
    
    // private(set) var spectrumDB: [Float]
    
    
    
    // MARK: - Initialization

    init(fftSize: Int, sampleRate: Float, chCount: Int) {
        precondition(fftSize.isPowerOfTwo, "FFT size must be a power of two")

        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.spectrumSize = (fftSize / 2) + 1
        
        self.channelsPeak = [Float](repeating: 0, count: chCount)
        self.log2n = vDSP_Length(Int(log2(Double(fftSize))))

        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        // Initialize Hanning Window
        self.hannWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Window gain correction
        var sum: Float = 0
        vDSP_sve(hannWindow, 1, &sum, vDSP_Length(fftSize))
        self.fftCorrection = 2.0 / sum  // Window correction + FFT normalization
        
        self.magnitudes = [[Float]](repeating: [Float](repeating: 0, count: spectrumSize), count: chCount)
                
        self.realp = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        self.imagp = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        self.splitComplex = DSPSplitComplex(realp: realp, imagp: imagp)
    }

    deinit {
        realp.deallocate()
        imagp.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    
    
    // MARK: - Processing Entry Point

    /// Call this from your MTAudioProcessingTap callback // or UnsafePointer<Float>
    func processAudioBuffer(_ buffer: UnsafeMutablePointer<AudioBufferList>) -> ([[Float]], [Float]) {
        // guard frameCount >= fftSize else { return (magnitudes, chDecibelsPeaks) }
        precondition(buffer.pointee.mNumberBuffers == magnitudes.count)

        for (channel, audioBuffer) in UnsafeMutableAudioBufferListPointer(buffer).enumerated() {
            let framesCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            
            guard let floatBuffer = audioBuffer.mData?.bindMemory(to: Float.self, capacity: framesCount) else {
                return (magnitudes, channelsPeak)
            }
            
            //Calculate maximun amplitude of the buffer
            var peak: Float = 0
            vDSP_maxmgv(floatBuffer, 1, &peak, vDSP_Length(framesCount))
            self.channelsPeak[channel] =  peak
                        
            
            /// CALCULATE FFT
            // Apply window
            let samplesToProcess = min(framesCount, fftSize)
            vDSP_vmul(floatBuffer, 1, hannWindow, 1, splitComplex.realp, 1, vDSP_Length(samplesToProcess))
            // Zero-pad if needed
            if samplesToProcess < fftSize {
                vDSP_vclr(splitComplex.realp.advanced(by: samplesToProcess), 1, vDSP_Length(fftSize - samplesToProcess))
            }
            // Zero fill for imaginary part
            vDSP_vclr(splitComplex.imagp, 1, vDSP_Length(fftSize))
                                    
            // Perform FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            
            // Extract DC and Nyquist (stored in packed format)
            let dc = abs(splitComplex.realp[0])
            let nyquist = abs(splitComplex.imagp[0])
            
            // 4. Vectorized magnitude extraction (bins 1...N/2-1)
            let bodyCount = spectrumSize - 2 // spectrumSize == (fftsize/2) + 1
            var bodySplit = DSPSplitComplex(realp: splitComplex.realp.advanced(by: 1), imagp: splitComplex.imagp.advanced(by: 1))
            
            magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
                vDSP_zvabs(&bodySplit, 1, magPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(bodyCount))
            }
            
            // 5. DC and Nyquist
            magnitudes[channel][0] = dc
            magnitudes[channel][spectrumSize - 1] = nyquist
                    
            // 6. Normalize FFT + window correction to all magnitudes
            /// windowCorrection = 2.0 / sum(hanningWindow)
            var scale = fftCorrection
            magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
                vDSP_vsmul(magPtr.baseAddress!, 1, &scale, magPtr.baseAddress!, 1, vDSP_Length(spectrumSize))
            }
            
            // 7. One-sided ×2 compensation (excluding DC and Nyquist)
            // var two: Float = 2.0
            // magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
            //     vDSP_vsmul(magPtr.baseAddress!.advanced(by: 1), 1, &two, magPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(bodyCount))
            // }
            
            // 8. Peak normalize to 0 dBFS
            // var maxMag: Float = 0.0
            // vDSP_maxv(magnitudes[channel], 1, &maxMag, vDSP_Length(spectrumSize))
            // maxMag = max(maxMag, epsilon)

            // var invMax = 1.0 / maxMag
            // vDSP_vsmul(magnitudes[channel], 1, &invMax, &magnitudes[channel], 1, vDSP_Length(spectrumSize))
            
            
            // 9. Clamp
            // var floor = epsilon
            // vDSP_vthr(magnitudes[channel], 1, &epsilon, &magnitudes[channel], 1, vDSP_Length(spectrumSize))
            
            /// Convert to DBS
            // var one: Float = 1.0
            // vDSP_vdbcon(magnitudes[channel], 1, &one, &spectrumDB, 1, vDSP_Length(spectrumSize), 0)
            // print("Spectrum dB: \(spectrumDB)\n")
            // Read spectrum

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
        // print("Magni: \(magnitudes)")
        return (magnitudes, channelsPeak)
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
