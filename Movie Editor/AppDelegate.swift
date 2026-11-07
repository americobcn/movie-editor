//
//  AppDelegate.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 19/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate, ExportSettingsPanelControllerDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var espc: ExportSettingsPanelController!

    private var player: PlayerModel!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        player = PlayerModel(meters: MeterModel())
        espc.delegate = self

        // The SwiftUI content replaces the old XIB view hierarchy
        let host = NSHostingController(rootView: ContentView(player: player))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 896, height: 731))

        window.allowsConcurrentViewDrawing = true
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = PlayerModel.defaultTitle
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // MARK: ExportSettingsPanelControllerDelegate
    func exportPresetDidChange(_ preset: String) {
        player.exportPreset = preset
    }

    // MARK: Menu actions
    @IBAction func loadMovie(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.movie, UTType.audiovisualContent, UTType.video]
        panel.message = "Select a movie"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await player.loadMovie(url: url) }
    }

    @IBAction func saveFile(_ sender: NSMenuItem) {
        player.presentSavePanel(export: sender.title == "Export")
    }

    @IBAction func removeAudioFromMovie(_ sender: NSMenuItem) {
        Task { await player.insertOrRemoveAudio(url: nil) }
    }

    @IBAction func clearInterface(_ sender: NSMenuItem) {
        player.close()
    }
}
