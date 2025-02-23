//
//  AppDelegate.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 19/04/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        window.allowsConcurrentViewDrawing = true
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "Americo's Movie Player"
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

