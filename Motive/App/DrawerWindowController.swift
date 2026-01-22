//
//  DrawerWindowController.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

// Note: Uses KeyablePanel from CommandBarWindowController.swift

@MainActor
final class DrawerWindowController {
    private let window: KeyablePanel
    private var statusBarButtonFrame: NSRect?
    private var resignKeyObserver: Any?
    var isVisible: Bool { window.isVisible }

    init<Content: View>(rootView: Content) {
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false  // Shadow handled by SwiftUI
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.hidesOnDeactivate = false
        
        // Hide when window loses key status (clicks outside)
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }
    
    deinit {
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Update the position reference for the status bar button
    func updateStatusBarButtonFrame(_ frame: NSRect?) {
        self.statusBarButtonFrame = frame
    }

    func show() {
        positionBelowStatusBar()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    private func positionBelowStatusBar() {
        guard let screen = NSScreen.main else { return }
        let width = window.frame.width
        let height = window.frame.height
        
        let x: CGFloat
        let y: CGFloat
        
        if let buttonFrame = statusBarButtonFrame {
            // Position below status bar icon, aligned to right edge
            x = buttonFrame.maxX - width
            y = buttonFrame.minY - height - 6  // 6pt gap below status bar
        } else {
            // Fallback: position at top-right of screen
            let visibleFrame = screen.visibleFrame
            x = visibleFrame.maxX - width - 12
            y = visibleFrame.maxY - height - 12
        }
        
        // Ensure window stays within screen bounds
        let screenFrame = screen.frame
        let clampedX = max(screenFrame.minX + 12, min(x, screenFrame.maxX - width - 12))
        let clampedY = max(screenFrame.minY + 12, y)
        
        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }
}
