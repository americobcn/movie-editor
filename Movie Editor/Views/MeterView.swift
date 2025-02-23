//
//  MeterView.swift
//  Movie Editor
//
//  Created by Américo Cot on 01/01/2021.
//  Copyright © 2021 Américo Cot Toloza. All rights reserved.
//

import Cocoa

class MeterView: NSView {
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.canDrawConcurrently = true
        self.layer?.bounds = CGRect(x: 0.0, y: 0.0, width: 10.0, height: 124.0)
        self.layer?.backgroundColor = NSColor.green.cgColor
            
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

//class MeterLayer: CALayer {
//    @NSManaged var height: CGFloat
//
//    override init() {
//        super.init()
//        self.frame = CGRect(x: super.frame.minX, y: super.frame.minY, width: 10.0, height: 120.0)
//    }
//
//    required init?(coder: NSCoder) {
//        super.init(coder: coder)
//    }
//
//    override init(layer: Any) {
//            super.init(layer: layer)
//            guard let meterLayer = layer as? MeterLayer else { return }
//            height = meterLayer.height
//        }
//
//    override func draw(in ctx: CGContext) {
//        ctx.setFillColor(NSColor.blue.cgColor)
//        let newHeight = presentation()?.height ?? 0
//        var rect = bounds
//        rect.size.height *= newHeight
//        ctx.fill(rect)
//        print("Meter Layer called")
//    }
//
//    override class func needsDisplay(forKey key: String) -> Bool {
//            if key == "bounds.size.height" {
//                return true
//            }
//            return super.needsDisplay(forKey: key)
//        }
//
//    override func action(forKey key: String) -> CAAction? {
//            if key == "progress" {
//                let animation = CABasicAnimation(keyPath: key)
//                animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
//                animation.toValue = presentation()?.value(forKey: key)
//                return animation
//            }
//            return super.action(forKey: key)
//        }
//
//}

