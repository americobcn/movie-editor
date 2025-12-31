//
//  TempiFFT.swift
//  TempiBeatDetection
//
//  Created by John Scalo on 1/12/16.
//  Copyright © 2016 John Scalo. See accompanying License.txt for terms.

/*  A functional FFT built atop Apple's Accelerate framework for optimum performance on any device. In addition to simply performing the FFT and providing access to the resulting data, TempiFFT provides the ability to map the FFT spectrum data into logical bands, either linear or logarithmic, for further analysis.

E.g.

let fft = TempiFFT(withSize: frameSize, sampleRate: 44100)

// Setting a window type reduces errors
fft.windowType = TempiFFTWindowType.hanning

// Perform the FFT
fft.fftForward(samples)

// Map FFT data to logical bands. This gives 4 bands per octave across 7 octaves = 28 bands.
fft.calculateLogarithmicBands(minFrequency: 100, maxFrequency: 11025, bandsPerOctave: 4)

// Process some data
for i in 0..<fft.numberOfBands {
let f = fft.frequencyAtBand(i)
let m = fft.magnitudeAtBand(i)
}
 
Note that TempiFFT expects a mono signal (i.e. numChannels == 1) which is ideal for performance.
*/

import Foundation
import Accelerate

@objc enum TempiFFTWindowType: NSInteger {
    case none
    case hanning
    case hamming
}

@objc class TempiFFT : NSObject {
    
    /// The length of the sample buffer we'll be analyzing.
    private(set) var size: Int
    
    /// The sample rate provided at init time.
    private(set) var sampleRate: Float
    
    /// The Nyquist frequency is ```sampleRate``` / 2
    var nyquistFrequency: Float {
        get {
            return sampleRate / 2.0
        }
    }
    
    // After performing the FFT, contains size/2 magnitudes, one for each frequency band.
    private var magnitudes: [Float] = []
    
    /// After calling calculateLinearBands() or calculateLogarithmicBands(), contains a magnitude for each band.
    private(set) var bandMagnitudes: [Float]!
    
    /// After calling calculateLinearBands() or calculateLogarithmicBands(), contains the average frequency for each band
    private(set) var bandFrequencies: [Float]!
    
    /// The average bandwidth throughout the spectrum (nyquist / magnitudes.count)
    var bandwidth: Float {
        get {
            return self.nyquistFrequency / Float(self.magnitudes.count)
        }
    }
    
    /// The number of calculated bands (must call calculateLinearBands() or calculateLogarithmicBands() first).
    private(set) var numberOfBands: Int = 0
    
    /// The minimum and maximum frequencies in the calculated band spectrum (must call calculateLinearBands() or calculateLogarithmicBands() first).
    private(set) var bandMinFreq, bandMaxFreq: Float!
    
    /// Supplying a window type (hanning or hamming) smooths the edges of the incoming waveform and reduces output errors from the FFT function (aka "spectral leakage" - ewww).
    var windowType = TempiFFTWindowType.none
    
    private var halfSize:Int
    private var log2Size:Int
    private var window:[Float] = []
    private var fftSetup:FFTSetup
    private var hasPerformedFFT: Bool = false
    private var complexBuffer: DSPSplitComplex!
    private var analysisBuffer: UnsafeMutablePointer<Float>!
    
    // Instantiate the FFT.
    // - Parameter size: The length of the sample buffer we'll be analyzing. Must be a power of 2. The resulting ```magnitudes``` are of length ```inSize/2```.
    // - Parameter sampleRate: Sampling rate of the provided audio data.
    init(size:Int, sampleRate: Float) {
        let sizeFloat = Float(size)
        self.sampleRate = sampleRate
        
        // Check if the size is a power of two
        let lg2 = logbf(sizeFloat)
        assert(remainderf(sizeFloat, powf(2.0, lg2)) == 0, "size must be a power of 2")
        
        self.size = size
        self.halfSize = size / 2
        
        // create fft setup
        self.log2Size = Int(log2f(sizeFloat))
        self.fftSetup = vDSP_create_fftsetup(UInt(log2Size), FFTRadix(FFT_RADIX2))!
            
        // Init the complexBuffer
        let real = UnsafeMutablePointer<Float>.allocate(capacity: self.halfSize) //= DSPSplitComplex(realp: reals, imagp: imags)
        let imaginary = UnsafeMutablePointer<Float>.allocate(capacity: self.halfSize)
        self.complexBuffer = DSPSplitComplex(realp: real, imagp: imaginary)
    }
    
    
    deinit {
        // destroy the fft setup object
        vDSP_destroy_fftsetup(fftSetup)
        complexBuffer.realp.deallocate()
        complexBuffer.imagp.deallocate()
        analysisBuffer?.deallocate()
    }
    
    
    // Perform a forward FFT on the provided single-channel audio data. When complete, the instance can be queried for information about the analysis or the magnitudes can be accessed directly.
    // - Parameter inMonoBuffer: Audio data in mono format

