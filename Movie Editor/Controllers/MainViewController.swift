//
//  MainViewController.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 19/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Foundation
import AVFoundation
import AppKit

private var VIEW_CONTROLLER_KVOCONTEXT = 0
private var CURRENT_TIME_KVOCONTEXT = 0

class MainViewController: NSViewController, ExportSettingsPanelControllerDelegate,  AudioSpectrumProviderDelegate { //AudioLevelProviderDelegate,
        
    enum AssetsError: Error {
        case noVideoTrack
        case noAudioTrack
        
        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "No video track found in the input asset"
            case .noAudioTrack:
                return "No audio track found in the input asset"
            }
        }
    }
    
    
    //MARK: Outlets Main View
    @IBOutlet weak var playerView: NSView!
    @IBOutlet weak var playPauseBtn: NSButton!
    @IBOutlet weak var movieTime: NSTextField!              // Time Code display
    @IBOutlet weak var scrubSlider: NSSlider!               // Scrubber slider    
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var volumeSlider: NSSlider!
    @IBOutlet weak var muteButton: NSButton!
    @IBOutlet weak var movieInfoDisplay: NSTextField!
    @IBOutlet weak var espc: ExportSettingsPanelController!     //Necesary for implement ExportSettingsPanelControllerDelegate
    @IBOutlet weak var mainViewMeters: NSView!
    @IBOutlet weak var mainSpectrumViewMeters: NSView!
    
    
    //MARK: Variables
    var url: URL!
    var audioUrl: URL!
    var folderToSaveFile: URL!
    var sourceUrlExtension: String!
    @objc private var mediaPlayer = AVPlayer()
    @objc dynamic var currentTime:Double = 0.0
    var isMuted: Bool = false
    private var playerLayer : AVPlayerLayer!
    private var sliderScrubberObserver: NSKeyValueObservation?
    private var sliderVolumeObserver: NSKeyValueObservation?
    private var smpteObserver: Any?
    var videoOutputSettings: [String: Any]?
    var hasAudioTrack: Bool = false

    //MARK: Tap and Metering related Variables
    var metersView = [MeterView]()
    var spectrumMeters = [SpectrumBarView]()
    var spectrumBarWidth: CGFloat = 0.0
    var spectrumBarHeight: [CGFloat] = []
    var volumeBarHeight: [CGFloat] = []
    var audioTap: AudioTapProcessor!
    var meterTimer: Timer?
    var audioSampleRate: Float!
    var spectrumBands: Int = 24 // default value
            
    //MARK: Asset related vars
    private var mediaAsset: AVAsset!
    private var assetReader: AVAssetReader!
    private var assetWriter: AVAssetWriter!
    private var videoTrackOutput: AVAssetReaderTrackOutput!
    private var audioTrackOutput: AVAssetReaderTrackOutput!     //AVAssetReaderOutput!
    private var audioInput: AVAssetWriterInput!
    private var audioInputQueue: DispatchQueue!
    
    //MARK: Export related vars
    var exportPreset: String = "AVAssetExportPresetHighestQuality"      // Default export preset if not changed in ExportSettingsController
    var exporter: AVAssetExportSession?
    @objc dynamic var progressValue: Float = 0.0
    
    //MARK: Media descriptors and movie properties
    private var duration:CMTime? //= CMTime.zero
    private var mediaPreferedRate: Float?
    
    var mediaTimeScale: CMTimeScale?
    var mediaPlayerRate: Float = 0.0
    var audioVolumeBeforeMute: Float = 0.0
    var loadedVideoTrackID: CMPersistentTrackID!
    var loadedAudioTrackID: CMPersistentTrackID!
        
    var fileType: AVMediaType!
    var videoFormatDesc: CMFormatDescription!
    var audioFormatDesc: CMFormatDescription!
    var asbd: UnsafePointer<AudioStreamBasicDescription>?
    var currentAssetTimeScale: CMTimeScale!
    
    var movieDimensions: CMVideoDimensions?
    var movieColorPrimaries: String = ""
    var movieFieldCount: CFPropertyList?
    var movieDepth: CFPropertyList?
    var movieCodec: String = ""
    var videoFrameRate: Float = 0.0
    var chCount: Int = 2
    
    enum playerStatus {
    case playing, stopped
    }
    
    //Seek Related vars
    private var isSeekInProgress = false
    private var chaseTime = CMTime.zero
    
    //MARK: Computed properties
    
    var rate: Float
    {
        get { return mediaPlayer.rate }
        set { mediaPlayer.rate = newValue }
    }
        
    var playerItem: AVPlayerItem? = nil
    {
        didSet {
            //  if needed, configure player item here before associating it with a player.
            //  (example: adding outputs, setting text style rules, selecting media options)
            // Here we load the movie into the playerView.layer, rather than is Dragged or Opened from File menu
            mediaPlayer.replaceCurrentItem(with: self.playerItem)
        }
    }
        
    @objc dynamic var movieCurrentTime: Double
    {
        get
        {
            if mediaPlayer.currentItem == nil { return (0.0) }
            else { return (currentTime) }
        }

        set
        {
            let newTime = CMTimeMakeWithSeconds(newValue, preferredTimescale: currentAssetTimeScale)   //CMTimeScale(NSEC_PER_SEC)
            currentTime = newValue
            seekSmoothlyToTime(newChaseTime: newTime)
         }
    }
    
    @objc dynamic var movieVolume: Float
    {
        get {
            if mediaPlayer.currentItem == nil { return (0.0) }
            else { return mediaPlayer.volume }
        }
        set { if !isMuted {
            mediaPlayer.volume = volumeSlider.floatValue //(pow(100.0, volumeSlider.floatValue) - 1.0) / 99.0
            }
        }
    }
    
