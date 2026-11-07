//
//  TransportBar.swift
//  Movie Editor
//

import SwiftUI

struct TransportBar: View {
    @Bindable var player: PlayerModel

    var body: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.scrub(to: $0) }),
                in: 0...max(player.duration, 0.001)
            )
            .disabled(!player.isLoaded)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(player.isExporting ? 1 : 0)
                    .frame(width: 24)

                Spacer()

                transportButton("backward.end.fill", help: "Go to start (↩)", key: .return) { player.seekToStart() }
                transportButton("backward.fill", help: "Rewind (⌘←)", key: .leftArrow, modifiers: .command) { player.fastBackward() }
                transportButton("backward.frame.fill", help: "Previous frame (←)", key: .leftArrow) { player.stepBackward() }
                transportButton(player.isPlaying ? "pause.fill" : "play.fill", help: player.isPlaying ? "Pause (Space)" : "Play (Space)", key: .space) { player.playPause() }
                transportButton("forward.frame.fill", help: "Next frame (→)", key: .rightArrow) { player.stepForward() }
                transportButton("forward.fill", help: "Fast forward (⌘→)", key: .rightArrow, modifiers: .command) { player.fastForward() }
                transportButton("forward.end.fill", help: "Go to end (⌘↩)", key: .return, modifiers: .command) { player.seekToEnd() }

                Spacer()

                Text(player.timecode)
                    .font(.system(.title3, design: .monospaced))

                Button {
                    player.toggleMute()
                } label: {
                    Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 20)
                }
                .help(player.isMuted ? "Unmute" : "Mute")
                .disabled(!player.isLoaded)

                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 90)
                    .disabled(!player.isLoaded)
            }
        }
    }

    private func transportButton(_ symbol: String, help: String, key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22)
        }
        .keyboardShortcut(key, modifiers: modifiers)
        .help(help)
        .disabled(!player.isLoaded)
    }
}