    func fftForward(_ inMonoBuffer: UnsafePointer<Float>) {
        analysisBuffer?.deallocate()
        analysisBuffer = UnsafeMutablePointer<Float>.allocate(capacity: self.size)
            
        if self.windowType != .none {
            // Setup Window
            if self.window.isEmpty {
                self.window = [Float](repeating: 0.0, count: size)
                switch self.windowType {
                case .hamming:
                    print("Hamming window")
                    vDSP_hamm_window(&self.window, UInt(size), 0)
                case .hanning:
                    print("Hann window")
                    vDSP_hann_window(&self.window, UInt(size), Int32(vDSP_HANN_NORM))
                default:
                    break
                }
            }
            // Apply the window
            vDSP_vmul(inMonoBuffer, 1, self.window, 1, analysisBuffer, 1, vDSP_Length(self.size))
        }
        

        analysisBuffer.withMemoryRebound(to: DSPComplex.self, capacity: self.size, { buf in
            vDSP_ctoz(buf, 2, &self.complexBuffer!, 1, vDSP_Length(self.halfSize))
            // buf.deallocate()
        })
                  
        // Perform a forward FFT
        vDSP_fft_zrip(self.fftSetup, &(self.complexBuffer!), 1, UInt(self.log2Size), Int32(FFT_FORWARD))                
        
        // Store and square (for better visualization & conversion to db) the magnitudes
        self.magnitudes = [Float](repeating: 0.0, count: self.halfSize)
        vDSP_zvmags(&(self.complexBuffer!), 1, &self.magnitudes, 1, UInt(self.halfSize))
        
        
        self.hasPerformedFFT = true
    }
    
    /// Applies logical banding on top of the spectrum data. The bands are spaced linearly throughout the spectrum.
    func calculateLinearBands(minFrequency: Float, maxFrequency: Float, numberOfBands: Int) {
        assert(hasPerformedFFT, "*** Perform the FFT first.")
        
        let actualMaxFrequency = min(self.nyquistFrequency, maxFrequency)
        
        self.numberOfBands = numberOfBands
        self.bandMagnitudes = [Float](repeating: 0.0, count: numberOfBands)
        self.bandFrequencies = [Float](repeating: 0.0, count: numberOfBands)
        
        let magLowerRange = magIndexForFreq(minFrequency)
        let magUpperRange = magIndexForFreq(actualMaxFrequency)
        let ratio: Float = Float(magUpperRange - magLowerRange) / Float(numberOfBands)
        
        for i in 0..<numberOfBands {
            let magsStartIdx: Int = Int(floorf(Float(i) * ratio)) + magLowerRange
            let magsEndIdx: Int = Int(floorf(Float(i + 1) * ratio)) + magLowerRange
            var magsAvg: Float
            if magsEndIdx == magsStartIdx {
                // Can happen when numberOfBands < # of magnitudes. No need to average anything.
                magsAvg = self.magnitudes[magsStartIdx]
            } else {
                magsAvg = fastAverage(self.magnitudes, magsStartIdx, magsEndIdx)
            }
            self.bandMagnitudes[i] = magsAvg
            self.bandFrequencies[i] = self.averageFrequencyInRange(magsStartIdx, magsEndIdx)
        }
        
        self.bandMinFreq = self.bandFrequencies[0]
        self.bandMaxFreq = self.bandFrequencies.last
    }
    
    /// Applies logical banding on top of the spectrum data. The bands are grouped by octave throughout the spectrum. Note that the actual min and max frequencies in the resulting band may be lower/higher than the minFrequency/maxFrequency because the band spectrum <i>includes</i> those frequencies but isn't necessarily bounded by them.
    func calculateLogarithmicBands(minFrequency: Float, maxFrequency: Float, bandsPerOctave: Int) {
        assert(hasPerformedFFT, "*** Perform the FFT first.")
        
        // The max can't be any higher than the nyquist
        let actualMaxFrequency = min(self.nyquistFrequency, maxFrequency)
        
        // The min can't be 0 otherwise we'll divide octaves infinitely
        let actualMinFrequency = max(1, minFrequency)
        
        // Define the octave frequencies we'll be working with. Note that in order to always include minFrequency, we'll have to set the lower boundary to the octave just below that frequency.
        var octaveBoundaryFreqs: [Float] = [Float]()
        var curFreq = actualMaxFrequency
        octaveBoundaryFreqs.append(curFreq)
        repeat {
            curFreq /= 2
            octaveBoundaryFreqs.append(curFreq)
        } while curFreq > actualMinFrequency
        
        octaveBoundaryFreqs = octaveBoundaryFreqs.reversed()
//        print(octaveBoundaryFreqs)
        
        self.bandMagnitudes = [Float]()
        self.bandFrequencies = [Float]()
        
        // Break up the spectrum by octave
        for i in 0..<octaveBoundaryFreqs.count - 1 {
            let lowerFreq = octaveBoundaryFreqs[i]
            let upperFreq = octaveBoundaryFreqs[i+1]
            
            let mags = self.magsInFreqRange(lowerFreq, upperFreq)
            let ratio =  Float(mags.count) / Float(bandsPerOctave)
            
            // Now that we have the magnitudes within this octave, cluster them into bandsPerOctave groups and average each group.
            for j in 0..<bandsPerOctave {
                let startIdx = Int(ratio * Float(j))
                var stopIdx = Int(ratio * Float(j+1)) - 1 // inclusive
                
                stopIdx = max(0, stopIdx)
                
                if stopIdx <= startIdx {
                    self.bandMagnitudes.append(mags[startIdx])
                } else {
                    let avg = fastAverage(mags, startIdx, stopIdx + 1)
                    self.bandMagnitudes.append(avg)
                }
                
                let startMagnitudesIdx = Int(lowerFreq / self.bandwidth) + startIdx
                let endMagnitudesIdx = startMagnitudesIdx + (stopIdx - startIdx)
                self.bandFrequencies.append(self.averageFrequencyInRange(startMagnitudesIdx, endMagnitudesIdx))
            }
        }
        
        self.numberOfBands = self.bandMagnitudes.count
        self.bandMinFreq = self.bandFrequencies[0]
        self.bandMaxFreq = self.bandFrequencies.last
    }
    
