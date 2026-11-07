//
//  LevelMetersView.swift
//  Movie Editor
//

import SwiftUI

struct LevelMetersView: View {
    var meters: MeterModel

    var body: some View {
        let levels = meters.channelLevels
        let volume = CGFloat(meters.volume)
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let spacing: CGFloat = 1
            let barWidth = max((size.width - spacing * CGFloat(levels.count + 1)) / CGFloat(levels.count), 1)
            for (index, level) in levels.enumerated() {
                let height = level * volume * size.height
                guard height > 0.5 else { continue }
                let x = spacing + CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                let bar = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(bar, with: .color(.green))
                context.stroke(bar, with: .color(.black), lineWidth: 0.5)
            }
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 5))
    }
}
