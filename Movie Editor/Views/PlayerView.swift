//
//  PlayerView.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 19/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

enum MediaFileType {
    case audio
    case video
    case unknown
    
    var avMediaType: AVMediaType? {
        switch self {
        case .audio: return .audio
        case .video: return .video
        case .unknown: return nil
        }
    }
}

class PlayerView: NSView {
    let supportedTypes: [NSPasteboard.PasteboardType] = [ .URL, .fileURL]
            
    override func awakeFromNib() {
        super.awakeFromNib()        
        self.registerForDraggedTypes(supportedTypes)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    //MARK: Drag and Drop
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canReadPasteboardObjects = sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
        
        if canReadPasteboardObjects {
            highlight()
               return .copy
           }
        
        return NSDragOperation()
    }
    
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingDestinationWindow?.orderFrontRegardless()
        guard let pasteboardObjects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil), pasteboardObjects.count > 0 else {
            return false
        }
                        
        pasteboardObjects.forEach { (object) in
            if let url = object as? URL {
                Task {
                    switch await checkFileType(url: url) {
                    case .video:
                        NotificationCenter.default.post(name: Notification.Name(rawValue: NOTIF_OPENFILE), object: url)
                        print("Video file selected")
                        break
                    case .audio:
                        NotificationCenter.default.post(name: Notification.Name(rawValue: NOTIF_REPLACE_AUDIO), object: url)
                        print("Audio file selected")
                        break
                    case .unknown:
                        return
                    }
                }
            }
            unhighlight()
        }
        return true
    }
    

    //MARK: checkFileType Robust but slow
    func checkFileType(url: URL) async -> MediaFileType {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("File does not exist at path: \(url.path)")
            return .unknown
        }
        
        // Try AVAsset to determine actual content type
        let asset = AVURLAsset(url: url)
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            // If it has video tracks, it's a video (even if it also has audio)
            if !videoTracks.isEmpty {
                return .video
            } else if !audioTracks.isEmpty {
                return .audio
            }
        } catch {
            print("Error opening AVURLAsset")
            let alert = NSAlert(error: error)
            alert.messageText = "Unsupported file type"
            alert.runModal()
            return .unknown
        }
        return .unknown
    }
    
    
    //MARK: checkFileTypeExt faster but weaker
    func checkFileTypeExt(url: URL) -> MediaFileType {
        // First, try using UTType (modern approach for macOS 11+)
        if #available(macOS 11.0, *) {
            if let utType = UTType(filenameExtension: url.pathExtension.lowercased()) {
                if utType.conforms(to: .audiovisualContent) {
                    if utType.conforms(to: .audio) {
                        return .audio
                    } else if utType.conforms(to: .movie) || utType.conforms(to: .video) {
                        return .video
                    }
                }
            }
        }
        
        // Fallback to extension-based checking
        let ext = url.pathExtension.lowercased()
        
        // Video formats
        let videoExtensions: Set<String> = [
            "mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv",
            "webm", "vob", "ogv", "ogg", "drc", "mng", "qt",
            "yuv", "rm", "rmvb", "asf", "amv", "mpg", "mpeg",
            "m2v", "svi", "3gp", "3g2", "mxf", "roq", "nsv"
        ]
        
        // Audio formats
        let audioExtensions: Set<String> = [
            "mp3", "wav", "aac", "m4a", "flac", "ogg", "wma",
            "aif", "aiff", "aifc", "caf", "opus", "oga", "mogg",
            "ape", "au", "amr", "awb", "dct", "dss", "dvf",
            "gsm", "iklax", "ivs", "m4b", "m4p", "mmf", "mpc",
            "msv", "nmf", "ra", "raw", "sln", "tta", "vox"
        ]
        
        if videoExtensions.contains(ext) {
            return .video
        } else if audioExtensions.contains(ext) {
            return .audio
        }
        
        return .unknown
    }


/*
    func checkFileType(url: URL) -> AVMediaType {
        print("Checking Extension")
        let extensionFile = url.pathExtension.lowercased()
        var mediaType: AVMediaType?
        switch extensionFile {
            case "mov":
                mediaType = .video
            case "mp4":
                mediaType = .video
            case "m4v":
                mediaType = .video
            case "wav":
                mediaType = .audio
            case "aif":
                mediaType = .audio
            case "aac":
                mediaType = .audio
            case "mp3":
                mediaType = .audio
        default:
            break
        }
        return mediaType ?? AVMediaType.depthData   //AVMediaType.depthData is a dummy return to prevent an exception
    }
*/
    func highlight() {
        self.layer?.borderColor = NSColor.controlAccentColor.cgColor
        self.layer?.borderWidth = 0.8
    }
    
    func unhighlight() {
        self.layer?.borderColor = NSColor.black.cgColor
        self.layer?.borderWidth = 0.5
    }
    
    
}


