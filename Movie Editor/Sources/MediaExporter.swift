//
//  MediaExporter.swift
//  Movie Editor
//
//  Created by Americo Cot on 15/12/25.
//  Copyright © 2025 Américo Cot Toloza. All rights reserved.
//

import AVFoundation
import AppKit

class MediaExporter {
    
    // MARK: - Properties
    private var assetReader: AVAssetReader?
    private var assetWriter: AVAssetWriter?
    private var progressIndicator: NSProgressIndicator
    
    // MARK: - Initialization
    init(progressIndicator: NSProgressIndicator) {
        self.progressIndicator = progressIndicator
    }
    
    // MARK: - Main Export Function
    func exportMedia(from inputAsset: AVAsset, to destURL: URL) async throws -> URL {
        // Setup reader and writer
        let assetReader = try AVAssetReader(asset: inputAsset)
        let assetWriter = try AVAssetWriter(outputURL: destURL, fileType: .mov)
        
        self.assetReader = assetReader
        self.assetWriter = assetWriter
        
        // Load tracks
        let videoTrack = try await inputAsset.loadTracks(withMediaType: .video).first
        let audioTrack = try? await inputAsset.loadTracks(withMediaType: .audio).first
        
        guard let videoTrack = videoTrack else {
            throw ExportError.noVideoTrack
        }
        
        // Setup video processing
        let videoConfig = try await setupVideoProcessing(
            videoTrack: videoTrack,
            assetReader: assetReader,
            assetWriter: assetWriter
        )
        
        // Setup audio processing (if available)
        let audioConfig = try? await setupAudioProcessing(
            audioTrack: audioTrack!,
            assetReader: assetReader,
            assetWriter: assetWriter
        )
        
        // Start processing
        assetWriter.startWriting()
        assetReader.startReading()
        assetWriter.startSession(atSourceTime: .zero)
        
        // Process media asynchronously
        return try await withCheckedThrowingContinuation { continuation in
            var audioFinished = audioConfig == nil // If no audio, mark as finished
            var videoFinished = false
            
            let finishHandler = { [weak self] in
                guard let self = self else { return }
                
                if audioFinished && videoFinished {
                    self.finishWriting(continuation: continuation)
                }
            }
            
            // Process audio if available
            if let audioConfig = audioConfig {
                processAudio(
                    config: audioConfig,
                    onFinish: {
                        DispatchQueue.main.async {
                            audioFinished = true
                            finishHandler()
                        }
                    }
                )
            }
            
            // Process video
            processVideo(
                config: videoConfig,
                onFinish: {
                    DispatchQueue.main.async {
                        videoFinished = true
                        finishHandler()
                    }
                }
            )
        }
    }
    
    // MARK: - Video Setup
    private func setupVideoProcessing(
        videoTrack: AVAssetTrack,
        assetReader: AVAssetReader,
        assetWriter: AVAssetWriter
    ) async throws -> MediaProcessingConfig {
        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        
        guard assetReader.canAdd(trackOutput) else {
            throw ExportError.cannotAddVideoOutput
        }
        assetReader.add(trackOutput)
        
        let formatDesc = try await videoTrack.load(.formatDescriptions).first
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: formatDesc
        )
        
        guard assetWriter.canAdd(writerInput) else {
            throw ExportError.cannotAddVideoInput
        }
        assetWriter.add(writerInput)
        
        let queue = DispatchQueue(label: "com.mediaexporter.video")
        
