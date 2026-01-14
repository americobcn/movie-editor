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
    
    private var maxFreq: Float
    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 1.0 / 30.0

    // Cache for smoother weighting: each bin maps to two bands with weights
    private struct BinWeighting {
        let lowerBand: Int
        let upperBand: Int
        let lowerWeight: Float
        let upperWeight: Float
    }
    
    private var binWeightings: [BinWeighting]? = nil
    private var cachedBandCount: Int = 0
    private var cachedMinFrequency: Float = 0
    private var cachedMaxFrequency: Float = 0
    private var cachedFFTSize: Int = 0
    private var cachedSampleRate: Float = 0

    // Reusable buffers
    private var bandsBuffer: [Float]? = nil
    private var bandContributionCounts: [Float]? = nil  // Track fractional contributions
    
    init(sampleRate: Float, channelCount: Int, fftSize: Int = 4096, spectrumBands: Int) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.spectrumBands = spectrumBands
        self.chDecibelsPeak = [Float](repeating: 0, count: channelCount)
        self.maxFreq = sampleRate / 2.0
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

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, nFrames: Int) {
        let (magnitudes, peaks) = fftAnalyzer.processAudioBuffer(bufferList, nFrames)
        
        // Convert peaks to dB
        for (idx, peak) in peaks.enumerated() {
            self.chDecibelsPeak[idx] = 20 * log10(max(peak, 1e-8))
        }
        
        guard !magnitudes.isEmpty else { return }
        
        // Build log spectrum from magnitudes
        let spectrum = makeLogSpectrum(magnitudesPerChannel: magnitudes, bandCount: self.spectrumBands, minFrequency: 20.0, maxFrequency: maxFreq, useMax: false)
        
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
        return makeLogSpectrum(
            magnitudesPerChannel: [magnitudes],
            bandCount: bandCount,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency,
            useMax: useMax
        )
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
        let spectrumSize = magnitudesPerChannel[0].count
        
        // CRITICAL: Skip DC (bin 0) AND Nyquist (last bin)
        // Nyquist bin often contains aliasing artifacts and shouldn't be used
        let firstBin = 1
        let lastBin = spectrumSize - 2  // Exclude Nyquist!
        
        // Validate frequency range
        guard minFrequency > 0 && maxFreq > minFrequency else {
            return [Float](repeating: -140.0, count: bandCount)
        }

        // -------- Mapping cache validation --------
        if binWeightings == nil ||
           cachedBandCount != bandCount ||
           cachedMinFrequency != minFrequency ||
           cachedMaxFrequency != maxFreq ||
           cachedFFTSize != fftSize ||
           cachedSampleRate != sampleRate {
            
            rebuildBinWeightings(
                bandCount: bandCount,
                minFrequency: minFrequency,
                maxFrequency: maxFreq,
                spectrumSize: spectrumSize,
                firstBin: firstBin,
                lastBin: lastBin
            )
        }

        guard let weightings = binWeightings else {
            return [Float](repeating: -140.0, count: bandCount)
        }

        // -------- Prepare output buffers --------
        if bandsBuffer == nil || bandsBuffer!.count != bandCount {
            bandsBuffer = [Float](repeating: 0.0, count: bandCount)
            bandContributionCounts = [Float](repeating: 0.0, count: bandCount)
        } else {
            var zero: Float = 0.0
            bandsBuffer!.withUnsafeMutableBufferPointer { ptr in
                vDSP_vfill(&zero, ptr.baseAddress!, 1, vDSP_Length(bandCount))
            }
            bandContributionCounts!.withUnsafeMutableBufferPointer { ptr in
                vDSP_vfill(&zero, ptr.baseAddress!, 1, vDSP_Length(bandCount))
            }
        }

        var bands = bandsBuffer!
        var contributions = bandContributionCounts!
        let channelCount = magnitudesPerChannel.count

        // -------- Aggregate bins with smooth weighting --------
        if useMax {
            // For max mode: accumulate weighted contributions, then find max
            var tempBands = [[Float]](repeating: [Float](repeating: 0.0, count: bandCount), count: channelCount)
            
            for ch in 0..<channelCount {
                let mags = magnitudesPerChannel[ch]
                for bin in firstBin...lastBin {
                    let weighting = weightings[bin]
                    guard weighting.lowerBand >= 0 else { continue }
                    
                    let magnitude = mags[bin]
                    tempBands[ch][weighting.lowerBand] = max(tempBands[ch][weighting.lowerBand], magnitude * weighting.lowerWeight)
                    tempBands[ch][weighting.upperBand] = max(tempBands[ch][weighting.upperBand], magnitude * weighting.upperWeight)
                }
            }
            
            // Take max across channels
            for ch in 0..<channelCount {
                for band in 0..<bandCount {
                    bands[band] = max(bands[band], tempBands[ch][band])
                }
            }
            
        } else {
            // Average mode: weighted sum with proper normalization
            for ch in 0..<channelCount {
                let mags = magnitudesPerChannel[ch]
                for bin in firstBin...lastBin {
                    let weighting = weightings[bin]
                    guard weighting.lowerBand >= 0 else { continue }
                    
                    let magnitude = mags[bin]
                    
                    // Contribute to lower band
                    bands[weighting.lowerBand] += magnitude * weighting.lowerWeight
                    contributions[weighting.lowerBand] += weighting.lowerWeight
                    
                    // Contribute to upper band
                    bands[weighting.upperBand] += magnitude * weighting.upperWeight
                    contributions[weighting.upperBand] += weighting.upperWeight
                }
            }
            
            // Normalize by total contributions and channel count
            let channelScale = 1.0 / Float(channelCount)
            for i in 0..<bandCount {
                if contributions[i] > 0 {
                    bands[i] = (bands[i] / contributions[i]) * channelScale
                } else {
                    bands[i] = 0.0
                }
            }
        }

        // -------- Convert to dB --------
        var result = bands
        
        // Floor to prevent log(0) - approximately -240 dBFS
        var floor: Float = 1.0e-12
        result.withUnsafeMutableBufferPointer { ptr in
            vDSP_vthr(ptr.baseAddress!, 1, &floor, ptr.baseAddress!, 1, vDSP_Length(bandCount))
        }
        
        // Convert to dB: 20·log10(x / reference)
        var reference: Float = 1.0
        vDSP_vdbcon(result, 1, &reference, &result, 1, vDSP_Length(bandCount), 0)

        bandsBuffer = bands
        return result
    }
    
    /// Rebuild the bin weighting map with smooth logarithmic transitions
    private func rebuildBinWeightings(
        bandCount: Int,
        minFrequency: Float,
        maxFrequency: Float,
        spectrumSize: Int,
        firstBin: Int,
        lastBin: Int
    ) {
        let binResolution = sampleRate / Float(fftSize)
        let logMin = log10(minFrequency)
        let logMax = log10(maxFrequency)
        let logRange = logMax - logMin
        
        guard logRange > 0 else {
            print("Invalid frequency range for log spectrum")
            return
        }
        
        var weightings = [BinWeighting](
            repeating: BinWeighting(lowerBand: -1, upperBand: -1, lowerWeight: 0, upperWeight: 0),
            count: spectrumSize
        )
        
        var totalContributions = [Float](repeating: 0.0, count: bandCount)
        var binsPerBand = [Int](repeating: 0, count: bandCount)
        
        // Calculate smooth weightings for each bin
        for bin in firstBin...lastBin {
            let frequency = Float(bin) * binResolution
            
            // Only include bins within our frequency range
            guard frequency >= minFrequency && frequency <= maxFrequency else {
                continue
            }
            
            // Calculate continuous band position (can be fractional)
            let normalizedLog = (log10(frequency) - logMin) / logRange
            let clamped = min(max(normalizedLog, 0.0), 0.9999)
            let continuousBand = clamped * Float(bandCount)
            
            // Split contribution between two adjacent bands
            let lowerBand = Int(continuousBand)
            let upperBand = min(lowerBand + 1, bandCount - 1)
            let fraction = continuousBand - Float(lowerBand)
            
            let lowerWeight = 1.0 - fraction
            let upperWeight = fraction
            
            weightings[bin] = BinWeighting(
                lowerBand: lowerBand,
                upperBand: upperBand,
                lowerWeight: lowerWeight,
                upperWeight: upperWeight
            )
            
            // Track contributions for debugging
            totalContributions[lowerBand] += lowerWeight
            totalContributions[upperBand] += upperWeight
            binsPerBand[lowerBand] += 1
            if fraction > 0.01 {  // Count bin as contributing to upper band if weight > 1%
                binsPerBand[upperBand] += 1
            }
        }
        
        self.binWeightings = weightings
        self.cachedBandCount = bandCount
        self.cachedMinFrequency = minFrequency
        self.cachedMaxFrequency = maxFrequency
        self.cachedFFTSize = fftSize
        self.cachedSampleRate = sampleRate
        
        print("""
        Log spectrum smooth weighting created:
        - Bands: \(bandCount)
        - Frequency range: \(minFrequency)-\(maxFrequency) Hz
        - Total bins mapped: \(lastBin - firstBin + 1)
        - Bins contributing per band: \(binsPerBand)
        - Total weighted contributions: \(totalContributions.map { String(format: "%.1f", $0) })
        """)
    }
}

// MARK: - Tap Callbacks

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
    
    context.processor.process(bufferList: bufferListInOut, nFrames: Int(numberFramesOut.pointee))
}

func createAudioProcessingTap(
    processor: AudioTapProcessor
) throws -> MTAudioProcessingTap { // Unmanaged<MTAudioProcessingTap>
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
    
    var tap: MTAudioProcessingTap? //Unmanaged<MTAudioProcessingTap>?
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

