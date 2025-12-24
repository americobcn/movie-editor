//
//  TapProcessor.swift
//  Movie Editor
//
//  Created by Américo Cot on 08/12/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Accelerate
import MediaToolbox

// Protocol to be adopted by object providing peak and average power levels.

protocol AudioLevelProviderDelegate: class {
    func levelsDidChange(peaks:[Float], averages:[Float], spectrum: [[Float]], bandsCount: Int)
}

class TapProcessor: NSObject {
    //MARK: Delegate variable
    var delegate:AudioLevelProviderDelegate?
    
    //MARK: Variables
    var numChannels:Int = 0
    var audioSampleRate: Float = 44100.0
    var maxFrames: Int = 0
    let stride = vDSP_Stride(1)
    var peakLevel: Float = 0.0
    var avgLevel: Float = 0.0
    var allChannelsSpectrum = [Float](repeating: 0.0, count: 20)
    weak var playerItem: AVPlayerItem?
    
    private var tap: MTAudioProcessingTap?  // Unmanaged<MTAudioProcessingTap>?
    private var fft: TempiFFT!
    private var magnitudesBuffer: [Float]!
    private var minFreq: Float = 20
    private var maxFreq: Float = 20480
    private var bandsPerOctave: Int = 2

    var chDecibelsAvg:[Float] = []      // Array to store the average magnitudes of the buffers
    var chDecibelsPeaks:[Float] = []    // Array to store the peaks magnitudes of the buffers
    var channelsSpectrum = [[Float]]()
    
    
    //MARK: Initialization
    override init() {
        super.init()
    }
    
    convenience init(playerItem: AVPlayerItem, channels: Int, sampleRate: Float) { //
        self.init()
        
        self.numChannels = channels
        self.audioSampleRate = sampleRate
        self.playerItem = playerItem        
    }
    
    
    @MainActor
    func setupProcessingTap() async {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            //clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) //kMTAudioProcessingTapCreationFlag_PreEffects
        print("MTAudioProcessingTapCreate error: \(err)\n")
                
        do {
            let audioTrack = try await playerItem?.asset.loadTracks(withMediaType: .audio).first
            let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
            inputParams.audioTapProcessor = tap //?.takeUnretainedValue() // tap?.takeRetainedValue()
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]
            playerItem?.audioMix = audioMix
            
        } catch {
            print("Error loading audio track on TapProcessor: \(error)")
        }
    }
    
    //MARK: TAP CALLBACKS
    let tapInit: MTAudioProcessingTapInitCallback = {
        (tap, clientInfo, tapStorageOut) in
        tapStorageOut.pointee = clientInfo //clientInfo
        print("TapProcessor: init \(tap)\nclientInfo: \(String(describing: clientInfo))\ntapStorage: \(tapStorageOut)\n")
    }
    
    let tapFinalize: MTAudioProcessingTapFinalizeCallback = {
        (tap) in
        // Release the retained reference
            let _ = Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeRetainedValue()
        print("TapProcessor: finalize \(tap)\n")
    }
    
    let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, maxFrames, processingFormat) in
        let selfMediaInput = Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        selfMediaInput.audioSampleRate = Float(processingFormat.pointee.mSampleRate)
        selfMediaInput.numChannels = Int(processingFormat.pointee.mChannelsPerFrame)
        
        selfMediaInput.chDecibelsAvg = [Float](repeating: 0.0, count: selfMediaInput.numChannels)
        selfMediaInput.chDecibelsPeaks = [Float](repeating: 0.0, count: selfMediaInput.numChannels)
        
        selfMediaInput.fft = TempiFFT(size: maxFrames, sampleRate: selfMediaInput.audioSampleRate)
        selfMediaInput.fft.windowType = .hanning        
        print("TapProcessor: prepare: \(tap), \ncount: \(maxFrames), \ndescription(ASBD):\(processingFormat)\nSampleRate: \(processingFormat.pointee.mSampleRate)\n)")
    }
    
    let tapUnprepare: MTAudioProcessingTapUnprepareCallback = {
        (tap) in
        print("TapProcessor: unprepare \(tap)\n")
    }
    
    
    let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        let selfMediaInput = Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        if status != noErr {
            print("Error TAPGetSourceAudio :\(String(describing: status.description))")
            return
        }        
        selfMediaInput.processAudioData(audioData: bufferListInOut, framesNumber: numberFrames)
    }
    
    
    @inline(__always) func processAudioData(audioData: UnsafeMutablePointer<AudioBufferList>, framesNumber: Int) {
        //Create array to store the processed values
        self.channelsSpectrum = [[Float]]() // Array to store the magnitudes of each frequency band for each channel AKA for eac
        let n = vDSP_Length(framesNumber)
                
        for (channel, buffer) in UnsafeMutableAudioBufferListPointer(audioData).enumerated() { // audioBufferList.enumerated()
            let floatBuffer = buffer.mData?.bindMemory(to: Float.self, capacity: framesNumber) // framesNumber refers to bufferListInOut, all channels buffer data
            
            //Calculate maximun magnitude of the buffer
            vDSP_maxmgv(floatBuffer!, stride, &peakLevel, n) // numElements / UInt(channelsCount)
            if peakLevel < 0.000_000_01 {
                peakLevel = 0.000_000_01   //-160 dB
            }
            //Convert magnitude to decibels
            self.chDecibelsPeaks[channel] = TempiFFT.toDB(peakLevel)   //20*log10(peakLevel)  // Peaks ara amplitude levels, so we use a 20 factor
            
            //Calculate RMS of the buffer
            vDSP_rmsqv(floatBuffer!, stride, &avgLevel, n) // numElements / UInt(channelsCount)
            if avgLevel < 0.000_000_01 {
                avgLevel = 0.000_000_01  //-160 dB
            }
            //Convert RMS to decibels
            self.chDecibelsAvg[channel] = TempiFFT.toDB(avgLevel)// 10*log10(avgLevel) // Averages are rms, power levels, so we use a 10 factor
            
            // Calculate FFT
            self.fft.fftForward(floatBuffer!)
            
            // Map FFT data to logical bands. This gives 2 bands per octave across 10 octaves = 20 bands.
            self.fft.calculateLogarithmicBands(minFrequency: self.minFreq, maxFrequency: self.maxFreq , bandsPerOctave: self.bandsPerOctave)
            
            // Process some data
            self.magnitudesBuffer = [Float](repeating: 0.0, count: fft.numberOfBands)
            for i in 0..<fft.numberOfBands {
                magnitudesBuffer[i] = scaleBetween(unscaledNum: TempiFFT.toDB(fft.magnitudeAtBand(i)), minAllowed: -120.0, maxAllowed: 0.0, min: -120.0, max: 55.0)

            }
            self.channelsSpectrum.append(magnitudesBuffer)
        }
                
        for channel in self.channelsSpectrum {
            for band in 0..<fft.numberOfBands {
                allChannelsSpectrum[band] += channel[band]/Float(numChannels)
            }
        }

        self.delegate?.levelsDidChange(peaks: self.chDecibelsPeaks, averages: self.chDecibelsAvg, spectrum: self.channelsSpectrum, bandsCount: self.fft.numberOfBands)
        
    }
        
    func scaleBetween(unscaledNum: Float, minAllowed: Float, maxAllowed: Float, min: Float, max: Float) -> Float {
      return (maxAllowed - minAllowed) * (unscaledNum - min) / (max - min) + minAllowed;
    }
    
    
    //MARK: deinit
    // deinit {
    //     print("TapProcesor deinit() called")
    //     // self.fft = nil
    //     // self.tap?.release()
    // }
}
