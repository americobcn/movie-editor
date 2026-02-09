//
//  ACTVerticalSliderCell.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 26/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Foundation
import AppKit

class ACTVerticalSliderCell: NSSliderCell {
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
                
    }

    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        var rect = aRect
        rect.size.width = CGFloat(3.0)
        self.numberOfTickMarks = 10
        let barRadius = CGFloat(0.5)
        
        // Guard against division by zero
        let range = self.minValue - self.maxValue
        guard range != 0 else { return }
        
        // Safe optional access to controlView
        guard let controlView = self.controlView else { return }
        
        let backGround = NSBezierPath(roundedRect: rect, xRadius: barRadius, yRadius: barRadius)
        NSColor.lightGray.setFill()
        backGround.fill()

        let value = CGFloat((self.doubleValue - self.maxValue) / range)
        let finalHeight = CGFloat(value * controlView.frame.size.height)
        var leftRect = rect
        leftRect.size.height = finalHeight
        let active = NSBezierPath(roundedRect: leftRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.darkGray.setFill()
        active.fill()
    }
    
    override func drawKnob(_ knobRect: NSRect) {
//        var rect = knobRect
//        rect.size.height = 2.5
//        NSColor.gray.setFill()
//        rect.fill()
    }
}