    private func magIndexForFreq(_ freq: Float) -> Int {
        return Int(Float(self.magnitudes.count) * freq / self.nyquistFrequency)
    }
    
    // On arrays of 1024 elements, this is ~35x faster than an iterational algorithm. Thanks Accelerate.framework!
    @inline(__always) private func fastAverage(_ array:UnsafePointer<Float>, _ startIdx: Int, _ stopIdx: Int) -> Float {
        var mean: Float = 0.0
        vDSP_meanv(array + startIdx, 1, &mean, UInt(stopIdx - startIdx))
        return mean
    }
    
    
    @inline(__always) private func fastAverage(_ startIdx: Int, _ stopIdx: Int) -> Float {
            var mean: Float = 0.0
            vDSP_meanv(magnitudes, startIdx, &mean, vDSP_Length(stopIdx - startIdx))
            return mean
    }
    
    
    @inline(__always) private func magsInFreqRange(_ lowFreq: Float, _ highFreq: Float) -> [Float] {
        let lowIndex = Int(lowFreq / self.bandwidth)
        var highIndex = Int(highFreq / self.bandwidth)
        
        if (lowIndex == highIndex) {
            // Occurs when both params are so small that they both fall into the first index
            highIndex += 1
        }
        
        return Array(self.magnitudes[lowIndex..<highIndex])
    }
    
    @inline(__always) private func averageFrequencyInRange(_ startIndex: Int, _ endIndex: Int) -> Float {
        return (self.bandwidth * Float(startIndex) + self.bandwidth * Float(endIndex)) / 2
    }
    
    /// Get the magnitude for the specified frequency band.
    /// - Parameter inBand: The frequency band you want a magnitude for.
    func magnitudeAtBand(_ inBand: Int) -> Float {
        assert(hasPerformedFFT, "*** Perform the FFT first.")
        assert(bandMagnitudes != nil, "*** Call calculateLinearBands() or calculateLogarithmicBands() first")
        
        return bandMagnitudes[inBand]
    }
    
    /// Get the magnitude of the requested frequency in the spectrum.
    /// - Parameter inFrequency: The requested frequency. Must be less than the Nyquist frequency (```sampleRate/2```).
    /// - Returns: A magnitude.
    func magnitudeAtFrequency(_ inFrequency: Float) -> Float {
        assert(hasPerformedFFT, "*** Perform the FFT first.")
        let index = Int(floorf(inFrequency / self.bandwidth ))
        return self.magnitudes[index]
    }
    
    /// Get the middle frequency of the Nth band.
    /// - Parameter inBand: An index where 0 <= inBand < size / 2.
    /// - Returns: The middle frequency of the provided band.
    func frequencyAtBand(_ inBand: Int) -> Float {
        assert(hasPerformedFFT, "*** Perform the FFT first.")
        assert(bandMagnitudes != nil, "*** Call calculateLinearBands() or calculateLogarithmicBands() first")
        return self.bandFrequencies[inBand]
    }
    
    /// Calculate the average magnitude of the frequency band bounded by lowFreq and highFreq, inclusive
    func averageMagnitude(lowFreq: Float, highFreq: Float) -> Float {
        let lowIndex = Int(lowFreq / bandwidth)
        let highIndex = Int(highFreq / bandwidth)
        return fastAverage(lowIndex, min(highIndex + 1, magnitudes.count))
        
    }
    
    /// Sum magnitudes across bands bounded by lowFreq and highFreq, inclusive
    func sumMagnitudes(lowFreq: Float, highFreq: Float, useDB: Bool) -> Float {
        
        var curFreq = lowFreq
        var total: Float = 0
        while curFreq <= highFreq {
            var mag = magnitudeAtFrequency(curFreq)
            if (useDB) {
                mag = max(0, TempiFFT.toDB(mag))
            }
            total += mag
            curFreq += self.bandwidth
        }
        
        return total
    }
    
    /// A convenience function that converts a linear magnitude (like those stored in ```magnitudes```) to db (which is log 10).
    class func toDB(_ inMagnitude: Float) -> Float {
        // ceil to 128db in order to avoid log10'ing 0
        let magnitude = max(inMagnitude, 0.000000000001)
        return 10 * log10f(magnitude)
    }

}