//MARK: Overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        // Setup playerLayer
        playerLayer = AVPlayerLayer(player: mediaPlayer)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.autoresizingMask = [.layerHeightSizable, .layerWidthSizable]
        playerLayer.frame = playerView.bounds
        playerLayer.backgroundColor = NSColor.black.cgColor
        
        //Setup playerView
        playerView.wantsLayer = true
        playerView.layer?.addSublayer(playerLayer)
        
        //Setup ScrubSlider
        scrubSlider.maxValue = 0.0
        scrubSlider.minValue = 0.0
        scrubSlider.trackFillColor = NSColor.lightGray
        
        //Setup Volume and Mute Button
        volumeSlider.isEnabled = false
        muteButton.isEnabled = false
        
        //Setup Progress Indicator
        progressIndicator.alphaValue = 0.0
        
        //Setup Meters View
        mainViewMeters.wantsLayer = true
        mainViewMeters.canDrawConcurrently = true
        
        //Setup SpectrumView
        mainSpectrumViewMeters.wantsLayer = true
        mainSpectrumViewMeters.canDrawConcurrently = true
        mainSpectrumViewMeters.layer?.cornerRadius = 6.0
        mainSpectrumViewMeters.layer?.backgroundColor = NSColor.black.cgColor
        
        view.needsDisplay = true
        
        // Here we add observers and set the movie time var and textfield CMTimeScale(NSEC_PER_SEC)
        smpteObserver = mediaPlayer.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.04, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: DispatchQueue.main)
        {
            (elapsedTime: CMTime) -> Void in
            if !self.movieTime.isHidden
                {
                    let time = Float(CMTimeGetSeconds(self.mediaPlayer.currentItem?.currentTime() ?? CMTime.zero))
                    let frame = Int(time * self.videoFrameRate)
                    let FF = Int(Float(frame).truncatingRemainder(dividingBy: self.videoFrameRate))
                    let seconds = Int(Float(frame - FF) / self.videoFrameRate)
                    let SS = seconds % 60
                    let MM = (seconds % 3600) / 60
                    let HH = seconds / 3600
                    self.movieTime.stringValue = String(format: "%02i:%02i:%02i:%02i", HH, MM, SS, FF)
                }
            
            } as AnyObject
        
        //  set up observer to update slider
        //  observer only runs while player is playing
        //  just needs to be fast enough for smooth animation
        sliderScrubberObserver = mediaPlayer.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.04, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: DispatchQueue.main)
         { (elapsedTime: CMTime) -> Void in
             
            // guard self.duration != CMTime.invalid else { return }
            if CMTimeGetSeconds(elapsedTime) == CMTimeGetSeconds(self.duration!)
            {
                //  sync currentTime with elaspedTime in
                //  case user clicks on PlayBtn here
                self.currentTime = CMTimeGetSeconds(elapsedTime)
                self.mediaPlayer.pause()
                self.playPauseBtn.title = "Play"
            }
            else
            {
                self.willChangeValue(forKey: "movieCurrentTime")
                self.currentTime = Double(CMTimeGetSeconds(self.mediaPlayer.currentTime()))
                self.didChangeValue(forKey: "movieCurrentTime")
            }
            } as AnyObject as? NSKeyValueObservation

        sliderVolumeObserver = mediaPlayer.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.04, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: DispatchQueue.main)
        { (elapsedTime: CMTime) -> Void in

           if !self.movieTime.isHidden
           {
                self.movieVolume = self.volumeSlider.floatValue
           }
           } as AnyObject as? NSKeyValueObservation
    
        //  bind movieCurrentTime var to scrubberSlider.value ---->>>>> Binded in NIB file
            
        //  KVO state change, adding observers for playerItem.duration and playerItem.status (needed for replace playerItem on the mediaPlayer), volume and rate
        addObserver(self, forKeyPath: #keyPath(MainViewController.mediaPlayer.currentItem.duration), options: [.new, .initial], context: &VIEW_CONTROLLER_KVOCONTEXT)
        addObserver(self, forKeyPath: #keyPath(MainViewController.mediaPlayer.currentItem.status), options: [.new, .initial], context: &VIEW_CONTROLLER_KVOCONTEXT)
        addObserver(self, forKeyPath: #keyPath(MainViewController.mediaPlayer.volume), options: [.new, .initial], context: &VIEW_CONTROLLER_KVOCONTEXT)
        addObserver(self, forKeyPath: #keyPath(MainViewController.mediaPlayer.rate), options: [.new, .initial], context: &VIEW_CONTROLLER_KVOCONTEXT)
                
        spectrumBarHeight = [CGFloat](repeating: 0.0, count: spectrumBands)
        volumeBarHeight = [CGFloat](repeating: 0.0, count: chCount)
        createSpectrumView()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        //Setting the delegate
        espc?.delegate = self
        
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleDragNotification(_:)),
                                               name: Notification.Name(rawValue: NOTIF_OPENFILE),
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleDragNotification(_:)),
                                               name: Notification.Name(rawValue: NOTIF_REPLACE_AUDIO),
                                               object: nil)
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?)
            {
                //  make sure the this KVO callback was intended for this view controller
                guard context == &VIEW_CONTROLLER_KVOCONTEXT else {
                    super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
                    return
                }
                
                if keyPath == #keyPath(MainViewController.mediaPlayer.rate)
                {
                    if let actualRate = change?[NSKeyValueChangeKey.newKey] as? Float {
                        switch actualRate {
                        case 0.0:
                            playPauseBtn.title = "Play"
                            print("STOPPED")
                        default:
                            playPauseBtn.title = "Stop"
                            print("PLAYING")
                        }
                    }
                }
                
                if keyPath == #keyPath(MainViewController.mediaPlayer.currentItem.duration)
                {
                    if let durationAsValue = change?[NSKeyValueChangeKey.newKey] as? NSValue
                    {
                        duration = durationAsValue.timeValue
                    }
                    else { duration = CMTime.zero }
                    
                    let hasValidDuration = duration!.isNumeric && duration!.value != 0
                    
                    scrubSlider!.isEnabled = hasValidDuration
                    scrubSlider!.floatValue = hasValidDuration ? Float(CMTimeGetSeconds(mediaPlayer.currentTime())) : 0.001
                    scrubSlider!.maxValue =  hasValidDuration ? Double(CMTimeGetSeconds(duration!)) : 0.001
                }
                

                if keyPath == #keyPath(MainViewController.mediaPlayer.currentItem.status)
                {
                    let newStatus: AVPlayerItem.Status
                    if let newStatusAsNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber
                    {
                        newStatus = AVPlayerItem.Status(rawValue: newStatusAsNumber.intValue)!
                    }
                    else { newStatus = .unknown }
                    
                    if newStatus == .failed
                    {
                        print("Error")
                    }
                }
            }
            
            override class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String>
            {
                let affectedKeyPathsMappingByKey: [String: Set<String>] = [
                    "duration":             [#keyPath(MainViewController.mediaPlayer.currentItem.duration)],
                    "rate":                 [#keyPath(MainViewController.mediaPlayer.rate)],
                    "movieVolume":          [#keyPath(MainViewController.mediaPlayer.volume)]
                ]
                return affectedKeyPathsMappingByKey[key] ?? super.keyPathsForValuesAffectingValue(forKey: key)
            }

    
    //MARK: Delegate funcions
    func exportPresetDidChange(_ preset: String) {
        exportPreset = preset
    }

    
    //MARK: Delegate functions                          NEED TO REVISIT, THIS IS NOT NECESARY
    func spectrumDidChange(spectrum: [Float], peaks: [Float]){
        //print("spectrumDidChange: \(spectrum)")
        for index in 0..<self.spectrumBands {
            self.spectrumBarHeight[index] = barHeight(magnitudeDB: spectrum[index], minDB: -50)
        }
        for index in 0..<self.chCount {
            self.volumeBarHeight[index] = barHeight(magnitudeDB: peaks[index], minDB: -120)
        }
    }
    
    func barHeight(magnitudeDB: Float, minDB: Float = -100.0, maxDB: Float = 0.0, maxHeight: Float = 130.0) -> CGFloat {
        let clamped = min(max(magnitudeDB, minDB), maxDB)
        let normalized = (clamped - minDB) / (maxDB - minDB)
        let gamma: Float = 0.7
        let curved = pow(normalized, gamma)
        
        return CGFloat(curved * maxHeight)
    }
    
    
    //MARK: Functions
    func loadMovieFromURL(loadUrl: URL) async {
        folderToSaveFile = loadUrl.deletingLastPathComponent()
        url = loadUrl
        sourceUrlExtension = loadUrl.pathExtension
        
        if mediaPlayer.rate != 0 {
            mediaPlayer.rate = 0 // media pause
        }
        
        //Load mediaAsset
        let loadOptions = [AVURLAssetPreferPreciseDurationAndTimingKey : true]
        mediaAsset = AVURLAsset(url: loadUrl, options: loadOptions)
        do {
             try await mediaAsset.loadTracks(withMediaType: AVMediaType.video)
            let (duration, metadata) = try await mediaAsset.load(.duration, .metadata)
            print("Metadata: \(metadata)\nDuration: \(duration)")
        } catch {
            print("Error loading mediaAsset: \(error)")
            return
        }
        

        let assetKeys = ["playable", "tracks", "duration", "hasProtectedContent"]
        
        //Load and Inspecting Video Track
        let videoTrack: AVAssetTrack
        do {
            videoTrack = try await mediaAsset.loadTracks(withMediaType: .video).first!
        } catch {
            print("Error: \(error)")
            return
        }
                    
        do {
            videoFormatDesc = try await videoTrack.load(.formatDescriptions)[0]
        } catch {
            print("Error: \(error)")
            return
        }
        do {
            videoFrameRate = try await videoTrack.load(.nominalFrameRate)
        } catch {
            print("Error: \(error)")
            return
        }
                
        loadedVideoTrackID = videoTrack.trackID
        let mediaSubType = CMFormatDescriptionGetMediaSubType(videoFormatDesc)
        if let formatName = CMFormatDescriptionGetExtension(videoFormatDesc, extensionKey: kCMFormatDescriptionExtension_FormatName) { //kCMFormatDescriptionExtension_FormatName
           //  print("mediaSubType: \(mediaSubType.toString()), formatName: \(formatName as! String)")
            if formatName as! String == "'hev1'" || mediaSubType.toString() == "hev1"{
                    let alertPanel = NSAlert() //
                    alertPanel.alertStyle = .warning
                    alertPanel.messageText = "Do you want to load a copy with the correct file tag?"
                    alertPanel.informativeText = "This is a HEVC(H.265) file tagged as 'hev1', the file should have the 'hvc1' tag."
                    alertPanel.addButton(withTitle: "Save")
                    alertPanel.addButton(withTitle: "Cancel")
                    alertPanel.beginSheetModal(for: self.view.window!, completionHandler: { result in
                        if result == .alertFirstButtonReturn {
                            let tagEditor = TagEditor(url: self.url)
                            do {
                                let tagResult = try tagEditor.changeTagFile()
                                // print("Output: \(tagResult.outputURL)")
                                // print("Modified: \(tagResult.wasModified)")
                                if tagResult.outputURL != self.url {
                                    Task {
                                        await self.loadMovieFromURL(loadUrl: tagResult.outputURL)
                                    }
                                }
                            } catch {
                                print("Error: \(error)")
                            }
                        } else {
                            return
                        }
                    })
                }
            }
                    
        // MARK: Inspecting Audio Track
        let audioTrack: AVAssetTrack!
        do {
            audioTrack = try await mediaAsset.loadTracks(withMediaType: .audio).first
            if audioTrack == nil {
                hasAudioTrack = false
            } else {
                hasAudioTrack = true
                do {
                    audioFormatDesc = try await audioTrack.load(.formatDescriptions)[0]
                    if let asbdLocal = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc) {
                        asbd = asbdLocal
                    }
                    chCount = Int((asbd?.pointee.mChannelsPerFrame)!)
                    loadedAudioTrackID = audioTrack.trackID
                } catch {
                    print("Can't get Audio Format Description")
                }
            }
        } catch {
            hasAudioTrack = false
        }
        
        //Associate to player Item to load on viewer
        playerItem = AVPlayerItem(asset: mediaAsset, automaticallyLoadedAssetKeys: assetKeys)
        do {
            self.duration = try await playerItem?.asset.load(.duration)
            currentAssetTimeScale = try await playerItem?.asset.load(.duration).timescale
        } catch {
            print("Couldn't get Duration")
        }
        
        self.view.window?.title =  loadUrl.lastPathComponent
                    
        //Seting initial audio volume and mute  button state
        muteButton.isEnabled = true
        volumeSlider.isEnabled = true
        volumeSlider.floatValue = mediaPlayer.volume
        
        
        //Setup the Tap for processing audio
        if hasAudioTrack {
            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc) + "\nAudio:\n" +
                                            getAudioTrackDescription(audioFormatDesc: audioFormatDesc)
            self.audioTap = AudioTapProcessor(sampleRate: self.audioSampleRate, channelCount: self.chCount, spectrumBands: self.spectrumBands)
            do {
                try await self.audioTap.attachTap(to: self.playerItem!, processor: self.audioTap)
            } catch {
                print("Error: Can't attach tap")
            }
            self.audioTap.delegate = self
            updateMetersView()
        } else {
            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc)
        }
    }
    
    func getVideoTrackDescription(videoFormatDesc: CMFormatDescription) -> String {
        // print("Video Description: \(videoFormatDesc)")
        //Local vars
        var interlacedPregressive = ""
        var videoDescription: String = ""
        movieColorPrimaries = ""
        //Getting video descriptors
        movieDimensions =  CMVideoFormatDescriptionGetDimensions(videoFormatDesc)
        if let tempPrimaries = CMFormatDescriptionGetExtension(videoFormatDesc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) {
            movieColorPrimaries = tempPrimaries as! String
            movieColorPrimaries = ", " + movieColorPrimaries
        }
        if let tempFields = CMFormatDescriptionGetExtension(videoFormatDesc, extensionKey: kCMFormatDescriptionExtension_FieldCount) {
            movieFieldCount = tempFields
            if Int(truncating: movieFieldCount as! NSNumber) == 1 {
                interlacedPregressive = "p"
            } else if Int(truncating: movieFieldCount as! NSNumber) == 2 {
                interlacedPregressive = "i"
            }
        }
        
        if let tempDepth = CMFormatDescriptionGetExtension(videoFormatDesc, extensionKey: kCMFormatDescriptionExtension_Depth) { movieDepth = tempDepth }
        
        //Standarizing videoFrameRate (videoTrack.nominalFrameRate)
        var videoFrameRateString = ""
        switch Int(videoFrameRate) {
            case 23:
                videoFrameRateString = String(format: "%2.2f", videoFrameRate)
            break
            case 29:
                videoFrameRateString = String(format: "%2.2f", videoFrameRate)
                break
            default:
                videoFrameRateString = String(format: "%2.0f", videoFrameRate)
                break
        }
        
        //Standarizing video codec name
        if let formatName = CMFormatDescriptionGetExtension(videoFormatDesc, extensionKey: kCMFormatDescriptionExtension_FormatName)
        {
            switch formatName as! String
            {
                case "'apch'":
                    movieCodec = "Apple ProRes 422 (HQ)"
                    break
                case "'avc1'",
                     "'x264'":
                    movieCodec = "H.264"
                    break
                case "'mpg4'",
                     "'mp4v'":
                    movieCodec = "MPEG-4 Video"
                    break
                case "'hev1'":
                    movieCodec = "HEVC(hev1 tag not readable)"
                    break
                case "'hvc1'":
                    movieCodec = "HEVC"
                    break
                default:
                    movieCodec = formatName as! String
                break
            }            
        }
        
        let duration = String(format: "%.2f", CMTimeGetSeconds(self.duration!))
        videoDescription = String(format: "Duration: \(duration)s\nVideo:\n\(movieCodec), \(String(describing: movieDimensions!.width))x\(String(describing: movieDimensions!.height))\(interlacedPregressive)\n\(videoFrameRateString)fps\(movieColorPrimaries), %ibits\n",Int(truncating: movieDepth! as! NSNumber)
        )
        
        return videoDescription
    }
    
    func getAudioTrackDescription(audioFormatDesc: CMFormatDescription) -> String {
        var audioDescription = ""
        var formatID: AudioFormatID!
        var formatIDDescription: String = ""
        var bitsPerChannel: UInt32 = 0
        var bitsPerChannelDescription: String = ""
        // var sampleRate: Float64!
        // var channels: UInt32!
        var channelsDescription = ""
        asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
        
        formatID = asbd?.pointee.mFormatID //.toString() as! String
        switch formatID {
        case kAudioFormatLinearPCM:
            formatIDDescription = "Linear PCM"
            break
        case kAudioFormatMPEG4AAC:
            formatIDDescription = "AAC"
            break
        case kAudioFormatMPEG4AAC_LD:
            formatIDDescription = "AAC-LD"
            break
        case kAudioFormatMPEG4AAC_HE:
            formatIDDescription = "AAC-HE"
            break
        case kAudioFormatMPEG4AAC_ELD:
            formatIDDescription = "AAC-ELD"
            break
        case kAudioFormatAC3:
            formatIDDescription = "AC3"
            break
        case kAudioFormatAppleIMA4:
            formatIDDescription = "Apple IMA4"
            break
        case kAudioFormatMPEGLayer1:
            formatIDDescription = "MPEG Layer 1"
            break
        case kAudioFormatMPEGLayer2:
            formatIDDescription = "MPEG Layer 2"
            break
        case  kAudioFormatMPEGLayer3:
            formatIDDescription = "MPEG Layer 3"
            break
        case kAudioFormatAppleLossless:
            formatIDDescription = "Apple Lossless"
            break
        case kAudioFormatAMR:
            formatIDDescription = "AMR"
            break
        default:
            break
        }
        
        if let tempBits = asbd?.pointee.mBitsPerChannel {bitsPerChannel = tempBits }
        if bitsPerChannel != 0 {
            bitsPerChannelDescription = "\(String(describing: bitsPerChannel))bits, "
        }
        if let tempSampleRate = asbd?.pointee.mSampleRate {
            audioSampleRate = Float(tempSampleRate)
        }
        
        //Channels
        if let tempChannels = asbd?.pointee.mChannelsPerFrame {
            chCount = Int(tempChannels)
        }
        switch chCount {
        case 1:
            channelsDescription = "Mono"
            chCount = 1
            break
        case 2:
            channelsDescription = "Stereo"
            chCount = 2
            break
        case 6:
            channelsDescription = "5.1"
            chCount = 6
            break
        default:
            channelsDescription  = String("\(chCount)")
            break
        }
            
        audioDescription = String(format:"\(formatIDDescription), \(bitsPerChannelDescription)\(channelsDescription),\n%2.0fHz", audioSampleRate)
        
        return audioDescription
    }

    func insertOrRemoveAudio(loadUrl: URL?) async {
        //folder where the new composition will be saved
        if mediaPlayer.rate != 0 {
            mediaPlayer.rate = 0 // media pause
        }
        
        // Reset audio tap
        self.audioTap?.delegate = nil
        self.audioTap = nil
        
        // removeSpectrumBarsAndMeterViews()
        
        let videoRangeMediaDuration = CMTimeRangeMake(start: .zero, duration: self.duration!)
        var audioAsset: AVURLAsset?
        var sourceAudioTrack: AVAssetTrack?
        
        
        if let loadUrl = loadUrl {
            // print("insertAudio with url: \(String(describing: loadUrl))")
            folderToSaveFile = loadUrl.deletingLastPathComponent()
            //Get the Audio Track
            let loadOptions = [AVURLAssetPreferPreciseDurationAndTimingKey : true]
            audioAsset = AVURLAsset(url: loadUrl, options:loadOptions)
            // print("audioAsset: \(String(describing: audioAsset?.description))")
            
            // Load audio track
            do {
                let audioTracks = try await audioAsset?.loadTracks(withMediaType: .audio)
                sourceAudioTrack = audioTracks?.first
            } catch {
                print("Error loading audio tracks: \(error.localizedDescription): \(AssetsError.noAudioTrack) ")
            }
            
            guard let sourceAudioTrack = sourceAudioTrack else {
                print("No audio track found")
                return
            }
            // print("sourceAudioTrack: \(String(describing: sourceAudioTrack))")
            
            
            do {
                let audioFormatDescriptions = try await sourceAudioTrack.load(.formatDescriptions)
                // print("audioFormatDesc: \(audioFormatDescriptions.debugDescription)")
                
                // Extract ASBD from the first format description
                if let formatDesc = audioFormatDescriptions.first {
                    self.audioFormatDesc = formatDesc
                    if let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        self.asbd = asbdPointer
                        print("ASBD successfully extracted")
                    } else {
                        print("Could not get ASBD from format description")
                    }
                }
            } catch {
                print("Error loading audio format descriptions: \(error.localizedDescription)")
            }
            
            // Determine channel count
            if let asbd = self.asbd {
                self.chCount = Int(asbd.pointee.mChannelsPerFrame)
                self.audioSampleRate = Float(asbd.pointee.mSampleRate)
            } else {
                print("ASBD is still nil, returning")
               return
            }                    
        }
        
                    
        //New Video Composition
        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        // print("composition: \(composition.description)")
        
        let insertAtTime = mediaPlayer.currentTime()
        // print("insertaAtTime: \(insertAtTime)")
        
        do {
            // Load video track
            let sourceVideoTrack = try await mediaPlayer.currentItem?.asset.loadTracks(withMediaType: .video).first
            // print("Source Video Track loaded: \(String(describing: sourceVideoTrack))")
            
            guard let sourceVideoTrack = sourceVideoTrack,
                  let compositionVideoTrack = compositionVideoTrack else {
                let alert = NSAlert()
                alert.messageText = "Missing video tracks"
                alert.runModal()
                print("Missing video tracks")
                return
            }
                                    
            try compositionVideoTrack.insertTimeRange(videoRangeMediaDuration,
                                                      of: sourceVideoTrack,
                                                      at: .zero
            )
                            
            // Insert the audio track
            if sourceAudioTrack != nil {
                let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                guard let compositionAudioTrack = compositionAudioTrack else {
                    print("Composition audio track is nil")
                    return
                }
                                
                try compositionAudioTrack.insertTimeRange(
                    videoRangeMediaDuration,
                    of: sourceAudioTrack!,
                    at: insertAtTime
                )
            }
            
            // Create the new player item FIRST
            let assetKeys = ["playable", "tracks", "duration", "hasProtectedContent"]
            let newPlayerItem = AVPlayerItem(asset: composition, automaticallyLoadedAssetKeys: assetKeys)
            
            // Setup processing tap with the new player item BEFORE assigning to self.playerItem
            if sourceAudioTrack != nil {
                self.audioTap = AudioTapProcessor(sampleRate: self.audioSampleRate, channelCount: self.chCount, spectrumBands: self.spectrumBands)
                self.audioTap.delegate = self
                do {
                    try await self.audioTap.attachTap(to: newPlayerItem, processor: self.audioTap)
                    
                } catch {
                    print("Error: Can't attach tap")
                }
                createSpectrumView()
                // let centers = logBandCenters(
                //     bandCount: self.spectrumBands,
                //     minFrequency: 20,
                //     maxFrequency: 24_000
                // )
                // var frequencies: [String] = []
                // for c in centers {
                //     frequencies.append(formatFrequency( c))
                // }
                
            }
                                                                
            // Now update the instance variables on main thread
            await MainActor.run {
                self.playerItem = newPlayerItem
                self.movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc)
                if sourceAudioTrack != nil {
                    self.movieInfoDisplay.stringValue += "\nAudio:\n" + getAudioTrackDescription(audioFormatDesc: audioFormatDesc)
                }
                self.isMuted = false
            }
        } catch {
            print("Error in audio/video processing: \(error)")
        }
                
        createSpectrumView()
    }
    
    func removeSpectrumBarsAndMeterViews() {
        for index in 0..<self.spectrumBands {
            self.spectrumBarHeight[index] = barHeight(magnitudeDB: 0.0, minDB: -120)
        }
        for index in 0..<self.chCount {
            self.volumeBarHeight[index] = barHeight(magnitudeDB: 0.0, minDB: -120)
        }
        // for view in metersView {
        //     view.animator().setFrameSize(NSSize(width: 10.0 , height: 0.0))
        //     view.removeFromSuperview()
        // }
        // for view in self.mainSpectrumViewMeters.subviews {
        //     view.animator().setFrameSize(NSSize(width: self.spectrumBarWidth , height: 0.0))
        //     view.removeFromSuperview()
        // }
    }
    
        
    @objc func handleDragNotification(_ notification: Notification) {
        if let url:URL = notification.object as? URL {
            self.audioUrl = url
            Task {
                switch notification.name.rawValue {
                case NOTIF_OPENFILE:
                    print("Calling loadMovieFromURL")
                    await loadMovieFromURL(loadUrl: url)
                    break
                case NOTIF_REPLACE_AUDIO:
                    print("Calling insertAudio")
                    await insertOrRemoveAudio(loadUrl: url ) // self.audioUrl
                    break
                default:
                    return
                }
            }
        }
    }
    
    
    func readAndWriteSamples(inputAsset: AVAsset, destURL: URL) async {
        let exporter = MediaExporter(progressIndicator: progressIndicator)
        Task {
            do {
                let outputURL = try await exporter.exportMedia(
                    from: inputAsset,
                    to: destURL,
                    fileExtension: sourceUrlExtension
                )
                print("Export completed: \(outputURL)")
            } catch {
                print("Export failed: \(error.localizedDescription)")
            }
        }
    }
    
    
    func exportMovie(toUrl: URL) {
        //Determining Compatipbility
        print("Exporting...\(String(describing: exportPreset)) to URL: \(toUrl.path)")
        guard let composition = mediaPlayer.currentItem?.asset else { return }
        //Generating the export session
        guard let exporter = AVAssetExportSession(asset: composition, presetName: exportPreset) else { return }
        var outURL: URL!
        if toUrl.pathExtension.isEmpty {
            outURL = toUrl.appendingPathExtension("mov")
        } else {
            outURL = toUrl.deletingPathExtension().appendingPathExtension("mov")
        }
        
        print("Exporting to: \(outURL.path)")
        
        exporter.outputFileType = .mov
        exporter.outputURL = outURL
        exporter.exportAsynchronously {
            print("EXPORTING..... PRESET: \(self.exportPreset)")
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(self)
                self.progressIndicator.alphaValue = 0.0
            }
            // switch exporter.status {
            switch exporter.status {
            case .completed:
                print("Succes")
                break
            case .failed:
                print("Something went wrong: \(exporter.error!.localizedDescription)")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export failed"
                    alert.informativeText = "Error: \(exporter.error!.localizedDescription)\nCheck if filename is already taken.\nTry adding the extension file type(.mov)."
                    alert.runModal()
                }
                break
            default:
                break
            }
        }
    }
    
    /// Functions called from movieCurrentTimme computed properties to smoothly scrubing
    public func seek(to time: CMTime) {
        seekSmoothlyToTime(newChaseTime: time)
    }
    
    private func seekSmoothlyToTime(newChaseTime: CMTime) {
        if CMTimeCompare(newChaseTime, chaseTime) != 0 {
            chaseTime = newChaseTime
            if !isSeekInProgress {
                trySeekToChaseTime()
            }
        }
    }
    
    private func trySeekToChaseTime() {
        guard mediaPlayer.status == .readyToPlay else { return }
        actuallySeekToTime()
    }
    
    private func actuallySeekToTime() {
        isSeekInProgress = true
        let seekTimeInProgress = chaseTime
        mediaPlayer.seek(to: seekTimeInProgress, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let `self` = self else { return }
            if CMTimeCompare(seekTimeInProgress, self.chaseTime) == 0 {
                self.isSeekInProgress = false
            } else {
                self.trySeekToChaseTime()
            }
        }
    }
    
    @objc func recalculateMeters() {
            for (idx, view) in self.mainViewMeters.subviews.enumerated() {
                view.animator().setFrameSize(NSSize(width: 10.0 , height: (self.volumeBarHeight[idx]) * CGFloat(mediaPlayer.volume)))
            }
        
            for (idx, view) in self.mainSpectrumViewMeters.subviews.enumerated() {
                view.animator().setFrameSize(NSSize(width: self.spectrumBarWidth , height: self.spectrumBarHeight[idx]))
                
            }
    }
            
    func updateMetersView() {
        volumeSlider.floatValue = 1.0
        muteButton.floatValue = 0.0
        metersView.removeAll()
        mainViewMeters.subviews.removeAll()
        //Adding meterViews
        if (metersView.count == 0 && mainViewMeters.subviews.count == 0) {
            for i in 0..<chCount {
                metersView.append(MeterView())
                let shift = i * 11
                metersView[i].setFrameOrigin(NSPoint(x: Double(shift), y: 0.0 ))
                mainViewMeters.addSubview(metersView[i])
            }
        }
    }
    
    
    func createSpectrumView() {
        //Setting up Spectrum visualizer
        let bounds = mainSpectrumViewMeters.bounds
        guard spectrumBands > 0 else { return }

        self.spectrumBarWidth = bounds.width / CGFloat(spectrumBands)

        // Reuse existing bars and create any missing ones
        for i in 0..<spectrumBands {
            let xshift = CGFloat(i) * self.spectrumBarWidth
            if i < spectrumMeters.count {
                let barView = spectrumMeters[i]
                barView.frame = NSRect(x: xshift, y: 0.0, width: self.spectrumBarWidth, height: 0.0)
            } else {
                let barView = SpectrumBarView()
                barView.frame = NSRect(x: xshift, y: 0.0, width: self.spectrumBarWidth, height: 0.0)
                mainSpectrumViewMeters.addSubview(barView)
                spectrumMeters.append(barView)
            }
        }
    }
    
    
    func handleTimer(status: playerStatus) {
        switch status {
        case .playing:
            // In order for the meters to keep updating while the user is interacting
            // with controls (like dragging the volume slider) we must schedule the
            // timer in the run loop's common modes. Using `scheduledTimer` adds
            // it to the default mode which is paused during event tracking.
            meterTimer?.invalidate()
            meterTimer = Timer(timeInterval: 1.0/Double(videoFrameRate), target: self, selector: #selector(recalculateMeters), userInfo: nil, repeats: true)
            if let t = meterTimer {
                RunLoop.main.add(t, forMode: .common)
            }
        case .stopped:
            meterTimer?.invalidate()
            //While in pause, set the meters to 0.0
            for view in metersView {
                view.animator().setFrameSize(NSSize(width: 10.0 , height: 0.0))
            }
            for (_, view) in self.mainSpectrumViewMeters.subviews.enumerated() {
                view.animator().setFrameSize(NSSize(width: self.spectrumBarWidth , height: 0.0))
            }
        }
    }
    
    // func getSpectrumBarHeight(mag: Float, minDB: Float, maxDB: Float) -> Float {
    //     let norm = (mag - minDB) / (maxDB - minDB)
    //     // print("Norm: \(norm - 1)")
    //   return (norm - 1.0) // * 2.0
    // }

    
    //MARK: Action Methods for Player Transport
        
    @IBAction func playPauseVideo(_ sender: NSButton) {
        if playerItem != nil {
            if (mediaPlayer.timeControlStatus == .playing) {
                mediaPlayer.pause()
                handleTimer(status: .stopped)
            // If playerItem is stopped at the end of the movie
            } else if mediaPlayer.currentTime() == mediaPlayer.currentItem?.duration && mediaPlayer.timeControlStatus == AVPlayer.TimeControlStatus.paused {
                mediaPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                mediaPlayer.play()
                handleTimer(status: .playing)
                
            } else {
                mediaPlayer.play()
                handleTimer(status: .playing)
            }
        }
    }
    
    //MARK: Frequency related functions
/*
    func logBandEdges(
        bandCount: Int,
        minFrequency: Float,
        maxFrequency: Float
    ) -> [(low: Float, high: Float)] {

        let logMin = log10(minFrequency)
        let logMax = log10(maxFrequency)
        let step = (logMax - logMin) / Float(bandCount)

        return (0..<bandCount).map { i in
            let low = pow(10, logMin + step * Float(i))
            let high = pow(10, logMin + step * Float(i + 1))
            return (low, high)
        }
    }

        
    func logBandCenters(
        bandCount: Int,
        minFrequency: Float,
        maxFrequency: Float
    ) -> [Float] {

        let edges = logBandEdges(
            bandCount: bandCount,
            minFrequency: minFrequency,
            maxFrequency: maxFrequency
        )

        return edges.map { band in
            sqrt(band.low * band.high)
        }
    }

        
    func formatFrequency(_ hz: Float) -> String {
        if hz >= 1000 {
            return String(format: "%.1fkHz", hz / 1000)
        } else {
            return String(format: "%.0fHz", hz)
        }
    }
*/
            
    //MARK: Action methods
    @IBAction func seekForeward(_ sender: NSButton) {
        if playerItem != nil {
            if mediaPlayer.rate != 0.0 { mediaPlayer.pause() }
            mediaPlayer.currentItem?.seek(to: mediaPlayer.currentTime() + CMTime(value: 1, timescale: CMTimeScale(Int(videoFrameRate))), toleranceBefore: .zero, toleranceAfter: .zero , completionHandler: nil)
        }
    }
        
    @IBAction func seekBackward(_ sender: NSButton) {
        if playerItem != nil {
            if mediaPlayer.rate != 0.0 { mediaPlayer.pause()}  //  pause player
//            if mediaPlayer.currentItem!.canStepBackward { mediaPlayer.currentItem?.step(byCount: -1) }
            mediaPlayer.currentItem?.seek(to: mediaPlayer.currentTime() - CMTime(value: 1, timescale: CMTimeScale(Int(videoFrameRate))), toleranceBefore: .zero, toleranceAfter: .zero , completionHandler: nil)
        }
    }
    
    @IBAction func playFastForward(_ sender: NSButton) {
        if playerItem != nil {
            mediaPlayer.rate = mediaPlayer.rate + 2.0
        }
    }
    
    @IBAction func playFastbackWard(_ sender: NSButton) {
        if playerItem != nil {
            mediaPlayer.rate = mediaPlayer.rate - 2.0
        }
    }

    @IBAction func seekToBegining(_ sender: NSButton) {
        if playerItem != nil {
            mediaPlayer.pause()
            mediaPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    @IBAction func seekToEnd(_ sender: NSButton) {
        Task {
            let end = try await mediaAsset.load(.duration)
            if playerItem != nil {
                mediaPlayer.pause()
                await mediaPlayer.seek(to: end, toleranceBefore: .zero , toleranceAfter:  .zero)
                movieCurrentTime = scrubSlider.maxValue
            }
        }
    }
    
    
    @IBAction func muteAudio(_ sender: NSButton) {
        if !isMuted {
           //  audioVolumeBeforeMute = mediaPlayer.volume
            mediaPlayer.volume = 0.0
            isMuted = true
        } else {
           //  mediaPlayer.volume = audioVolumeBeforeMute
            isMuted = false
        }
    }
    
        
    @IBAction func removeAudioFromMovie(_ sender: NSMenuItem) {
            if playerItem != nil {
                Task {
                    //await removeAudio()
                    await insertOrRemoveAudio(loadUrl: nil)
                }
        }
    }

    
    @IBAction func loadMovie(_ sender: NSMenuItem)  {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.movie, UTType.audiovisualContent, UTType.video]
        panel.message = "Select a movie"
        let response = panel.runModal()
        if response == NSApplication.ModalResponse.OK {
            Task {
                await loadMovieFromURL(loadUrl: panel.url!)
                
            }
        }        
    }
    
    
    @IBAction func saveFile(_ sender: NSMenuItem) {
            //Check if there is a Movie to Save/Export
            if mediaPlayer.currentItem != nil {
                //Open Save Panel
                let savePanel = NSSavePanel()
                savePanel.directoryURL = folderToSaveFile
                switch sender.title {
                case "Save":
                    savePanel.message = "Save as a new file without transcoding video, audio: AAC, 320kbs."
                case "Export":
                    savePanel.message = "Export to \(espc.codecExportPopup.selectedItem!.title)."
                default:
                    savePanel.message = ""
                }
                savePanel.allowedContentTypes = [UTType.movie, UTType.audiovisualContent, UTType.video]
                savePanel.nameFieldStringValue =  url.lastPathComponent
                
                let response = savePanel.runModal()
                if response == NSApplication.ModalResponse.OK {
                    progressIndicator.alphaValue = 1.0
                    progressIndicator.startAnimation(self)
                    if sender.title == "Save" {
                        Task {
                            await readAndWriteSamples(inputAsset: mediaPlayer.currentItem!.asset, destURL: savePanel.url!)
                        }
                    }
                    if sender.title == "Export" {
                        exportMovie(toUrl: savePanel.url!)
                    }
                } else { return }
            } else { return }
    }
    
    @IBAction func clearViewer(_ sender: NSMenuItem) {
        removeSpectrumBarsAndMeterViews()
        playerItem = nil
        movieInfoDisplay.stringValue = ""
        movieTime.stringValue = String(format: "00:00:00:00")
        volumeSlider.isEnabled = false
        scrubSlider.isEnabled = false
        muteButton.isEnabled = false
        view.window?.title = "Americo's Movie Player"
        metersView.removeAll()
        mainViewMeters.subviews.removeAll()
    }
}


//MARK: Extension AVPlayer
extension AVPlayer {
    var isPlaying: Bool {
        if (self.rate != 0 && self.error == nil) {
            return true
        } else {
            return false
        }
    }
    
}

extension AVAssetTrack {
    var mediaFormat: String {
        var format = ""
        Task {
            let descriptions = try await self.load(.formatDescriptions)
            for (index, formatDesc) in descriptions.enumerated() {
                // Get String representation of media type (vide, soun, sbtl, etc.)
                let type =
                    CMFormatDescriptionGetMediaType(formatDesc).toString()
                // Get String representation media subtype (avc1, aac, tx3g, etc.)
                let subType =
                    CMFormatDescriptionGetMediaSubType(formatDesc).toString()
                // Format string as type/subType
                format += "\(type)/\(subType)"
                // Comma separate if more than one format description
                if index < descriptions.count - 1 {
                    format += ","
                }
            }
        }
        return format
    }
}
 
extension FourCharCode {
    // Create a String representation of a FourCC
    func toString() -> String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xff),
            CChar((self >> 16) & 0xff),
            CChar((self >> 8) & 0xff),
            CChar(self & 0xff),
            0
        ]
        let result = String(cString: bytes)
        let characterSet = CharacterSet.whitespaces
        return result.trimmingCharacters(in: characterSet)
    }
}



