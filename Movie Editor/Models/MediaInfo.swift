//
//  MediaInfo.swift
//  Movie Editor
//
//  Pure helpers that turn track format descriptions into display text.
//

import AVFoundation

extension FourCharCode {
    // Create a String representation of a FourCC
    func toString() -> String {
        let bytes: [CChar] = [
            CChar(truncatingIfNeeded: (self >> 24) & 0xff),
            CChar(truncatingIfNeeded: (self >> 16) & 0xff),
            CChar(truncatingIfNeeded: (self >> 8) & 0xff),
            CChar(truncatingIfNeeded: self & 0xff),
            0
        ]
        let result = String(cString: bytes)
        return result.trimmingCharacters(in: .whitespaces)
    }
}

enum MediaInfo {

    struct AudioInfo {
        let text: String
        let sampleRate: Float
        let channelCount: Int
    }

    /// HH:MM:SS:FF timecode.
    static func timecode(seconds: Double, frameRate: Float) -> String {
        guard frameRate > 0 else { return "00:00:00:00" }
        let frame = Int(Float(seconds) * frameRate)
        let ff = Int(Float(frame).truncatingRemainder(dividingBy: frameRate))
        let secs = Int(Float(frame - ff) / frameRate)
        return String(format: "%02i:%02i:%02i:%02i", secs / 3600, (secs % 3600) / 60, secs % 60, ff)
    }

    static func videoDescription(_ desc: CMFormatDescription, frameRate: Float, duration: CMTime) -> String {
        guard duration.isNumeric else { return "Error: Invalid duration" }

        let dims = CMVideoFormatDescriptionGetDimensions(desc)

        var primaries = ""
        if let p = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String {
            primaries = ", " + p
        }

        var scan = ""
        if let fields = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_FieldCount) as? NSNumber {
            scan = fields.intValue == 1 ? "p" : (fields.intValue == 2 ? "i" : "")
        }

        let depth = (CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_Depth) as? NSNumber)?.intValue ?? 0

        let fpsString: String
        switch Int(frameRate) {
        case 23, 29: fpsString = String(format: "%2.2f", frameRate)
        default:     fpsString = String(format: "%2.0f", frameRate)
        }

        var codec = ""
        if let name = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_FormatName) as? String {
            switch name {
            case "'apch'":              codec = "Apple ProRes 422 (HQ)"
            case "'avc1'", "'x264'":    codec = "H.264"
            case "'mpg4'", "'mp4v'":    codec = "MPEG-4 Video"
            case "'hev1'":              codec = "HEVC(hev1 tag not readable)"
            case "'hvc1'":              codec = "HEVC"
            default:                    codec = name
            }
        }

        let durationString = String(format: "%.2f", CMTimeGetSeconds(duration))
        return "Duration: \(durationString)s\nVideo:\n\(codec), \(dims.width)x\(dims.height)\(scan)\n\(fpsString)fps\(primaries), \(depth)bits\n"
    }

    /// Returns nil when the format has no usable stream description or no channels.
    static func audio(_ desc: CMFormatDescription) -> AudioInfo? {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee,
              asbd.mChannelsPerFrame > 0 else { return nil }

        let formatName: String
        switch asbd.mFormatID {
        case kAudioFormatLinearPCM:     formatName = "Linear PCM"
        case kAudioFormatMPEG4AAC:      formatName = "AAC"
        case kAudioFormatMPEG4AAC_LD:   formatName = "AAC-LD"
        case kAudioFormatMPEG4AAC_HE:   formatName = "AAC-HE"
        case kAudioFormatMPEG4AAC_ELD:  formatName = "AAC-ELD"
        case kAudioFormatAC3:           formatName = "AC3"
        case kAudioFormatAppleIMA4:     formatName = "Apple IMA4"
        case kAudioFormatMPEGLayer1:    formatName = "MPEG Layer 1"
        case kAudioFormatMPEGLayer2:    formatName = "MPEG Layer 2"
        case kAudioFormatMPEGLayer3:    formatName = "MPEG Layer 3"
        case kAudioFormatAppleLossless: formatName = "Apple Lossless"
        case kAudioFormatAMR:           formatName = "AMR"
        default:                        formatName = ""
        }

        let bits = asbd.mBitsPerChannel != 0 ? "\(asbd.mBitsPerChannel)bits, " : ""
        let channels = Int(asbd.mChannelsPerFrame)
        let channelName: String
        switch channels {
        case 1:  channelName = "Mono"
        case 2:  channelName = "Stereo"
        case 6:  channelName = "5.1"
        default: channelName = "\(channels)"
        }

        let sampleRate = Float(asbd.mSampleRate)
        let text = String(format: "\(formatName), \(bits)\(channelName),\n%2.0fHz", sampleRate)
        return AudioInfo(text: text, sampleRate: sampleRate, channelCount: channels)
    }
}
