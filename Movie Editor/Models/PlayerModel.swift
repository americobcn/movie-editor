//
//  PlayerModel.swift
//  Movie Editor
//
//  Owns the AVPlayer and everything the old MainViewController did apart from drawing:
//  loading, transport, seeking, audio replacement, save/export.
//

import AVFoundation
import AppKit
import Observation
import UniformTypeIdentifiers

enum MediaFileType {
    case audio
    case video
    case unknown
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class PlayerModel {

    static let defaultTitle = "Americo's Movie Player"
    private static let assetKeys = ["playable", "tracks", "duration", "hasProtectedContent"]
    private static let assetOptions = [AVURLAssetPreferPreciseDurationAndTimingKey: true]

    let player = AVPlayer()
    let meters: MeterModel

    // MARK: Observable state
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var timecode = "00:00:00:00"
    private(set) var isMuted = false
    private(set) var windowTitle = PlayerModel.defaultTitle
    private(set) var isExporting = false
    private(set) var videoInfoText = ""
    private(set) var audioInfoText: String?
    var volume: Float = 1 { didSet { applyVolume() } }
    var alert: AlertItem?
    /// Set when a loaded file is an `hev1`-tagged HEVC movie; the view asks whether to fix the tag.
    var hev1Candidate: URL?
    var exportPreset = "AVAssetExportPresetHighestQuality"

    var mediaInfo: String {
        guard let audioInfoText else { return videoInfoText }
        return videoInfoText + "\nAudio:\n" + audioInfoText
    }

    // MARK: Internals
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var audioTap: AudioTapProcessor?
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var folderToSave: URL?
    @ObservationIgnored private var frameRate: Float = 0
    @ObservationIgnored private var durationTime = CMTime.zero
    @ObservationIgnored private var assetTimeScale: CMTimeScale = 600
    @ObservationIgnored private var isSeekInProgress = false
    @ObservationIgnored private var chaseTime = CMTime.zero

    init(meters: MeterModel) {
        self.meters = meters
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let rate = change.newValue ?? 0
            Task { @MainActor in self?.rateDidChange(rate) }
        }
    }

