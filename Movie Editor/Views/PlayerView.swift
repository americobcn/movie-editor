//
//  PlayerView.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 19/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

class PlayerView: NSView {
    
    let supportedTypes: [NSPasteboard.PasteboardType] = [ .URL, .fileURL]
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Drawing code here.

    
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()        
        self.registerForDraggedTypes(supportedTypes)
        
    }
    

//    MARK: Drag and Drop
    
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
            if let url = object as? NSURL {
                switch checkFileType(url: url as URL) {
                case AVMediaType.video:
                    NotificationCenter.default.post(name: Notification.Name(rawValue: NOTIF_OPENFILE), object: url)
                case AVMediaType.audio:
                    NotificationCenter.default.post(name: Notification.Name(rawValue: NOTIF_REPLACE_AUDIO), object: url)
                default:
                    break
                }
            }
            unhighlight()
        }
        return true
    }
    

//    MARK: Functions
    
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
    
    func highlight() {
        self.layer?.borderColor = NSColor.controlAccentColor.cgColor
        self.layer?.borderWidth = 0.8
    }
    
    func unhighlight() {
        self.layer?.borderColor = NSColor.black.cgColor
        self.layer?.borderWidth = 0.5
    }
    
    
}


