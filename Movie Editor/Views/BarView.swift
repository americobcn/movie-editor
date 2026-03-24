//
//  SpectrumBarView.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 4/1/22.
//  Copyright © 2022 Américo Cot Toloza. All rights reserved.
//

import Cocoa

class BarView: NSView {
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.canDrawConcurrently = true        
        self.layer?.backgroundColor = NSColor.green.cgColor
        self.layer?.borderColor = NSColor.black.cgColor
        self.layer?.borderWidth = 0.5
        self.layer?.cornerRadius = 3.0
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }    
}
