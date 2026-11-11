//
//  LineSlider.swift
//  Movie Editor
//

import SwiftUI

/// A slider with a slim track and a vertical rectangular thumb, replacing the default circular knob.
struct LineSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding var value: Value
    var range: ClosedRange<Value> = 0...1

    @Environment(\.isEnabled) private var isEnabled

    private let trackHeight: CGFloat = 4
    private let thumbSize = CGSize(width: 5, height: 18)

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return min(max(Double(value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbSize.width, 1)
            let thumbX = fraction * travel

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.tint)
                    .frame(width: thumbX + thumbSize.width / 2, height: trackHeight)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.primary)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .offset(x: thumbX)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = min(max((drag.location.x - thumbSize.width / 2) / travel, 0), 1)
                        value = range.lowerBound + Value(position) * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: thumbSize.height)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
        }
    }
}
