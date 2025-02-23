//
//  AudioSignalProcessor.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 6/1/22.
//  Copyright © 2022 Américo Cot Toloza. All rights reserved.
//

import Accelerate

class AudioSignalProcessor {
    static func fft(data: UnsafeMutablePointer<Float>, fftSetup: OpaquePointer, framesNumber: Int) -> [Float] {
        let halfSize = framesNumber / 2
        //output setup
        
        var realIn = [Float](repeating: 0, count: framesNumber)
        var imagIn = [Float](repeating: 0, count: framesNumber)
        let realOut = UnsafeMutablePointer<Float>.allocate(capacity: framesNumber)
        let imagOut = UnsafeMutablePointer<Float>.allocate(capacity: framesNumber)
            //fill in real input part with audio samples
        for i in 0..<framesNumber {
            realIn[i] = data[i]
        }
        //Aplyying window
        var window = [Float](repeating: 0, count: framesNumber)
        vDSP_hann_window(&window, UInt(framesNumber), Int32(vDSP_HANN_NORM))
        vDSP_vmul(realIn, 1, window, 1, &realIn, 1, vDSP_Length(framesNumber))
        
        //Executing DFT
        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, realOut, imagOut)
        //our results are now inside realOut and imagOut
        //package it inside a complex vector representation used in the vDSP framework
        var complex = DSPSplitComplex(realp: realOut, imagp: imagOut)
            
        //setup magnitude output
        var magnitudes = [Float](repeating: 0, count: halfSize)
            
        //calculate magnitude results
        vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            
        //normalize
        var normalizedMagnitudes = [Float](repeating: 0.0, count: halfSize)
        var scalingFactor = Float(25.0/Float(halfSize))
        vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, vDSP_Length(halfSize))
        return normalizedMagnitudes
    }
}
