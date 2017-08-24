//
//  AppDelegate.swift
//  OSXMetalParticles
//
//  Created by Simon Gladman on 12/06/2015.
//  Copyright (c) 2015 Simon Gladman. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.styleMask = [.closable, .titled, .miniaturizable]

        window.setContentSize(NSSize(width: 1024, height: 768))
        window.showsResizeIndicator = false
        window.center()
        window.title = "OS X Metal Particles"
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true;
    }
    
}
