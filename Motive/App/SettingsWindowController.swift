//
//  SettingsWindowController.swift
//  Motive
//
//  Manages the settings window directly.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    private var configManager: ConfigManager?
    private var appState: AppState?
    
    private override init() {
        super.init()
    }
    
    func configure(configManager: ConfigManager, appState: AppState) {
        self.configManager = configManager
        self.appState = appState
    }
    
    func show() {
        // If window exists and is visible, just bring to front
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        guard let configManager = configManager, let appState = appState else {
            Log.error("SettingsWindowController not configured")
            return
        }
        
        // Create settings view
        let settingsView = SettingsView()
            .environmentObject(configManager)
            .environmentObject(appState)
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = L10n.Settings.general
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        self.window = window
        
        // Show window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
    }
    
    // MARK: - NSWindowDelegate
    
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // Restore accessory mode (hide dock icon)
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
