//
//  LineSlider.swift
//  Movie Editor
//

//
// LineSlider.swift
// Movie Editor
//

import SwiftUI

/// A slider with a slim track and a rectangular thumb that supports both horizontal and vertical orientations.
struct LineSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding var value: Value
    var range: ClosedRange<Value> = 0...1
    var axis: Axis = .horizontal

    @Environment(\.isEnabled) private var isEnabled

    private let trackWidth: CGFloat = 3
    
    // Invertimos las dimensiones del thumb según la orientación
    private var thumbSize: CGSize {
        axis == .horizontal
            ? CGSize(width: 3, height: 16)
            : CGSize(width: 16, height: 3)
    }

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return min(max(Double(value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            // Determinamos el espacio total que puede recorrer el thumb según el eje
            let totalLength = axis == .horizontal ? proxy.size.width : proxy.size.height
            let thumbLength = axis == .horizontal ? thumbSize.width : thumbSize.height
            let travel = max(totalLength - thumbLength, 1)
            
            // En vertical invertimos el recorrido para que empiece desde abajo (opcional, estándar en controles de volumen/brillo)
            let currentFraction = axis == .horizontal ? fraction : (1 - fraction)
            let thumbOffset = currentFraction * travel

            ZStack(alignment: axis == .horizontal ? .leading : .top) {
                // Track de fondo (Inactivo)
                Capsule()
                    .fill(.quaternary)
                    .frame(
                        width: axis == .horizontal ? proxy.size.width : trackWidth,
                        height: axis == .horizontal ? trackWidth : proxy.size.height
                    )

                // Track activo (Relleno verde)
                Capsule()
                    .fill(.green)
                    .frame(
                        width: axis == .horizontal ? (thumbOffset + thumbSize.width / 2) : trackWidth,
                        height: axis == .horizontal ? trackWidth : (proxy.size.height - thumbOffset + thumbSize.height / 2)
                    )
                    // En vertical, el track activo se alinea abajo moviendo su posición
                    .offset(
                        x: 0,
                        y: axis == .horizontal ? 0 : thumbOffset - thumbSize.height / 2
                    )

                // Thumb del slider
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.primary)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .offset(
                        x: axis == .horizontal ? thumbOffset : 0,
                        y: axis == .horizontal ? 0 : thumbOffset
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let location = axis == .horizontal ? drag.location.x : drag.location.y
                        let offset = axis == .horizontal ? thumbSize.width : thumbSize.height
                        
                        var position = min(max((location - offset / 2) / travel, 0), 1)
                        
                        // Si es vertical, invertimos el cálculo para que arrastrar hacia arriba aumente el valor
                        if axis == .vertical {
                            position = 1 - position
                        }
                        
                        value = range.lowerBound + Value(position) * (range.upperBound - range.lowerBound)
                    }
                )
        }
        // Ajustamos el frame por defecto según la orientación
        .frame(
            width: axis == .horizontal ? nil : thumbSize.width,
            height: axis == .horizontal ? thumbSize.height : nil
        )
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
        }
    }
}










/*
import SwiftUI

/// A slider with a slim track and a vertical rectangular thumb, replacing the default circular knob.
struct LineSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding var value: Value
    var range: ClosedRange<Value> = 0...1
    var axis: Axis = .horizontal
    
    @Environment(\.isEnabled) private var isEnabled

    private let trackHeight: CGFloat = 3
    private let thumbSize = CGSize(width: 3, height: 16)

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
                    .fill(.green)
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
*/
