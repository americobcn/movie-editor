//
//  MainViewController.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 19/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Foundation
import  AVFoundation
import AppKit

private var VIEW_CONTROLLER_KVOCONTEXT = 0
private var CURRENT_TIME_KVOCONTEXT = 0

class MainViewController: NSViewController, ExportSettingsPanelControllerDelegate, AudioLevelProviderDelegate {
    
    struct Spectrum {
        var freqs: [Float] = [Float]()
        var values: [Float] = [Float]()
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
    var folderToSaveFile: URL!
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
    let tapi = TapProcessor()
    private var meterTable = MeterTable()
    var meterTimer: Timer?
    var chCount = 2 // default value
    var chMetertablePeaks: [Float]!
    var chMetertableAvgs: [Float]!
    var spectrumMetertableCoeff: [Float]!
    var spectrumBands = 20 // default value
    var metertableSpectrum: [Float]!
    
    
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
    private var duration:CMTime = CMTime.zero           //  movie duration
    private var mediaPreferedRate: Float?
    
    var mediaTimeScale: CMTimeScale?
    var mediaPlayerRate: Float = 0.0
    var audioVolumeBeforeMute: Float = 0.0
    var loadedVideoTrackID: CMPersistentTrackID!
    var loadedAudioTrackID: CMPersistentTrackID!
        
    var fileType: AVMediaType!
    var videoFormatDesc: CMFormatDescription!
    var audioFormatDesc: CMFormatDescription!
    var asbd: UnsafePointer<AudioStreamBasicDescription>?                 //Audio Strem Basic Description
    var currentAssetTimeScale: CMTimeScale!
    
    var movieDimensions: CMVideoDimensions?
    var movieColorPrimaries: String = ""   //CFPropertyList?
    var movieFieldCount: CFPropertyList?
    var movieDepth: CFPropertyList?
    var movieCodec: String = ""
    var videoFrameRate: Float = 0.0
    var numChannels: Int = 0
    
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
            mediaPlayer.volume = (pow(100.0, volumeSlider.floatValue) - 1.0) / 99.0
            }
        }
    }
    
//MARK: Overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tapi.delegate = self
        
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

            if CMTimeGetSeconds(elapsedTime) == CMTimeGetSeconds(self.duration)
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
        
        chMetertablePeaks = [Float](repeating: 0.0, count: chCount)
        chMetertableAvgs = [Float](repeating: 0.0, count: chCount)
        metertableSpectrum = [Float](repeating: 0.0, count: spectrumBands) // spectrumBands default value
        spectrumMetertableCoeff = [Float](repeating: 0.0, count: spectrumBands)
        createSpectrumView()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        //Setting the delegate
        espc?.delegate = self
        
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
//       addObserver for Load a movie file
        NotificationCenter.default.addObserver(self, selector: #selector(handleDragNotification(_:)),
        name: Notification.Name(rawValue: NOTIF_OPENFILE), object: nil)
