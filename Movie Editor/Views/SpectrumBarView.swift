//
//  SpectrumBarView.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 4/1/22.
//  Copyright © 2022 Américo Cot Toloza. All rights reserved.
//

import Cocoa

class SpectrumBarView: NSView {
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.canDrawConcurrently = true
        self.layer?.bounds = CGRect(x: 0.0, y: 0.0, width: 20.0, height: 124.0)
        self.layer?.backgroundColor = NSColor.green.cgColor
        self.layer?.borderColor = NSColor.black.cgColor
        self.layer?.borderWidth = 0.7
        self.layer?.cornerRadius = 3.0
            
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

//    override func draw(_ dirtyRect: NSRect) {
//        super.draw(dirtyRect)
//
//        // Drawing code here.
//    }
    
}