    // MARK: - Loading
    func loadMovie(url loadUrl: URL) async {
        player.pause()

        let asset = AVURLAsset(url: loadUrl, options: Self.assetOptions)
        let videoDesc: CMFormatDescription
        let fps: Float
        let assetDuration: CMTime
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                showError("No video track found in the input asset")
                return
            }
            guard let desc = try await track.load(.formatDescriptions).first else {
                showError("No format description found for the video track")
                return
            }
            videoDesc = desc
            fps = try await track.load(.nominalFrameRate)
            assetDuration = try await asset.load(.duration)
        } catch {
            showError("Couldn't load movie", error.localizedDescription)
            return
        }

        sourceURL = loadUrl
        folderToSave = loadUrl.deletingLastPathComponent()
        frameRate = fps
        durationTime = assetDuration
        duration = assetDuration.isNumeric ? CMTimeGetSeconds(assetDuration) : 0
        if assetDuration.timescale > 0 { assetTimeScale = assetDuration.timescale }
        if hasHev1Tag(videoDesc) { hev1Candidate = loadUrl }

        // Audio track, if any
        audioTap?.delegate = nil
        audioTap = nil
        meters.reset()
        var audioInfo: MediaInfo.AudioInfo?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let audioDesc = try? await audioTrack.load(.formatDescriptions).first {
            audioInfo = MediaInfo.audio(audioDesc)
        }

        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: Self.assetKeys)
        videoInfoText = MediaInfo.videoDescription(videoDesc, frameRate: fps, duration: assetDuration)
        audioInfoText = audioInfo?.text
        if let audioInfo { await attachTap(audioInfo, to: item) }

        volume = 1
        isMuted = false
        install(item)
        windowTitle = loadUrl.lastPathComponent
    }

    /// Replaces the audio with `audioURL`, or removes it when `audioURL` is nil.
    func insertOrRemoveAudio(url audioURL: URL?) async {
        guard isLoaded, let currentAsset = player.currentItem?.asset else { return }
        player.pause()
        audioTap?.delegate = nil
        audioTap = nil
        meters.reset()

        guard durationTime.isNumeric, durationTime.value != 0 else {
            showError("Invalid duration for video composition")
            return
        }
        let videoRange = CMTimeRange(start: .zero, duration: durationTime)

        var sourceAudioTrack: AVAssetTrack?
        var audioInfo: MediaInfo.AudioInfo?
        if let audioURL {
            folderToSave = audioURL.deletingLastPathComponent()
            let audioAsset = AVURLAsset(url: audioURL, options: Self.assetOptions)
            sourceAudioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first
            guard let track = sourceAudioTrack else {
                showError("No audio track found", audioURL.lastPathComponent)
                return
            }
            guard let desc = try? await track.load(.formatDescriptions).first,
                  let info = MediaInfo.audio(desc) else {
                showError("Couldn't read the audio format", audioURL.lastPathComponent)
                return
            }
            audioInfo = info
        }

        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceVideo = try? await currentAsset.loadTracks(withMediaType: .video).first else {
            showError("Missing video tracks")
            return
        }
        let insertAt = player.currentTime()

        do {
            try compositionVideo.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
            if let sourceAudioTrack {
                guard let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    showError("Couldn't add an audio track to the composition")
                    return
                }
                try compositionAudio.insertTimeRange(videoRange, of: sourceAudioTrack, at: insertAt)
            }

            let item = AVPlayerItem(asset: composition, automaticallyLoadedAssetKeys: Self.assetKeys)
            // Attach the tap before the item goes to the player
            if let audioInfo { await attachTap(audioInfo, to: item) }
            audioInfoText = audioInfo?.text
            if audioInfo != nil { isMuted = false }
            install(item)
        } catch {
            showError("Error in audio/video processing", error.localizedDescription)
        }
    }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeTimeObserver()
        audioTap?.delegate = nil
        audioTap = nil
        meters.reset()
        meters.configure(channelCount: 2)
        isLoaded = false
        currentTime = 0
        duration = 0
        durationTime = .zero
        timecode = "00:00:00:00"
        videoInfoText = ""
        audioInfoText = nil
        windowTitle = Self.defaultTitle
    }

    private func install(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        installTimeObserver()
        currentTime = 0
        chaseTime = .zero
        timecode = "00:00:00:00"
        isLoaded = true
        applyVolume()
    }

    private func attachTap(_ info: MediaInfo.AudioInfo, to item: AVPlayerItem) async {
        do {
            let tap = try AudioTapProcessor(sampleRate: info.sampleRate, channelCount: info.channelCount, spectrumBands: meters.spectrumBands)
            tap.delegate = meters
            try await tap.attachTap(to: item, processor: tap)
            audioTap = tap
            meters.configure(channelCount: info.channelCount)
        } catch {
            print("Error: Can't initialize audio tap or attach tap: \(error)")
        }
    }

    private func hasHev1Tag(_ desc: CMFormatDescription) -> Bool {
        guard let name = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_FormatName) as? String else { return false }
        return name == "'hev1'" || CMFormatDescriptionGetMediaSubType(desc).toString() == "hev1"
    }

    /// Writes a copy with the `hvc1` tag and loads it.
    func fixHev1Tag() {
        guard let url = hev1Candidate else { return }
        hev1Candidate = nil
        do {
            let result = try TagEditor(url: url).changeTagFile()
            if result.outputURL != url {
                Task { await loadMovie(url: result.outputURL) }
            }
        } catch {
            showError("Couldn't change the file tag", error.localizedDescription)
        }
    }

    // MARK: - Drag and drop
    func handleDrop(_ urls: [URL]) {
        Task {
            for url in urls {
                switch await checkFileType(url: url) {
                case .video: await loadMovie(url: url)
                case .audio: await insertOrRemoveAudio(url: url)
                case .unknown: break
                }
            }
        }
    }

    func checkFileType(url: URL) async -> MediaFileType {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("File does not exist at path: \(url.path)")
            return .unknown
        }
        let asset = AVURLAsset(url: url)
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if !videoTracks.isEmpty { return .video }   // video wins even if it has audio too
            if !audioTracks.isEmpty { return .audio }
        } catch {
            showError("Unsupported file type", error.localizedDescription)
        }
        return .unknown
    }

    // MARK: - Transport
    func playPause() {
        guard isLoaded else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if player.currentTime() == player.currentItem?.duration {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
        }
    }

    private var frameStep: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(max(Int(frameRate), 1)))
    }

    func stepForward() {
        guard isLoaded else { return }
        player.pause()
        player.seek(to: player.currentTime() + frameStep, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stepBackward() {
        guard isLoaded else { return }
        player.pause()
        player.seek(to: player.currentTime() - frameStep, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func fastForward() {
        guard isLoaded else { return }
        player.rate += 2.0
    }

    func fastBackward() {
        guard isLoaded else { return }
        player.rate -= 2.0
    }

    func seekToStart() {
        guard isLoaded else { return }
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekToEnd() {
        guard isLoaded else { return }
        player.pause()
        let end = durationTime
        Task {
            await player.seek(to: end, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = duration
        }
    }

    func toggleMute() {
        isMuted.toggle()
        applyVolume()
    }

    private func applyVolume() {
        player.volume = isMuted ? 0 : volume
        meters.volume = player.volume
    }

    private func rateDidChange(_ rate: Float) {
        isPlaying = rate != 0
        meters.setPlaying(isPlaying)
    }

    // MARK: - Time observation and scrubbing
    private func installTimeObserver() {
        removeTimeObserver()
        let interval = CMTimeMakeWithSeconds(1.0 / Double(max(frameRate, 1)), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.timeDidUpdate(time) }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func timeDidUpdate(_ elapsed: CMTime) {
        let seconds = CMTimeGetSeconds(player.currentTime())
        timecode = MediaInfo.timecode(seconds: seconds, frameRate: frameRate)
        if durationTime.isNumeric, CMTimeGetSeconds(elapsed) == CMTimeGetSeconds(durationTime) {
            // Reached the end: pause so Play restarts from the beginning
            currentTime = CMTimeGetSeconds(elapsed)
            player.pause()
        } else {
            currentTime = seconds
        }
    }

    /// Called by the scrub slider.
    func scrub(to seconds: Double) {
        currentTime = seconds
        seekSmoothly(to: CMTimeMakeWithSeconds(seconds, preferredTimescale: assetTimeScale))
    }

    // Seek chasing: only one seek in flight, always chasing the latest requested time.
    private func seekSmoothly(to newChaseTime: CMTime) {
        guard CMTimeCompare(newChaseTime, chaseTime) != 0 else { return }
        chaseTime = newChaseTime
        if !isSeekInProgress { trySeekToChaseTime() }
    }

    private func trySeekToChaseTime() {
        guard player.status == .readyToPlay else { return }
        isSeekInProgress = true
        let target = chaseTime
        Task {
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            if CMTimeCompare(target, chaseTime) == 0 {
                isSeekInProgress = false
            } else {
                trySeekToChaseTime()
            }
        }
    }

    // MARK: - Save / Export
    func presentSavePanel(export: Bool) {
        guard isLoaded, let sourceURL else { return }
        let panel = NSSavePanel()
        panel.directoryURL = folderToSave
        if export {
            let codec = ExportSettingsPanelController.VideoCodec.allCases.first { $0.codecDescription == exportPreset }
            panel.message = "Export to \(codec?.rawValue ?? exportPreset)."
        } else {
            panel.message = "Save as a new file without transcoding video, audio: AAC, 320kbs."
        }
        panel.allowedContentTypes = [.movie, .audiovisualContent, .video]
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            if export {
                await exportMovie(to: destination)
            } else {
                await save(to: destination)
            }
        }
    }

    /// Pass-through video, AAC audio.
    private func save(to destURL: URL) async {
        guard let asset = player.currentItem?.asset, let sourceURL else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let outputURL = try await MediaExporter().exportMedia(from: asset, to: destURL, fileExtension: sourceURL.pathExtension)
            print("Export completed: \(outputURL)")
        } catch {
            print("Export failed: \(error.localizedDescription)")
        }
    }

    private func exportMovie(to toURL: URL) async {
        guard let asset = player.currentItem?.asset,
              let session = AVAssetExportSession(asset: asset, presetName: exportPreset) else { return }
        let outURL = toURL.deletingPathExtension().appendingPathExtension("mov")
        isExporting = true
        defer { isExporting = false }
        do {
            try await session.export(to: outURL, as: .mov)
        } catch {
            showError("Export failed", "Error: \(error.localizedDescription)\nCheck if filename is already taken.\nTry adding the extension file type(.mov).")
        }
    }

    // MARK: - Helpers
    private func showError(_ title: String, _ message: String = "") {
        print("\(title) \(message)")
        alert = AlertItem(title: title, message: message)
    }
}
