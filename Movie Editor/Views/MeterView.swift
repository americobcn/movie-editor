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
        self.layer?.bounds = CGRect(x: 0.0, y: 0.0, width: 20.0, height: 124.0)
        self.layer?.backgroundColor = NSColor.green.cgColor
            
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

