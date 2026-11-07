//
//  ContentView.swift
//  Movie Editor
//

import SwiftUI

struct ContentView: View {
    @Bindable var player: PlayerModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            VideoSurface(player: player.player)
                .frame(minHeight: 240)
                .overlay {
                    if isDropTargeted {
                        Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    player.handleDrop(urls)
                    return true
                } isTargeted: { isDropTargeted = $0 }

            TransportBar(player: player)

            HStack(alignment: .top, spacing: 12) {
                GroupBox() {
                    Text(player.mediaInfo)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                .frame(width: 230)

                SpectrumView(meters: player.meters)
                LevelMetersView(meters: player.meters)
                    .frame(width: 125)
            }
            .frame(height: 140)
            .alert("Do you want to load a copy with the correct file tag?", isPresented: hev1Binding) {
                Button("Save") { player.fixHev1Tag() }
                Button("Cancel", role: .cancel) { player.hev1Candidate = nil }
            } message: {
                Text("This is a HEVC(H.265) file tagged as 'hev1', the file should have the 'hvc1' tag.")
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 560)
        .preferredColorScheme(.dark)
        .navigationTitle(player.windowTitle)
        .alert(player.alert?.title ?? "", isPresented: alertBinding) {
            Button("OK") { player.alert = nil }
        } message: {
            Text(player.alert?.message ?? "")
        }
    }

    // Both alerts are dismissed by their buttons, so the setters have nothing to do.
    private var hev1Binding: Binding<Bool> {
        Binding(get: { player.hev1Candidate != nil }, set: { _ in })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { player.alert != nil }, set: { if !$0 { player.alert = nil } })
    }
}
