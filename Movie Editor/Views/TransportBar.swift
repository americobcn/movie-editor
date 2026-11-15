//
//  TransportBar.swift
//  Movie Editor
//

import SwiftUI

struct TransportBar: View {
    @Bindable var player: PlayerModel

    var body: some View {
        VStack(spacing: 10) {
            LineSlider(
                value: Binding(get: { player.currentTime }, set: { player.scrub(to: $0) }),
                range: 0...max(player.duration, 0.001)
            )
            .disabled(!player.isLoaded)

            HStack(spacing: 5) {
                
                Text(player.timecode)
                    .disabled(!player.isLoaded)
                    .font(.system(.title2, design: .monospaced))
                    .accessibility(identifier: "Current time")
                    .foregroundStyle(player.isLoaded ? .green : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6)) // Fondo agrupado
                
                Spacer()
                
                HStack(spacing: 8) {
                    transportButton("backward.end.fill", help: "Go to start (↩)", key: .return) { player.seekToStart() }
                    transportButton("backward.fill", help: "Rewind (⌘←)", key: .leftArrow, modifiers: .command) { player.fastBackward() }
                    transportButton("backward.frame.fill", help: "Previous frame (←)", key: .leftArrow) { player.stepBackward() }
                    transportButton(player.isPlaying ? "pause.fill" : "play.fill", help: player.isPlaying ? "Pause (Space)" : "Play (Space)", key: .space) { player.playPause() }
                    transportButton("forward.frame.fill", help: "Next frame (→)", key: .rightArrow) { player.stepForward() }
                    transportButton("forward.fill", help: "Fast forward (⌘→)", key: .rightArrow, modifiers: .command) { player.fastForward() }
                    transportButton("forward.end.fill", help: "Go to end (⌘↩)", key: .return, modifiers: .command) { player.seekToEnd() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                                                
                Spacer()
                
                Button {
                    player.toggleMute()
                } label: {
                    Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 10)
                }
                .help(player.isMuted ? "Unmute" : "Mute")
                .disabled(!player.isLoaded)
            }
        }
    }

    private func transportButton(_ symbol: String, help: String, key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 30)
        }
        .foregroundStyle(player.isLoaded ? .primary : .secondary)
        .keyboardShortcut(key, modifiers: modifiers)
        .help(help)
        .disabled(!player.isLoaded)
    }
}