        return MediaProcessingConfig(
            input: writerInput,
            output: trackOutput,
            queue: queue
        )
    }
    
    // MARK: - Audio Setup
    private func setupAudioProcessing(
        audioTrack: AVAssetTrack?,
        assetReader: AVAssetReader,
        assetWriter: AVAssetWriter
    ) async throws -> MediaProcessingConfig {
        guard let audioTrack = audioTrack else {
            throw ExportError.noAudioTrack
        }
        
        let formatDesc = try await audioTrack.load(.formatDescriptions).first
        guard let formatDesc = formatDesc else {
            throw ExportError.noAudioFormatDescription
        }
        
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            throw ExportError.invalidAudioFormat
        }
        
        let sampleRate = Float(asbd.pointee.mSampleRate)
        let channelsPerFrame = Int(asbd.pointee.mChannelsPerFrame)
        var bitsPerChannel = Int(asbd.pointee.mBitsPerChannel)
        
        if bitsPerChannel == 0 {
            bitsPerChannel = 24
        }
        
        // Reader settings
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelsPerFrame,
            AVLinearPCMBitDepthKey: bitsPerChannel,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        
        guard assetReader.canAdd(trackOutput) else {
            throw ExportError.cannotAddAudioOutput
        }
        assetReader.add(trackOutput)
        
        // Writer settings
        let bitRate = calculateAudioBitRate(channels: channelsPerFrame)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelsPerFrame,
            AVEncoderBitRateKey: bitRate,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        
        guard assetWriter.canAdd(writerInput) else {
            throw ExportError.cannotAddAudioInput
        }
        assetWriter.add(writerInput)
        
        let queue = DispatchQueue(label: "com.mediaexporter.audio")
        
        return MediaProcessingConfig(
            input: writerInput,
            output: trackOutput,
            queue: queue
        )
    }
    
    // MARK: - Processing
    private func processVideo(config: MediaProcessingConfig, onFinish: @escaping () -> Void) {
        let input = config.input
        let output = config.output
        
        input.requestMediaDataWhenReady(on: config.queue) {
            while input.isReadyForMoreMediaData {
                if let sampleBuffer = output.copyNextSampleBuffer() {
                    input.append(sampleBuffer)
                } else {
                    input.markAsFinished()
                    onFinish()
                    break
                }
            }
        }
    }
    
    private func processAudio(config: MediaProcessingConfig, onFinish: @escaping () -> Void) {
        let input = config.input
        let output = config.output
        
        input.requestMediaDataWhenReady(on: config.queue) {
            while input.isReadyForMoreMediaData {
                if let sampleBuffer = output.copyNextSampleBuffer() {
                    input.append(sampleBuffer)
                } else {
                    input.markAsFinished()
                    onFinish()
                    break
                }
            }
        }
    }
    
    // MARK: - Completion
    private func finishWriting(continuation: CheckedContinuation<URL, Error>) {
        guard let assetWriter = assetWriter else {
            continuation.resume(throwing: ExportError.writerNotInitialized)
            return
        }
        
        assetWriter.finishWriting { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil)
                self.progressIndicator.alphaValue = 0.0
                
                switch assetWriter.status {
                case .completed:
                    print("✅ Media export completed successfully")
                    continuation.resume(returning: assetWriter.outputURL)
                    
                case .failed:
                    print("❌ Media export failed: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
                    continuation.resume(throwing: assetWriter.error ?? ExportError.writingFailed)
                    
                case .cancelled:
                    print("⚠️ Media export cancelled")
                    continuation.resume(throwing: ExportError.cancelled)
                    
                default:
                    continuation.resume(throwing: ExportError.unknownStatus)
                }
            }
        }
        
        assetReader?.cancelReading()
    }
    
    // MARK: - Helpers
    private func calculateAudioBitRate(channels: Int) -> Int {
        switch channels {
        case 1:
            return 160_000
        case 2:
            return 320_000
        default:
            return 256_000
        }
    }
}

// MARK: - Supporting Types
struct MediaProcessingConfig {
    let input: AVAssetWriterInput
    let output: AVAssetReaderTrackOutput
    let queue: DispatchQueue
}

enum ExportError: LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case noAudioFormatDescription
    case invalidAudioFormat
    case cannotAddVideoOutput
    case cannotAddVideoInput
    case cannotAddAudioOutput
    case cannotAddAudioInput
    case writerNotInitialized
    case writingFailed
    case cancelled
    case unknownStatus
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in the input asset"
        case .noAudioTrack:
            return "No audio track found in the input asset"
        case .noAudioFormatDescription:
            return "Could not load audio format description"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .cannotAddVideoOutput:
            return "Cannot add video output to asset reader"
        case .cannotAddVideoInput:
            return "Cannot add video input to asset writer"
        case .cannotAddAudioOutput:
            return "Cannot add audio output to asset reader"
        case .cannotAddAudioInput:
            return "Cannot add audio input to asset writer"
        case .writerNotInitialized:
            return "Asset writer not initialized"
        case .writingFailed:
            return "Media writing failed"
        case .cancelled:
            return "Export was cancelled"
        case .unknownStatus:
            return "Unknown export status"
        }
    }
}

// MARK: - Usage Example
/*
let exporter = MediaExporter(progressIndicator: myProgressIndicator)

Task {
    do {
        let outputURL = try await exporter.exportMedia(
            from: inputAsset,
            to: destinationURL
        )
        print("Export completed: \(outputURL)")
    } catch {
        print("Export failed: \(error.localizedDescription)")
    }
}
*/
