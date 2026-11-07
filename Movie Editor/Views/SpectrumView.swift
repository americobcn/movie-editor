//
//  SpectrumView.swift
//  Movie Editor
//

import SwiftUI

struct SpectrumView: View {
    var meters: MeterModel

    var body: some View {
        let levels = meters.spectrumLevels
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let barWidth = size.width / CGFloat(levels.count)
            for (index, level) in levels.enumerated() {
                let height = level * size.height
                guard height > 0.5 else { continue }
                let rect = CGRect(x: CGFloat(index) * barWidth, y: size.height - height, width: barWidth, height: height)
                let bar = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(bar, with: .color(.green))
                context.stroke(bar, with: .color(.black), lineWidth: 0.5)
            }
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 6))
    }
}