//       addObserver for replace audio
        NotificationCenter.default.addObserver(self, selector: #selector(handleDragNotification(_:)),
        name: Notification.Name(rawValue: NOTIF_REPLACE_AUDIO), object: nil)
                
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?)
            {
                //  make sure the this KVO callback was intended for this view controller
                guard context == &VIEW_CONTROLLER_KVOCONTEXT else {
                    super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
                    return
                }
                
    //            if keyPath == #keyPath(MainViewController.scrubSlider)
    //            {
    //                print("Called scrubSlider observer")
    //                if let newValue = change?[NSKeyValueChangeKey.newKey] as? Double {
    //                    print("scrubSlider: \(newValue)")
    //                    mediaPlayer.pause()
    //                }
    //
    //            }
                if keyPath == #keyPath(MainViewController.mediaPlayer.rate)
                {
                    if let actualRate = change?[NSKeyValueChangeKey.newKey] as? Float {
//                        print("MediaPlayerRate Observer called")
                        switch actualRate {
                        case 0.0:
                            playPauseBtn.title = "Play"
                        default:
                            playPauseBtn.title = "Stop"
                            
                        }
//                        if rateAsValue == 0.0 {
//                            playPauseBtn.title = "Play"
//
//                        }
                    }
                }
                
                if keyPath == #keyPath(MainViewController.mediaPlayer.currentItem.duration)
                {
                    //  handle NSNull value for NSKeyValueChangeNewKey
                    //  i.e. when `player.currentItem` is nil
//                     print("Called durations observer")
                    if let durationAsValue = change?[NSKeyValueChangeKey.newKey] as? NSValue
                    {
                        duration = durationAsValue.timeValue
                    }
                    else { duration = CMTime.zero }
                    
                    let hasValidDuration = duration.isNumeric && duration.value != 0
                    
                    scrubSlider!.isEnabled = hasValidDuration
                    scrubSlider!.floatValue = hasValidDuration ? Float(CMTimeGetSeconds(mediaPlayer.currentTime())) : 0.001
                    scrubSlider!.maxValue =  hasValidDuration ? Double(CMTimeGetSeconds(duration)) : 0.001

                }
                

                // Here we observe PlayerItem status, if it change, a new Player Item will be set
                if keyPath == #keyPath(MainViewController.mediaPlayer.currentItem.status)
                {
//                    print("Called status observer")
                    //    display error if status becomes `.Failed`
//                    print("Observing keyPath: MainViewController.mediaPlayer.currentItem.status")
                    //  handle NSNull value for NSKeyValueChangeNewKey
                    //  i.e. when `player.currentItem` is nil
                    let newStatus: AVPlayerItem.Status
                    
                    if let newStatusAsNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber
                    {
                        newStatus = AVPlayerItem.Status(rawValue: newStatusAsNumber.intValue)!
                    }
                    else { newStatus = .unknown }
                    
                    if newStatus == .failed
                    {
    //                    handleErrorWithMessage(mediaPlayer.currentItem?.error?.localizedDescription, error:mediaPlayer.currentItem?.error)
                        print("Error")
                    }
                }
                
//                if keyPath == #keyPath(MainViewController.exporter.progress)
//                {
//                    print("Observing keyPath: MainViewController.progressIndicator")
//                    if let newValue = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
//                        progressIndicator.doubleValue = Double(truncating: newValue)
//                        print("PROGRESS: \(progress)")
//                    }
//                }
            }
            
            override class func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String>
            {
                let affectedKeyPathsMappingByKey: [String: Set<String>] = [
                    "duration":             [#keyPath(MainViewController.mediaPlayer.currentItem.duration)],
                    "rate":                 [#keyPath(MainViewController.mediaPlayer.rate)],
                    "movieVolume":          [#keyPath(MainViewController.mediaPlayer.volume)]
//                    "progress":             [#keyPath(MainViewController.exporter.progress)]
                    //playPauseBtn.title = "Play"
                ]
                return affectedKeyPathsMappingByKey[key] ?? super.keyPathsForValuesAffectingValue(forKey: key)
            }

//  MARK: Delegate funcions
    
    func exportPresetDidChange(_ preset: String) {
//        print("Delegate called")
        exportPreset = preset
    }

//MARK: Delegate function
    func levelsDidChange(peaks:[Float], averages:[Float], spectrum: [[Float]], bandsCount: Int) {
        //Updating coefficients for drawing metersView and spectrumViews
        for (index, peak) in peaks.enumerated() {
            self.chMetertablePeaks[index] = meterTable.valueForPower(peak)
        }

        for (index, avg) in averages.enumerated() {
            self.chMetertableAvgs[index] = meterTable.valueForPower(avg)
        }
        
        for index in 0..<self.spectrumBands {
            self.spectrumMetertableCoeff[index] = meterTable.valueForPower(spectrum[0][index])
            }
    }

    
//MARK: Functions
    
    func loadMovieFromURL(loadUrl: URL) {
        
        //folder where the new file will be saved
        folderToSaveFile = loadUrl.deletingLastPathComponent()
        //From 'url' we will recover the file name for saving file
        url = loadUrl
//        let file_name = loadUrl.lastPathComponent
        //Pause player if it is playing
        if mediaPlayer.rate != 0 {
            mediaPlayer.pause()
        }
        
        //Load mediaAsset
        let loadOptions = [AVURLAssetPreferPreciseDurationAndTimingKey : true]
        mediaAsset = AVURLAsset(url: loadUrl, options: loadOptions)
        if mediaAsset.tracks(withMediaType: AVMediaType.video).count == 0 {
            return
        }
        print("mediaAsset: \(mediaAsset.tracks.debugDescription)")
        let assetKeys = ["playable", "tracks", "duration", "hasProtectedContent"]
        
        //Load and Inspecting Video Track

        if let videoTrack = mediaAsset.tracks(withMediaType: .video).first {
            videoFormatDesc = (videoTrack.formatDescriptions[0] as! CMFormatDescription)
            loadedVideoTrackID = videoTrack.trackID
            videoFrameRate = videoTrack.nominalFrameRate
            if let formatName = CMFormatDescriptionGetExtension(videoFormatDesc, extensionKey: kCMFormatDescriptionExtension_FormatName) {
                if formatName as! String == "'hev1'" {
                    let alertPanel = NSAlert() //
                    alertPanel.alertStyle = .warning
                    alertPanel.messageText = "Do you want to load a copy with the correct file tag?"
                    alertPanel.informativeText = "This is a HEVC(H.265) file tagged as 'hev1', the file should have the 'hvc1' tag."
                    alertPanel.addButton(withTitle: "Save")
                    alertPanel.addButton(withTitle: "Cancel")
                    alertPanel.beginSheetModal(for: self.view.window!, completionHandler: { result in
                        if result == .alertFirstButtonReturn {
                            let tagEditor = TagEditor(url: self.url)
                            let savedURL = tagEditor.changeTagFile()
                            if savedURL != self.url {
                                self.loadMovieFromURL(loadUrl: savedURL)
                            }
                        } else { return }
                    })
                    
                }
            }
//            print("-------------------------------------")
//            print("VIDEO DESCRIPTORS:")
//            print(videoFormatDesc!)
//            print("-------------------------------------")
//            print("************** VIDEO TRACK ***********************************************")
//            print("**************************************************************************")
//            print("TrackID:                 \(videoTrack.trackID)")
//            print("Is Decodable:            \(videoTrack.isDecodable)")
//            print("Common Metadata:         \(videoTrack.commonMetadata)")
//            print("Metadata:                \(videoTrack.metadata)")
//            print("Available Metadata:      \(videoTrack.availableMetadataFormats)")
//            print("Estimated Data Rate:     \(videoTrack.estimatedDataRate / 1024) MBs per Secons)")
//            print("Minim Frame duration:    \(videoTrack.minFrameDuration)")
//            print("Nominal Frame Rate:      \(videoTrack.nominalFrameRate)")
//            print("Time Range:              \(videoTrack.timeRange)")
//            print("Natural Size:            \(videoTrack.naturalSize)")
            print("Format Descriptions:     \(videoTrack.formatDescriptions)")
//            print("**************************************************************************")
//            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc)
                    
        } else { return }

        print(mediaAsset.tracks(withMediaType: .audio).debugDescription)
        //Inspecting Audio Track
        if let audioTrack = mediaAsset.tracks(withMediaType: .audio).first {
            hasAudioTrack = true
            audioFormatDesc = (audioTrack.formatDescriptions[0] as! CMFormatDescription)
            if let asbdLocal = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc) {
                asbd = asbdLocal
            }
            chCount = Int((asbd?.pointee.mChannelsPerFrame)!)
//            print("Channel Count: \(chCount)")
            loadedAudioTrackID = audioTrack.trackID
            
//            print("-------------------------------------")
//            print("AUDIO DESCRIPTORS:")
//            print(audioFormatDesc!)
//            print("-------------------------------------")
//            print("************** AUDIO TRACK ***********************************************")
//            print("**************************************************************************")
//            print("TrackID: \(audioTrack.trackID)")
//            print("Is Decodable: \(audioTrack.isDecodable)")
//            print("Common Metadata: \(audioTrack.commonMetadata)")
//            print("Available Metadata: \(audioTrack.availableMetadataFormats)")
//            print("Estimated Data Rate: \(audioTrack.estimatedDataRate / 1024) MBs per Secons")
//            print("Audio Format Descriptors: \(String(describing: audioFormatDesc))")
//            print("**************************************************************************")
//            print("AUDIO STREAM BASIC DESCRIPTORS: \n\(String(describing: asbd?.pointee))")
            
//            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc) + "\nAudio:\n" +
//                                            getAudioTrackDescription(audioFormatDesc: audioFormatDesc)
                        
                    
        } else {
            hasAudioTrack = false
        }
        
        
        
        //Associate to player Item to load on viewer
        playerItem = AVPlayerItem(asset: mediaAsset, automaticallyLoadedAssetKeys: assetKeys)
        currentAssetTimeScale = playerItem?.asset.duration.timescale
        self.view.window?.title =  loadUrl.lastPathComponent
                    
        //Seting initial audio volume and mute  button state
        muteButton.isEnabled = true
        volumeSlider.isEnabled = true
        volumeSlider.floatValue = mediaPlayer.volume
        // isMuted = false
        
        //Setup the Tap for processing audio
        if hasAudioTrack {
            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc) + "\nAudio:\n" +
                                            getAudioTrackDescription(audioFormatDesc: audioFormatDesc)
            tapi.setupProcessingTap(playerItem: playerItem, channels: chCount)
            //Adding channels view
            updateMetersView()
        } else {
            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc)
        }
        
    }
    
    func getVideoTrackDescription(videoFormatDesc: CMFormatDescription) -> String {
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
        
        videoDescription = String(format: "Video:\n\(movieCodec), \(String(describing: movieDimensions!.width))x\(String(describing: movieDimensions!.height))\(interlacedPregressive)\n\(videoFrameRateString)fps\(movieColorPrimaries), %ibits\n",Int(truncating: movieDepth! as! NSNumber))
        return videoDescription
    }
    
    func getAudioTrackDescription(audioFormatDesc: CMFormatDescription) -> String {
        var audioDescription = ""
        var formatID: AudioFormatID!
        var formatIDDescription: String = ""
        var bitsPerChannel: UInt32 = 0
        var bitsPerChannelDescription: String = ""
        var sampleRate: Float64!
        var channels: UInt32!
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
        if let tempSampleRate = asbd?.pointee.mSampleRate {sampleRate = tempSampleRate }
        //Channels
        if let tempChannels = asbd?.pointee.mChannelsPerFrame {channels = tempChannels }
        switch channels {
        case 1:
            channelsDescription = "Mono"
            numChannels = 1
            break
        case 2:
            channelsDescription = "Stereo"
            numChannels = 2
            break
        case 6:
            channelsDescription = "5.1"
            numChannels = 6
            break
        default:
            channelsDescription  = String("\(channels)")
            break
        }
        
        
        
        audioDescription = String(format:"\(formatIDDescription), \(bitsPerChannelDescription)\(channelsDescription),\n%2.0fHz",sampleRate)
        
        
        
        return audioDescription
    }
    
    func insertAudio(loadUrl: URL) {
        //folder where the bew file will be saved
        folderToSaveFile = loadUrl.deletingLastPathComponent()
//        print(folderToSaveFile)
        //Get the Audio Track
        let audioAsset = AVAsset(url: loadUrl)
        let insertAtTime = mediaPlayer.currentTime()
        
        //New Video Composition
        let composition = AVMutableComposition()
        
        //Inserting Video Track
        let compostitionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let sourceVideoTrack = mediaPlayer.currentItem?.asset.tracks(withMediaType: .video).first
        let x = CMTimeRangeMake(start: .zero, duration: (mediaPlayer.currentItem?.asset.duration)!)
        try! compostitionVideoTrack!.insertTimeRange(x, of: sourceVideoTrack!, at: .zero)
    
        //Inserting Audio Track
        let compostitionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first
        try! compostitionAudioTrack!.insertTimeRange(x, of: sourceAudioTrack!, at: insertAtTime)
    
        //Replacing mediaItem in the player
        playerItem = AVPlayerItem(asset: (compostitionVideoTrack?.asset)!)
        audioFormatDesc = (sourceAudioTrack!.formatDescriptions[0] as! CMFormatDescription)
        if let asbdLocal = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc) {
            asbd = asbdLocal
        }
        chCount = Int((asbd?.pointee.mChannelsPerFrame)!)
        
        movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc) + "\nAudio:\n" + getAudioTrackDescription(audioFormatDesc: audioFormatDesc)
        
        //Adding the Tap for process
        tapi.setupProcessingTap(playerItem: playerItem, channels: chCount)
        isMuted = false
        //Update metewrs View
