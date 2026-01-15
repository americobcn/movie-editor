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

    private let windowCoherentGain: Float
    private let scaleFactor: Float  // For bins 1...N/2-1 (one-sided spectrum)
    private let scaleDCNyquist: Float  // For DC and Nyquist (no doubling)

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
        
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        // Initialize Hanning Window
        self.hannWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Calculate window coherent gain (average value)
        // For Hann window: coherent gain ≈ 0.5
        var sum: Float = 0
        vDSP_sve(hannWindow, 1, &sum, vDSP_Length(fftSize))
        self.windowCoherentGain = sum / Float(fftSize)
        
        // Scaling factors for proper magnitude spectrum
        // For one-sided spectrum (bins 1 to N/2-1): multiply by 2
        // Formula: 2 / (N * coherentGain)
        self.scaleFactor = 2.0 / (Float(fftSize) * windowCoherentGain)
        
        // For DC and Nyquist: no doubling needed
        // Formula: 1 / (N * coherentGain)
        self.scaleDCNyquist = 1.0 / (Float(fftSize) * windowCoherentGain)
        
        self.magnitudes = [[Float]](repeating: [Float](repeating: 0, count: spectrumSize), count: chCount)
        
        self.realp = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        self.imagp = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        self.splitComplex = DSPSplitComplex(realp: realp, imagp: imagp)
        
        print("""
                FFT Analyzer initialized:
                - FFT Size: \(fftSize)
                - Sample Rate: \(sampleRate) Hz
                - Spectrum Size: \(spectrumSize)
                - Window Coherent Gain: \(windowCoherentGain)
                - Scale Factor (bins 1...N/2-1): \(scaleFactor)
                - Scale Factor (DC & Nyquist): \(scaleDCNyquist)                
                """)
    }

    deinit {
        realp.deallocate()
        imagp.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    
    
    // MARK: - Processing Entry Point

    /// Call this from your MTAudioProcessingTap callback // or UnsafePointer<Float>
    func processAudioBuffer(_ bufferList: UnsafeMutablePointer<AudioBufferList>, _ framesIn: Int) -> ([[Float]], [Float]) {
        // precondition(buffer.pointee.mNumberBuffers == magnitudes.count, "Buffer channel count must match initialized channel count")
        if bufferList.pointee.mNumberBuffers != magnitudes.count { return ([], []) }
        
        for (channel, audioBuffer) in UnsafeMutableAudioBufferListPointer(bufferList).enumerated() {
            guard let floatBuffer = audioBuffer.mData?.bindMemory(to: Float.self, capacity: framesIn) else {
                continue  // Skip this channel if buffer is invalid
            }
            
            //Calculate maximun amplitude of the buffer
            var peak: Float = 0
            vDSP_maxmgv(floatBuffer, 1, &peak, vDSP_Length(framesIn))
            self.channelsPeak[channel] =  peak
                                    
            /// CALCULATE FFT
            // 1. Apply Hann window to input samples
            let samplesToProcess = min(framesIn, fftSize)
            vDSP_vmul(floatBuffer, 1, hannWindow, 1, splitComplex.realp, 1, vDSP_Length(samplesToProcess))
            
            // 2. Zero-pad if input is shorter than FFT size
            if samplesToProcess < fftSize {
                vDSP_vclr(splitComplex.realp.advanced(by: samplesToProcess), 1, vDSP_Length(fftSize - samplesToProcess))
            }
            
            // 3. Zero-fill imaginary part (real-to-complex FFT)
            vDSP_vclr(splitComplex.imagp, 1, vDSP_Length(fftSize))
                                    
            // 4. Perform in-place real-to-complex FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                            
            
            
            // 5. Extract DC and Nyquist (stored in packed format by vDSP)
            // After vDSP_fft_zrip: DC is in realp[0], Nyquist is in imagp[0]
            let dc = abs(splitComplex.realp[0])
            let nyquist = abs(splitComplex.imagp[0])
            // print("DC Normalized: \(dc/Float(fftSize))")
            
            // 6. Compute magnitudes for bins 1...N/2-1 using vectorized operations
            let bodyCount = spectrumSize - 2 // Exclude DC (bin 0) and Nyquist (bin N/2)
            var bodySplit = DSPSplitComplex(realp: splitComplex.realp.advanced(by: 1), imagp: splitComplex.imagp.advanced(by: 1))
            
            magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
                // Compute sqrt(real^2 + imag^2) for bins 1...N/2-1
                vDSP_zvabs(&bodySplit, 1, magPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(bodyCount))
            }
            
            // 7. Store DC and Nyquist magnitudes
            magnitudes[channel][0] = dc
            magnitudes[channel][spectrumSize - 1] = nyquist
                        
            // 6. Apply proper scaling factors
            magnitudes[channel].withUnsafeMutableBufferPointer { magPtr in
                guard let basePtr = magPtr.baseAddress else { return }
                
                // Scale DC with single-sided factor (no doubling)
                var scaleDC = scaleDCNyquist
                vDSP_vsmul(basePtr, 1, &scaleDC, basePtr, 1, 1)
                
                // Scale bins 1...N/2-1 with doubled factor (one-sided spectrum)
                var scaleBody = scaleFactor
                vDSP_vsmul(basePtr.advanced(by: 1), 1, &scaleBody, basePtr.advanced(by: 1), 1, vDSP_Length(bodyCount))
                
                // Scale Nyquist with single-sided factor (no doubling)
                var scaleNyq = scaleDCNyquist
                vDSP_vsmul(basePtr.advanced(by: spectrumSize - 1), 1, &scaleNyq, basePtr.advanced(by: spectrumSize - 1), 1, 1)
            }
            // print("DC bin: \(magnitudes[channel][0])\tNyquist bin: \(magnitudes[channel][spectrumSize - 1])") //
        }
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
