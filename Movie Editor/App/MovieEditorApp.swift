//
//  MovieEditorApp.swift
//  Movie Editor
//

import SwiftUI

@main
struct MovieEditorApp: App {
    @State private var player = PlayerModel(meters: MeterModel())

    var body: some Scene {
        Window(PlayerModel.defaultTitle, id: "main") {
            ContentView(player: player)
        }
        .defaultSize(width: 896, height: 731)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { player.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close") { player.close() }
                    .keyboardShortcut("w")
                    .disabled(!player.isLoaded)
                Divider()
                Button("Save") { player.presentSavePanel(export: false) }
                    .keyboardShortcut("s")
                    .disabled(!player.isLoaded)
                Button("Export") { player.presentSavePanel(export: true) }
                    .keyboardShortcut("e")
                    .disabled(!player.isLoaded)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Remove Audio Track") { Task { await player.insertOrRemoveAudio(url: nil) } }
                    .keyboardShortcut("r")
                    .disabled(!player.isLoaded)
            }
        }

        Settings {
            ExportSettingsView()
        }
    }
}
