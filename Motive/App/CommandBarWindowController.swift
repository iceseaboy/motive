//
//  CommandBarWindowController.swift
//  Motive
//
//  Dynamic height CommandBar window - auto-sizes based on SwiftUI content
//

import AppKit
import SwiftUI

@MainActor
final class CommandBarWindowController {
    private let window: KeyablePanel
    private let hostingView: NSHostingView<AnyView>
    private let containerView: NSView
    private var resignKeyObserver: Any?
    private var resignActiveObserver: Any?
    private var currentHeight: CGFloat = CommandBarWindowController.heights["idle"] ?? 100

    // Must match SwiftUI CommandBarView width
    private static let panelWidth: CGFloat = 680
    
    /// Whether the window has been shown at least once (for lazy initialization)
    private var hasBeenShown = false
    
    /// When true, the window will not hide on resign key (used during delete confirmation)
    var suppressAutoHide: Bool = false
    
    /// Tracks intended visibility. Using window.isVisible is unreliable during
    /// the 0.1s hide fade-out animation (still true until orderOut completes).
    /// This flag is set synchronously in show()/hide() to prevent race conditions.
    private var isIntendedVisible = false
    
    /// Whether the command bar is logically visible (not mid-hide-animation)
    var isVisible: Bool { isIntendedVisible }
    
    // Height constants matching CommandBarMode
    static let heights: [String: CGFloat] = [
        "idle": 100,
        "input": 100,
        "command": 450,
        "history": 450,
        "projects": 450,
        "fileCompletion": 450,
        "running": 160,
        "completed": 160,
        "error": 160
    ]

    init<Content: View>(rootView: Content) {
        hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.safeAreaRegions = []
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: currentHeight))
        containerView.wantsLayer = true
        
        // Initialize window off-screen to prevent first-frame flash at (0,0)
        let panel = KeyablePanel(
            contentRect: NSRect(x: -10000, y: -10000, width: Self.panelWidth, height: 100),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.contentView = containerView
        panel.applyFloatingPanelStyle()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.alphaValue = 0
        
        window = panel
        
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        setupObservers()
    }
    
    private func setupObservers() {
        // Hide when window loses key status (unless suppressed)
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.suppressAutoHide {
                self.hide()
            }
        }
        
        // Also hide when app loses active status
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.suppressAutoHide && self.window.isKeyWindow {
                self.hide()
            }
        }
    }
    
    deinit {
        [resignKeyObserver, resignActiveObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    func show() {
        // Mark as visible immediately (before animation) to prevent race conditions.
        // This ensures subsequent showCommandBar() calls know we're visible.
        isIntendedVisible = true
        
        // 1. Position window BEFORE showing (invisible)
        positionWindowAtCenter()
        
        // 2. Activate app
        NSApp.activate(ignoringOtherApps: true)
        
        // 3. Show window with fade-in animation
        window.orderFrontRegardless()
        window.makeKey()
        window.invalidateShadow()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        
        // 4. Focus input field after animation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.focusFirstResponder()
        }
        
        hasBeenShown = true
    }

    func hide() {
        // Skip if already logically hidden (prevents double-hide)
        guard isIntendedVisible else { return }
        
        // Mark as hidden immediately, BEFORE the fade-out animation.
        // This prevents the race condition where show() is called during the
        // 0.1s fade-out and incorrectly thinks the window is still visible.
        isIntendedVisible = false
        
        // Resign first responder immediately
        window.makeFirstResponder(nil)
        
        // Fade out then order out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            // Only order out if we're still in "hidden" state.
            // If show() was called during the fade-out, isIntendedVisible is
            // now true and we must NOT order out.
            if !self.isIntendedVisible {
                self.window.orderOut(nil)
            }
        })
    }
    
    /// Update window height with smooth animation.
    /// Window expands DOWNWARD — top edge (input position) stays fixed.
    ///
    /// Uses the **actual window frame height** for the guard, not just the
    /// cached `currentHeight`, to self-correct any drift between the two
    /// (e.g., after a `positionWindowAtCenter` call or animation artefact).
    func updateHeight(to newHeight: CGFloat, animated: Bool = true) {
        let currentFrame = window.frame
        // Compare against the real window frame height — not the cached
        // `currentHeight` — so we can fix drift caused by other frame changes.
        guard abs(newHeight - currentFrame.height) > 0.5 else {
            currentHeight = newHeight          // keep cache in sync
            return
        }
        
        let heightDelta = newHeight - currentFrame.height
        
        var newFrame = currentFrame
        newFrame.size.height = newHeight
        // Keep TOP edge fixed, expand downward
        newFrame.origin.y -= heightDelta
        
        if animated && window.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: window.isVisible)
        }
        window.invalidateShadow()
        
        currentHeight = newHeight
    }
    
    func focusFirstResponder() {
        if let textField = window.contentView?.findFirstTextField() {
            window.makeFirstResponder(textField)
        }
    }

    func getWindow() -> NSWindow {
        window
    }
    
    /// Reposition window to center of current screen (for multi-monitor support)
    func recenter() {
        positionWindowAtCenter()
    }

    private func positionWindowAtCenter() {
        guard let screen = screenForMouse() ?? window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        
        let height = max(96, currentHeight)
        let windowSize = NSSize(width: Self.panelWidth, height: height)
        let x = screenFrame.midX - windowSize.width / 2
        
        // Position input at ~55% from bottom of screen
        let topEdgeY = screenFrame.minY + screenFrame.height * 0.55 + 100
        let y = topEdgeY - height
        
        // Set frame without display (we're not visible yet or already positioned)
        window.setFrame(NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height), display: false)
    }

    private func screenForMouse() -> NSScreen? {
        KeyablePanel.screenForMouse()
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Apply shared floating-panel style used by CommandBar and Drawer.
    ///
    /// Rounded corners: the NSThemeFrame (from `.titled`) handles window-level
    /// clipping and border — they share the same system corner radius, so no
    /// double-outline. SwiftUI `.clipShape()` on each view provides the visual
    /// content rounding at our custom radius.
    ///
    /// Shadow: system shadow via `hasShadow = true`, managed by the window
    /// server. No custom NSShadow needed.
    func applyFloatingPanelStyle() {
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Do NOT set cornerRadius / masksToBounds on contentView.
        // That creates a second clipping shape that conflicts with the
        // NSThemeFrame's own border, producing the visible double-outline.
        contentView?.wantsLayer = true
    }

    /// Find the screen that currently contains the mouse pointer.
    static func screenForMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(mouseLocation, 1, &displayID, &count) == .success, count > 0 {
            return NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
            }
        }
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }
}