//        print("chCount: \(chCount)")
        updateMetersView()
    }
    
    @objc func handleDragNotification(_ notification: Notification) {
        if notification.name.rawValue == NOTIF_OPENFILE {
            if let url:URL = notification.object as? URL {
                loadMovieFromURL(loadUrl: url)
            }
        } else if notification.name.rawValue == NOTIF_REPLACE_AUDIO {
            if let url:URL = notification.object as? URL {
                insertAudio(loadUrl: url)
            }
        }
    }
    
    func readAndWriteSamples(inputAsset: AVAsset, destURL: URL, completion:@escaping (URL)->Void) {
//        print("Saving...")
        var audioFinished = false
        var videoFinished = false
        
        //Initialize assetReader and assetWriter
        do {
               assetReader = try AVAssetReader(asset: inputAsset)
            } catch {
               print("Can't initialize assetReader")
           }
           
        do {
            assetWriter = try AVAssetWriter(outputURL: destURL, fileType: .mov)
           } catch {
               print("Can't initialize assetReader")
           }
           
        //Configuring readerTackOutput for assetReader
        let videoTrack = inputAsset.tracks(withMediaType: .video).first
        videoTrackOutput = AVAssetReaderTrackOutput(track: videoTrack!, outputSettings: nil)
        if assetReader.canAdd(videoTrackOutput) {
               assetReader.add(videoTrackOutput)
           } else {
               fatalError("No se ha podido añadir videoTrackOutput")
        }
        
        //Configuring Audio Track for reading
        let audioTrack =  inputAsset.tracks(withMediaType: .audio).first
        // Maybe we don't have audio
        audioFinished = true
        if audioTrack != nil {
            audioFinished = false
            audioFormatDesc = (audioTrack!.formatDescriptions[0] as! CMFormatDescription)
            let asbdLocal = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
            let mSampleRate = (Float(asbdLocal!.pointee.mSampleRate))
            let mChannelsPerFrame = (Int(asbdLocal!.pointee.mChannelsPerFrame))
            var mBitsPerChannel:Int = 0
            mBitsPerChannel = (Int(asbdLocal!.pointee.mBitsPerChannel))
            if mBitsPerChannel == 0 {
                 mBitsPerChannel = 24
            }
            
            let audioSettingsReader:[String:Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                                                    AVSampleRateKey: NSNumber(value:mSampleRate),
                                                    AVNumberOfChannelsKey: NSNumber(value: mChannelsPerFrame),
                                                    AVLinearPCMBitDepthKey: NSNumber(value: mBitsPerChannel) ,
                                                    AVLinearPCMIsFloatKey: false,
                                                    AVLinearPCMIsBigEndianKey: false,
                                                    AVLinearPCMIsNonInterleaved: false]
            print("audioSettingsReader passed")
            audioTrackOutput = AVAssetReaderTrackOutput(track: audioTrack!, outputSettings: audioSettingsReader)
            if assetReader.canAdd(audioTrackOutput) {
                    assetReader.add(audioTrackOutput)
                } else {
                    fatalError("No se ha podido añadir audioTrackOutput")
            }

            var bitRate: Int!
            switch asbdLocal!.pointee.mChannelsPerFrame {
            case 1:
                bitRate = 160000
            case 2:
                bitRate = 320000
            default:
                bitRate = 256000
            }
            
//            Configuring writer
            let audioSettingsWriter:[String:Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: NSNumber(value: mSampleRate),
                AVNumberOfChannelsKey: NSNumber(value: mChannelsPerFrame),
                AVEncoderBitRateKey: bitRate,
                AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant]
            
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettingsWriter)
            audioInputQueue = DispatchQueue(label: "audioQueue")
            assetWriter.add(audioInput)
        }
        

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormatDesc)
                
