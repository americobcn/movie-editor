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
        self.layer?.borderColor = NSColor.black.cgColor
        self.layer?.borderWidth = 0.5
        self.layer?.cornerRadius = 3.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.green.cgColor
    }
}

