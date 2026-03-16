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
    private var windowedScratch: UnsafeMutablePointer<Float>

    
    private var magnitudes: [[Float]]
    private var channelsPeak: [Float]
    private let processingLock = NSLock()

    // MARK: - Errors
    
    enum FFTError: Error {
        case setupFailed
        case invalidBufferSize
        case channelCountMismatch(expected: Int, actual: UInt32)
    }
    
    // MARK: - Initialization

    init(fftSize: Int, sampleRate: Float, chCount: Int) throws {
        precondition(fftSize.isPowerOfTwo, "FFT size must be a power of two")

        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.spectrumSize = (fftSize / 2) + 1
        
        self.channelsPeak = [Float](repeating: 0, count: chCount)
        
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw FFTError.setupFailed
        }
        self.fftSetup = setup
        
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
        
        let halfSize = fftSize / 2
        self.realp = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        self.imagp = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        self.realp.initialize(repeating: 0, count: halfSize)
        self.imagp.initialize(repeating: 0, count: halfSize)
        self.splitComplex = DSPSplitComplex(realp: realp, imagp: imagp)
        self.windowedScratch = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        self.windowedScratch.initialize(repeating: 0, count: fftSize)
    }

    deinit {
        let halfSize = fftSize / 2
        realp.deinitialize(count: halfSize)
        realp.deallocate()
        imagp.deinitialize(count: halfSize)
        imagp.deallocate()
        windowedScratch.deinitialize(count: fftSize)
        windowedScratch.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Processing Entry Point

    /// Process audio buffer from MTAudioProcessingTap callback
    /// - Parameters:
    ///   - bufferList: Audio buffer list from the tap
    ///   - framesIn: Number of frames in the buffer
    /// - Returns: Tuple of (magnitudes per channel, peak levels per channel)
    func processAudioBuffer(_ bufferList: UnsafeMutablePointer<AudioBufferList>, _ framesIn: Int) -> ([[Float]], [Float]) {
        if bufferList.pointee.mNumberBuffers != magnitudes.count {
            assertionFailure("Channel count mismatch: expected \(magnitudes.count), got \(bufferList.pointee.mNumberBuffers)")
            return ([], [])
        }
        
        processingLock.lock()
        defer { processingLock.unlock() }

        for (channel, audioBuffer) in UnsafeMutableAudioBufferListPointer(bufferList).enumerated() {
            let requiredBytes = framesIn * MemoryLayout<Float>.stride
            guard audioBuffer.mDataByteSize >= requiredBytes else {
                print("Warning: Buffer too small. Expected \(requiredBytes) bytes, got \(audioBuffer.mDataByteSize)")
                continue
            }
            guard let floatBuffer = audioBuffer.mData?.bindMemory(to: Float.self, capacity: framesIn) else {
                continue  // Skip this channel if buffer is invalid
            }

            //Calculate maximun amplitude of the buffer
            var peak: Float = 0
            vDSP_maxmgv(floatBuffer, 1, &peak, vDSP_Length(framesIn))
            self.channelsPeak[channel] = peak

            /// CALCULATE FFT
            // 1. Apply Hann window into scratch buffer
            let samplesToProcess = min(framesIn, fftSize)
            vDSP_vmul(floatBuffer, 1, hannWindow, 1, windowedScratch, 1, vDSP_Length(samplesToProcess))

            // 2. Zero-pad scratch buffer if needed
            if samplesToProcess < fftSize {
                vDSP_vclr(windowedScratch.advanced(by: samplesToProcess), 1, vDSP_Length(fftSize - samplesToProcess))
            }

            // 3. Pack into split-complex format: realp[k] = x[2k], imagp[k] = x[2k+1]
            let scratchAsComplex = UnsafePointer<DSPComplex>(OpaquePointer(windowedScratch))
            vDSP_ctoz(scratchAsComplex, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                                    
            // 4. Perform in-place real-to-complex FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                            
            
            
            // 5. Extract DC and Nyquist (stored in packed format by vDSP)
            // After vDSP_fft_zrip: DC is in realp[0], Nyquist is in imagp[0]
            let dc = abs(splitComplex.realp[0])
            let nyquist = abs(splitComplex.imagp[0])            
            
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
                        
            // 7. Apply proper scaling factors
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
        return (magnitudes.map { $0 }, Array(channelsPeak))
    }
    
    func frequency(at index: Int) -> Float {
        return Float(index) * sampleRate / Float(fftSize)
    }
}


extension Int {
    var isPowerOfTwo: Bool {
        (self & (self - 1)) == 0 && self > 0
    }
}