// MARK:// Old functions

/*
    func insertAudio(loadUrl: URL) async {
        //folder where the new composition will be saved
        print("insertAudio with url: \(loadUrl)")
        folderToSaveFile = loadUrl.deletingLastPathComponent()
        
        //Get the Audio Track
        let loadOptions = [AVURLAssetPreferPreciseDurationAndTimingKey : true]
        let audioAsset = AVURLAsset(url: loadUrl, options:loadOptions)
        print("audioAsset: \(audioAsset.description)")
        
        // Load audio track
        var sourceAudioTrack: AVAssetTrack?
        do {
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            sourceAudioTrack = audioTracks.first
        } catch {
            print("Error loading audio tracks: \(error.localizedDescription): \(AssetsError.noAudioTrack)")
        }
        guard let sourceAudioTrack = sourceAudioTrack else {
            print("No audio track found")
            return
        }
        print("sourceAudioTrack: \(String(describing: sourceAudioTrack))")
        
        
        //New Video Composition
        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        print("composition: \(composition.description)")
        
        let insertAtTime = mediaPlayer.currentTime()
        print("insertaAtTime: \(insertAtTime)")
        
        do {
            // Load video track
            let sourceVideoTrack = try await mediaPlayer.currentItem?.asset.loadTracks(withMediaType: .video).first
            print("Source Video Track loaded: \(String(describing: sourceVideoTrack))")
            
            guard let sourceVideoTrack = sourceVideoTrack,
                  let compositionVideoTrack = compositionVideoTrack else {
                let alert = NSAlert()
                alert.messageText = "Missing video tracks"
                alert.runModal()
                print("Missing video tracks")
                return
            }
            
            let x = CMTimeRangeMake(start: .zero, duration: self.duration!)
            print("Video Time Range x: \(x)")
            try compositionVideoTrack.insertTimeRange(x, of: sourceVideoTrack, at: .zero)
                                    
            let audioFormatDescriptions = try await sourceAudioTrack.load(.formatDescriptions)
            print("audioFormatDesc: \(audioFormatDescriptions.debugDescription)")
            
            // Extract ASBD from the first format description
            if let formatDesc = audioFormatDescriptions.first {
                self.audioFormatDesc = formatDesc
                if let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                    self.asbd = asbdPointer
                    print("ASBD successfully extracted")
                } else {
                    print("Could not get ASBD from format description")
                }
            }
            
            // Insert the audio track
            guard let compositionAudioTrack = compositionAudioTrack else {
                print("Composition audio track is nil")
                return
            }
            
            try compositionAudioTrack.insertTimeRange(
                CMTimeRangeMake(start: .zero, duration: self.duration!),
                of: sourceAudioTrack,
                at: insertAtTime
            )
            print("compostingAudioTrack: \(compositionAudioTrack.asset!.description)")
            
            // Create the new player item FIRST
            let assetKeys = ["playable", "tracks", "duration", "hasProtectedContent"]
            let newPlayerItem = AVPlayerItem(asset: composition, automaticallyLoadedAssetKeys: assetKeys)
            
            
            // Determine channel count
            let channelCount: Int
            if let asbd = self.asbd {
                channelCount = Int(asbd.pointee.mChannelsPerFrame)
                print("Channel count: \(channelCount), PlayerItem: \(newPlayerItem.description)")
            } else {
                print("ASBD is still nil, returning")
               return
            }
            
            // Setup processing tap with the new player item BEFORE assigning to self.playerItem
            self.tapi = TapProcessor()
            self.tapi.delegate = self
            await tapi.setupProcessingTap(playerItem: newPlayerItem, channels: channelCount)
            
            
            // Now update the instance variables on main thread
            await MainActor.run {
                self.playerItem = newPlayerItem
                self.chCount = channelCount
                self.movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc) + "\nAudio:\n" + getAudioTrackDescription(audioFormatDesc: audioFormatDesc)
                self.isMuted = false
            }
                    
            //Update meters View
            await MainActor.run {
                updateMetersView()
            }
            
        } catch {
            print("Error in audio/video processing: \(error)")
        }
    }
    
    func removeAudio() async {
        //New Video Composition
        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        print("composition: \(composition.description)")
        
        do {
            // Load video track
            let sourceVideoTrack = try await mediaPlayer.currentItem?.asset.loadTracks(withMediaType: .video).first
            print("Source Video Track loaded: \(String(describing: sourceVideoTrack))")
            
            guard let sourceVideoTrack = sourceVideoTrack,
                  let compositionVideoTrack = compositionVideoTrack else {
                print("Missing video tracks")
                return
            }
            
            let x = CMTimeRangeMake(start: .zero, duration: self.duration!)
            print("Video Time Range x: \(x)")
            try compositionVideoTrack.insertTimeRange(x, of: sourceVideoTrack, at: .zero)
                                
            // Create the new player item FIRST
            let assetKeys = ["playable", "tracks", "duration", "hasProtectedContent"]
            let newPlayerItem = AVPlayerItem(asset: composition, automaticallyLoadedAssetKeys: assetKeys)
                                
            // Now update the instance variables on main thread
            await MainActor.run {
                self.playerItem = newPlayerItem
                self.movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc)
            }
        } catch {
            print("Error removing processing: \(error)")
        }
    }
*/
    
