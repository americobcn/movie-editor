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
    weak var delegate:AudioLevelProviderDelegate?
    
    //MARK: Variables
    var numChannels = 0 //setupProcessingTap from mvc set this variable
    var audioProcessingFormat:  AudioStreamBasicDescription?//UnsafePointer<AudioStreamBasicDescription>?
    var audioSampleRate: Float = 0.0
    var allChannelsSpectrum = [Float](repeating: 0.0, count: 20)
    //MARK: Tap and Metering related Variables
    private var tap: Unmanaged<MTAudioProcessingTap>?
    private var fft: TempiFFT!
    
    
    //MARK: GET AUDIO BUFFERS
    func setupProcessingTap(playerItem: AVPlayerItem?, channels: Int) {
        print("setupProcessingTap: tap count: \(tap.debugDescription)")
        numChannels = channels
        
        var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
        init: tapInit,
        finalize: tapFinalize,
        prepare: tapPrepare,
        unprepare: tapUnprepare,
        process: tapProcess)
        
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) //kMTAudioProcessingTapCreationFlag_PreEffects
        
        print("err: \(err)\n")
        if err == noErr {
            print("Tap created succesfully")
        }
        
        let audioTrack = playerItem!.asset.tracks(withMediaType: AVMediaType.audio).first!
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = tap?.takeUnretainedValue() // tap?.takeRetainedValue()
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]
        playerItem!.audioMix = audioMix
    }
    
    //MARK: TAP CALLBACKS
    
    let tapInit: MTAudioProcessingTapInitCallback = {
        (tap, clientInfo, tapStorageOut) in
        tapStorageOut.pointee = clientInfo
                
        print("init \(tap), clientInfo: \(String(describing: clientInfo)), tapStorage: \(tapStorageOut)\n")

        
    }
    
    let tapFinalize: MTAudioProcessingTapFinalizeCallback = {
        (tap) in
        
        print("finalize \(tap)\n")
    }
    
    let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, itemCount, basicDescription) in
        
        print("prepare: \(tap), \(itemCount), \(basicDescription)\n")
        let selfMediaInput = Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
