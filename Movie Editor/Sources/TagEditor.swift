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

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Errors that can occur during tag editing operations
enum TagEditorError: LocalizedError {
    case fileReadFailed(URL, Error)
    case fileWriteFailed(URL, Error)
    case tagNotFound
    case tagReplacementFailed
    case noDestinationSelected
    
    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url, let error):
            return "Failed to read file at \(url.path): \(error.localizedDescription)"
        case .fileWriteFailed(let url, let error):
            return "Failed to write file to \(url.path): \(error.localizedDescription)"
        case .tagNotFound:
            return "The 'hev1' tag was not found in the file"
        case .tagReplacementFailed:
            return "Tag replacement verification failed"
        case .noDestinationSelected:
            return "No destination file was selected"
        }
    }
}

/// Result of a tag editing operation
struct TagEditResult {
    let outputURL: URL
    let wasModified: Bool
    let message: String
}

/// Editor for converting video codec tags from 'hev1' to 'hvc1'
final class TagEditor {
    
    // MARK: - Properties
    
    private let sourceURL: URL
    private let sourceTag = Data("hev1".utf8)
    private let targetTag = Data("hvc1".utf8)
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.sourceURL = url
    }
    
    // MARK: - Public Methods
    
    /// Processes the video file and changes the codec tag if necessary
    /// - Returns: Result containing the output URL and operation details
    /// - Throws: TagEditorError if the operation fails
    func changeTagFile() throws -> TagEditResult {
        // Read file data
        let data = try readFileData()
        
        // Check if tag replacement is needed
        guard let range = data.range(of: sourceTag) else {
            return TagEditResult(
                outputURL: sourceURL,
                wasModified: false,
                message: "File already uses 'hvc1' or tag not found"
            )
        }
        
        // Replace tag
        var modifiedData = data
        modifiedData.replaceSubrange(range, with: targetTag)
        
        // Verify replacement
        guard modifiedData.subdata(in: range) == targetTag else {
            throw TagEditorError.tagReplacementFailed
        }
        
        // Get destination URL
        guard let destinationURL = openSavePanel() else {
            throw TagEditorError.noDestinationSelected
        }
        
        // Write modified data
        try writeFileData(modifiedData, to: destinationURL)
        
        return TagEditResult(
            outputURL: destinationURL,
            wasModified: true,
            message: "Successfully converted 'hev1' to 'hvc1' tag"
        )
    }
    
    // MARK: - Private Methods
    
    /// Reads the entire file into memory
    private func readFileData() throws -> Data {
        do {
            return try Data(contentsOf: sourceURL)
        } catch {
            throw TagEditorError.fileReadFailed(sourceURL, error)
        }
    }
    
    /// Writes data to the specified URL
    private func writeFileData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw TagEditorError.fileWriteFailed(url, error)
        }
    }
    
    /// Displays a save panel for the user to choose output location
    private func openSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.movie, .audiovisualContent, .video]
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = generateOutputFileName()
        panel.message = "Save a copy of the file with the 'hvc1' tag"
        panel.prompt = "Save"
        
        return panel.runModal() == .OK ? panel.url : nil
    }
    
    /// Generates an output filename based on the source file
    private func generateOutputFileName() -> String {
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        return "\(filename)_hvc1.\(ext)"
    }
}

// MARK: - Convenience Usage

extension TagEditor {
    
    /// Convenience method that handles errors and displays alerts
    /// - Parameter parentWindow: Optional parent window for modal alerts
    /// - Returns: The output URL, or the original URL if no changes were made
    @discardableResult
    func changeTagFileWithUI(parentWindow: NSWindow? = nil) -> URL {
        do {
            let result = try changeTagFile()
            
            if result.wasModified {
                showAlert(
                    message: "Success",
                    info: result.message,
                    style: .informational,
                    window: parentWindow
                )
            }
            
            return result.outputURL
            
        } catch let error as TagEditorError {
            showAlert(
                message: "Operation Failed",
                info: error.localizedDescription,
                style: .warning,
                window: parentWindow
            )
            return sourceURL
            
        } catch {
            showAlert(
                message: "Unexpected Error",
                info: error.localizedDescription,
                style: .critical,
                window: parentWindow
            )
            return sourceURL
        }
    }
    
    /// Displays an alert dialog
    private func showAlert(message: String, info: String, style: NSAlert.Style, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        
        if let window = window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