//        Configuring queue for each track
        let videoInputQueue = DispatchQueue(label: "videoQueue")
    
        assetWriter.add(videoInput)
        
        assetWriter.startWriting()
        assetReader.startReading()
        assetWriter.startSession(atSourceTime: .zero)
        
        let closeWriter:()->Void = {
            if (audioFinished && videoFinished){
                self.assetWriter?.finishWriting(completionHandler: {
                    DispatchQueue.main.async {
                    completion((self.assetWriter?.outputURL)!)
                        if self.assetWriter.status == .failed {
                            print("Writing asset failed ☹️ Error: \(String(describing: self.assetWriter.error))")
                        }
                        if self.assetWriter.status == .completed {
                            self.progressIndicator.stopAnimation(self)
                            self.progressIndicator.alphaValue = 0.0
                            print("Writing asset succesfully writed ")
                        }
                    }
                })
                self.assetReader?.cancelReading()
            }
        }
        
        if audioInput != nil {
            audioInput.requestMediaDataWhenReady(on: audioInputQueue) {
             //request data here
             while(self.audioInput.isReadyForMoreMediaData){
                let sample = self.audioTrackOutput.copyNextSampleBuffer()
                    if (sample != nil){
                     self.audioInput.append(sample!)
                    }else{
                         self.audioInput.markAsFinished()
                         DispatchQueue.main.async {
                            audioFinished = true
                            closeWriter()
                        }
                        break;
                    }
                }
            }
        }
                   
           videoInput.requestMediaDataWhenReady(on: videoInputQueue) {
               //request data here
               while(videoInput.isReadyForMoreMediaData){
                let sample = self.videoTrackOutput.copyNextSampleBuffer()
                   if (sample != nil){
                       videoInput.append(sample!)
                   }else{
                       videoInput.markAsFinished()
                       DispatchQueue.main.async {
                           videoFinished = true
                           closeWriter()
                       }
                       break;
                   }
               }
           }
           
       }
    
    
   func exportMovie(toUrl: URL) {
        //Determining Compatipbility
    
    print("Exporting...\(String(describing: exportPreset))")
    guard let composition = mediaPlayer.currentItem?.asset else { return }
    let compatibles = AVAssetExportSession.exportPresets(compatibleWith: composition)
    print(compatibles)
    AVAssetExportSession.determineCompatibility(ofExportPreset: exportPreset, with: composition, outputFileType: .mp4, completionHandler: { (isCompatible) in
            if !isCompatible {
                print("NO ES COMPATIBLE")
                return
        }})
        //Generating the export session
    guard let exporter = AVAssetExportSession(asset: composition, presetName: exportPreset) else { return }
        exporter.outputFileType = AVFileType.mp4
        exporter.outputURL = toUrl
    // Make porgressor Indicator visible
//        progressIndicator.alphaValue = 1.0
//        progressIndicator.startAnimation(self)
        exporter.exportAsynchronously {
            print("EXPORTING..... PRESET: \(self.exportPreset)")
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(self)
                self.progressIndicator.alphaValue = 0.0
            }
            switch exporter.status {
            case .completed:
                print("Succes")
                break
            case .failed:
                print("Something goes wrong")
                break
            default:
                break
            }
        }
    }
    