//        selfMediaInput.audioProcessingFormat = AudioStreamBasicDescription(mSampleRate: basicDescription.pointee.mSampleRate,
//                                                                        mFormatID: basicDescription.pointee.mFormatID,
//                                                                           mFormatFlags:basicDescription.pointee.mFormatFlags,
//                                                                           mBytesPerPacket:basicDescription.pointee.mBytesPerPacket,
//                                                                           mFramesPerPacket:basicDescription.pointee.mFramesPerPacket,
//                                                                           mBytesPerFrame:basicDescription.pointee.mBytesPerFrame,
//                                                                           mChannelsPerFrame:basicDescription.pointee.mChannelsPerFrame,
//                                                                           mBitsPerChannel:basicDescription.pointee.mBitsPerChannel,
//                                                                           mReserved:basicDescription.pointee.mReserved)
        selfMediaInput.audioSampleRate = Float(basicDescription.pointee.mSampleRate)
        print("Tap prepare")
    }
    
    let tapUnprepare: MTAudioProcessingTapUnprepareCallback = {
        (tap) in
//        print("unprepare \(tap)\n")
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
//        let numOfBuffers =  Int(audioData.pointee.mNumberBuffers)  // == number of channels
        var chDecibelsAvg = [Float](repeating: 0.0, count: numChannels) // Array to store the average magnitudes of the buffers
        var chDecibelsPeaks = [Float](repeating: 0.0, count: numChannels) // Array to store the peaks magnitudes of the buffers
        var channelsSpectrum = [[Float]]() // Array to store the magnitudes of each frequency band for each channel AKA for each buffer
                
        //Setup processing variables
        let stride = vDSP_Stride(1)
//        let n = vDSP_Length(audioData.pointee.mBuffers.mDataByteSize / UInt32(MemoryLayout<Float>.stride)) //    / audioData.pointee.mNumberBuffers) //
        let n = vDSP_Length(framesNumber)
        var peakLevel: Float = 0.0 // Var to store the current peak. Will be appended to chDecibelsPeaks array
        var avgLevel: Float = 0.0 // Var to store the current average. Will be appended to chDecibelsAvg array

        self.fft = TempiFFT(inSize: framesNumber, inSampleRate: audioSampleRate)
        self.fft.windowType = TempiFFTWindowType.hanning
        
        for (index, buffer) in UnsafeMutableAudioBufferListPointer(audioData).enumerated() { // audioBufferList.enumerated()
            let floatBuffer = buffer.mData?.bindMemory(to: Float.self, capacity: framesNumber) // framesNumber refers to bufferListInOut, all channels buffer data
//            var floatBuffer = buffer.mData?.assumingMemoryBound(to: Float.self)
            
            //Calculate maximun magnitude of the buffer
            vDSP_maxmgv(floatBuffer!, stride, &peakLevel, n) // numElements / UInt(channelsCount)
            if peakLevel < 0.000_000_01 {
                peakLevel = 0.000_000_01   //-160 dB
            }
            //Convert magnitude to decibels
            chDecibelsPeaks[index] = 20*log10(peakLevel)  // Peaks ara amplitude levels, so we use a 20 factor
                        
            //Calculate RMS of the buffer
            vDSP_rmsqv(floatBuffer!, stride, &avgLevel, n) // numElements / UInt(channelsCount)
            if avgLevel < 0.000_000_01 {
                avgLevel = 0.000_000_01  //-160 dB
            }
            //Convert RMS to decibels
            chDecibelsAvg[index] = 10*log10(avgLevel) // Averages are rms, power levels, so we use a 10 factor
            
            /*FFT*/
//            self.fft.fftForward(convertArr(count: Int(framesNumber), data: floatBuffer!))
//            let fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(framesNumber), vDSP_DFT_Direction.FORWARD)!
//            let result = AudioSignalProcessor.fft(data: floatBuffer!, fftSetup: fftSetup , framesNumber: framesNumber)
//            print(result)
            
            self.fft.fftForward(floatBuffer!)
            // Map FFT data to logical bands. This gives 2 bands per octave across 10 octaves = 20 bands.
            fft.calculateLogarithmicBands(minFrequency: 20, maxFrequency: 20480, bandsPerOctave: 2)
            // Process some data
            var mags = [Float](repeating: 0.0, count: fft.numberOfBands)
            for i in 0..<fft.numberOfBands {
                mags[i] = scaleBetween(unscaledNum: TempiFFT.toDB(fft.magnitudeAtBand(i)), minAllowed: -120.0, maxAllowed: 0.0, min: -120.0, max: 55.0)
//                print("Freq:\(fft.frequencyAtBand(i)) M: \(mags[i])")
            }
            channelsSpectrum.append(mags)
            
        }
        
//        vDSP_vadd(channelsSpectrum[0], 1, channelsSpectrum[1], 1, &allChannelsSpectrum, 1, 20)
//        vDSP_vsmul(allChannelsSpectrum, 1, &scalar , &allChannelsSpectrum, 1, 20)
        
        for channel in channelsSpectrum {
            for index in 0..<fft.numberOfBands {
                allChannelsSpectrum[index] += channel[index]/Float(numChannels)
            }
        }
        
        self.delegate?.levelsDidChange(peaks: chDecibelsPeaks, averages: chDecibelsAvg, spectrum: channelsSpectrum, bandsCount: fft.numberOfBands)
        
        
    }
        
    func scaleBetween(unscaledNum: Float, minAllowed: Float, maxAllowed: Float, min: Float, max: Float) -> Float {
      return (maxAllowed - minAllowed) * (unscaledNum - min) / (max - min) + minAllowed;
    }
    
    deinit {
        self.fft = nil
        self.tap?.release()
    }
}
