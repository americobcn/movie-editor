//
//  TagEditor.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 10/05/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//
//  This class will edit the tag file 'hev1' of a HEVC movie file, aka H.265 into 'hvc1' tag that Apple apis can read.
//  You have to initialize the class with the original URL, after that you call changeTagFile().
//  changeTagFile() will save a copy of the movie with the correct TAG and will return the url of the copy.
//


class TagEditor: NSObject {
    
    private var urlToChange: URL!
    private var data: Data?
    
    var finalURL: URL?
    
    var isChanged: Bool = false
    var isSaved: Bool = false
        
    override init() {
        super.init()
    }
    
    init(url: URL) {
        self.urlToChange = url
    }
    
    func changeTagFile() -> URL {
        
        do {
            data = try Data(contentsOf: urlToChange)
            //Tag to lookfor as Data
            let pattern: Data? = "hev1".data(using: .utf8)
            //Tag ok as Data
            let replaceData: Data? = "hvc1".data(using: .utf8)
            // Look for the wrong tag
            if let range = data!.range(of: pattern!) {
                // Replace the wrong Tag with the Ok one
                data!.replaceSubrange(range, with: replaceData!)
                //
                if data?.subdata(in: range) == replaceData {
                    print("TAG changed")
                    isChanged = true
                } else { print("Somethig went wrong") }
            }
        } catch { print("Error reading data") }
        
        //Tryieng to save a copy
        
        if isChanged {
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.allowedFileTypes = ["mov", "mp4"]
            savePanel.allowsOtherFileTypes = false
            savePanel.nameFieldStringValue = urlToChange.lastPathComponent
            savePanel.message = "Save a copy of the file with the TAG 'hvc1'."
            let response = savePanel.runModal()
            if response == NSApplication.ModalResponse.OK {
                do {
                    print("Writing a copy")
                    finalURL = savePanel.url
                    print(finalURL as Any)
                    try data?.write(to: finalURL!)
                    isSaved = true
                } catch { print("Writing file error.")}
            } else if response == NSApplication.ModalResponse.cancel {
                return urlToChange
            }
        } else { print("Tag is not ok")}
        
        return finalURL!
    }
    
}