//  Functions called from movieCurrentTimme computed properties to smoothly scrubing
    
//    public func seek(to time: CMTime) {
//        seekSmoothlyToTime(newChaseTime: time)
//    }
    
    private func seekSmoothlyToTime(newChaseTime: CMTime) {
        if CMTimeCompare(newChaseTime, chaseTime) != 0 {
            chaseTime = newChaseTime
            if !isSeekInProgress {
//                print("seekSmoothlyToTime called --- trySekkToChaseTime")
                trySeekToChaseTime()
            }
        }
    }
    
    private func trySeekToChaseTime() {
        guard mediaPlayer.status == .readyToPlay else { return }
//        print("trySekkToChaseTime called --- actuallySeekToTime")
        actuallySeekToTime()
    }
    
    private func actuallySeekToTime() {
        isSeekInProgress = true
        let seekTimeInProgress = chaseTime
        
        mediaPlayer.seek(to: seekTimeInProgress, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let `self` = self else { return }
//            print("seekTo completion: called --- trySeekToChaseTime")
            if CMTimeCompare(seekTimeInProgress, self.chaseTime) == 0 {
                self.isSeekInProgress = false
            } else {
                self.trySeekToChaseTime()
            }
        }
    }
    
    @objc func recalculateMeters() {
            for (idx, view) in self.mainViewMeters.subviews.enumerated() {
                view.animator().setFrameSize(NSSize(width: 10.0 , height: 130.0 * CGFloat(self.chMetertablePeaks[idx] * self.volumeSlider.floatValue)))  // ERRRORRRRRR
            }
        
            for (idx, view) in self.mainSpectrumViewMeters.subviews.enumerated() {
                view.animator().setFrameSize(NSSize(width: 20.0 , height: 130.0 * CGFloat(self.spectrumMetertableCoeff[idx])))
            }
    }
        
    func updateMetersView() {
        volumeSlider.floatValue = 1.0 // Sometimes when replacing a movie gets to 0.0
        muteButton.floatValue = 0.0
        metersView.removeAll()
        mainViewMeters.subviews.removeAll()
        //Adding meterViews
        if (metersView.count == 0 && mainViewMeters.subviews.count == 0) {
            for i in 0..<chCount {
//                print("Adding \(chCount) views to mainViewMeters")
                metersView.append(MeterView())
                let shift = i * 11
                metersView[i].setFrameOrigin(NSPoint(x: Double(shift), y: 0.0 ))
                mainViewMeters.addSubview(metersView[i])
            }
        }
    }
        
    func createSpectrumView() {
        //Setting up Spectrum visualizer
        for i in 0..<spectrumBands {
            let shift = i * 20
            spectrumMeters.append(SpectrumBarView())
            spectrumMeters[i].setFrameOrigin(NSPoint(x: 0.0 + Double(shift), y: 0.0))
            mainSpectrumViewMeters.addSubview(spectrumMeters[i])
        }
    }
        
    func handleTimer(status: playerStatus) {
        switch status {
        case .playing:
            meterTimer = Timer.scheduledTimer(timeInterval: 0.010/Double(videoFrameRate), target: self, selector: #selector(recalculateMeters), userInfo: nil, repeats: true)
        case .stopped:
            meterTimer?.invalidate()
            //While in pause, set the meters to 0.0
            for view in metersView {
                view.animator().setFrameSize(NSSize(width: 10.0 , height: 0.0))
            }
            for (_, view) in self.mainSpectrumViewMeters.subviews.enumerated() {
//                print("Updating \(self.mainSpectrumViewMeters.subviews.count)")
                view.animator().setFrameSize(NSSize(width: 20.0 , height: 0.0))
            }
        }
    }

//  MARK: Action Methods for Player Transport
        
    @IBAction func playPauseVideo(_ sender: NSButton) {
        if playerItem != nil {
            if (mediaPlayer.timeControlStatus == AVPlayer.TimeControlStatus.playing) {
                mediaPlayer.pause()
                handleTimer(status: .stopped)
            // If playerItem arrive at the end of the movie
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
        if playerItem != nil {
            mediaPlayer.pause()
//            print("Duration in Seconds: \(mediaAsset.duration)")
            mediaPlayer.seek(to: mediaAsset.duration, toleranceBefore: .zero , toleranceAfter:  .zero)
            movieCurrentTime = scrubSlider.maxValue
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
            let composition = AVMutableComposition()
            let compostitionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let sourceVideoTrack = mediaPlayer.currentItem?.asset.tracks(withMediaType: .video)
            let x = CMTimeRangeMake(start: .zero, duration: (mediaPlayer.currentItem?.asset.duration)!)
            try! compostitionVideoTrack!.insertTimeRange(x, of: sourceVideoTrack![0], at: .zero)
            let newMediaItem = AVPlayerItem(asset: (compostitionVideoTrack?.asset)!)
            mediaPlayer.replaceCurrentItem(with: newMediaItem)
            movieInfoDisplay.stringValue = getVideoTrackDescription(videoFormatDesc: videoFormatDesc)
        }
    }
    
    @IBAction func loadMovie(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["mov","mp4"]
        panel.message = "Select a movie"
        let response = panel.runModal()
        if response == NSApplication.ModalResponse.OK {
            loadMovieFromURL(loadUrl: panel.url!)
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
            savePanel.allowedFileTypes = ["mov", "mp4"]
            savePanel.nameFieldStringValue =  url.lastPathComponent   //(self.view.window?.title as! String)
        
            let response = savePanel.runModal()
            if response == NSApplication.ModalResponse.OK {
                progressIndicator.alphaValue = 1.0
                progressIndicator.startAnimation(self)
                if sender.title == "Save" {
                    readAndWriteSamples(inputAsset: mediaPlayer.currentItem!.asset, destURL: savePanel.url!, completion: {_ in })
                }
                if sender.title == "Export" {
                    exportMovie(toUrl: savePanel.url!)                    
                }
            } else { return }
        } else { return }
    }
    
    @IBAction func clearViewer(_ sender: NSMenuItem) {
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
        let descriptions = self.formatDescriptions as! [CMFormatDescription]
//        for desc in descriptions {
//            print("-----------------------------------------------------------")
//            print("Extensions: \(String(describing: CMFormatDescriptionGetExtension(desc , extensionKey: "Extensions" as CFString)))")
//            print("-----------------------------------------------------------")
//        }
        
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

