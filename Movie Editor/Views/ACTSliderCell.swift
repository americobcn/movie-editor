//
//  ACTSliderCell.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 26/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

class ACTSliderCell: NSSliderCell {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        var rect = aRect
        rect.size.height = CGFloat(5.0)
        let barRadius = CGFloat(0.5)
        let value = CGFloat((self.doubleValue - self.minValue) / (self.maxValue - self.minValue))
        let finalWidth = CGFloat(value * (self.controlView!.frame.size.width))
        var leftRect = rect
        leftRect.size.width = finalWidth
        
        let bg = NSBezierPath(roundedRect: rect, xRadius: barRadius, yRadius: barRadius)
        NSColor.lightGray.setFill()
        bg.fill()
        let active = NSBezierPath(roundedRect: leftRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.darkGray.setFill()
        active.fill()
    }
    
    override func drawKnob(_ knobRect: NSRect) {
//        var rect = knobRect
//        rect.size.width = 2.5
//        NSColor.white.setFill()
//        rect.fill()
    }
}
